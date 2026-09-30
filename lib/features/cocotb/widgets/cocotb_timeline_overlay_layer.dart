// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_timeline_overlay.dart';
import 'package:wavecrux/plugins/timeline_overlay_layer.dart';

/// [TimelineOverlayLayer] adapter for the cocotb log timeline strip.
///
/// Registers the existing [CocotbTimelineOverlay] widget through the
/// canonical [extraTimelineOverlaysProvider]/[timelineOverlayLayersProvider]
/// seam so the cocotb strip and any Pro-tier strip (SVA, future coverage)
/// route through the same registry. The host (`WaveformViewCenter`) reads
/// the unified [timelineOverlayLayersProvider], sorts by ascending
/// [priority], and mounts each layer's widget in order.
///
/// Priority `100` matches the historical paint order — the cocotb strip
/// sits directly below the time ruler, with higher-priority Pro layers
/// (SVA at `200`) painting closer to the waveform canvas. Height
/// `8` matches [cocotbTimelineOverlayHeight] so the layout-budget
/// reservation is unchanged from the pre-registry behavior.
class CocotbTimelineOverlayLayer extends TimelineOverlayLayer {
  const CocotbTimelineOverlayLayer();

  @override
  String get id => 'cocotb';

  @override
  int get priority => 100;

  @override
  double get height => cocotbTimelineOverlayHeight;

  @override
  Widget build(BuildContext context) => const CocotbTimelineOverlay();
}
