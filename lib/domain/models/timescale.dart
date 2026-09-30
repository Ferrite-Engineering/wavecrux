// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' show pow;

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';

/// The simulation timescale: one tick = [factor] × [unit].
///
/// For example, a 1 ns timescale is `Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds)`.
@immutable
class Timescale {
  const Timescale({required this.factor, required this.unit});

  /// The numeric multiplier (typically 1, 10, or 100).
  final int factor;

  /// The physical time unit.
  final TimescaleUnit unit;

  // ── computed ───────────────────────────────────────────────────────────────

  /// Human-readable representation, e.g. `"1ns"`, `"10ps"`, `"100µs"`.
  String get displayString => '$factor${unit.symbol}';

  /// Duration of one simulation tick in seconds.
  ///
  /// Returns `null` when [unit] is [TimescaleUnit.unknown].
  double? get secondsPerTick {
    final exp = unit.exponent;
    if (exp == null) return null;
    return factor * pow(10.0, exp).toDouble();
  }

  // ── copyWith ───────────────────────────────────────────────────────────────

  Timescale copyWith({int? factor, TimescaleUnit? unit}) =>
      Timescale(factor: factor ?? this.factor, unit: unit ?? this.unit);

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Timescale &&
          runtimeType == other.runtimeType &&
          factor == other.factor &&
          unit == other.unit;

  @override
  int get hashCode => Object.hash(factor, unit);

  @override
  String toString() => 'Timescale($displayString)';
}
