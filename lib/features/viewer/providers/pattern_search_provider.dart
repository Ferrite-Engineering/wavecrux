// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/pattern_expression.dart';
import 'package:wavecrux/domain/models/pattern_match.dart';
import 'package:wavecrux/domain/models/pattern_search_result.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/signal_query/pattern_search_service.dart';

part 'pattern_search_provider.g.dart';

// Sentinel for optional nullable fields in copyWith.
const _copyWithSentinel = Object();

// ── PatternSearchState ────────────────────────────────────────────────────────

/// Immutable state for the multi-signal pattern search feature.
@immutable
class PatternSearchState {
  const PatternSearchState({
    this.result,
    this.currentMatchIndex = 0,
    this.isSearching = false,
    this.error,
    this.noWaveform = false,
  });

  /// The most recent search result, or `null` when no search has been run.
  final PatternSearchResult? result;

  /// Zero-based index of the currently highlighted match.
  final int currentMatchIndex;

  /// Whether a search is currently in progress.
  final bool isSearching;

  /// Error message from the most recent search failure, or `null`.
  ///
  /// Carries raw failure text (e.g. an exception string) for display in the
  /// search toolbar. The "no waveform loaded" guidance case is signalled via
  /// [noWaveform] instead, so the toolbar can render a localized label.
  final String? error;

  /// True when a search was attempted with no waveform file loaded. The
  /// toolbar renders a localized guidance label for this case rather than the
  /// raw [error] string.
  final bool noWaveform;

  /// Whether the state has a completed result (may have zero matches).
  bool get hasResult => result != null && !isSearching;

  /// Whether there is at least one match to navigate.
  bool get hasMatches => result != null && result!.hasMatches;

  /// Total number of matches.
  int get matchCount => result?.matchCount ?? 0;

  /// The currently focused match, or `null` when there are no matches.
  PatternMatch? get currentMatch {
    if (!hasMatches) return null;
    final matches = result!.matches;
    if (currentMatchIndex < 0 || currentMatchIndex >= matches.length) {
      return null;
    }
    return matches[currentMatchIndex];
  }

  /// All match time ranges, for overlay rendering on the time ruler and canvas.
  List<TimeRange> get matchRanges {
    if (result == null || !result!.hasMatches) return const [];
    return result!.matches
        .map((m) => TimeRange(start: m.time, end: m.endTime))
        .toList();
  }

  PatternSearchState copyWith({
    PatternSearchResult? result,
    int? currentMatchIndex,
    bool? isSearching,
    Object? error = _copyWithSentinel,
    bool? noWaveform,
    bool clearResult = false,
  }) => PatternSearchState(
    result: clearResult ? null : (result ?? this.result),
    currentMatchIndex: currentMatchIndex ?? this.currentMatchIndex,
    isSearching: isSearching ?? this.isSearching,
    error: identical(error, _copyWithSentinel) ? this.error : error as String?,
    noWaveform: noWaveform ?? this.noWaveform,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PatternSearchState &&
          runtimeType == other.runtimeType &&
          result == other.result &&
          currentMatchIndex == other.currentMatchIndex &&
          isSearching == other.isSearching &&
          error == other.error &&
          noWaveform == other.noWaveform;

  @override
  int get hashCode =>
      Object.hash(result, currentMatchIndex, isSearching, error, noWaveform);

  @override
  String toString() =>
      'PatternSearchState(matches: $matchCount, index: $currentMatchIndex, '
      'searching: $isSearching, error: $error, noWaveform: $noWaveform)';
}

// ── PatternSearchNotifier ─────────────────────────────────────────────────────

/// Manages multi-signal pattern search state.
///
/// Call [search] with a [PatternExpression] and time bounds to run the search.
/// [nextMatch] / [prevMatch] cycle through results and move the primary cursor.
/// [clearSearch] dismisses the results.
@Riverpod(keepAlive: true)
class PatternSearchNotifier extends _$PatternSearchNotifier {
  static const _service = PatternSearchService();

  @override
  PatternSearchState build() => const PatternSearchState();

  // ── public API ───────────────────────────────────────────────────────────────

  /// Searches `[startTime, endTime)` for regions where [expression] is true.
  ///
  /// Signal paths in [expression] may be raw signalRefs (as produced by the
  /// builder mode), signal leaf names (e.g. `chip_select`), or full
  /// hierarchical paths (e.g. `pattern_search_test.chip_select`).  All forms
  /// are resolved to signalRefs before the search runs.
  ///
  /// Loads any unreferenced signals before searching.  On completion, jumps the
  /// primary cursor to the first match (if any).
  Future<void> search(
    PatternExpression expression,
    int startTime,
    int endTime,
  ) async {
    state = const PatternSearchState(isSearching: true);

    try {
      final source = ref.read(waveformSourceProvider).value;
      if (source == null) {
        state = const PatternSearchState(noWaveform: true);
        return;
      }

      // Translate any signal name / full path in the expression to the opaque
      // signalRef that the data source understands.
      final variablesMap = ref.read(signalVariablesMapProvider);
      final resolved = _resolveSignalRefs(expression, variablesMap);

      for (final path in resolved.signalPaths) {
        if (!source.isSignalLoaded(path)) {
          await source.loadSignal(path);
        }
      }

      // The signal loads above are async and can span a tab close. Riverpod 3
      // disposes the notifier eagerly, so writing `state` afterwards throws
      // `UnmountedRefException`. Bail out instead — the result is for a tab
      // that no longer exists.
      if (!ref.mounted) return;

      final result = _service.search(resolved, source, startTime, endTime);

      state = PatternSearchState(result: result);

      // Past the no-waveform bail and the disposal check, so this counts
      // searches that actually ran against a trace — a zero-match run still
      // counts, because the user did use pattern search. `nextMatch` /
      // `prevMatch` are navigation within one run and are not recorded.
      ref
          .read(telemetryServiceProvider)
          .record(
            TelemetryEvent(
              'search.used',
              properties: const <String, Object?>{'mode': 'pattern'},
            ),
          );

      if (result.hasMatches) {
        _jumpToMatch(0, result);
      }
    } on Object catch (e) {
      state = PatternSearchState(error: e.toString());
    }
  }

