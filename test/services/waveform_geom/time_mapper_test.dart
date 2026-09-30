// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

void main() {
  group('TimeMapper', () {
    // ── construction ──────────────────────────────────────────────────────────

    group('TimeMapper.fitAll', () {
      test('ticksPerPixel equals range / viewportWidth', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        expect(m.ticksPerPixel, equals(10.0));
      });

      test('panOffsetTicks equals startTime', () {
        final m = TimeMapper.fitAll(
          startTime: 50,
          endTime: 1050,
          viewportWidth: 100,
        );
        expect(m.panOffsetTicks, equals(50.0));
      });

      test('non-zero startTime: visibleStartTime equals startTime', () {
        final m = TimeMapper.fitAll(
          startTime: 200,
          endTime: 1200,
          viewportWidth: 100,
        );
        expect(m.visibleStartTime, equals(200));
        expect(m.visibleEndTime, equals(1200));
      });

      test('zero range defaults ticksPerPixel to 1', () {
        final m = TimeMapper.fitAll(
          startTime: 100,
          endTime: 100,
          viewportWidth: 100,
        );
        expect(m.ticksPerPixel, equals(1.0));
      });

      test('zero viewportWidth defaults ticksPerPixel to 1', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 0,
        );
        expect(m.ticksPerPixel, equals(1.0));
      });
    });

    group('TimeMapper.empty', () {
      test('produces a non-null mapper', () {
        expect(TimeMapper.empty(), isNotNull);
      });

      test('isEmpty is true', () {
        expect(TimeMapper.empty().isEmpty, isTrue);
      });
    });

    // ── isEmpty ───────────────────────────────────────────────────────────────

    group('isEmpty', () {
      test('false when endTime > startTime', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 100,
          viewportWidth: 100,
        );
        expect(m.isEmpty, isFalse);
      });

      test('true when endTime == startTime', () {
        final m = TimeMapper.fitAll(
          startTime: 50,
          endTime: 50,
          viewportWidth: 100,
        );
        expect(m.isEmpty, isTrue);
      });
    });

    // ── coordinate conversion ─────────────────────────────────────────────────

    group('timeToPixel', () {
      late TimeMapper m;
      setUp(() {
        m = TimeMapper.fitAll(startTime: 0, endTime: 1000, viewportWidth: 100);
      });

      test('startTime maps to pixel 0', () {
        expect(m.timeToPixel(0), equals(0.0));
      });

      test('endTime maps to viewportWidth', () {
        expect(m.timeToPixel(1000), equals(100.0));
      });

      test('midpoint maps to viewport center', () {
        expect(m.timeToPixel(500), equals(50.0));
      });

      test('quarter and three-quarter points', () {
        expect(m.timeToPixel(250), equals(25.0));
        expect(m.timeToPixel(750), equals(75.0));
      });

      test('off-screen time before start returns negative x', () {
        expect(m.timeToPixel(-100), lessThan(0.0));
      });

      test('off-screen time after end exceeds viewportWidth', () {
        expect(m.timeToPixel(1100), greaterThan(100.0));
      });
    });

    group('pixelToTime', () {
      late TimeMapper m;
      setUp(() {
        m = TimeMapper.fitAll(startTime: 0, endTime: 1000, viewportWidth: 100);
      });

      test('pixel 0 maps to startTime', () {
        expect(m.pixelToTime(0), equals(0));
      });

      test('viewportWidth maps to endTime', () {
        expect(m.pixelToTime(100), equals(1000));
      });

      test('viewport center maps to midpoint', () {
        expect(m.pixelToTime(50), equals(500));
      });
    });

    group('round-trip: timeToPixel → pixelToTime', () {
      test('exact integer times round-trip for integer tick spacings', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        for (final t in [0, 100, 250, 500, 750, 1000]) {
          expect(m.pixelToTime(m.timeToPixel(t)), equals(t));
        }
      });
    });

    // ── visibleRange ──────────────────────────────────────────────────────────

    group('visibleRange', () {
      test('equals endTime - startTime after fitAll', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        expect(m.visibleRange, equals(1000));
      });

      test('approximately halves after 2× zoom in', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        final zoomed = m.zoomAround(50, 2);
        expect(zoomed.visibleRange, closeTo(500, 5));
      });
    });

    // ── zoom ──────────────────────────────────────────────────────────────────

    group('zoomAround', () {
      late TimeMapper m;
      setUp(() {
        m = TimeMapper.fitAll(startTime: 0, endTime: 1000, viewportWidth: 100);
      });

      test('factor > 1 reduces ticksPerPixel (zoom in)', () {
        expect(m.zoomAround(50, 2).ticksPerPixel, lessThan(m.ticksPerPixel));
      });

      test('factor < 1 increases ticksPerPixel (zoom out)', () {
        // Zoom in first — at fit-all maxTicksPerPixel == current ticksPerPixel,
        // so zooming out is clamped and would be a no-op.
        final zoomed = m.zoomAround(50, 4); // tpp=2.5
        expect(
          zoomed.zoomAround(50, 0.5).ticksPerPixel,
          greaterThan(zoomed.ticksPerPixel),
        );
      });

      test('focal pixel stays at same simulation time after zoom in', () {
        // Focal pixel 30 = time 300 (fitAll: 10 ticks/px)
        final zoomed = m.zoomAround(30, 2);
        expect(zoomed.timeToPixel(300), closeTo(30, 0.001));
      });

      test('focal pixel stays at same simulation time after zoom out', () {
        final zoomed = m.zoomAround(70, 1 / 2);
        expect(zoomed.timeToPixel(700), closeTo(70, 0.001));
      });

      test('zoom factor 1.0 leaves ticksPerPixel and panOffset unchanged', () {
        final unchanged = m.zoomAround(50, 1);
        expect(unchanged.ticksPerPixel, equals(m.ticksPerPixel));
        expect(unchanged.panOffsetTicks, equals(m.panOffsetTicks));
      });

      test('factor <= 0 returns same mapper', () {
        expect(m.zoomAround(50, 0), equals(m));
        expect(m.zoomAround(50, -1), equals(m));
      });

      test('extreme zoom in clamps to minTicksPerPixel', () {
        final z = m.zoomAround(50, 1000000000000);
        expect(z.ticksPerPixel, greaterThanOrEqualTo(m.minTicksPerPixel));
        // And that bound means something: one tick across the viewport, not a
        // fraction of one. 100 px viewport → 0.01 ticks/px.
        expect(z.ticksPerPixel, closeTo(0.01, 1e-9));
        expect(z.visibleRange, TimeMapper.minVisibleTicks);
      });

      test('extreme zoom out clamps to maxTicksPerPixel', () {
        final z = m.zoomAround(50, 1e-12);
        expect(z.ticksPerPixel, lessThanOrEqualTo(m.maxTicksPerPixel));
      });

      test('does not mutate original', () {
        final original = m.ticksPerPixel;
        m.zoomAround(50, 2); // result ignored
        expect(m.ticksPerPixel, equals(original));
      });
    });

    // ── pan ───────────────────────────────────────────────────────────────────

    group('panByPixels', () {
      late TimeMapper m;
      setUp(() {
        m = TimeMapper.fitAll(startTime: 0, endTime: 1000, viewportWidth: 100);
      });

      test('positive delta shifts panOffsetTicks forward', () {
        // 10 px * 10 ticks/px = 100 ticks
        expect(m.panByPixels(10).panOffsetTicks, closeTo(100, 0.001));
      });

      test('negative delta shifts panOffsetTicks backward', () {
        expect(m.panByPixels(-5).panOffsetTicks, closeTo(-50, 0.001));
      });

      test('zero delta leaves panOffsetTicks unchanged', () {
        expect(m.panByPixels(0).panOffsetTicks, equals(m.panOffsetTicks));
      });

      test('does not mutate original', () {
        final original = m.panOffsetTicks;
        m.panByPixels(20);
        expect(m.panOffsetTicks, equals(original));
      });
    });

    group('panByTime', () {
      late TimeMapper m;
      setUp(() {
        m = TimeMapper.fitAll(startTime: 0, endTime: 1000, viewportWidth: 100);
      });

      test('positive delta increases panOffsetTicks', () {
        expect(m.panByTime(200).panOffsetTicks, equals(200));
      });

      test('negative delta decreases panOffsetTicks', () {
        expect(m.panByTime(-100).panOffsetTicks, equals(-100));
      });
    });

    // ── fitAll() ──────────────────────────────────────────────────────────────

    group('fitAll()', () {
      test('resets zoom after zoom-in', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        final reset = m.zoomAround(50, 4).fitAll();
        expect(reset.ticksPerPixel, closeTo(10, 0.001));
        expect(reset.panOffsetTicks, closeTo(0, 0.001));
      });

      test('preserves simulation range and viewport width', () {
        final m = TimeMapper.fitAll(
          startTime: 100,
          endTime: 2100,
          viewportWidth: 800,
        );
        final reset = m.zoomAround(400, 3).fitAll();
        expect(reset.startTime, equals(100));
        expect(reset.endTime, equals(2100));
        expect(reset.viewportWidth, equals(800));
      });

      test('visible range spans full simulation after fitAll', () {
        final reset = TimeMapper.fitAll(
          startTime: 0,
          endTime: 500,
          viewportWidth: 500,
        ).zoomAround(250, 10).fitAll();
        expect(reset.visibleStartTime, equals(0));
        expect(reset.visibleEndTime, equals(500));
      });
    });

    // ── zoomToRange ───────────────────────────────────────────────────────────

    group('zoomToRange', () {
      late TimeMapper m;
      setUp(() {
        m = TimeMapper.fitAll(startTime: 0, endTime: 1000, viewportWidth: 100);
      });

      test('zooms viewport to exactly show the specified range', () {
        final ranged = m.zoomToRange(200, 700);
        expect(ranged.visibleStartTime, equals(200));
        expect(ranged.visibleEndTime, equals(700));
      });

      test('zero-range returns same mapper', () {
        expect(m.zoomToRange(300, 300), equals(m));
      });

      test('inverted range returns same mapper', () {
        expect(m.zoomToRange(700, 200), equals(m));
      });
    });

    // ── withViewportWidth ─────────────────────────────────────────────────────

    group('withViewportWidth', () {
      late TimeMapper m;
      setUp(() {
        m = TimeMapper.fitAll(startTime: 0, endTime: 1000, viewportWidth: 100);
      });

      test('updates viewportWidth', () {
        expect(m.withViewportWidth(200).viewportWidth, equals(200.0));
      });

      test('preserves center simulation time', () {
        // Center at pixel 50 = time 500 (10 ticks/px)
        final resized = m.withViewportWidth(200);
        // New center pixel = 100; should still map to time 500
        expect(resized.pixelToTime(100), equals(500));
      });

      test('preserves ticksPerPixel (zoom level unchanged)', () {
        expect(m.withViewportWidth(200).ticksPerPixel, equals(m.ticksPerPixel));
      });

      test('returns same mapper when width is unchanged', () {
        expect(m.withViewportWidth(100), equals(m));
      });

      test('returns same mapper for non-positive width', () {
        expect(m.withViewportWidth(0), equals(m));
        expect(m.withViewportWidth(-10), equals(m));
      });
    });

    // ── withSimulationRange ───────────────────────────────────────────────────

    group('withSimulationRange', () {
      test('returns fit-all mapper for the new range', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 100,
          viewportWidth: 100,
        ).zoomAround(50, 5);
        final reloaded = m.withSimulationRange(0, 2000);
        expect(reloaded.startTime, equals(0));
        expect(reloaded.endTime, equals(2000));
        expect(reloaded.visibleStartTime, equals(0));
        expect(reloaded.visibleEndTime, equals(2000));
      });

      test('preserves viewportWidth', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 100,
          viewportWidth: 800,
        );
        expect(m.withSimulationRange(0, 500).viewportWidth, equals(800));
      });
    });

    // ── maxTicksPerPixel ──────────────────────────────────────────────────────

    group('maxTicksPerPixel', () {
      test('equals the fit-all ticksPerPixel', () {
        // fitAll: 1000/100 = 10; max = 10 (fit-all is the maximum zoom-out)
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        expect(m.maxTicksPerPixel, closeTo(10, 0.001));
      });

      test('returns 1.0 for empty simulation range', () {
        expect(TimeMapper.empty().maxTicksPerPixel, equals(1));
      });

      test('is the fit-all scale on a SHORT trace too — no 1.0 floor', () {
        // The regression. `math.max(1, range / viewportWidth)` used to floor
        // this at 1.0, so a 70-tick trace in a 1400 px viewport — which fits
        // at 0.05 ticks/px — could zoom out to 1.0 and show 1400 ticks: the
        // data crushed into the left 5 % of the canvas and blank space for the
        // rest. Fit All corrected it, which is what proved the extent was
        // known and simply not being clamped to.
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 70,
          viewportWidth: 1400,
        );
        expect(m.maxTicksPerPixel, closeTo(0.05, 1e-9));
        expect(
          m.zoomAround(700, 1e-6).visibleRange,
          lessThanOrEqualTo(70),
          reason: 'zooming out from fit-all must not widen the viewport',
        );
      });
    });

    // ── minTicksPerPixel ──────────────────────────────────────────────────────

    group('minTicksPerPixel', () {
      test('is one simulation tick across the viewport', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        expect(m.minTicksPerPixel, closeTo(1 / 100, 1e-9));
      });

      test('never exceeds maxTicksPerPixel on a trace only a tick long', () {
        // `clamp` asserts `min <= max`. On a **one**-tick trace the floor
        // would otherwise ask for a wider viewport than fit-all allows, which
        // would make the trace unfittable; the floor yields instead, and both
        // bounds collapse onto the same scale.
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1,
          viewportWidth: 1000,
        );
        expect(m.minTicksPerPixel, lessThanOrEqualTo(m.maxTicksPerPixel));
        expect(m.minTicksPerPixel, m.maxTicksPerPixel);
        expect(m.canZoomIn, isFalse);
        expect(m.canZoomOut, isFalse);
        expect(m.zoomAround(500, 1000000).visibleRange, 1);
      });

      test('a two-tick trace can still zoom to its one-tick floor', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 2,
          viewportWidth: 1000,
        );
        expect(m.zoomAround(500, 1000000).visibleRange, 1);
      });
    });

    // ── canZoomIn / canZoomOut ────────────────────────────────────────────────

    group('canZoomIn / canZoomOut', () {
      test('fit-all can zoom in but not out', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 70,
          viewportWidth: 1400,
        );
        expect(m.canZoomOut, isFalse);
        expect(m.canZoomIn, isTrue);
      });

      test('the finest zoom can zoom out but not in', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 70,
          viewportWidth: 1400,
        ).zoomAround(700, 1000000000);
        expect(m.canZoomIn, isFalse);
        expect(m.canZoomOut, isTrue);
      });

      test('an empty mapper reports neither — there is nothing to zoom', () {
        expect(TimeMapper.empty().canZoomIn, isFalse);
        expect(TimeMapper.empty().canZoomOut, isFalse);
      });
    });

    // ── clamped ───────────────────────────────────────────────────────────────

    group('clamped', () {
      test('returns same instance when panOffset is already within bounds', () {
        // zoomAround(50, 4): tpp=2.5, pan=375, valid range [0, 750]
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        ).zoomAround(50, 4);
        expect(identical(m.clamped(), m), isTrue);
      });

      test('clamps panOffset to startTime when below startTime', () {
        const m = TimeMapper(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
          ticksPerPixel: 2.5,
          panOffsetTicks: -50,
        );
        expect(m.clamped().panOffsetTicks, equals(0));
      });

      test('clamps panOffset to maxOffset when above right limit', () {
        // tpp=2.5, maxOffset = 1000 - 100*2.5 = 750
        const m = TimeMapper(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
          ticksPerPixel: 2.5,
          panOffsetTicks: 900,
        );
        expect(m.clamped().panOffsetTicks, equals(750));
      });

      test('no-op on empty mapper (returns same instance)', () {
        final empty = TimeMapper.empty();
        expect(empty.clamped(), equals(empty));
      });

      test('at fit-all zoom, panOffset is pinned to startTime', () {
        // At fit-all: tpp=10, maxOffset = 1000 - 100*10 = 0 = startTime
        // Any positive pan should be clamped back to 0.
        const m = TimeMapper(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
          ticksPerPixel: 10,
          panOffsetTicks: 100,
        );
        expect(m.clamped().panOffsetTicks, equals(0));
      });

      test('with non-zero startTime, left clamp is startTime', () {
        const m = TimeMapper(
          startTime: 500,
          endTime: 1500,
          viewportWidth: 100,
          ticksPerPixel: 2.5,
          panOffsetTicks: 300, // below startTime (500)
        );
        expect(m.clamped().panOffsetTicks, equals(500));
      });
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    group('copyWith', () {
      test('overrides specified fields', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        final copy = m.copyWith(startTime: 50, endTime: 2000);
        expect(copy.startTime, equals(50));
        expect(copy.endTime, equals(2000));
        expect(copy.viewportWidth, equals(m.viewportWidth));
      });

      test('preserves unspecified fields', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        final copy = m.copyWith(viewportWidth: 200);
        expect(copy.ticksPerPixel, equals(m.ticksPerPixel));
        expect(copy.panOffsetTicks, equals(m.panOffsetTicks));
      });
    });

    // ── equality ──────────────────────────────────────────────────────────────

    group('equality', () {
      test('equal instances compare equal', () {
        final a = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        final b = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        expect(a, equals(b));
      });

      test('hashCode matches for equal instances', () {
        final a = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        final b = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        expect(a.hashCode, equals(b.hashCode));
      });

      test('differing ticksPerPixel produces inequality', () {
        final a = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        expect(a, isNot(equals(a.copyWith(ticksPerPixel: 20))));
      });

      test('differing panOffsetTicks produces inequality', () {
        final a = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        expect(a, isNot(equals(a.panByTime(100))));
      });

      test('identical reference equals itself', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        // Verifying the operator== overload directly (not relying on expect's matcher).
        expect(m == m, isTrue);
      });
    });

    // ── toString ──────────────────────────────────────────────────────────────

    group('toString', () {
      test('includes all key fields', () {
        final m = TimeMapper.fitAll(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 100,
        );
        final s = m.toString();
        expect(s, contains('startTime: 0'));
        expect(s, contains('endTime: 1000'));
        expect(s, contains('viewportWidth: 100'));
      });
    });
  });
}
