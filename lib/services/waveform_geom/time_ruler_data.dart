// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// A single mark on the time ruler.
@immutable
class TickMark {
  const TickMark({
    required this.x,
    required this.time,
    required this.isMajor,
    this.label,
  });

  /// Pixel x-position within the viewport.
  final double x;

  /// Simulation time in ticks.
  final int time;

  /// Whether this is a labeled major tick (as opposed to an unlabeled minor).
  final bool isMajor;

  /// Human-readable time label; present only on major ticks.
  final String? label;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TickMark &&
        other.x == x &&
        other.time == time &&
        other.isMajor == isMajor &&
        other.label == label;
  }

  @override
  int get hashCode => Object.hash(x, time, isMajor, label);

  @override
  String toString() =>
      'TickMark(x: $x, time: $time, isMajor: $isMajor, label: $label)';
}

/// Pre-computed tick marks for the time ruler at the current zoom level.
///
/// Obtain via [TimeRulerData.compute]; consumed by the ruler painter.
@immutable
class TimeRulerData {
  // Primary constructor before factory (sort_constructors_first).
  const TimeRulerData(this.ticks);

  /// Computes tick marks for [mapper] at the given [viewportWidth].
  ///
  /// An optional [timescale] is forwarded to [TimeFormatService] so that
  /// major-tick labels show human-readable time strings.
  factory TimeRulerData.compute(
    TimeMapper mapper,
    double viewportWidth, {
    Timescale? timescale,
  }) {
    if (mapper.isEmpty || viewportWidth <= 0) {
      return const TimeRulerData(<TickMark>[]);
    }
    if (mapper.visibleRange <= 0) return const TimeRulerData(<TickMark>[]);

    final formatter = TimeFormatService(timescale: timescale);
    final majorInterval = niceInterval(mapper.visibleRange / targetMajorTicks);
    final minorInterval = _minorInterval(majorInterval);

    final marks = <TickMark>[];

    // Minor ticks (no labels).
    if (minorInterval > 0) {
      var t = _floorDiv(mapper.visibleStartTime, minorInterval) * minorInterval;
      while (t <= mapper.visibleEndTime + minorInterval) {
        if (t % majorInterval != 0) {
          final x = mapper.timeToPixel(t);
          if (x >= -1 && x <= viewportWidth + 1) {
            marks.add(TickMark(x: x, time: t, isMajor: false));
          }
        }
        t += minorInterval;
      }
    }

    // Major ticks (with labels).
    var t = _floorDiv(mapper.visibleStartTime, majorInterval) * majorInterval;
    while (t <= mapper.visibleEndTime + majorInterval) {
      final x = mapper.timeToPixel(t);
      if (x >= -1 && x <= viewportWidth + 1) {
        marks.add(
          TickMark(
            x: x,
            time: t,
            isMajor: true,
            label: formatter.format(t),
          ),
        );
      }
      t += majorInterval;
    }

    marks.sort((a, b) => a.x.compareTo(b.x));
    return TimeRulerData(List<TickMark>.unmodifiable(marks));
  }

  // ── fields ─────────────────────────────────────────────────────────────────

  final List<TickMark> ticks;

  // ── constants ──────────────────────────────────────────────────────────────

  /// Target number of major ticks visible across the viewport.
  static const int targetMajorTicks = 8;

  // ── tick interval utilities ────────────────────────────────────────────────

  /// Returns the smallest "nice" tick interval ≥ [raw].
  ///
  /// "Nice" intervals follow the sequence 1×10^n, 2×10^n, 5×10^n.
  /// The minimum returned value is 1 (simulation time is integer).
  static int niceInterval(double raw) {
    if (raw <= 0) return 1;
    final exp = (math.log(raw) / math.ln10).floor();
    final magnitude = math.pow(10.0, exp) as double;
    final normalized = raw / magnitude;

    final double niceNormalized;
    if (normalized <= 1.0) {
      niceNormalized = 1.0;
    } else if (normalized <= 2.0) {
      niceNormalized = 2.0;
    } else if (normalized <= 5.0) {
      niceNormalized = 5.0;
    } else {
      niceNormalized = 10.0;
    }

    return math.max(1, (niceNormalized * magnitude).round());
  }

  /// Returns the minor tick interval for a given [majorInterval].
  ///
  /// Produces 5 subdivisions for multiples of 5, 2 subdivisions for multiples
  /// of 2, 1 subdivision otherwise, and 0 (no minor ticks) for interval = 1.
  static int _minorInterval(int majorInterval) {
    if (majorInterval <= 1) return 0;
    if (majorInterval % 5 == 0) return majorInterval ~/ 5;
    if (majorInterval.isEven) return majorInterval ~/ 2;
    return 1;
  }

  /// Floor division that rounds toward negative infinity (handles negative [a]).
  static int _floorDiv(int a, int b) {
    assert(b > 0, 'divisor must be positive');
    return (a / b.toDouble()).floor();
  }
}
