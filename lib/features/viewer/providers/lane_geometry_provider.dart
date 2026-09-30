// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/translator_expansion_provider.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';

part 'lane_geometry_provider.g.dart';

/// The shared lane-geometry source of truth for the three per-row columns.
///
/// Keyed by [LaneMetrics] so that the signal-names list, waveform canvas, and
/// value column — which each resolve an *equal* [LaneMetrics] from
/// `MobileMetrics.of(context, deviceClass)` — receive the **same** cached
/// [LaneGeometry] instance and therefore the same per-row heights/offsets.
/// Recomputes whenever the arranged signal list changes.
///
/// Declares [SignalGroupsNotifier] as a dependency because
/// [signalGroupsProvider] is overridden per tab (see `wavecrux_tab_overrides`).
/// Without it this provider is hoisted to the root container and reads the
/// empty root signal list, so the value column — the one column that sources
/// its row list from `geometry.rows` — renders blank even though the canvas and
/// names list (which read `signalGroupsProvider` directly in the tab scope)
/// show data.
@Riverpod(dependencies: [SignalGroupsNotifier, signalChildRowCounts])
LaneGeometry laneGeometry(Ref ref, LaneMetrics metrics) {
  final group = ref.watch(signalGroupsProvider);
  final childRowCounts = ref.watch(signalChildRowCountsProvider);
  return LaneGeometry(
    entries: group.entries,
    metrics: metrics,
    childRowCounts: childRowCounts,
  );
}