  /// Advances to the next match, wrapping around, and jumps the cursor.
  void nextMatch() {
    final s = state;
    if (!s.hasMatches) return;
    final next = (s.currentMatchIndex + 1) % s.matchCount;
    state = s.copyWith(currentMatchIndex: next);
    _jumpToMatch(next, s.result!);
  }

  /// Goes back to the previous match, wrapping around, and jumps the cursor.
  void prevMatch() {
    final s = state;
    if (!s.hasMatches) return;
    final prev = (s.currentMatchIndex - 1 + s.matchCount) % s.matchCount;
    state = s.copyWith(currentMatchIndex: prev);
    _jumpToMatch(prev, s.result!);
  }

  /// Clears the current search result and resets to idle.
  void clearSearch() {
    state = const PatternSearchState();
  }

  // ── private ──────────────────────────────────────────────────────────────────

  void _jumpToMatch(int index, PatternSearchResult result) {
    final match = result.matches[index];
    ref.read(cursorStateProvider.notifier).placePrimary(match.time);
    ref.read(navigationProvider.notifier).jumpToTime(match.time);
  }

  // ── signal-name resolution ────────────────────────────────────────────────

  /// Recursively walks [expr] and replaces every [SignalCondition.signalPath]
  /// with the matching signalRef from [variablesMap].
  ///
  /// Accepts three input forms (in priority order):
  ///   1. Exact signalRef — already valid, returned unchanged.
  ///   2. Full hierarchical path, e.g. `top.cpu.clk`.
  ///   3. Leaf signal name, e.g. `clk` — only when unambiguous.
  ///
  /// Throws [FormatException] if a path cannot be resolved or is ambiguous.
  static PatternExpression _resolveSignalRefs(
    PatternExpression expr,
    Map<String, Variable> variablesMap,
  ) {
    // Build reverse-lookup structures once for the whole tree walk.
    final byFullPath = <String, String>{}; // fullPath → signalRef
    final byName = <String, List<String>>{}; // leaf name → [signalRefs]
    for (final entry in variablesMap.entries) {
      final signalRef = entry.key;
      final v = entry.value;
      byFullPath[v.fullPath] = signalRef;
      byName.putIfAbsent(v.name, () => []).add(signalRef);
    }

    return _resolveExpr(expr, variablesMap, byFullPath, byName);
  }

  static PatternExpression _resolveExpr(
    PatternExpression expr,
    Map<String, Variable> byRef,
    Map<String, String> byFullPath,
    Map<String, List<String>> byName,
  ) => switch (expr) {
    SignalCondition() => SignalCondition(
      signalPath: _resolveOnePath(expr.signalPath, byRef, byFullPath, byName),
      operator: expr.operator,
      value: expr.value,
    ),
    AndExpression() => AndExpression(
      left: _resolveExpr(expr.left, byRef, byFullPath, byName),
      right: _resolveExpr(expr.right, byRef, byFullPath, byName),
    ),
    OrExpression() => OrExpression(
      left: _resolveExpr(expr.left, byRef, byFullPath, byName),
      right: _resolveExpr(expr.right, byRef, byFullPath, byName),
    ),
    NotExpression() => NotExpression(
      operand: _resolveExpr(expr.operand, byRef, byFullPath, byName),
    ),
  };

  static String _resolveOnePath(
    String signalPath,
    Map<String, Variable> byRef,
    Map<String, String> byFullPath,
    Map<String, List<String>> byName,
  ) {
    // 1. Already a valid signalRef — builder mode, no translation needed.
    if (byRef.containsKey(signalPath)) return signalPath;

    // 2. Full hierarchical path match.
    final byPathMatch = byFullPath[signalPath];
    if (byPathMatch != null) return byPathMatch;

    // 3. Leaf name match — may be ambiguous.
    final nameMatches = byName[signalPath];
    if (nameMatches != null) {
      if (nameMatches.length == 1) return nameMatches.first;
      throw FormatException(
        'Ambiguous signal name "$signalPath": matches signals in multiple '
        'scopes. Use the full hierarchical path to disambiguate.',
      );
    }

    throw FormatException('Unknown signal: "$signalPath"');
  }
}
