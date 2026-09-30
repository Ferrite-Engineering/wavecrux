// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

class _MockSource extends Mock implements WaveformDataSource {}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

void main() {
  group('TimeMapperNotifier', () {
    // ── initial state ─────────────────────────────────────────────────────────

    test('initial state is empty mapper', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(timeMapperProvider).isEmpty, isTrue);
    });

    // ── initialize ────────────────────────────────────────────────────────────

    group('initialize', () {
      test('fitAll=true sets fit-all mapper', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container
            .read(timeMapperProvider.notifier)
            .initialize(
              startTime: 0,
              endTime: 1000,
              viewportWidth: 100,
            );

        final mapper = container.read(timeMapperProvider);
        expect(mapper.isEmpty, isFalse);
        expect(mapper.visibleStartTime, equals(0));
        expect(mapper.visibleEndTime, equals(1000));
      });

      test('fitAll=true (default) sets ticksPerPixel from range', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container
            .read(timeMapperProvider.notifier)
            .initialize(
              startTime: 0,
              endTime: 2000,
              viewportWidth: 200,
            );

        // 2000 ticks / 200 px = 10 ticks/px
        expect(
          container.read(timeMapperProvider).ticksPerPixel,
          equals(10.0),
        );
      });

      test('fitAll=false preserves current ticksPerPixel', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // First initialize to establish a ticksPerPixel.
        container.read(timeMapperProvider.notifier)
          ..initialize(
            startTime: 0,
            endTime: 1000,
            viewportWidth: 100,
          )
          ..zoomIn(focalPixel: 50, factor: 4);
        final zoomedTPP = container.read(timeMapperProvider).ticksPerPixel;

        // Re-initialize with fitAll=false — zoom level should be preserved.
        container
            .read(timeMapperProvider.notifier)
            .initialize(
              startTime: 0,
              endTime: 1000,
              viewportWidth: 100,
              fitAll: false,
            );

        expect(
          container.read(timeMapperProvider).ticksPerPixel,
          closeTo(zoomedTPP, 0.001),
        );
      });
    });

    // ── zoomIn / zoomOut ──────────────────────────────────────────────────────

    group('zoomIn / zoomOut', () {
      test('zoomIn reduces ticksPerPixel', () {
        final container = _initializedContainer();
        addTearDown(container.dispose);

        final before = container.read(timeMapperProvider).ticksPerPixel;
        container.read(timeMapperProvider.notifier).zoomIn(focalPixel: 50);
        expect(
          container.read(timeMapperProvider).ticksPerPixel,
          lessThan(before),
        );
      });

      test('zoomOut increases ticksPerPixel', () {
        final container = _initializedContainer();
        addTearDown(container.dispose);

        // Zoom in first — at fit-all the viewport already shows the full range,
        // so zooming out further is clamped and would be a no-op.
        container.read(timeMapperProvider.notifier).zoomIn(focalPixel: 50);

        final before = container.read(timeMapperProvider).ticksPerPixel;
        container.read(timeMapperProvider.notifier).zoomOut(focalPixel: 50);
        expect(
          container.read(timeMapperProvider).ticksPerPixel,
          greaterThan(before),
        );
      });

      test('zoomIn then zoomOut approximately restores ticksPerPixel', () {
        final container = _initializedContainer();
        addTearDown(container.dispose);

        final before = container.read(timeMapperProvider).ticksPerPixel;
        container.read(timeMapperProvider.notifier)
          ..zoomIn(focalPixel: 50)
          ..zoomOut(focalPixel: 50);
        expect(
          container.read(timeMapperProvider).ticksPerPixel,
          closeTo(before, 0.001),
        );
      });
    });

    // ── pan ───────────────────────────────────────────────────────────────────

    group('pan / panByTime', () {
      test('pan shifts panOffsetTicks', () {
        final container = _initializedContainer();
        addTearDown(container.dispose);

        // Zoom in 4× so there is room to pan (at fit-all the pan is clamped to 0).
        // After zoomIn(focalPixel:50, factor:4): tpp=2.5, panOffset≈375.
        container
            .read(timeMapperProvider.notifier)
            .zoomIn(focalPixel: 50, factor: 4);
        final before = container.read(timeMapperProvider).panOffsetTicks;
        container.read(timeMapperProvider.notifier).pan(10);
        // 10 px × 2.5 ticks/px = 25 ticks
        expect(
          container.read(timeMapperProvider).panOffsetTicks,
          closeTo(before + 25, 0.001),
        );
      });

      test('panByTime shifts panOffsetTicks by exact ticks', () {
        final container = _initializedContainer();
        addTearDown(container.dispose);

        // Zoom in so there is room to pan; panOffset settles at ~375.
        container
            .read(timeMapperProvider.notifier)
            .zoomIn(focalPixel: 50, factor: 4);
        // panByTime(200) → 375 + 200 = 575 (within maxOffset=750)
        container.read(timeMapperProvider.notifier).panByTime(200);
        expect(
          container.read(timeMapperProvider).panOffsetTicks,
          closeTo(575, 0.001),
        );
      });

      test('setPanOffsetTicks sets the offset directly (within bounds)', () {
        final container = _initializedContainer();
        addTearDown(container.dispose);

        // Zoom in 4× so there is headroom (max offset ≈ 750).
        container
            .read(timeMapperProvider.notifier)
            .zoomIn(focalPixel: 50, factor: 4);
        container.read(timeMapperProvider.notifier).setPanOffsetTicks(500);
        expect(
          container.read(timeMapperProvider).panOffsetTicks,
          closeTo(500, 0.001),
        );
      });

      test('setPanOffsetTicks clamps to the valid scroll range', () {
        final container = _initializedContainer();
        addTearDown(container.dispose);

        // Zoom in 4× so there is headroom (max offset ≈ 750).
        container
            .read(timeMapperProvider.notifier)
            .zoomIn(focalPixel: 50, factor: 4);
        // Below startTime → clamps to 0.
        container.read(timeMapperProvider.notifier).setPanOffsetTicks(-100);
        expect(
          container.read(timeMapperProvider).panOffsetTicks,
          greaterThanOrEqualTo(0),
        );
        // Past endTime - viewport → clamps to max.
        container.read(timeMapperProvider.notifier).setPanOffsetTicks(10000);
        final tpp = container.read(timeMapperProvider).ticksPerPixel;
        // maxOffset = endTime (1000) - viewportWidth (100) * tpp
        final expectedMax = 1000 - 100 * tpp;
        expect(
          container.read(timeMapperProvider).panOffsetTicks,
          closeTo(expectedMax, 0.001),
        );
      });
    });

    // ── pan clamping ──────────────────────────────────────────────────────────

    group('pan clamping', () {
      test('pan cannot move left of startTime', () {
        final container = _initializedContainer();
        addTearDown(container.dispose);

        // At fit-all panOffset=0; panning left must stay at startTime (0).
        container.read(timeMapperProvider.notifier).pan(-50);
        expect(
          container.read(timeMapperProvider).panOffsetTicks,
          greaterThanOrEqualTo(0),
        );
      });

      test(
        'panByTime cannot move right beyond endTime minus viewport ticks',
        () {
          final container = _initializedContainer();
          addTearDown(container.dispose);

          // Zoom in so the valid right limit is < endTime.
          container
              .read(timeMapperProvider.notifier)
              .zoomIn(focalPixel: 50, factor: 4);
          final mapper = container.read(timeMapperProvider);
          final maxOffset =
              mapper.endTime - mapper.viewportWidth * mapper.ticksPerPixel;

          // Try to pan far beyond the right limit.
          container.read(timeMapperProvider.notifier).panByTime(10000);
          expect(
            container.read(timeMapperProvider).panOffsetTicks,
            lessThanOrEqualTo(maxOffset + 0.001),
          );
        },
      );

      test('zoomOut cannot exceed fit-all ticksPerPixel', () {
        final container = _initializedContainer();
        addTearDown(container.dispose);

        // Zoom in, then attempt to zoom out far beyond fit-all.
        container.read(timeMapperProvider.notifier).zoomIn(focalPixel: 50);
        container
            .read(timeMapperProvider.notifier)
            .zoomOut(focalPixel: 50, factor: 1000);

        final mapper = container.read(timeMapperProvider);
        expect(
          mapper.ticksPerPixel,
          lessThanOrEqualTo(mapper.maxTicksPerPixel + 0.001),
        );
      });
    });

    // ── the zoom limits, on a SHORT trace ─────────────────────────────────────
    //
    // Every group above runs 1000 ticks across 100 px, where fit-all is 10
    // ticks/px and the old `math.max(1, range / viewportWidth)` floor was never
    // the binding constraint. A **short** trace is where it was: 70 ticks in a
    // 1400 px viewport fits at 0.05 ticks/px, and the floor let the zoom out to
    // 1.0 — twenty times the trace, the data crushed into the left 5 % of the
    // canvas with blank space for the rest. Fit All corrected it, which proved
    // the viewer knew the true extent all along and simply was not clamping to
    // it.

    group('a 70-tick trace in a 1400 px viewport', () {
      ProviderContainer shortTrace() {
        final container = ProviderContainer();
        container
            .read(timeMapperProvider.notifier)
            .initialize(startTime: 0, endTime: 70, viewportWidth: 1400);
        return container;
      }

      test('zoom-out never shows more than the whole trace', () {
        final container = shortTrace();
        addTearDown(container.dispose);
        // Zoom in so there is somewhere to come back from, then lean on the
        // zoom-out control the way the user did.
        final notifier = container.read(timeMapperProvider.notifier)
          ..zoomIn(focalPixel: 700, factor: 8);
        for (var i = 0; i < 20; i++) {
          notifier.zoomOut(focalPixel: 700);
        }

        final mapper = container.read(timeMapperProvider);
        expect(
          mapper.visibleRange,
          lessThanOrEqualTo(70),
          reason:
              'the viewport shows ${mapper.visibleRange} ticks of a 70-tick '
              'trace — everything past 70 is blank canvas',
        );
        // And the most zoomed-out state IS fit-all, not merely bounded by it.
        expect(mapper.visibleStartTime, 0);
        expect(mapper.visibleEndTime, 70);
        expect(mapper.ticksPerPixel, closeTo(70 / 1400, 1e-9));
      });

      test('at that limit the zoom-out control reports itself unavailable', () {
        final container = shortTrace();
        addTearDown(container.dispose);
        // `initialize` fits all, which is already the limit.
        expect(container.read(timeMapperProvider).canZoomOut, isFalse);
        expect(container.read(timeMapperProvider).canZoomIn, isTrue);

        container.read(timeMapperProvider.notifier).zoomIn(focalPixel: 700);
        expect(container.read(timeMapperProvider).canZoomOut, isTrue);
      });

      test('zoom-in bottoms out at one tick across the viewport', () {
        final container = shortTrace();
        addTearDown(container.dispose);
        final notifier = container.read(timeMapperProvider.notifier);
        for (var i = 0; i < 40; i++) {
          notifier.zoomIn(focalPixel: 700);
        }

        final mapper = container.read(timeMapperProvider);
        expect(
          mapper.visibleRange,
          TimeMapper.minVisibleTicks,
          reason:
              'below one tick the trace carries no detail to reveal — a '
              'narrower viewport is a flat expanse at a bigger magnification',
        );
        expect(mapper.canZoomIn, isFalse);
        expect(mapper.canZoomOut, isTrue);
      });

      test('panning cannot scroll the viewport off the end of the data', () {
        final container = shortTrace();
        addTearDown(container.dispose);
        final notifier = container.read(timeMapperProvider.notifier)
          ..zoomIn(focalPixel: 700, factor: 4)
          ..panByTime(100000);
        var mapper = container.read(timeMapperProvider);
        expect(mapper.visibleEndTime, lessThanOrEqualTo(70));
        expect(
          mapper.visibleEndTime,
          70,
          reason: 'the end of the trace stays reachable at the right edge',
        );

        notifier.panByTime(-100000);
        mapper = container.read(timeMapperProvider);
        expect(mapper.visibleStartTime, 0);
      });

      test('a requested range past the end of the trace is pulled back', () {
        // `zoomToRange` is the one mutator a *peer* drives — a collaboration
        // follower applying a presenter's viewport, the shared-pointer overlay
        // re-centring — so it can be handed a range the local trace does not
        // have.
        final container = shortTrace();
        addTearDown(container.dispose);
        container.read(timeMapperProvider.notifier).zoomToRange(500, 540);

        final mapper = container.read(timeMapperProvider);
        expect(mapper.visibleEndTime, lessThanOrEqualTo(70));
        expect(mapper.visibleStartTime, greaterThanOrEqualTo(0));
      });

      test('a range wider than the trace becomes fit-all, not blank space', () {
        final container = shortTrace();
        addTearDown(container.dispose);
        container.read(timeMapperProvider.notifier).zoomToRange(0, 5000);

        final mapper = container.read(timeMapperProvider);
        expect(mapper.visibleStartTime, 0);
        expect(mapper.visibleEndTime, 70);
      });

      test(
        'a session saved under the old unbounded zoom-out reopens fitted',
        () {
          // The self-healing path: sidecars written before the clamp carry a
          // `ticksPerPixel` of 1.0 for this trace, which is 20× fit-all.
          final container = ProviderContainer();
          addTearDown(container.dispose);
          container.read(timeMapperProvider.notifier)
            ..setPendingZoomPan(ticksPerPixel: 1, panOffsetTicks: 0)
            ..initialize(startTime: 0, endTime: 70, viewportWidth: 1400);

          final mapper = container.read(timeMapperProvider);
          expect(mapper.visibleEndTime, 70);
          expect(mapper.ticksPerPixel, closeTo(70 / 1400, 1e-9));
        },
      );
    });

    // ── fitAll ────────────────────────────────────────────────────────────────

    test('fitAll restores full visible range after zoom-in', () {
      final container = _initializedContainer();
      addTearDown(container.dispose);

      container.read(timeMapperProvider.notifier)
        ..zoomIn(focalPixel: 50, factor: 8)
        ..fitAll();

      final mapper = container.read(timeMapperProvider);
      expect(mapper.visibleStartTime, equals(0));
      expect(mapper.visibleEndTime, equals(1000));
    });

    // ── zoomToRange ───────────────────────────────────────────────────────────

    test('zoomToRange shows exactly the requested range', () {
      final container = _initializedContainer();
      addTearDown(container.dispose);

      container.read(timeMapperProvider.notifier).zoomToRange(200, 600);

      final mapper = container.read(timeMapperProvider);
      expect(mapper.visibleStartTime, equals(200));
      expect(mapper.visibleEndTime, equals(600));
    });

    // ── updateViewportWidth ───────────────────────────────────────────────────

    group('updateViewportWidth', () {
      test('changes viewportWidth', () {
        final container = _initializedContainer();
        addTearDown(container.dispose);

        container.read(timeMapperProvider.notifier).updateViewportWidth(400);

        expect(
          container.read(timeMapperProvider).viewportWidth,
          equals(400),
        );
      });

      test('fit-all mode: recalculates ticksPerPixel to maintain fit-all', () {
        // After initialize (fit-all mode), resizing should keep the full
        // simulation visible — ticksPerPixel must scale with the new width.
        final container = _initializedContainer(); // 0–1000 ticks, 100 px wide
        addTearDown(container.dispose);

        // Widen the viewport: 100 px → 500 px.
        container.read(timeMapperProvider.notifier).updateViewportWidth(500);

        final mapper = container.read(timeMapperProvider);
        // Fit-all: ticksPerPixel = 1000 / 500 = 2.0
        expect(mapper.ticksPerPixel, closeTo(2.0, 0.001));
        expect(mapper.viewportWidth, equals(500));
        // The full range should still be visible.
        expect(mapper.visibleStartTime, equals(0));
        expect(mapper.visibleEndTime, equals(1000));
      });

      test('zoomed-in mode: preserves ticksPerPixel on resize', () {
        final container = _initializedContainer();
        addTearDown(container.dispose);

        // Zoom in to leave fit-all mode.
        container
            .read(timeMapperProvider.notifier)
            .zoomIn(focalPixel: 50, factor: 4);
        final tppBeforeResize = container
            .read(timeMapperProvider)
            .ticksPerPixel;

        // Resize — zoom level must be preserved (more/less waveform visible).
        container.read(timeMapperProvider.notifier).updateViewportWidth(200);

        expect(
          container.read(timeMapperProvider).ticksPerPixel,
          closeTo(tppBeforeResize, 0.001),
        );
        expect(
          container.read(timeMapperProvider).viewportWidth,
          equals(200),
        );
      });

      test(
        'zoomed-in mode: snaps to fit-all when viewport exceeds simulation',
        () {
          // Start at 0–1000 ticks, 100 px wide, then zoom in 4×.
          // At 4× zoom: ticksPerPixel = 2.5, viewport shows 250 ticks.
          // Widen to 600 px → 2.5 ticks/px × 600 px = 1500 ticks > 1000 range
          // → should snap to fit-all.
          final container = _initializedContainer();
          addTearDown(container.dispose);

          container
              .read(timeMapperProvider.notifier)
              .zoomIn(focalPixel: 50, factor: 4);

          container.read(timeMapperProvider.notifier).updateViewportWidth(600);

          final mapper = container.read(timeMapperProvider);
          // Snapped to fit-all: ticksPerPixel = 1000 / 600 ≈ 1.667
          expect(
            mapper.ticksPerPixel,
            closeTo(1000 / 600, 0.001),
          );
          expect(mapper.visibleStartTime, equals(0));
          expect(mapper.visibleEndTime, equals(1000));
        },
      );

      test('fitAll() followed by resize maintains fit-all', () {
        final container = _initializedContainer();
        addTearDown(container.dispose);

        // Zoom in, then explicitly fit-all.
        container.read(timeMapperProvider.notifier)
          ..zoomIn(focalPixel: 50, factor: 4)
          ..fitAll();

        // Resize — should still maintain fit-all.
        container.read(timeMapperProvider.notifier).updateViewportWidth(250);

        final mapper = container.read(timeMapperProvider);
        expect(mapper.ticksPerPixel, closeTo(1000 / 250, 0.001));
        expect(mapper.visibleStartTime, equals(0));
        expect(mapper.visibleEndTime, equals(1000));
      });

      test('zoomOut to limit re-enters fit-all mode for subsequent resize', () {
        final container = _initializedContainer();
        addTearDown(container.dispose);

        // Zoom in, then zoom all the way back out to the fit-all limit.
        container.read(timeMapperProvider.notifier)
          ..zoomIn(focalPixel: 50, factor: 4)
          ..zoomOut(focalPixel: 50, factor: 1000); // far past fit-all

        // Now resize — should recalculate to maintain fit-all.
        container.read(timeMapperProvider.notifier).updateViewportWidth(200);

        final mapper = container.read(timeMapperProvider);
        expect(mapper.ticksPerPixel, closeTo(1000 / 200, 0.001));
        expect(mapper.visibleStartTime, equals(0));
        expect(mapper.visibleEndTime, equals(1000));
      });
    });
  });

  // ── visibleTimeRangeProvider ──────────────────────────────────────────────

  group('visibleTimeRangeProvider', () {
    test('returns non-null range for empty mapper', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // empty mapper: panOffsetTicks=0, viewportWidth=1000, ticksPerPixel=1
      // → visibleStartTime=0, visibleEndTime=1000
      final range = container.read(visibleTimeRangeProvider);
      expect(range.$1, equals(0));
      expect(range.$2, equals(1000));
    });

    test('returns correct range after initialize', () {
      final container = _initializedContainer();
      addTearDown(container.dispose);

      final range = container.read(visibleTimeRangeProvider);
      expect(range.$1, equals(0));
      expect(range.$2, equals(1000));
    });

    test('updates when mapper changes via zoomToRange', () {
      final container = _initializedContainer();
      addTearDown(container.dispose);

      container.read(timeMapperProvider.notifier).zoomToRange(100, 500);

      final range = container.read(visibleTimeRangeProvider);
      expect(range.$1, equals(100));
      expect(range.$2, equals(500));
    });
  });

  // ── currentTimescaleProvider ──────────────────────────────────────────────

  group('currentTimescaleProvider', () {
    test('returns null when no waveform is loaded', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(currentTimescaleProvider), isNull);
    });

    test('returns timescale from the loaded waveform source', () {
      const ts = Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);
      final source = _MockSource();
      when(() => source.timescale).thenReturn(ts);

      final container = ProviderContainer(
        overrides: [
          waveformSourceProvider.overrideWith(
            () => _FakeSourceNotifier(source),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentTimescaleProvider), equals(ts));
    });

    test('returns null when source has no timescale', () {
      final source = _MockSource();
      when(() => source.timescale).thenReturn(null);

      final container = ProviderContainer(
        overrides: [
          waveformSourceProvider.overrideWith(
            () => _FakeSourceNotifier(source),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentTimescaleProvider), isNull);
    });

    test('can be overridden directly (for widget-test use)', () {
      const ts = Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);
      final container = ProviderContainer(
        overrides: [
          currentTimescaleProvider.overrideWith((_) => ts),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentTimescaleProvider), equals(ts));
    });
  });

  // ── timeRulerDataProvider ─────────────────────────────────────────────────

  group('timeRulerDataProvider', () {
    test('returns empty ticks for empty mapper', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(timeRulerDataProvider).ticks, isEmpty);
    });

    test('returns non-empty ticks after initialize', () {
      final container = _initializedContainer();
      addTearDown(container.dispose);

      expect(container.read(timeRulerDataProvider).ticks, isNotEmpty);
    });

    test('updates after zoom change', () {
      final container = _initializedContainer();
      addTearDown(container.dispose);

      final before = container.read(timeRulerDataProvider).ticks.length;
      container
          .read(timeMapperProvider.notifier)
          .zoomIn(focalPixel: 50, factor: 10);
      final after = container.read(timeRulerDataProvider).ticks.length;
      // Zoomed in → finer ticks, different count
      expect(after, isNot(equals(before)));
    });

    test('major tick labels contain SI unit when timescale is provided', () {
      const ts = Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);
      final container = ProviderContainer(
        overrides: [
          currentTimescaleProvider.overrideWith((_) => ts),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 1000,
            viewportWidth: 1000,
          );

      final major = container
          .read(timeRulerDataProvider)
          .ticks
          .where((t) => t.isMajor)
          .toList();

      expect(major, isNotEmpty);
      for (final tick in major) {
        final label = tick.label!;
        final hasUnit =
            label.contains('ns') ||
            label.contains('µs') ||
            label.contains('ms') ||
            label.contains(' s');
        expect(
          hasUnit,
          isTrue,
          reason: 'label "$label" lacks an SI time unit',
        );
      }
    });

    test('major tick labels contain "ticks" when no timescale', () {
      final container = _initializedContainer();
      addTearDown(container.dispose);

      final major = container
          .read(timeRulerDataProvider)
          .ticks
          .where((t) => t.isMajor)
          .toList();

      for (final tick in major) {
        expect(tick.label, contains('ticks'));
      }
    });
  });
}

/// Returns a [ProviderContainer] pre-initialized with a 0–1000 tick, 100 px
/// wide mapper. Caller is responsible for calling [ProviderContainer.dispose].
ProviderContainer _initializedContainer() {
  final container = ProviderContainer();
  container
      .read(timeMapperProvider.notifier)
      .initialize(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 100,
      );
  return container;
}
