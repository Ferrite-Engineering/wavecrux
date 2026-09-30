// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/diff_result.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_match.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/domain/models/variable.dart';

/// Stateless service that compares two waveform hierarchies and computes
/// time-region divergences between matched signal pairs.
///
/// ### Matching strategy
/// 1. **Exact path match** — `top.cpu.clk` in A matches `top.cpu.clk` in B.
/// 2. **Leaf-name match** — when the root scope name differs, the signal path
///    with the root stripped is compared (e.g. `dut_a.cpu.clk` matches
///    `dut_b.cpu.clk`).  The first hit wins; if multiple signals share the
///    same leaf path, all are reported as exact-only and the extras go to
///    unmatchedA / unmatchedB.
///
/// ### Diff algorithm
/// For a matched pair the service walks the union of both signals' value-change
/// events in the `[startTime, endTime]` window.  At each event time the current
/// values of both signals are compared.  A divergence region opens when the
/// values first differ and closes when they become equal again (or at
/// `endTime`).  X and Z are compared literally — `x` != `0` and `x` != `z`.
///
/// ### XOR trace
/// For 1-bit signals, produces a `List<SignalChange>` with `"1"` where the
/// two signals differ and `"0"` where they agree.  For multi-bit signals,
/// produces a 1-bit "any-bit-differs" trace using the same convention.
class WaveformDiffService {
  const WaveformDiffService();

  // ── public API ──────────────────────────────────────────────────────────────

  /// Flattens both hierarchies and auto-matches signals by path.
  ///
  /// Returns [SignalMatch] entries with [SignalMatch.isDifferent] = false and
  /// empty [SignalMatch.divergenceRegions] — call [computeDiff] or
  /// [computeFullDiff] to populate those fields.
  List<SignalMatch> matchSignals(
    List<Scope> hierarchyA,
    List<Scope> hierarchyB,
  ) {
    final flatA = _flattenVariables(hierarchyA);
    final flatB = _flattenVariables(hierarchyB);

    final mapA = <String, Variable>{for (final v in flatA) v.fullPath: v};
    final mapB = <String, Variable>{for (final v in flatB) v.fullPath: v};

    final matches = <SignalMatch>[];
    final usedB = <String>{};

    // Pass 1: exact path match.
    for (final pathA in mapA.keys) {
      if (mapB.containsKey(pathA)) {
        matches.add(
          SignalMatch(
            pathA: pathA,
            pathB: pathA,
            signalRefA: mapA[pathA]!.signalRef,
            signalRefB: mapB[pathA]!.signalRef,
          ),
        );
        usedB.add(pathA);
      }
    }
    final exactMatchedA = {for (final m in matches) m.pathA};

    // Pass 2: leaf-path match for unmatched signals.
    //
    // Build a leaf-path index for B, using paths with the root scope stripped.
    // Only include B paths not already matched and that appear exactly once
    // (no ambiguous leaf-name matches).
    final leafIndexB = _buildLeafIndex(mapB, usedB);

    for (final pathA in mapA.keys) {
      if (exactMatchedA.contains(pathA)) continue;
      final leafA = _stripRoot(pathA);
      final pathB = leafIndexB[leafA];
      if (pathB != null) {
        matches.add(
          SignalMatch(
            pathA: pathA,
            pathB: pathB,
            signalRefA: mapA[pathA]!.signalRef,
            signalRefB: mapB[pathB]!.signalRef,
          ),
        );
        usedB.add(pathB);
      }
    }

    return matches;
  }

  /// Computes the divergence regions for a single matched signal pair.
  ///
  /// Both [queryA] and [queryB] must have the respective signals loaded.
  /// Returns a new [SignalMatch] with [divergenceRegions] and [isDifferent]
  /// populated.
  SignalMatch computeDiff(
    SignalMatch match,
    WaveformDataSource queryA,
    WaveformDataSource queryB,
    int startTime,
    int endTime,
  ) {
    final changesA = queryA.changesInRange(
      match.signalRefA,
      startTime,
      endTime,
    );
    final changesB = queryB.changesInRange(
      match.signalRefB,
      startTime,
      endTime,
    );

    // The value at startTime is the last change at or before startTime.
    final initA = queryA.valueAt(match.signalRefA, startTime) ?? 'x';
    final initB = queryB.valueAt(match.signalRefB, startTime) ?? 'x';

    final regions = _findDivergenceRegions(
      changesA,
      changesB,
      initA,
      initB,
      startTime,
      endTime,
    );

    return match.copyWith(
      isDifferent: regions.isNotEmpty,
      divergenceRegions: regions,
    );
  }

