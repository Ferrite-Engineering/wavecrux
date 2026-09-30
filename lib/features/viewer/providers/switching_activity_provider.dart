// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/activity_report.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/signal_query/switching_activity_service.dart';

part 'switching_activity_provider.g.dart';

// ── SwitchingActivityState ────────────────────────────────────────────────────

/// Immutable state for the switching activity analysis feature.
@immutable
class SwitchingActivityState {
  const SwitchingActivityState({
    this.report,
    this.heatmapValues = const {},
    this.isAnalyzing = false,
  });

  /// The most recent analysis result, or `null` when no analysis has run.
  final ActivityReport? report;

  /// Normalized heat values per signal path (0.0 = coolest, 1.0 = hottest).
  ///
  /// Empty when [report] is `null`.
  final Map<String, double> heatmapValues;

  /// Whether an analysis is currently in progress.
  final bool isAnalyzing;

  /// Whether analysis results are displayed (report present or currently computing).
  bool get isActive => report != null || isAnalyzing;

  SwitchingActivityState copyWith({
    ActivityReport? report,
    Map<String, double>? heatmapValues,
    bool? isAnalyzing,
    bool clearReport = false,
  }) => SwitchingActivityState(
    report: clearReport ? null : (report ?? this.report),
    heatmapValues: clearReport
        ? const {}
        : (heatmapValues ?? this.heatmapValues),
    isAnalyzing: isAnalyzing ?? this.isAnalyzing,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SwitchingActivityState &&
          report == other.report &&
          heatmapValues == other.heatmapValues &&
          isAnalyzing == other.isAnalyzing;

  @override
  int get hashCode => Object.hash(report, heatmapValues, isAnalyzing);

  @override
  String toString() =>
      'SwitchingActivityState(active: $isActive, analyzing: $isAnalyzing, '
      'signals: ${report?.signals.length ?? 0})';
}

// ── SwitchingActivityNotifier ─────────────────────────────────────────────────

/// Manages switching activity analysis state.
///
/// Call [analyze] with a list of signal paths and a time range to run the
/// analysis.  [clear] dismisses the result and resets to idle.
@Riverpod(keepAlive: true)
class SwitchingActivityNotifier extends _$SwitchingActivityNotifier {
  @override
  SwitchingActivityState build() => const SwitchingActivityState();

  // ── public API ───────────────────────────────────────────────────────────────

  /// Runs switching activity analysis over [signalRefToPath] in `[startTime, endTime)`.
  ///
  /// Keys are opaque signal references used for [WaveformDataSource] queries;
  /// values are the full hierarchical display paths shown in the report and
  /// used as keys in [SwitchingActivityState.heatmapValues].
  /// Loads any signals not yet loaded, then delegates to
  /// [SwitchingActivityService.analyzeAll] and computes heatmap values.
  /// Does nothing when [signalRefToPath] is empty or no waveform source is loaded.
  Future<void> analyze(
    Map<String, String> signalRefToPath,
    int startTime,
    int endTime,
  ) async {
    if (signalRefToPath.isEmpty) return;
    final source = ref.read(waveformSourceProvider).value;
    if (source == null) return;

    state = state.copyWith(isAnalyzing: true);

    for (final signalRef in signalRefToPath.keys) {
      if (!source.isSignalLoaded(signalRef)) {
        await source.loadSignal(signalRef);
      }
    }

    // The signal loads above are async and can span a tab close. Riverpod 3
    // disposes the notifier eagerly, so writing `state` afterwards throws
    // `UnmountedRefException`. Bail out — the analysis is for a dead tab.
    if (!ref.mounted) return;

    const service = SwitchingActivityService();
    final report = service.analyzeAll(
      signalRefToPath,
      source,
      startTime,
      endTime,
    );
    final heatmapValues = service.computeHeatmapValues(report);

    state = SwitchingActivityState(
      report: report,
      heatmapValues: heatmapValues,
    );
  }

  /// Clears the active analysis result and resets to idle.
  void clear() => state = const SwitchingActivityState();
}
