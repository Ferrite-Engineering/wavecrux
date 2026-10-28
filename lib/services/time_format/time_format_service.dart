// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/timescale.dart';

/// Formats simulation time tick counts as human-readable strings with
/// auto-scaling SI unit prefixes.
///
/// Example (1 ns timescale):
/// - `format(1500)` → `"1.5 µs"`
/// - `format(1_000_000_000)` → `"1 s"`
/// - `formatDelta(0, 500)` → `"500 ns"`
///
/// When no [timescale] is available, raw tick counts are returned (e.g.
/// `"1500 ticks"`).
@immutable
class TimeFormatService {
  const TimeFormatService({this.timescale});

  /// The simulation timescale used to convert ticks to SI time.
  ///
  /// When null, or when the unit is [TimescaleUnit.unknown], formatted strings
  /// fall back to raw tick counts.
  final Timescale? timescale;

  /// Formats [ticks] as a human-readable time string.
  ///
  /// Returns `"$ticks ticks"` when no timescale is available.
  String format(int ticks) {
    final spt = timescale?.secondsPerTick;
    if (spt == null) return '$ticks ticks';
    if (ticks == 0) return '0 ${timescale!.unit.symbol}';
    return _formatSeconds(ticks.toDouble() * spt);
  }

  /// Formats [ticks] as a ruler label for ticks [interval] apart: the unit
  /// as [format] picks it, with as many decimals as the interval needs in
  /// that unit, so neighbouring labels always differ (74.60 µs, 74.62 µs,
  /// not 74.6 µs twice). Every label of one interval gets the same number of
  /// decimals, trailing zeros kept.
  ///
  /// Returns `"$ticks ticks"` when no timescale is available.
  String formatTick(int ticks, {required int interval}) {
    final spt = timescale?.secondsPerTick;
    if (spt == null) return '$ticks ticks';
    if (ticks == 0) return '0 ${timescale!.unit.symbol}';
    final seconds = ticks.toDouble() * spt;
    final (:scale, :unit) = _unitFor(seconds.abs());
    final step = interval.abs().toDouble() * spt * scale;
    final value = seconds.abs() * scale;
    final decimals = _decimalsFor(step);
    final sign = seconds < 0 ? '-' : '';
    if (decimals == null) return '$sign${_formatValue(value)} $unit';
    return '$sign${value.toStringAsFixed(decimals)} $unit';
  }

  /// The decimals that tell values [step] apart, or null for a step of one
  /// unit or more (the significant-figure rule is enough there). A step is
  /// 1, 2 or 5 times a power of ten, so the power's decimals suffice.
  static int? _decimalsFor(double step) {
    if (step <= 0 || step >= 1) return null;
    // A small epsilon: 0.1 is not exactly representable, and log10 of a
    // value a hair below it must not ask for a second decimal.
    return (-(math.log(step) / math.ln10) - 1e-9).ceil();
  }

  /// Formats the absolute time difference between [ticksA] and [ticksB].
  ///
  /// The result is always non-negative. Returns `"0 [unit]"` when equal.
  String formatDelta(int ticksA, int ticksB) {
    final spt = timescale?.secondsPerTick;
    final deltaTicks = (ticksB - ticksA).abs();
    if (spt == null) return '$deltaTicks ticks';
    if (deltaTicks == 0) return '0 ${timescale!.unit.symbol}';
    return _formatSeconds(deltaTicks.toDouble() * spt);
  }

  // ── private helpers ────────────────────────────────────────────────────────

  static String _formatSeconds(double seconds) {
    final sign = seconds < 0 ? '-' : '';
    final absSeconds = seconds.abs();
    final (:scale, :unit) = _unitFor(absSeconds);
    return '$sign${_formatValue(absSeconds * scale)} $unit';
  }

  /// The SI unit for a time of [absSeconds], and the factor from seconds to
  /// it.
  static ({double scale, String unit}) _unitFor(double absSeconds) {
    if (absSeconds >= 1.0) return (scale: 1, unit: 's');
    if (absSeconds >= 1e-3) return (scale: 1e3, unit: 'ms');
    if (absSeconds >= 1e-6) return (scale: 1e6, unit: 'µs');
    if (absSeconds >= 1e-9) return (scale: 1e9, unit: 'ns');
    if (absSeconds >= 1e-12) return (scale: 1e12, unit: 'ps');
    return (scale: 1e15, unit: 'fs');
  }

  /// Formats [value] with up to 3 significant figures, stripping trailing zeros.
  static String _formatValue(double value) {
    final int decimalPlaces;
    if (value >= 100.0) {
      decimalPlaces = 0;
    } else if (value >= 10.0) {
      decimalPlaces = 1;
    } else {
      decimalPlaces = 2;
    }

    final fixed = value.toStringAsFixed(decimalPlaces);
    if (decimalPlaces == 0) return fixed;

    // Strip trailing fractional zeros ("1.50" → "1.5", "1.00" → "1").
    var result = fixed;
    while (result.endsWith('0')) {
      result = result.substring(0, result.length - 1);
    }
    if (result.endsWith('.')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