  /// Computes a 1-bit XOR trace for a matched signal pair.
  ///
  /// For 1-bit signals: `"1"` when values differ, `"0"` when equal.
  /// For multi-bit signals: `"1"` when any bit differs, `"0"` when all match.
  ///
  /// The trace always begins at [startTime] with an explicit initial value.
  /// Only returns changes when the XOR value actually flips (run-length
  /// compressed), so the result can be fed directly to [ScalarSignalPainter]
  /// as a 1-bit waveform.
  List<SignalChange> computeXorTrace(
    SignalMatch match,
    WaveformDataSource queryA,
    WaveformDataSource queryB,
    int startTime,
    int endTime,
  ) {
    final changesA = queryA.changesInRange(
      match.signalRefA,
      startTime,
      endTime,
    );
    final changesB = queryB.changesInRange(
      match.signalRefB,
      startTime,
      endTime,
    );

    final initA = queryA.valueAt(match.signalRefA, startTime) ?? 'x';
    final initB = queryB.valueAt(match.signalRefB, startTime) ?? 'x';

    return _buildXorTrace(
      changesA,
      changesB,
      initA,
      initB,
      startTime,
      endTime,
    );
  }

  /// Runs [matchSignals] + [computeDiff] for all pairs and returns a
  /// complete [DiffResult].
  DiffResult computeFullDiff(
    List<Scope> hierarchyA,
    List<Scope> hierarchyB,
    WaveformDataSource queryA,
    WaveformDataSource queryB,
    int startTime,
    int endTime,
  ) {
    final flatA = _flattenVariables(hierarchyA);
    final flatB = _flattenVariables(hierarchyB);

    final mapA = <String, Variable>{for (final v in flatA) v.fullPath: v};
    final mapB = <String, Variable>{for (final v in flatB) v.fullPath: v};

    final matches = <SignalMatch>[];
    final usedB = <String>{};

    // Pass 1: exact path match.
    for (final pathA in mapA.keys) {
      if (mapB.containsKey(pathA)) {
        matches.add(
          SignalMatch(
            pathA: pathA,
            pathB: pathA,
            signalRefA: mapA[pathA]!.signalRef,
            signalRefB: mapB[pathA]!.signalRef,
          ),
        );
        usedB.add(pathA);
      }
    }
    final exactMatchedA = {for (final m in matches) m.pathA};

    // Pass 2: leaf-path match for remaining signals.
    final leafIndexB = _buildLeafIndex(mapB, usedB);
    final unmatchedA = <String>[];

    for (final pathA in mapA.keys) {
      if (exactMatchedA.contains(pathA)) continue;
      final leafA = _stripRoot(pathA);
      final pathB = leafIndexB[leafA];
      if (pathB != null) {
        matches.add(
          SignalMatch(
            pathA: pathA,
            pathB: pathB,
            signalRefA: mapA[pathA]!.signalRef,
            signalRefB: mapB[pathB]!.signalRef,
          ),
        );
        usedB.add(pathB);
      } else {
        unmatchedA.add(pathA);
      }
    }

    final unmatchedB = mapB.keys.where((p) => !usedB.contains(p)).toList()
      ..sort();
    unmatchedA.sort();

    // Compute diff for each matched pair.
    final diffed = [
      for (final m in matches)
        computeDiff(m, queryA, queryB, startTime, endTime),
    ];

    return DiffResult(
      matchedSignals: diffed,
      unmatchedA: unmatchedA,
      unmatchedB: unmatchedB,
    );
  }

  // ── hierarchy helpers ───────────────────────────────────────────────────────

  List<Variable> _flattenVariables(List<Scope> scopes) {
    final result = <Variable>[];
    for (final scope in scopes) {
      _collectVariables(scope, result);
    }
    return result;
  }

  void _collectVariables(Scope scope, List<Variable> out) {
    out.addAll(scope.variables);
    for (final child in scope.childScopes) {
      _collectVariables(child, out);
    }
  }

