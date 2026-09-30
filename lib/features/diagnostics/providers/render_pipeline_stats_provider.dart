// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/features/viewer/widgets/render_stats_collector.dart';

part 'render_pipeline_stats_provider.g.dart';

/// Root-scope [RenderStatsCollector] instance.
///
/// **Per-pane scoping invariant.** The waveform canvas is wrapped in a
/// `_PaneScopedCanvas` that re-overrides `renderStatsCollectorProvider`
/// with the **per-pane** collector (allocated and owned by
/// [PaneContainerManager]). Every canvas paint event lands on its pane's
/// collector — never on this root-scope instance. The pane's collector
/// bridges into the pane's own `paneRenderStatsProvider` so each
/// `LiveStatisticsStrip` and `PaneRenderStatsPopover` reads cleanly
/// isolated paint history (Issue 31: VERIFICATION_GUIDE §22.9.11).
///
/// This root-scope instance is therefore the fallback for a canvas built
/// outside any pane scope, which in the app does not happen. It registers no
/// frame-timings callback: frame timings are an app-level signal, read only by
/// the App Diagnostics dialog, which collects them itself while it is open.
///
/// **There is no collector → root `paneRenderStatsProvider` bridge.**
/// A previous incarnation registered an `onPaint` listener that wrote
/// every collector pulse into the root-scope notifier (in case a strip
/// fell back to the root scope). Because the per-pane override is
/// applied at the `_PaneScopedCanvas` level, the root collector never
/// actually pulses — so the bridge was dead code. Worse, in the edge
/// cases where the override *was* bypassed (test harnesses that build
/// the canvas outside `_PaneScopedCanvas`, deprecated diagnostics
/// surfaces), the bridge silently mixed every pane's paint samples
/// into the root notifier, breaking the per-pane sparkline contract.
/// Removing the bridge guarantees per-pane isolation by construction.
@Riverpod(keepAlive: true)
RenderStatsCollector renderStatsCollector(Ref ref) {
  final collector = RenderStatsCollector();
  ref.onDispose(collector.dispose);
  return collector;
}
