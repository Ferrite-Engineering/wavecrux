// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';
import 'package:wavecrux/services/waveform_geom/time_ruler_data.dart';

void main() {
  group('TimeRulerData', () {
    // ── empty / degenerate cases ──────────────────────────────────────────────

    group('compute — empty/degenerate', () {
      test('empty mapper returns no ticks', () {
        final ruler = TimeRulerData.compute(TimeMapper.empty(), 1000);
        expect(ruler.ticks, isEmpty);
      });

      test('zero viewport width returns no ticks', () {
        final mapper = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 1000,
        );
        final ruler = TimeRulerData.compute(mapper, 0);
        expect(ruler.ticks, isEmpty);
      });

      test('zero-range mapper returns no ticks', () {
        final mapper = TimeMapper.fitAll(
          startTime: 500,
          endTime: 500,
          viewportWidth: 1000,
        );
        final ruler = TimeRulerData.compute(mapper, 1000);
        expect(ruler.ticks, isEmpty);
      });
    });

    // ── major ticks ───────────────────────────────────────────────────────────

    group('compute — major ticks', () {
      test('produces roughly targetMajorTicks major ticks', () {
        final mapper = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 1000,
        );
        final major = TimeRulerData.compute(
          mapper,
          1000,
        ).ticks.where((t) => t.isMajor).toList();
        expect(major.length, greaterThanOrEqualTo(4));
        expect(major.length, lessThanOrEqualTo(16));
      });

      test('every major tick has a non-null, non-empty label', () {
        final mapper = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 1000,
        );
        final ruler = TimeRulerData.compute(mapper, 1000);
        for (final tick in ruler.ticks.where((t) => t.isMajor)) {
          expect(tick.label, isNotNull);
          expect(tick.label, isNotEmpty);
        }
      });

      test('major ticks are evenly spaced in time', () {
        final mapper = TimeMapper.fitAll(
          startTime: 0,
          endTime: 100,
          viewportWidth: 1000,
        );
        final major = TimeRulerData.compute(
          mapper,
          1000,
        ).ticks.where((t) => t.isMajor).toList();
        if (major.length >= 3) {
          final interval = major[1].time - major[0].time;
          for (var i = 2; i < major.length; i++) {
            expect(major[i].time - major[i - 1].time, equals(interval));
          }
        }
      });

      test('major tick times are multiples of the computed interval', () {
        final mapper = TimeMapper.fitAll(
          startTime: 0,
          endTime: 100,
          viewportWidth: 1000,
        );
        final major = TimeRulerData.compute(
          mapper,
          1000,
        ).ticks.where((t) => t.isMajor).toList();
        if (major.length >= 2) {
          final interval = major[1].time - major[0].time;
          for (final tick in major) {
            expect(tick.time % interval, equals(0));
          }
        }
      });
    });

    // ── minor ticks ───────────────────────────────────────────────────────────

    group('compute — minor ticks', () {
      test('minor ticks have null labels', () {
        final mapper = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 1000,
        );
        final ruler = TimeRulerData.compute(mapper, 1000);
        for (final tick in ruler.ticks.where((t) => !t.isMajor)) {
          expect(tick.label, isNull);
        }
      });

      test('minor tick times are not at major tick positions', () {
        final mapper = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 1000,
        );
        final ruler = TimeRulerData.compute(mapper, 1000);
        final majorTimes = ruler.ticks
            .where((t) => t.isMajor)
            .map((t) => t.time)
            .toSet();
        for (final tick in ruler.ticks.where((t) => !t.isMajor)) {
          expect(majorTimes.contains(tick.time), isFalse);
        }
      });
    });

    // ── ordering and pixel positions ──────────────────────────────────────────

    group('compute — ordering', () {
      test('ticks are sorted ascending by x position', () {
        final mapper = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 1000,
        );
        final ruler = TimeRulerData.compute(mapper, 1000);
        for (var i = 1; i < ruler.ticks.length; i++) {
          expect(ruler.ticks[i].x, greaterThanOrEqualTo(ruler.ticks[i - 1].x));
        }
      });

      test('tick x matches mapper.timeToPixel for that time', () {
        final mapper = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 1000,
        );
        final ruler = TimeRulerData.compute(mapper, 1000);
        for (final tick in ruler.ticks) {
          expect(tick.x, closeTo(mapper.timeToPixel(tick.time), 0.001));
        }
      });

      test('all ticks are within or 1 px outside the viewport', () {
        final mapper = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 1000,
        );
        final ruler = TimeRulerData.compute(mapper, 1000);
        for (final tick in ruler.ticks) {
          expect(tick.x, greaterThanOrEqualTo(-1));
          expect(tick.x, lessThanOrEqualTo(1001));
        }
      });
    });

    // ── labels use TimeFormatService ──────────────────────────────────────────

    group('compute — label formatting', () {
      test('without timescale, major labels contain "ticks"', () {
        final mapper = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 1000,
        );
        final ruler = TimeRulerData.compute(mapper, 1000);
        for (final tick in ruler.ticks.where((t) => t.isMajor)) {
          expect(tick.label, contains('ticks'));
        }
      });

      test('with ns timescale, major labels contain a time unit symbol', () {
        final mapper = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 1000,
        );
        const ts = Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);
        final ruler = TimeRulerData.compute(mapper, 1000, timescale: ts);
        for (final tick in ruler.ticks.where((t) => t.isMajor)) {
          final hasUnit =
              tick.label!.contains('ns') ||
              tick.label!.contains('µs') ||
              tick.label!.contains('ms') ||
              tick.label!.contains(' s');
          expect(
            hasUnit,
            isTrue,
            reason: 'label "${tick.label}" lacks a SI time unit',
          );
        }
      });
    });

    // ── zoom-level consistency ────────────────────────────────────────────────

    group('compute — zoom level', () {
      test('zoomed in uses a finer major tick interval', () {
        final base = TimeMapper.fitAll(
          startTime: 0,
          endTime: 10000,
          viewportWidth: 1000,
        );
        final zoomed = base.zoomAround(500, 10);
        final baseInterval = _majorInterval(TimeRulerData.compute(base, 1000));
        final zoomedInterval = _majorInterval(
          TimeRulerData.compute(zoomed, 1000),
        );
        expect(zoomedInterval, lessThanOrEqualTo(baseInterval));
      });

      test('zoomed out uses a coarser major tick interval', () {
        final base = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 1000,
        );
        final zoomedOut = base.zoomAround(500, 0.1);
        final baseInterval = _majorInterval(TimeRulerData.compute(base, 1000));
        final zoomedOutInterval = _majorInterval(
          TimeRulerData.compute(zoomedOut, 1000),
        );
        expect(zoomedOutInterval, greaterThanOrEqualTo(baseInterval));
      });
    });

    // ── niceInterval ─────────────────────────────────────────────────────────

    group('niceInterval', () {
      test('raw <= 0 returns 1', () {
        expect(TimeRulerData.niceInterval(0), equals(1));
        expect(TimeRulerData.niceInterval(-5), equals(1));
      });

      test('raw < 1 returns 1 (minimum interval is 1 tick)', () {
        expect(TimeRulerData.niceInterval(0.001), equals(1));
        expect(TimeRulerData.niceInterval(0.9), equals(1));
      });

      test(
        'raw = 1 → 1',
        () => expect(TimeRulerData.niceInterval(1), equals(1)),
      );
      test(
        'raw = 1.5 → 2',
        () => expect(TimeRulerData.niceInterval(1.5), equals(2)),
      );
      test(
        'raw = 2 → 2',
        () => expect(TimeRulerData.niceInterval(2), equals(2)),
      );
      test(
        'raw = 3 → 5',
        () => expect(TimeRulerData.niceInterval(3), equals(5)),
      );
      test(
        'raw = 5 → 5',
        () => expect(TimeRulerData.niceInterval(5), equals(5)),
      );
      test(
        'raw = 7 → 10',
        () => expect(TimeRulerData.niceInterval(7), equals(10)),
      );
      test(
        'raw = 10 → 10',
        () => expect(TimeRulerData.niceInterval(10), equals(10)),
      );
      test(
        'raw = 15 → 20',
        () => expect(TimeRulerData.niceInterval(15), equals(20)),
      );
      test(
        'raw = 30 → 50',
        () => expect(TimeRulerData.niceInterval(30), equals(50)),
      );
      test(
        'raw = 50 → 50',
        () => expect(TimeRulerData.niceInterval(50), equals(50)),
      );
      test(
        'raw = 60 → 100',
        () => expect(TimeRulerData.niceInterval(60), equals(100)),
      );
      test(
        'raw = 100 → 100',
        () => expect(TimeRulerData.niceInterval(100), equals(100)),
      );
      test(
        'raw = 150 → 200',
        () => expect(TimeRulerData.niceInterval(150), equals(200)),
      );

      test('result is always >= raw (rounds up, never down)', () {
        for (final raw in [
          0.5,
          1.0,
          1.5,
          2.5,
          3.0,
          7.5,
          12.0,
          25.0,
          75.0,
          125.0,
        ]) {
          expect(
            TimeRulerData.niceInterval(raw).toDouble(),
            greaterThanOrEqualTo(raw - 0.001),
            reason: 'niceInterval($raw) should be >= $raw',
          );
        }
      });
    });

    // ── TickMark value class ──────────────────────────────────────────────────

    group('TickMark equality', () {
      const a = TickMark(x: 10, time: 100, isMajor: true, label: '100 ticks');
      const b = TickMark(x: 10, time: 100, isMajor: true, label: '100 ticks');

      test('equal ticks compare equal', () => expect(a, equals(b)));

      test('hashCode matches for equal ticks', () {
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different x produces inequality', () {
        const c = TickMark(x: 20, time: 100, isMajor: true, label: '100 ticks');
        expect(a, isNot(equals(c)));
      });

      test('different isMajor produces inequality', () {
        const c = TickMark(x: 10, time: 100, isMajor: false);
        expect(a, isNot(equals(c)));
      });

      test('different label produces inequality', () {
        const c = TickMark(x: 10, time: 100, isMajor: true, label: 'other');
        expect(a, isNot(equals(c)));
      });

      test('toString includes all fields', () {
        final s = a.toString();
        expect(s, contains('x: 10'));
        expect(s, contains('time: 100'));
        expect(s, contains('isMajor: true'));
      });
    });
  });
}

/// Returns the interval between the first two major ticks (0 if fewer than 2).
int _majorInterval(TimeRulerData ruler) {
  final major = ruler.ticks.where((t) => t.isMajor).toList();
  if (major.length < 2) return 0;
  return major[1].time - major[0].time;
}
