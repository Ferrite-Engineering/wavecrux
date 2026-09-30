// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_horizontal_scrollbar.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

class _StubMapperNotifier extends TimeMapperNotifier {
  _StubMapperNotifier(this._initial);
  final TimeMapper _initial;

  @override
  TimeMapper build() => _initial;
}

Widget _wrap({
  required Widget child,
  required TimeMapper mapper,
  Locale locale = const Locale('en'),
  DeviceClass deviceClass = DeviceClass.desktop,
  Size surface = const Size(800, 200),
}) {
  return ProviderScope(
    overrides: [
      timeMapperProvider.overrideWith(() => _StubMapperNotifier(mapper)),
      // Stub the file-loaded check so the scrollbar's gate is open in
      // tests. Production reads this from waveformSourceProvider.
      waveformIsLoadedProvider.overrideWith((ref) => true),
      deviceClassProvider.overrideWithValue(deviceClass),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: surface.width,
          height: surface.height,
          child: child,
        ),
      ),
    ),
  );
}

TimeMapper _mapper({
  int startTime = 0,
  int endTime = 1000,
  double viewportWidth = 800,
  double ticksPerPixel = 1,
  double panOffsetTicks = 0,
}) {
  return TimeMapper(
    startTime: startTime,
    endTime: endTime,
    viewportWidth: viewportWidth,
    ticksPerPixel: ticksPerPixel,
    panOffsetTicks: panOffsetTicks,
  );
}

void main() {
  Finder internalStack() => find.descendant(
    of: find.byType(WaveformHorizontalScrollbar),
    matching: find.byType(Stack),
  );

  group('WaveformHorizontalScrollbar — visibility', () {
    testWidgets('renders nothing when the simulation range is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          child: const WaveformHorizontalScrollbar(),
          mapper: _mapper(endTime: 0),
        ),
      );
      await tester.pumpAndSettle();
      // Empty mapper → widget renders an empty band (no Stack) so it still
      // reserves the bandHeight in the column flow. This keeps the
      // canvas/value-column/signal-list viewport heights identical and
      // prevents the bidirectional vertical scroll sync from drifting at
      // the bottom of the list.
      expect(internalStack(), findsNothing);
    });

    testWidgets(
      'renders nothing when fully zoomed out (visible >= full range)',
      (tester) async {
        // viewportWidth (800) * ticksPerPixel (1.25) = 1000 ticks visible
        // — exactly the full simulation range, so no scroll is possible. The
        // widget still reserves bandHeight (empty band, no Stack) so sibling
        // columns stay aligned.
        await tester.pumpWidget(
          _wrap(
            child: const WaveformHorizontalScrollbar(),
            mapper: _mapper(ticksPerPixel: 1.25),
          ),
        );
        await tester.pumpAndSettle();
        expect(internalStack(), findsNothing);
      },
    );

    testWidgets('renders track + thumb when zoomed in', (tester) async {
      await tester.pumpWidget(
        _wrap(
          child: const WaveformHorizontalScrollbar(),
          // Visible range = 200 ticks, full range = 1000 → thumb covers
          // 20% of the track.
          mapper: _mapper(ticksPerPixel: 0.25),
        ),
      );
      await tester.pumpAndSettle();
      expect(internalStack(), findsOneWidget);
    });
  });

  group('WaveformHorizontalScrollbar — locale sweep', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          _wrap(
            child: const WaveformHorizontalScrollbar(),
            mapper: _mapper(ticksPerPixel: 0.25),
            locale: Locale(locale),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('WaveformHorizontalScrollbar — interaction', () {
    testWidgets('drag updates the pan offset via the notifier', (tester) async {
      final stub = _StubMapperNotifier(_mapper(ticksPerPixel: 0.25));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timeMapperProvider.overrideWith(() => stub),
            waveformIsLoadedProvider.overrideWith((ref) => true),
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 80,
                child: WaveformHorizontalScrollbar(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialOffset = stub.state.panOffsetTicks;
      // Drag from the center of the scrollbar toward the right.
      final scrollbar = find.byType(WaveformHorizontalScrollbar);
      final start = tester.getCenter(scrollbar);
      await tester.dragFrom(start, const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(
        stub.state.panOffsetTicks,
        greaterThan(initialOffset),
        reason: 'Dragging right should increase the pan offset',
      );
    });

    testWidgets('tap on track outside thumb jumps the pan offset', (
      tester,
    ) async {
      // Visible range = 100 ticks, full range = 1000 → thumb covers 10%.
      // Initial offset = 0 → thumb is at the very left.
      final stub = _StubMapperNotifier(_mapper(ticksPerPixel: 0.125));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timeMapperProvider.overrideWith(() => stub),
            waveformIsLoadedProvider.overrideWith((ref) => true),
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 80,
                child: WaveformHorizontalScrollbar(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap near the right edge of the track — thumb is far left, so this
      // tap is clearly outside it.
      final scrollbar = find.byType(WaveformHorizontalScrollbar);
      final box = tester.getRect(scrollbar);
      await tester.tapAt(Offset(box.right - 40, box.center.dy));
      await tester.pumpAndSettle();
      expect(
        stub.state.panOffsetTicks,
        greaterThan(0),
        reason: 'Tapping right of the thumb should pan forward',
      );
    });
  });

  group('WaveformHorizontalScrollbar — touch sizing', () {
    testWidgets('uses taller hit band on touch device classes', (tester) async {
      await tester.pumpWidget(
        _wrap(
          child: const WaveformHorizontalScrollbar(),
          mapper: _mapper(ticksPerPixel: 0.25),
          deviceClass: DeviceClass.tablet,
        ),
      );
      await tester.pumpAndSettle();
      // Touch band height is 24 dp per MobileMetrics; desktop is 16 dp.
      final stack = tester.getRect(internalStack());
      expect(stack.height, greaterThanOrEqualTo(20));
    });
  });
}
