// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/plugins/timeline_overlay_layer.dart';

/// Open-core extension point through which the Pro overlay (or any future
/// open-core feature beyond the built-in cocotb strip) contributes
/// additional [TimelineOverlayLayer] instances to the strip painted between
/// the time ruler and the waveform canvas.
///
/// The host (`WaveformViewCenter`) does *not* read this provider directly.
/// Instead it watches [timelineOverlayLayersProvider], which combines the
/// open-core defaults (the cocotb log strip, registered through
/// `CocotbTimelineOverlayLayer`) with the layers returned here, and sorts
/// the unified list by ascending [TimelineOverlayLayer.priority]. The
/// open-core default of this provider is an empty list; Pro's
/// `proOverrides` replaces it with a list that includes the SVA assertion
/// overlay (and any future Pro-tier strips) — the cocotb layer remains
/// available regardless of whether Pro overrides this provider.
final extraTimelineOverlaysProvider = Provider<List<TimelineOverlayLayer>>(
  (_) => const [],
);
