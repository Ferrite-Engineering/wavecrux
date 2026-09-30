// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:wavecrux/domain/models/fsm_layout.dart';
import 'package:wavecrux/domain/models/fsm_model.dart';

/// Computes a 2D layout for an [FsmModel].
///
/// Uses a circular layout: states are placed on a circle inset from the
/// canvas edges. This is deterministic, predictable, avoids edge crossings
/// for small FSMs (≤ 8 states), and degrades gracefully to a single point
/// for trivial models.
///
/// Output coordinates are normalised to `[0, 1]`; the rendering layer is
/// responsible for scaling to pixel space and applying margins.
class FsmLayoutService {
  const FsmLayoutService();

  /// Default normalised radius. Leaves room for state circles drawn at
  /// pixel radius 30–50 without clipping at typical canvas sizes.
  static const double _defaultRadius = 0.38;

  /// Centre of the layout in normalised coordinates.
  static const double _centerX = 0.5;
  static const double _centerY = 0.5;

  /// Computes positions for every state in [model].
  FsmLayout compute(FsmModel model) {
    final states = model.states;
    if (states.isEmpty) {
      return const FsmLayout(positions: {});
    }

    if (states.length == 1) {
      return FsmLayout(
        positions: {
          states.first.id: const FsmStatePosition(
            stateId: '',
            x: _centerX,
            y: _centerY,
          ).copyWith(stateId: states.first.id),
        },
      );
    }

    // Place states uniformly on a circle. Start at the top (12 o'clock)
    // and proceed clockwise so the first state in numeric order appears
    // at the top — easy to read.
    final positions = <String, FsmStatePosition>{};
    final n = states.length;
    final radius = _radiusFor(n);

    for (var i = 0; i < n; i++) {
      // Angle θ measured clockwise from the top (−π/2 baseline).
      final theta = -math.pi / 2 + (2 * math.pi * i / n);
      final x = _centerX + radius * math.cos(theta);
      final y = _centerY + radius * math.sin(theta);
      positions[states[i].id] = FsmStatePosition(
        stateId: states[i].id,
        x: x,
        y: y,
      );
    }

    return FsmLayout(positions: positions);
  }

  /// Slightly enlarges the radius for FSMs with many states so node labels
  /// don't crowd. Capped to keep nodes inside the unit square.
  static double _radiusFor(int n) {
    if (n <= 4) return 0.30;
    if (n <= 8) return _defaultRadius;
    if (n <= 16) return 0.42;
    return 0.45;
  }
}
