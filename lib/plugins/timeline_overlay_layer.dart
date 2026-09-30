// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// Open-core extension point for additional, fixed-height strips painted
/// between the time ruler and the waveform canvas.
///
/// The cocotb log overlay (`CocotbTimelineOverlay`) is the original example
/// of such a strip — a thin, severity-coloured marker band that lights up
/// at every loaded log entry's timestamp. SVA assertion visualization (Pro
/// tier) and any future timeline-correlated overlay (FSM trace events,
/// coverage hits, breakpoint markers) plug into the host the same way:
/// each layer reserves a fixed [height] of vertical space, exposes a
/// [build] entry point that returns the widget the host will mount, and
/// declares an integer [priority] that controls vertical paint order — the
/// host sorts by ascending [priority] so larger-priority layers appear
/// closer to the waveform canvas.
///
/// Layers are registered through [extraTimelineOverlaysProvider]. The
/// open-core default is an empty list; the Pro overlay's `proOverrides`
/// contributes its own implementations (e.g. an SVA assertion strip) so
/// they appear above the cocotb strip without forking
/// `WaveformViewCenter`. Per `wavecrux/CLAUDE.md` §"Extension Points",
/// adding a new strip first lands the open-core seam, *then* the Pro
/// implementation registers through it.
@immutable
abstract class TimelineOverlayLayer {
  /// Subclasses opt in to const construction.
  const TimelineOverlayLayer();

  /// Stable identifier (e.g. `"sva"`, `"coverage"`). Used for telemetry,
  /// tests, and debugging. Must be unique across all registered layers.
  String get id;

  /// Vertical paint order. Lower paints higher (closer to the time ruler);
  /// higher paints lower (closer to the waveform canvas). Open-core
  /// reserves the cocotb strip at an implicit priority of 100; new layers
  /// should pick a value with room to interleave (e.g. SVA at 200).
  int get priority;

  /// Logical pixels of vertical space the layer reserves between the time
  /// ruler and the waveform canvas. The host adds this to the layout
  /// budget; layers should keep this small (≤ 16 dp) so the canvas stays
  /// usable on narrow windows.
  double get height;

  /// Builds the widget the host mounts at the reserved height. The widget
  /// is responsible for its own painting, hit-testing, and Riverpod
  /// subscriptions — the host does not wrap it in [IgnorePointer], so a
  /// layer that wants tap-through behaviour must wrap itself.
  Widget build(BuildContext context);
}
