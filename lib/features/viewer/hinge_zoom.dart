// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

/// Hinge travel that doubles (or halves) the zoom.
///
/// About a third of the comfortable laptop range (roughly 70° to 150°), so a
/// deliberate tilt moves a few octaves and a hand resting on the hinge moves
/// nothing visible.
const double kHingeZoomDegreesPerDoubling = 15;

/// Hinge movement ignored as noise. Below this the reference angle is kept,
/// so slow drift accumulates until it is a real tilt instead of being lost.
const double kHingeZoomDeadbandDegrees = 2;

/// One hinge-zoom step from the reference angle [from] to [to], in degrees.
///
/// Returns null while the movement is inside [kHingeZoomDeadbandDegrees]
/// (keep the reference). Otherwise returns the zoom factor (> 1) and its
/// direction: closing the screen towards the viewer (the angle shrinks) zooms
/// in, as leaning in to look closer does; opening it zooms out.
({double factor, bool zoomIn})? hingeZoomStep(double from, double to) {
  final delta = to - from;
  if (delta.abs() < kHingeZoomDeadbandDegrees) return null;
  final factor = math
      .pow(2, delta.abs() / kHingeZoomDegreesPerDoubling)
      .toDouble();
  return (factor: factor, zoomIn: delta < 0);
}
