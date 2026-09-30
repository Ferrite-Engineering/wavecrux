// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_timeline_overlay_layer.dart';
import 'package:wavecrux/plugins/extra_timeline_overlays_provider.dart';
import 'package:wavecrux/plugins/timeline_overlay_layer.dart';

/// Unified registry of every [TimelineOverlayLayer] mounted by the
/// host (`WaveformViewCenter`) between the time ruler and the
/// waveform canvas.
///
/// Combines the open-core default layers (currently just the cocotb
/// log strip) with any layers contributed through
/// [extraTimelineOverlaysProvider] (Pro-tier SVA, future coverage,
/// etc.) and returns them sorted by ascending
/// [TimelineOverlayLayer.priority] so larger-priority layers paint
/// closer to the waveform canvas.
///
/// Why a separate unified provider instead of seeding the cocotb
/// layer into [extraTimelineOverlaysProvider]'s default: keeping the
/// "extras" seam purely additive lets the Pro overlay's `proOverrides`
/// override [extraTimelineOverlaysProvider] with `[SvaAssertionOverlayLayer()]`
/// (just its own contributions) without having to remember to spread
/// the open-core default. The cocotb strip is registered open-core-side
/// here, the extras seam stays composable.
final timelineOverlayLayersProvider = Provider<List<TimelineOverlayLayer>>(
  (ref) {
    final extras = ref.watch(extraTimelineOverlaysProvider);
    return [
      const CocotbTimelineOverlayLayer(),
      ...extras,
    ]..sort((a, b) => a.priority.compareTo(b.priority));
  },
);
