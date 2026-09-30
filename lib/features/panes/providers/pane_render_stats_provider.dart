// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/pane_render_stats.dart';
import 'package:wavecrux/domain/models/render_pipeline_stats.dart';

/// Per-pane mutable render-statistics container (split-pane).
///
/// Each pane's [ProviderContainer] gets its own instance of this notifier
/// via [PaneContainerManager], so the sparkline buffer is naturally
/// pane-local: switching the active pane swaps the visible sparkline
/// without losing history (see ARCHITECTURE.md §8.8). The notifier
/// publishes [PaneRenderStats] with a bounded rolling history capped at
/// [kPaneRenderStatsHistoryDepth].
///
/// Callers — typically the per-pane `RenderStatsCollector` listener — push
/// frames via [record]. Tests reach for [reset] before each scenario.
class PaneRenderStatsNotifier extends Notifier<PaneRenderStats> {
  @override
  PaneRenderStats build() => const PaneRenderStats();

  /// Records [latest] as the most recent paint result for this pane and
  /// appends `latest.totalPaintTimeUs / 1000` to the sparkline. Drops the
  /// oldest sample when the buffer exceeds [kPaneRenderStatsHistoryDepth].
  void record(RenderPipelineStats latest) {
    final ms = latest.totalPaintTimeUs / 1000.0;
    final next = [...state.paintTimesMs, ms];
    if (next.length > kPaneRenderStatsHistoryDepth) {
      next.removeRange(0, next.length - kPaneRenderStatsHistoryDepth);
    }
    state = state.copyWith(latest: latest, paintTimesMs: next);
  }

  /// Resets this pane's sparkline buffer. Used by tests.
  void reset() {
    state = const PaneRenderStats();
  }
}

/// Per-pane [NotifierProvider] holding the rolling [PaneRenderStats] for
/// the canvas painted into this pane.
///
/// Resolved within each pane's [UncontrolledProviderScope] (see
/// [PaneContainerManager]) — the manager constructs a child
/// [ProviderContainer] that overrides this provider with a fresh notifier
/// so the two panes in a split layout get independent sparkline buffers.
/// In the root container the provider falls back to a default instance
/// (used by tests and by toolbar/status bar widgets that read aggregated
/// stats outside any pane scope).
final paneRenderStatsProvider =
    NotifierProvider<PaneRenderStatsNotifier, PaneRenderStats>(
      PaneRenderStatsNotifier.new,
    );
