// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/var_direction.dart';

/// Coarse-grained port direction used for signal search filtering.
///
/// Maps from the more detailed [VarDirection] stored on [Variable]:
/// - [VarDirection.input] → [input]
/// - [VarDirection.output] → [output]
/// - [VarDirection.inout] → [inout]
/// - All other values (unknown, implicit, buffer, linkage) → [unknown]
enum SignalDirection {
  input,
  output,
  inout,
  unknown;

  /// Converts a [VarDirection] to the coarse-grained [SignalDirection].
  static SignalDirection fromVarDirection(VarDirection dir) => switch (dir) {
    VarDirection.input => SignalDirection.input,
    VarDirection.output => SignalDirection.output,
    VarDirection.inout => SignalDirection.inout,
    _ => SignalDirection.unknown,
  };
}
