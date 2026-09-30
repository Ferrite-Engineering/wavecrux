// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/render_pipeline_stats.dart';

/// Per-pane render statistics snapshot (split-pane).
///
/// Wraps a [RenderPipelineStats] payload (latest paint result) plus a
/// short rolling history of paint times in milliseconds used by the
/// statistics strip's paint-time sparkline. The history is capped at
/// [kPaneRenderStatsHistoryDepth] entries; older samples are evicted
/// in FIFO order so each pane keeps its own ~60 s sparkline window.
///
/// Pure Dart — no Flutter imports.
@immutable
class PaneRenderStats {
  const PaneRenderStats({this.latest, this.paintTimesMs = const <double>[]});

  /// The most recent [RenderPipelineStats] frame painted into this pane's
  /// canvas, or null when no frame has been recorded yet.
  final RenderPipelineStats? latest;

  /// Rolling sparkline of paint times in milliseconds, oldest entry first.
  /// Bounded by [kPaneRenderStatsHistoryDepth].
  final List<double> paintTimesMs;

  PaneRenderStats copyWith({
    RenderPipelineStats? latest,
    List<double>? paintTimesMs,
  }) => PaneRenderStats(
    latest: latest ?? this.latest,
    paintTimesMs: paintTimesMs ?? this.paintTimesMs,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaneRenderStats &&
          runtimeType == other.runtimeType &&
          latest == other.latest &&
          paintTimesMs.length == other.paintTimesMs.length &&
          _listEquals(paintTimesMs, other.paintTimesMs);

  @override
  int get hashCode => Object.hash(latest, Object.hashAll(paintTimesMs));

  @override
  String toString() =>
      'PaneRenderStats(latest: $latest, history: ${paintTimesMs.length} samples)';

  static bool _listEquals(List<double> a, List<double> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Maximum number of paint-time samples retained per pane. At a 2 s polling
/// interval (the Live Statistics Strip's sample cadence) this corresponds
/// to roughly 60 seconds of history — matching the description in
/// ARCHITECTURE.md §8.8 of the per-pane segment behavior under split-pane.
const int kPaneRenderStatsHistoryDepth = 30;