  /// Returns a map of `leaf-path → full-path` for B variables not yet matched.
  ///
  /// Leaf path = full path with the first path component removed.
  /// Entries where multiple B variables share the same leaf path are excluded
  /// (ambiguous — neither gets matched).
  Map<String, String> _buildLeafIndex(
    Map<String, Variable> mapB,
    Set<String> usedB,
  ) {
    final leafToFullPaths = <String, List<String>>{};
    for (final pathB in mapB.keys) {
      if (usedB.contains(pathB)) continue;
      final leaf = _stripRoot(pathB);
      (leafToFullPaths[leaf] ??= []).add(pathB);
    }
    return {
      for (final entry in leafToFullPaths.entries)
        if (entry.value.length == 1 && entry.key.isNotEmpty)
          entry.key: entry.value.first,
    };
  }

  /// Removes the first path component (root scope name) from a full path.
  ///
  /// `"top.cpu.clk"` → `"cpu.clk"`.  A single-component path returns an
  /// empty string (so single-scope signals never ambiguously match).
  String _stripRoot(String fullPath) {
    final dot = fullPath.indexOf('.');
    return dot < 0 ? '' : fullPath.substring(dot + 1);
  }

  // ── diff algorithm ──────────────────────────────────────────────────────────

  /// Walk the union of [changesA] and [changesB] and collect time intervals
  /// where the two signals have different values.
  ///
  /// Uses a two-pointer merge so each change list is visited at most once —
  /// O(|changesA| + |changesB|) per call.
  List<TimeRange> _findDivergenceRegions(
    List<SignalChange> changesA,
    List<SignalChange> changesB,
    String initValueA,
    String initValueB,
    int startTime,
    int endTime,
  ) {
    final regions = <TimeRange>[];
    int? regionStart;

    _mergeWalk(
      changesA,
      changesB,
      initValueA,
      initValueB,
      startTime,
      endTime,
      (t, valA, valB) {
        final differs = valA != valB;
        if (differs && regionStart == null) {
          regionStart = t;
        } else if (!differs && regionStart != null) {
          regions.add(TimeRange(start: regionStart!, end: t));
          regionStart = null;
        }
      },
    );

    if (regionStart != null) {
      regions.add(TimeRange(start: regionStart!, end: endTime));
    }

    return regions;
  }

  /// Builds a run-length-compressed 1-bit XOR trace.
  List<SignalChange> _buildXorTrace(
    List<SignalChange> changesA,
    List<SignalChange> changesB,
    String initValueA,
    String initValueB,
    int startTime,
    int endTime,
  ) {
    final trace = <SignalChange>[];
    String? lastXorValue;

    _mergeWalk(
      changesA,
      changesB,
      initValueA,
      initValueB,
      startTime,
      endTime,
      (t, valA, valB) {
        final xor = valA != valB ? '1' : '0';
        if (xor != lastXorValue) {
          trace.add(SignalChange(time: t, value: xor));
          lastXorValue = xor;
        }
      },
    );

    return trace;
  }

  /// O(|a| + |b|) merge-walk over the sorted union of event times.
  ///
  /// Calls [onEvent] once for each unique time in [startTime, endTime] where
  /// either signal changes, and once for [startTime] itself.
  /// [onEvent] receives the current values of both signals at that time.
  void _mergeWalk(
    List<SignalChange> a,
    List<SignalChange> b,
    String initA,
    String initB,
    int startTime,
    int endTime,
    void Function(int t, String valA, String valB) onEvent,
  ) {
    var iA = 0;
    var iB = 0;
    var valA = initA;
    var valB = initB;

    // Advance past any pre-window changes (should not occur if changesInRange
    // is correctly bounded, but guard defensively).
    while (iA < a.length && a[iA].time < startTime) {
      valA = a[iA].value;
      iA++;
    }
    while (iB < b.length && b[iB].time < startTime) {
      valB = b[iB].value;
      iB++;
    }

    // Emit the initial state at startTime.
    onEvent(startTime, valA, valB);

    while (iA < a.length || iB < b.length) {
      final tA = iA < a.length ? a[iA].time : endTime + 1;
      final tB = iB < b.length ? b[iB].time : endTime + 1;

      final t = tA <= tB ? tA : tB;
      if (t > endTime) break;

      // Advance both cursors to time t (multiple changes at the same time are
      // consumed in sequence; only the last value at t is used).
      while (iA < a.length && a[iA].time == t) {
        valA = a[iA].value;
        iA++;
      }
      while (iB < b.length && b[iB].time == t) {
        valB = b[iB].value;
        iB++;
      }

      onEvent(t, valA, valB);
    }
  }
}
