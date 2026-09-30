// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/waveform_geom/analog_scale_service.dart';

void main() {
  // Tolerance for floating-point comparisons.
  const eps = 1e-9;

  group('AnalogScale.valueToY', () {
    const scale = AnalogScale(
      displayMin: 0,
      displayMax: 10,
      ticks: [],
    );
    const top = 4.0;
    const bottom = 26.0; // lane height 30, vMargin 4

    test('min value maps to bottom', () {
      expect(scale.valueToY(0, top, bottom), closeTo(bottom, eps));
    });

    test('max value maps to top', () {
      expect(scale.valueToY(10, top, bottom), closeTo(top, eps));
    });

    test('midpoint maps to vertical centre', () {
      expect(scale.valueToY(5, top, bottom), closeTo((top + bottom) / 2, eps));
    });

    test('value below min is clamped to bottom', () {
      expect(scale.valueToY(-5, top, bottom), closeTo(bottom, eps));
    });

    test('value above max is clamped to top', () {
      expect(scale.valueToY(20, top, bottom), closeTo(top, eps));
    });

    test('no-range scale returns lane centre', () {
      const flat = AnalogScale(displayMin: 5, displayMax: 5, ticks: []);
      expect(flat.valueToY(5, top, bottom), closeTo((top + bottom) / 2, eps));
    });

    test('negative range [−10, 0]: min maps to bottom', () {
      const neg = AnalogScale(displayMin: -10, displayMax: 0, ticks: []);
      expect(neg.valueToY(-10, top, bottom), closeTo(bottom, eps));
      expect(neg.valueToY(0, top, bottom), closeTo(top, eps));
    });
  });

  group('AnalogScaleService.computeAutoScale', () {
    test('empty input returns default ±1 scale', () {
      final scale = AnalogScaleService.computeAutoScale([]);
      expect(scale.displayMin, equals(-1));
      expect(scale.displayMax, equals(1));
    });

    test('only NaN/infinite values returns default ±1 scale', () {
      final scale = AnalogScaleService.computeAutoScale([
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]);
      expect(scale.displayMin, equals(-1));
      expect(scale.displayMax, equals(1));
    });

    test('single finite value expands symmetrically', () {
      final scale = AnalogScaleService.computeAutoScale([5.0]);
      expect(scale.displayMin, closeTo(0, eps));
      expect(scale.displayMax, closeTo(10, eps));
    });

    test('single zero value expands to [-1, 1]', () {
      final scale = AnalogScaleService.computeAutoScale([0.0]);
      expect(scale.displayMin, closeTo(-1, eps));
      expect(scale.displayMax, closeTo(1, eps));
    });

    test('range [0, 10] gets 10% padding each side → [-1, 11]', () {
      final scale = AnalogScaleService.computeAutoScale([0.0, 10.0]);
      expect(scale.displayMin, closeTo(-1, eps));
      expect(scale.displayMax, closeTo(11, eps));
    });

    test('NaN values are excluded from range calculation', () {
      final scale = AnalogScaleService.computeAutoScale([
        double.nan,
        0.0,
        double.nan,
        10.0,
        double.nan,
      ]);
      expect(scale.displayMin, closeTo(-1, eps));
      expect(scale.displayMax, closeTo(11, eps));
    });

    test('displayMin < displayMax for a valid range', () {
      final scale = AnalogScaleService.computeAutoScale([-5.0, 5.0]);
      expect(scale.displayMin, lessThan(scale.displayMax));
    });

    test('ticks are non-empty for a valid range', () {
      final scale = AnalogScaleService.computeAutoScale([0.0, 10.0]);
      expect(scale.ticks, isNotEmpty);
    });

    test('all ticks fall within [displayMin, displayMax]', () {
      final scale = AnalogScaleService.computeAutoScale([0.0, 10.0]);
      for (final t in scale.ticks) {
        expect(t, greaterThanOrEqualTo(scale.displayMin - eps));
        expect(t, lessThanOrEqualTo(scale.displayMax + eps));
      }
    });

    test('identical min/max values expand range', () {
      final scale = AnalogScaleService.computeAutoScale([3.0, 3.0]);
      expect(scale.displayMin, lessThan(scale.displayMax));
    });

    test('very small values (picosecond range)', () {
      final scale = AnalogScaleService.computeAutoScale([0.0, 1e-12]);
      expect(scale.displayMin, lessThan(scale.displayMax));
      expect(scale.ticks, isNotEmpty);
    });

    test('very large values (mega range)', () {
      final scale = AnalogScaleService.computeAutoScale([0.0, 1e6]);
      expect(scale.displayMin, lessThan(scale.displayMax));
      expect(scale.ticks, isNotEmpty);
    });

    test('negative range [-10, -1] stays negative', () {
      final scale = AnalogScaleService.computeAutoScale([-10.0, -1.0]);
      expect(scale.displayMin, lessThan(-1));
      expect(scale.displayMax, greaterThan(-10));
    });
  });

  group('AnalogScaleService.computeManualScale', () {
    test('valid [0, 5] range preserved exactly', () {
      final scale = AnalogScaleService.computeManualScale(0, 5);
      expect(scale.displayMin, equals(0));
      expect(scale.displayMax, equals(5));
    });

    test('inverted range (min >= max) falls back to ±1', () {
      final scale = AnalogScaleService.computeManualScale(5, 0);
      expect(scale.displayMin, equals(-1));
      expect(scale.displayMax, equals(1));
    });

    test('equal min/max falls back to ±1', () {
      final scale = AnalogScaleService.computeManualScale(3, 3);
      expect(scale.displayMin, equals(-1));
      expect(scale.displayMax, equals(1));
    });

    test('non-finite min falls back to ±1', () {
      final scale = AnalogScaleService.computeManualScale(double.nan, 5);
      expect(scale.displayMin, equals(-1));
      expect(scale.displayMax, equals(1));
    });

    test('non-finite max falls back to ±1', () {
      final scale = AnalogScaleService.computeManualScale(0, double.infinity);
      expect(scale.displayMin, equals(-1));
      expect(scale.displayMax, equals(1));
    });

    test('ticks fall within [min, max]', () {
      final scale = AnalogScaleService.computeManualScale(-2, 2);
      for (final t in scale.ticks) {
        expect(t, greaterThanOrEqualTo(scale.displayMin - eps));
        expect(t, lessThanOrEqualTo(scale.displayMax + eps));
      }
    });
  });

  group('AnalogScaleService.niceTickValues', () {
    test('returns empty for zero range', () {
      expect(AnalogScaleService.niceTickValues(5, 5), isEmpty);
    });

    test('returns empty for inverted range', () {
      expect(AnalogScaleService.niceTickValues(10, 0), isEmpty);
    });

    test('ticks are monotonically increasing', () {
      final ticks = AnalogScaleService.niceTickValues(-10, 10);
      for (var i = 1; i < ticks.length; i++) {
        expect(ticks[i], greaterThan(ticks[i - 1]));
      }
    });

    test('[-1, 1] includes zero', () {
      final ticks = AnalogScaleService.niceTickValues(-1, 1);
      expect(
        ticks.any((t) => t.abs() < eps),
        isTrue,
        reason: 'expected zero tick in [-1, 1]',
      );
    });

    test('[0, 10] starts at 0', () {
      final ticks = AnalogScaleService.niceTickValues(0, 10);
      expect(ticks.first, closeTo(0, eps));
    });

    test('produces approximately 4–6 ticks for typical ranges', () {
      for (final range in [
        (0.0, 1.0),
        (0.0, 100.0),
        (-5.0, 5.0),
        (-1e-3, 1e-3),
        (0.0, 1e6),
      ]) {
        final ticks = AnalogScaleService.niceTickValues(range.$1, range.$2);
        expect(
          ticks.length,
          greaterThanOrEqualTo(2),
          reason: 'too few ticks for range $range',
        );
        expect(
          ticks.length,
          lessThanOrEqualTo(8),
          reason: 'too many ticks for range $range',
        );
      }
    });

    test('interval is a multiple of 1, 2, or 5 × 10^n', () {
      final ticks = AnalogScaleService.niceTickValues(0, 10);
      if (ticks.length >= 2) {
        final interval = ticks[1] - ticks[0];
        final exp = (math.log(interval.abs()) / math.ln10).round();
        final magnitude = math.pow(10.0, exp) as double;
        final normalized = interval / magnitude;
        expect(
          [1.0, 2.0, 5.0, 10.0].any((n) => (n - normalized).abs() < 0.01),
          isTrue,
          reason: 'interval $interval is not a nice value',
        );
      }
    });
  });

  group('AnalogScale equality', () {
    test('identical instances are equal', () {
      const a = AnalogScale(displayMin: 0, displayMax: 10, ticks: [0, 5, 10]);
      const b = AnalogScale(displayMin: 0, displayMax: 10, ticks: [0, 5, 10]);
      expect(a, equals(b));
    });

    test('different displayMin are not equal', () {
      const a = AnalogScale(displayMin: 0, displayMax: 10, ticks: []);
      const b = AnalogScale(displayMin: 1, displayMax: 10, ticks: []);
      expect(a, isNot(equals(b)));
    });

    test('different tick lists are not equal', () {
      const a = AnalogScale(displayMin: 0, displayMax: 10, ticks: [0, 5]);
      const b = AnalogScale(displayMin: 0, displayMax: 10, ticks: [0, 10]);
      expect(a, isNot(equals(b)));
    });

    test('equal instances have same hashCode', () {
      const a = AnalogScale(displayMin: 0, displayMax: 10, ticks: [0, 5, 10]);
      const b = AnalogScale(displayMin: 0, displayMax: 10, ticks: [0, 5, 10]);
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
