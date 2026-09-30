// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/waveform/display_changes.dart';

// ── XOriginResult ─────────────────────────────────────────────────────────────

/// The result of tracing a single signal's X origin backward in time.
@immutable
class XOriginResult {
  const XOriginResult({
    required this.signalPath,
    required this.originTime,
    this.previousValue,
  });

  /// Full hierarchical path of the traced signal (e.g. `"top.cpu.status"`).
  final String signalPath;

  /// Simulation tick at which the signal first entered its current X streak.
  final int originTime;

  /// Value held by the signal immediately before it became X, or `null` if
  /// the signal was X from the very beginning of the simulation record.
  final String? previousValue;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is XOriginResult &&
          signalPath == other.signalPath &&
          originTime == other.originTime &&
          previousValue == other.previousValue;

  @override
  int get hashCode => Object.hash(signalPath, originTime, previousValue);

  @override
  String toString() =>
      'XOriginResult(path: $signalPath, originTime: $originTime, '
      'prev: $previousValue)';
}

// ── XCausalNode ───────────────────────────────────────────────────────────────

/// A node in the X-origin causal chain.
///
/// The root node represents the signal whose X origin was requested.
/// Each child represents a sibling signal in the same scope that was also X
/// at the root's X-start time — indicating co-temporal X propagation.
///
/// Depth is intentionally limited to two levels (root + direct siblings) to
/// avoid exponential fan-out and infinite cycles when tracing without RTL.
@immutable
class XCausalNode {
  const XCausalNode({
    required this.signalPath,
    required this.signalRef,
    required this.xStartTime,
    this.previousValue,
    this.children = const [],
  });

  /// Full hierarchical path (e.g. `"top.cpu.dataout"`).
  final String signalPath;

  /// Opaque signal reference used for [WaveformDataSource] queries.
  final String signalRef;

  /// Simulation tick at which this signal entered its current X streak.
  final int xStartTime;

  /// Value immediately before X, or `null` if X since start.
  final String? previousValue;

  /// Co-temporal X sibling nodes (only non-empty on the root node).
  final List<XCausalNode> children;

