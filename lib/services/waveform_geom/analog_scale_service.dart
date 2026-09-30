// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A computed Y-axis scale for one analog signal lane.
///
/// Maps floating-point signal values to pixel Y coordinates within a lane.
/// Oscilloscope convention: higher values are at the *top* of the lane
/// (smaller Y), lower values at the *bottom* (larger Y).
///
/// Obtain via [AnalogScaleService.computeAutoScale] or
/// [AnalogScaleService.computeManualScale].
@immutable
class AnalogScale {
  const AnalogScale({
    required this.displayMin,
    required this.displayMax,
    required this.ticks,
  });

  /// Signal value that maps to the bottom edge of the lane.
  final double displayMin;

  /// Signal value that maps to the top edge of the lane.
  final double displayMax;

  /// Nice gridline tick values within [displayMin]..[displayMax].
  final List<double> ticks;

  /// True when the scale covers a non-zero range.
  bool get hasRange => displayMax > displayMin;

  /// Converts [value] to a pixel Y coordinate within the lane's
  /// [top]..[bottom] bounds.
  ///
  /// Values outside [displayMin]..[displayMax] are clamped to the lane edges.
  double valueToY(double value, double top, double bottom) {
    if (!hasRange) return (top + bottom) / 2;
    final fraction = ((value - displayMin) / (displayMax - displayMin)).clamp(
      0.0,
      1.0,
    );
    // fraction 0.0 → bottom of lane, fraction 1.0 → top of lane.
    return bottom - fraction * (bottom - top);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AnalogScale) return false;
    if (other.displayMin != displayMin || other.displayMax != displayMax) {
      return false;
    }
    if (other.ticks.length != ticks.length) return false;
    for (var i = 0; i < ticks.length; i++) {
      if (other.ticks[i] != ticks[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(displayMin, displayMax, Object.hashAll(ticks));

  @override
  String toString() =>
      'AnalogScale(min: $displayMin, max: $displayMax, ticks: $ticks)';
}

/// Computes Y-axis scales for analog (real-valued) signal lanes.
///
/// Usage:
/// ```dart
/// final scale = AnalogScaleService.computeAutoScale(values);
/// final y = scale.valueToY(3.14, laneBounds.top + 4, laneBounds.bottom - 4);
/// ```
abstract final class AnalogScaleService {
  /// Padding added above and below the data min/max when auto-ranging.
  static const double paddingFraction = 0.10;

  /// Computes a scale from the data [values], adding [paddingFraction] × range
  /// of vertical padding above and below the min/max.
  ///
  /// NaN and infinite values are excluded from the range calculation.
  /// If [values] is empty or contains only non-finite values, falls back to
  /// a ±1 default scale.
  static AnalogScale computeAutoScale(Iterable<double> values) {
    final finite = values.where((v) => v.isFinite).toList();

    if (finite.isEmpty) {
      return AnalogScale(
        displayMin: -1,
        displayMax: 1,
        ticks: niceTickValues(-1, 1),
      );
    }

    var minVal = finite.reduce(math.min);
    var maxVal = finite.reduce(math.max);

    if (minVal == maxVal) {
      // Single constant value — expand symmetrically.
      final delta = minVal == 0 ? 1.0 : minVal.abs();
      minVal -= delta;
      maxVal += delta;
    } else {
      final padding = (maxVal - minVal) * paddingFraction;
      minVal -= padding;
      maxVal += padding;
    }

    return AnalogScale(
      displayMin: minVal,
      displayMax: maxVal,
      ticks: niceTickValues(minVal, maxVal),
    );
  }

  /// Computes a scale using explicit [min] and [max] values (no padding added).
  ///
  /// Falls back to a ±1 default if [min] >= [max] or either value is
  /// non-finite.
  static AnalogScale computeManualScale(double min, double max) {
    if (!min.isFinite || !max.isFinite || min >= max) {
      return AnalogScale(
        displayMin: -1,
        displayMax: 1,
        ticks: niceTickValues(-1, 1),
      );
    }
    return AnalogScale(
      displayMin: min,
      displayMax: max,
      ticks: niceTickValues(min, max),
    );
  }

  /// Returns "nice" tick values spanning [min]..[max].
  ///
  /// Targets approximately 4–5 evenly spaced ticks.  Intervals are always
  /// multiples of 1, 2, or 5 × 10^n so that labels are round numbers.
  static List<double> niceTickValues(double min, double max) {
    final range = max - min;
    if (range <= 0 || !range.isFinite) return [];

    const targetTicks = 4;
    final raw = range / targetTicks;
    final exp = (math.log(raw) / math.ln10).floor();
    final magnitude = math.pow(10.0, exp) as double;
    final normalized = raw / magnitude;

    final double niceNorm;
    if (normalized <= 1.5) {
      niceNorm = 1.0;
    } else if (normalized <= 3.0) {
      niceNorm = 2.0;
    } else if (normalized <= 7.0) {
      niceNorm = 5.0;
    } else {
      niceNorm = 10.0;
    }

    final interval = niceNorm * magnitude;

    // First tick >= min (using ceiling division to avoid fp overshoot).
    final first = (min / interval).ceil() * interval;
    final ticks = <double>[];
    var v = first;
    // Small epsilon avoids fp rounding from adding/dropping a boundary tick.
    final eps = interval * 1e-9;
    while (v <= max + eps) {
      ticks.add(v);
      v += interval;
    }
    return ticks;
  }
}
