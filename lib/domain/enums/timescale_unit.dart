// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The physical time unit used by the simulation timescale.
enum TimescaleUnit {
  femtoSeconds,
  picoSeconds,
  nanoSeconds,
  microSeconds,
  milliSeconds,
  seconds,
  unknown;

  /// The base-10 exponent that converts this unit to seconds.
  ///
  /// Returns `null` for [unknown].
  ///
  /// Examples: [nanoSeconds] → -9, [picoSeconds] → -12.
  int? get exponent => switch (this) {
    TimescaleUnit.femtoSeconds => -15,
    TimescaleUnit.picoSeconds => -12,
    TimescaleUnit.nanoSeconds => -9,
    TimescaleUnit.microSeconds => -6,
    TimescaleUnit.milliSeconds => -3,
    TimescaleUnit.seconds => 0,
    TimescaleUnit.unknown => null,
  };

  /// The abbreviated SI symbol used in display strings (e.g. `"ns"`, `"ps"`).
  String get symbol => switch (this) {
    TimescaleUnit.femtoSeconds => 'fs',
    TimescaleUnit.picoSeconds => 'ps',
    TimescaleUnit.nanoSeconds => 'ns',
    TimescaleUnit.microSeconds => 'µs',
    TimescaleUnit.milliSeconds => 'ms',
    TimescaleUnit.seconds => 's',
    TimescaleUnit.unknown => '?',
  };
}
