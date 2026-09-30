// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/diff_result.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/diff/waveform_diff_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

part 'diff_provider.g.dart';

// ── DiffSignalStatus ──────────────────────────────────────────────────────────

/// Diff status of a signal from file A relative to its counterpart in file B.
///
/// Used by [diffSignalStatusProvider] to drive color overrides in the signal
/// list panel: green = identical, red = different, grey = no counterpart.
enum DiffSignalStatus {
  /// Matched in both files and values are identical across the comparison range.
  identical,

  /// Matched in both files but differs in at least one time range.
  different,

  /// Present only in file A; no counterpart was found in file B.
  unmatchedA,
}

// ── DiffState ─────────────────────────────────────────────────────────────────

/// Immutable state for the waveform diff/comparison feature.
@immutable
class DiffState {
  const DiffState({
    this.secondFilePath,
    this.diffResult,
    this.xorTraces = const {},
    this.divergenceIndex = 0,
    this.isLoading = false,
    this.error,
  });

  /// Absolute path of the second (comparison) waveform file, or null.
  final String? secondFilePath;

  /// Full diff result after both files have been compared, or null.
  final DiffResult? diffResult;

  /// XOR traces keyed by signal path in file A (only for differing signals).
  ///
  /// Each trace is a run-length-compressed 1-bit waveform: `"1"` where the
  /// two signals differ, `"0"` where they agree.
  final Map<String, List<SignalChange>> xorTraces;

  /// Index into [allDivergenceTimes] pointing to the current divergence
  /// navigation position.
  final int divergenceIndex;

  /// True while the second file is being parsed and the diff computed.
  final bool isLoading;

  /// Human-readable error message from the last failed [DiffNotifier.loadSecondFile].
  final String? error;

  // ── derived ─────────────────────────────────────────────────────────────────

  /// True when a comparison file is active (even if still loading).
  bool get isActive => secondFilePath != null;

  /// Flat sorted list of all divergence region start times across all differing
  /// signals.  Duplicate start times (multiple signals diverging at the same
  /// moment) are deduplicated.
  List<int> get allDivergenceTimes {
    if (diffResult == null) return const [];
    final times = <int>{};
    for (final match in diffResult!.matchedSignals) {
      for (final region in match.divergenceRegions) {
        times.add(region.start);
      }
    }
    return times.toList()..sort();
  }

  /// Total number of unique divergence start times.
  int get totalDivergences => allDivergenceTimes.length;

  /// Simulation tick of the currently selected divergence, or null.
  int? get currentDivergenceTime {
    final times = allDivergenceTimes;
    if (times.isEmpty) return null;
    return times[divergenceIndex.clamp(0, times.length - 1)];
  }

  /// Union of all divergence [TimeRange]s across all differing signals.
  ///
  /// May contain overlapping ranges; the canvas renders them as transparent
  /// overlays so visual overlap is intentional.
  List<TimeRange> get allDivergenceRegions {
    if (diffResult == null) return const [];
    final regions = <TimeRange>[];
    for (final match in diffResult!.matchedSignals) {
      regions.addAll(match.divergenceRegions);
    }
    return regions;
  }