  XCausalNode copyWith({
    String? signalPath,
    String? signalRef,
    int? xStartTime,
    String? previousValue,
    List<XCausalNode>? children,
  }) => XCausalNode(
    signalPath: signalPath ?? this.signalPath,
    signalRef: signalRef ?? this.signalRef,
    xStartTime: xStartTime ?? this.xStartTime,
    previousValue: previousValue ?? this.previousValue,
    children: children ?? this.children,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is XCausalNode &&
          signalPath == other.signalPath &&
          signalRef == other.signalRef &&
          xStartTime == other.xStartTime &&
          previousValue == other.previousValue &&
          _listEquals(children, other.children);

  @override
  int get hashCode =>
      Object.hash(signalPath, signalRef, xStartTime, previousValue);

  @override
  String toString() =>
      'XCausalNode(path: $signalPath, xStart: $xStartTime, '
      'prev: $previousValue, children: ${children.length})';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ── XTraceService ─────────────────────────────────────────────────────────────

/// Stateless service for X-origin tracing.
///
/// ### findXOrigin
/// Given a signal whose value at [time] is X, walks backward through its
/// value changes to find the **first tick** of the current X streak.  Returns
/// `null` when the signal is not X at [time] or its data is not loaded.
///
/// ### buildCausalChain
/// Constructs a shallow (two-level) causal tree:
/// - Root: the queried signal with its X-origin time.
/// - Children: sibling signals in the same scope that are **also X** at the
///   root's X-start time (heuristic co-temporal propagation).
///
/// Because WaveCrux operates on waveform data only (no RTL netlist), causal
/// relationships are inferred from co-temporal X occurrence in the same scope.
class XTraceService {
  const XTraceService();

  // ── public API ──────────────────────────────────────────────────────────────

  /// Returns the X-origin for [signalRef]/[signalPath] at simulation tick
  /// [time], or `null` if the signal is not X at [time].
  ///
  /// [signalRef] must already be loaded (via [WaveformDataSource.loadSignal]).
  XOriginResult? findXOrigin(
    String signalRef,
    String signalPath,
    int time,
    WaveformDataSource query,
  ) {
    final valueAtTime = query.valueAt(signalRef, time);
    if (valueAtTime == null || !_containsX(valueAtTime)) return null;

    // The history up to and including [time], as the inclusive index range
    // [lo, hi]. A packed store is walked in place: the walk below visits only
    // the X streak and the one change before it, where materializing the
    // whole history first cost O(every change since the trace began) — on
    // every X-trace request, and on every cursor move for a caller that
    // traces each X-valued signal at the cursor.
    final int lo;
    final int hi;
    final int Function(int) timeOf;
    final String Function(int) valueOf;
    final bool Function(int) isX;
    final compact = query is CompactChangesSource
        ? (query as CompactChangesSource).compactChangesFor(signalRef)
        : null;
    if (compact != null) {
      lo = compact.lowerBoundGE(query.startTime);
      hi = compact.upperBoundLE(time);
      timeOf = compact.timeAt;
      valueOf = compact.valueAt;
      isX = compact.valueContainsX;
    } else {
      final changes = query.changesInRange(
        signalRef,
        query.startTime,
        time + 1,
      );
      lo = 0;
      hi = changes.length - 1;
      timeOf = (i) => changes[i].time;
      valueOf = (i) => changes[i].value;
      isX = (i) => _containsX(changes[i].value);
    }

    // Walk backward: find the last non-X change — its successor is when X began.
    var originTime = query.startTime; // default: X since simulation start
    String? previousValue;

    for (var i = hi; i >= lo; i--) {
      if (!isX(i)) {
        previousValue = valueOf(i);
        // The next change after this non-X entry is the start of the X streak.
        if (i + 1 <= hi) {
          originTime = timeOf(i + 1);
        }
        // If i+1 is past the range the history ended on a non-X value, but
        // valueAt(time) is X — this implies the initial pre-change value was X
        // and this non-X was the most recent change. Guard: treat origin as
        // startTime and previousValue as this non-X value.
        break;
      }
      // Still in X territory — keep tracking the earliest X change.
      originTime = timeOf(i);
    }

    // When every change in the range was X, the signal may have had a non-X
    // initial value before the very first change. Check valueAt(startTime).
    if (previousValue == null && originTime > query.startTime) {
      final initVal = query.valueAt(signalRef, query.startTime);
      if (initVal != null && !_containsX(initVal)) {
        previousValue = initVal;
      } else if (initVal != null && _containsX(initVal)) {
        originTime = query.startTime;
      }
    }

    return XOriginResult(
      signalPath: signalPath,
      originTime: originTime,
      previousValue: previousValue,
    );
  }

  /// Builds a shallow causal chain rooted at [variable] at time [time].
  ///
  /// Returns a root [XCausalNode] whose [XCausalNode.children] are sibling
  /// signals (in the same scope) that are also X at the root's X-start time.
  ///
  /// Siblings whose signal data is not loaded are silently skipped.
  XCausalNode buildCausalChain(
    Variable variable,
    int time,
    List<Scope> hierarchy,
    WaveformDataSource query,
  ) {
    final origin = findXOrigin(
      variable.signalRef,
      variable.fullPath,
      time,
      query,
    );
    final xStartTime = origin?.originTime ?? time;

    // Collect loaded siblings in the same scope.
    final siblings = _findScopeVariables(variable.scopePath, hierarchy)
        .where(
          (v) =>
              v.signalRef != variable.signalRef &&
              query.isSignalLoaded(v.signalRef),
        )
        .toList();

    // Build leaf nodes for siblings that are X at xStartTime.
    final children = <XCausalNode>[];
    for (final sibling in siblings) {
      final val = query.valueAt(sibling.signalRef, xStartTime);
      if (val == null || !_containsX(val)) continue;

      final siblingOrigin = findXOrigin(
        sibling.signalRef,
        sibling.fullPath,
        xStartTime,
        query,
      );
      children.add(
        XCausalNode(
          signalPath: sibling.fullPath,
          signalRef: sibling.signalRef,
          xStartTime: siblingOrigin?.originTime ?? xStartTime,
          previousValue: siblingOrigin?.previousValue,
        ),
      );
    }

    return XCausalNode(
      signalPath: variable.fullPath,
      signalRef: variable.signalRef,
      xStartTime: xStartTime,
      previousValue: origin?.previousValue,
      children: children,
    );
  }

  // ── helpers ─────────────────────────────────────────────────────────────────

  bool _containsX(String value) => value.toLowerCase().contains('x');

  /// Returns all variables declared directly in the scope at [scopePath],
  /// or an empty list if no matching scope is found.
  List<Variable> _findScopeVariables(
    String scopePath,
    List<Scope> hierarchy,
  ) {
    for (final scope in hierarchy) {
      final result = _searchScope(scopePath, scope);
      if (result != null) return result;
    }
    return const [];
  }

  List<Variable>? _searchScope(String targetPath, Scope scope) {
    if (scope.path == targetPath) return scope.variables;
    for (final child in scope.childScopes) {
      final result = _searchScope(targetPath, child);
      if (result != null) return result;
    }
    return null;
  }
}
