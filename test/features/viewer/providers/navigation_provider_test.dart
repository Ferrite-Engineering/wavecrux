// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/time_selection.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

// Helper: creates a container with TimeMapper initialized to a known range.
ProviderContainer _container({
  int start = 0,
  int end = 10000,
  double viewportWidth = 1000,
}) {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c
      .read(timeMapperProvider.notifier)
      .initialize(
        startTime: start,
        endTime: end,
        viewportWidth: viewportWidth,
      );
  return c;
}

TimeMapper _mapper(ProviderContainer c) => c.read(timeMapperProvider);

void main() {
  group('NavigationNotifier — initial state', () {
    test('selection is null on startup', () {
      final c = _container();
      expect(c.read(navigationProvider), isNull);
    });
  });

  group('NavigationNotifier — zoomIn', () {
    test('zoomIn reduces ticksPerPixel (zooms into centre)', () {
      final c = _container();
      final before = _mapper(c).ticksPerPixel;
      c.read(navigationProvider.notifier).zoomIn();
      expect(_mapper(c).ticksPerPixel, lessThan(before));
    });

    test('zoomIn with focal pixel reduces ticksPerPixel', () {
      final c = _container();
      final before = _mapper(c).ticksPerPixel;
      c.read(navigationProvider.notifier).zoomIn(focalPixel: 200);
      expect(_mapper(c).ticksPerPixel, lessThan(before));
    });

    test('zoomIn uses viewport centre when focalPixel is null', () {
      final c = _container();
      // Two calls with null focalPixel should both reduce ticksPerPixel.
      c.read(navigationProvider.notifier).zoomIn();
      final after1 = _mapper(c).ticksPerPixel;
      c.read(navigationProvider.notifier).zoomIn();
      expect(_mapper(c).ticksPerPixel, lessThan(after1));
    });

    test('zoomIn applies the defined zoomFactor', () {
      final c = _container();
      final before = _mapper(c).ticksPerPixel;
      c.read(navigationProvider.notifier).zoomIn();
      final expected = before / NavigationNotifier.zoomFactor;
      expect(
        _mapper(c).ticksPerPixel,
        closeTo(expected, expected * 0.001),
      );
    });
  });

  group('NavigationNotifier — zoomOut', () {
    test('zoomOut increases ticksPerPixel (zooms out from centre)', () {
      final c = _container();
      // First zoom in so we are not at the max-zoom-out limit.
      c.read(navigationProvider.notifier).zoomIn();
      c.read(navigationProvider.notifier).zoomIn();
      final before = _mapper(c).ticksPerPixel;
      c.read(navigationProvider.notifier).zoomOut();
      expect(_mapper(c).ticksPerPixel, greaterThan(before));
    });

    test('zoomOut applies the defined zoomFactor', () {
      final c = _container();
      // Zoom in first so there is room to zoom out.
      c.read(navigationProvider.notifier).zoomIn();
      c.read(navigationProvider.notifier).zoomIn();
      final before = _mapper(c).ticksPerPixel;
      c.read(navigationProvider.notifier).zoomOut();
      final expected = before * NavigationNotifier.zoomFactor;
      expect(
        _mapper(c).ticksPerPixel,
        closeTo(expected, expected * 0.001),
      );
    });
  });

  group('NavigationNotifier — panLeft / panRight', () {
    test('panLeft moves visible window earlier in time', () {
      final c = _container();
      // Zoom in so there is room to pan left.
      c.read(navigationProvider.notifier).zoomIn();
      c.read(navigationProvider.notifier).zoomIn();
      c.read(navigationProvider.notifier).zoomIn();
      final before = _mapper(c).panOffsetTicks;
      c.read(navigationProvider.notifier).panLeft();
      expect(_mapper(c).panOffsetTicks, lessThan(before));
    });

    test('panRight moves visible window later in time', () {
      final c = _container();
      // Zoom in first — at fit-all the right pan limit collapses to 0 and
      // panRight would be clamped to a no-op.
      c.read(navigationProvider.notifier).zoomIn();
      c.read(navigationProvider.notifier).zoomIn();
      final before = _mapper(c).panOffsetTicks;
      c.read(navigationProvider.notifier).panRight();
      expect(_mapper(c).panOffsetTicks, greaterThan(before));
    });

    test('panLeft with small=true moves less than with small=false', () {
      final c1 = _container();
      final c2 = _container();
      // Zoom in a few steps so there is room.
      for (final c in [c1, c2]) {
        for (var i = 0; i < 4; i++) {
          c.read(navigationProvider.notifier).zoomIn();
        }
      }
      final before1 = _mapper(c1).panOffsetTicks;
      final before2 = _mapper(c2).panOffsetTicks;
      c1.read(navigationProvider.notifier).panLeft();
      c2.read(navigationProvider.notifier).panLeft(small: true);
      final largeDelta = (before1 - _mapper(c1).panOffsetTicks).abs();
      final smallDelta = (before2 - _mapper(c2).panOffsetTicks).abs();
      expect(largeDelta, greaterThan(smallDelta));
    });

    test('panRight with small=true moves less than with small=false', () {
      final c1 = _container();
      final c2 = _container();
      // Zoom in so there is room to pan right (at fit-all the limit is 0).
      for (final c in [c1, c2]) {
        for (var i = 0; i < 4; i++) {
          c.read(navigationProvider.notifier).zoomIn();
        }
      }
      final before1 = _mapper(c1).panOffsetTicks;
      final before2 = _mapper(c2).panOffsetTicks;
      c1.read(navigationProvider.notifier).panRight();
      c2.read(navigationProvider.notifier).panRight(small: true);
      final largeDelta = (_mapper(c1).panOffsetTicks - before1).abs();
      final smallDelta = (_mapper(c2).panOffsetTicks - before2).abs();
      expect(largeDelta, greaterThan(smallDelta));
    });
  });

  group('NavigationNotifier — fitAll', () {
    test('fitAll restores fit-all zoom level', () {
      final c = _container();
      // Zoom in to change the level.
      c.read(navigationProvider.notifier).zoomIn();
      c.read(navigationProvider.notifier).zoomIn();
      c.read(navigationProvider.notifier).fitAll();
      final mapper = _mapper(c);
      // After fitAll the full range fits in the viewport.
      expect(mapper.visibleStartTime, equals(mapper.startTime));
      expect(mapper.visibleEndTime, equals(mapper.endTime));
    });
  });

  group('NavigationNotifier — jumpToStart', () {
    test('jumpToStart sets left edge to simulation startTime', () {
      final c = _container();
      // Zoom in so panRight is not a no-op at fit-all, then pan away from start.
      c.read(navigationProvider.notifier).zoomIn();
      c.read(navigationProvider.notifier).zoomIn();
      c.read(navigationProvider.notifier).panRight();
      c.read(navigationProvider.notifier).panRight();
      c.read(navigationProvider.notifier).jumpToStart();
      expect(
        _mapper(c).panOffsetTicks.round(),
        equals(_mapper(c).startTime),
      );
    });

    test('jumpToStart is a no-op on an empty mapper', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // No initialize call → mapper is empty.
      expect(
        () => c.read(navigationProvider.notifier).jumpToStart(),
        returnsNormally,
      );
    });
  });

  group('NavigationNotifier — jumpToEnd', () {
    test('jumpToEnd sets right edge to simulation endTime', () {
      final c = _container();
      c.read(navigationProvider.notifier).jumpToEnd();
      final mapper = _mapper(c);
      expect(mapper.visibleEndTime, equals(mapper.endTime));
    });

    test('jumpToEnd is a no-op on an empty mapper', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(
        () => c.read(navigationProvider.notifier).jumpToEnd(),
        returnsNormally,
      );
    });
  });

  group('NavigationNotifier — jumpToTime', () {
    test('jumpToTime centres viewport on given time', () {
      final c = _container();
      const target = 5000;
      c.read(navigationProvider.notifier).jumpToTime(target);
      final mapper = _mapper(c);
      final centre = (mapper.visibleStartTime + mapper.visibleEndTime) / 2;
      // Allow ±1 tick rounding error.
      expect(centre, closeTo(target.toDouble(), 1.0));
    });

    test('jumpToTime is a no-op on an empty mapper', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(
        () => c.read(navigationProvider.notifier).jumpToTime(1000),
        returnsNormally,
      );
    });
  });

  group('NavigationNotifier — selection management', () {
    test('setSelection stores the selection', () {
      final c = _container();
      const sel = TimeSelection(startTime: 100, endTime: 500);
      c.read(navigationProvider.notifier).setSelection(sel);
      expect(c.read(navigationProvider), equals(sel));
    });

    test('setSelection with null clears the selection', () {
      final c = _container();
      c
          .read(navigationProvider.notifier)
          .setSelection(
            const TimeSelection(startTime: 100, endTime: 500),
          );
      c.read(navigationProvider.notifier).setSelection(null);
      expect(c.read(navigationProvider), isNull);
    });

    test('clearSelection sets state to null', () {
      final c = _container();
      c
          .read(navigationProvider.notifier)
          .setSelection(
            const TimeSelection(startTime: 100, endTime: 500),
          );
      c.read(navigationProvider.notifier).clearSelection();
      expect(c.read(navigationProvider), isNull);
    });
  });

  group('NavigationNotifier — zoomToSelection', () {
    test('zoomToSelection zooms to the selection range and clears it', () {
      final c = _container();
      const sel = TimeSelection(startTime: 2000, endTime: 4000);
      c.read(navigationProvider.notifier).setSelection(sel);
      c.read(navigationProvider.notifier).zoomToSelection();

      final mapper = _mapper(c);
      // The visible range should now match the selection.
      expect(mapper.visibleStartTime, equals(2000));
      expect(mapper.visibleEndTime, equals(4000));
      // Selection cleared.
      expect(c.read(navigationProvider), isNull);
    });

    test('zoomToSelection with inverted range normalizes before zooming', () {
      final c = _container();
      // Inverted: endTime < startTime.
      const sel = TimeSelection(startTime: 4000, endTime: 2000);
      c.read(navigationProvider.notifier).setSelection(sel);
      c.read(navigationProvider.notifier).zoomToSelection();

      final mapper = _mapper(c);
      expect(mapper.visibleStartTime, equals(2000));
      expect(mapper.visibleEndTime, equals(4000));
    });

    test('zoomToSelection is a no-op when selection is null', () {
      final c = _container();
      final before = _mapper(c).ticksPerPixel;
      c.read(navigationProvider.notifier).zoomToSelection();
      expect(_mapper(c).ticksPerPixel, equals(before));
    });

    test('zoomToSelection is a no-op when selection is empty', () {
      final c = _container();
      final before = _mapper(c).ticksPerPixel;
      c
          .read(navigationProvider.notifier)
          .setSelection(
            const TimeSelection(startTime: 1000, endTime: 1000),
          );
      c.read(navigationProvider.notifier).zoomToSelection();
      expect(_mapper(c).ticksPerPixel, equals(before));
    });
  });
}
