// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Determines how an analog signal trace is drawn between recorded data points.
enum AnalogInterpolation {
  /// Connect consecutive data points with straight lines.
  linear,

  /// Hold each value constant until the next recorded change (step function).
  stepHold,
}