  DiffState copyWith({
    String? secondFilePath,
    DiffResult? diffResult,
    Map<String, List<SignalChange>>? xorTraces,
    int? divergenceIndex,
    bool? isLoading,
    String? error,
  }) => DiffState(
    secondFilePath: secondFilePath ?? this.secondFilePath,
    diffResult: diffResult ?? this.diffResult,
    xorTraces: xorTraces ?? this.xorTraces,
    divergenceIndex: divergenceIndex ?? this.divergenceIndex,
    isLoading: isLoading ?? this.isLoading,
    error: error ?? this.error,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiffState &&
          runtimeType == other.runtimeType &&
          secondFilePath == other.secondFilePath &&
          diffResult == other.diffResult &&
          mapEquals(xorTraces, other.xorTraces) &&
          divergenceIndex == other.divergenceIndex &&
          isLoading == other.isLoading &&
          error == other.error;

  @override
  int get hashCode => Object.hash(
    secondFilePath,
    diffResult,
    Object.hashAll(xorTraces.keys),
    divergenceIndex,
    isLoading,
    error,
  );

  @override
  String toString() =>
      'DiffState(path: $secondFilePath, loading: $isLoading, '
      'divergences: $totalDivergences, idx: $divergenceIndex)';
}

// ── DiffNotifier ──────────────────────────────────────────────────────────────

/// Factory for the comparison waveform source. A test seam: override this
/// provider to inject a fake [WaveformDataSource] that records open/close
/// without touching native FFI, so leak-on-reload and leak-on-dispose paths can
/// be asserted.
@riverpod
WaveformDataSource Function() diffSecondSourceFactory(Ref ref) =>
    WellenProvider.new;

/// Manages the waveform comparison (diff) state.
///
/// Call [loadSecondFile] to open a second waveform and compare it against the
/// currently loaded primary file.  The notifier computes divergence regions and
/// XOR traces for all matched signal pairs, then exposes them through
/// [DiffState].
///
/// [nextDivergence] / [prevDivergence] navigate through all divergence start
/// times, moving the primary cursor and panning the viewport to each one.
///
/// Call [clearDiff] to release the comparison file and reset to idle.
@Riverpod(keepAlive: true)
class DiffNotifier extends _$DiffNotifier {
  // Holds the second waveform source so it stays alive for XOR queries.
  WaveformDataSource? _secondSource;

  @override
  DiffState build() {
    // The comparison file is a second native waveform source. Nothing else
    // closes it, so without this the whole second file leaks when the tab is
    // closed while a diff is loaded.
    ref.onDispose(() {
      _secondSource?.close();
      _secondSource = null;
    });
    return const DiffState();
  }

  // ── public API ───────────────────────────────────────────────────────────────

  /// Opens [path] as the comparison waveform, matches signals against the
  /// primary file, and computes divergence regions + XOR traces.
  ///
  /// Uses [WellenProvider] (Rust FFI) on desktop / mobile — the same backend
  /// the primary [WaveformSourceNotifier] uses. The diff feature is not
  /// currently wired for Flutter Web (no path-based file load on web); on web
  /// hosts [WellenProvider]'s stub throws `UnsupportedError`.
  ///
  /// If no primary file is loaded yet, stores [path] and defers diff
  /// computation until the primary file becomes available.
  Future<void> loadSecondFile(String path) async {
    state = DiffState(secondFilePath: path, isLoading: true);

    try {
      _secondSource?.close();
      _secondSource = null;

      final newSource = ref.read(diffSecondSourceFactoryProvider)();
      await newSource.openFile(path);
      // Opening the comparison file is slow enough to span a tab close.
      // Riverpod 3 disposes the notifier eagerly, so `state` writes below
      // would throw `UnmountedRefException` — and the just-opened source
      // would leak, since onDispose already ran before it was assigned.
      if (!ref.mounted) {
        newSource.close();
        return;
      }
      _secondSource = newSource;

      final firstSource = ref.read(waveformSourceProvider).value;
      if (firstSource == null) {
        // Primary not loaded yet — store path, await primary open.
        state = DiffState(secondFilePath: path);
        return;
      }

      const service = WaveformDiffService();

      // Pre-match to know which signals to load.
      final matches = service.matchSignals(
        firstSource.rootScopes,
        newSource.rootScopes,
      );

      // Load matched signals in both sources using their opaque signalRefs
      // (not fullPaths), since backends index by idcode / u32 handle.
      for (final match in matches) {
        if (!firstSource.isSignalLoaded(match.signalRefA)) {
          await firstSource.loadSignal(match.signalRefA);
        }
        if (!newSource.isSignalLoaded(match.signalRefB)) {
          await newSource.loadSignal(match.signalRefB);
        }
      }

      // Compute full diff (re-runs matching and divergence detection).
      final diffResult = service.computeFullDiff(
        firstSource.rootScopes,
        newSource.rootScopes,
        firstSource,
        newSource,
        firstSource.startTime,
        firstSource.endTime,
      );

      // Compute XOR traces for all differing signals.
      // Key by signalRefA (the opaque VCD idcode / wellen handle) — the canvas
      // looks up XOR traces by signalRef, not by the full hierarchical pathA.
      final xorTraces = <String, List<SignalChange>>{};
      for (final match in diffResult.matchedSignals) {
        if (!match.isDifferent) continue;
        xorTraces[match.signalRefA] = service.computeXorTrace(
          match,
          firstSource,
          newSource,
          firstSource.startTime,
          firstSource.endTime,
        );
      }

      // Signal loading + diff computation above are slow; re-check before
      // publishing a result for a tab that may no longer exist.
      if (!ref.mounted) return;

      state = DiffState(
        secondFilePath: path,
        diffResult: diffResult,
        xorTraces: xorTraces,
        // divergenceIndex defaults to 0
      );
    } on Object catch (e) {
      _secondSource?.close();
      _secondSource = null;
      if (!ref.mounted) return;
      state = DiffState(error: e.toString());
    }
  }

