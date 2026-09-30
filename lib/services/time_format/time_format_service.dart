// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

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

    final double absValue;
    final String unit;

    if (absSeconds >= 1.0) {
      absValue = absSeconds;
      unit = 's';
    } else if (absSeconds >= 1e-3) {
      absValue = absSeconds * 1e3;
      unit = 'ms';
    } else if (absSeconds >= 1e-6) {
      absValue = absSeconds * 1e6;
      unit = 'µs';
    } else if (absSeconds >= 1e-9) {
      absValue = absSeconds * 1e9;
      unit = 'ns';
    } else if (absSeconds >= 1e-12) {
      absValue = absSeconds * 1e12;
      unit = 'ps';
    } else {
      absValue = absSeconds * 1e15;
      unit = 'fs';
    }

    return '$sign${_formatValue(absValue)} $unit';
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