  /// Removes the comparison file and resets state to idle.
  void clearDiff() {
    _secondSource?.close();
    _secondSource = null;
    state = const DiffState();
  }

  /// Moves to the next divergence after the current cursor position.
  ///
  /// Wraps around to the first divergence if the cursor is past the last one.
  void nextDivergence() {
    final times = state.allDivergenceTimes;
    if (times.isEmpty) return;

    final cursorTime = ref.read(cursorStateProvider).primaryCursorTime;

    final int newIndex;
    if (cursorTime == null) {
      newIndex = 0;
    } else {
      final idx = times.indexWhere((t) => t > cursorTime);
      newIndex = idx == -1 ? 0 : idx;
    }

    state = state.copyWith(divergenceIndex: newIndex);
    _jumpToTime(times[newIndex]);
  }

  /// Moves to the previous divergence before the current cursor position.
  ///
  /// Wraps around to the last divergence if the cursor is before the first one.
  void prevDivergence() {
    final times = state.allDivergenceTimes;
    if (times.isEmpty) return;

    final cursorTime = ref.read(cursorStateProvider).primaryCursorTime;

    int newIndex;
    if (cursorTime == null) {
      newIndex = times.length - 1;
    } else {
      newIndex = -1;
      for (var i = times.length - 1; i >= 0; i--) {
        if (times[i] < cursorTime) {
          newIndex = i;
          break;
        }
      }
      if (newIndex == -1) newIndex = times.length - 1;
    }

    state = state.copyWith(divergenceIndex: newIndex);
    _jumpToTime(times[newIndex]);
  }

  // ── helpers ──────────────────────────────────────────────────────────────────

  void _jumpToTime(int time) {
    ref.read(cursorStateProvider.notifier).placePrimary(time);
    ref.read(navigationProvider.notifier).jumpToTime(time);
  }
}

// ── derived providers ─────────────────────────────────────────────────────────

/// Derived provider returning the XOR traces map from [DiffNotifier].
///
/// The canvas watches this to inject XOR diff lanes after each matched signal
/// that has divergences.  Returns an empty map when no comparison is active.
@riverpod
Map<String, List<SignalChange>> diffXorTraces(Ref ref) {
  return ref.watch(diffProvider).xorTraces;
}

/// Derived provider that maps each primary-file signal's opaque [signalRef] to
/// its [DiffSignalStatus] when a comparison is active.
///
/// Keyed by [SignalMatch.signalRefA] (the VCD idcode / wellen handle) so that
/// [SignalListPanel] can do O(1) lookups without scanning the full match list.
///
/// Returns an empty map when no comparison is loaded or while loading.
@riverpod
Map<String, DiffSignalStatus> diffSignalStatus(Ref ref) {
  final diff = ref.watch(diffProvider);
  final diffResult = diff.diffResult;
  if (!diff.isActive || diffResult == null) return const {};

  final result = <String, DiffSignalStatus>{};

  for (final match in diffResult.matchedSignals) {
    result[match.signalRefA] = match.isDifferent
        ? DiffSignalStatus.different
        : DiffSignalStatus.identical;
  }

  // Map unmatched file-A paths to their signalRefs via the loaded hierarchy so
  // the signal list panel can apply the "no counterpart" grey indicator.
  if (diffResult.unmatchedA.isNotEmpty) {
    final variablesMap = ref.watch(signalVariablesMapProvider);
    final unmatchedPaths = diffResult.unmatchedA.toSet();
    for (final v in variablesMap.values) {
      if (unmatchedPaths.contains(v.fullPath)) {
        result[v.signalRef] = DiffSignalStatus.unmatchedA;
      }
    }
  }

  return result;
}
