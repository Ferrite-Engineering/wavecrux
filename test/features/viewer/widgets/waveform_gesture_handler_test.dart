// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/inline_cursor_value_overlay.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_gesture_handler.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

// ── test helpers ─────────────────────────────────────────────────────────────

ProviderContainer _initContainer() {
  // Keep auto-dispose providers alive by adding listeners before any reads.
  // WaveformGestureHandler uses ref.read (not ref.watch) in event handlers,
  // so without explicit listeners the Riverpod scheduler would queue a pending
  // dispose timer and fail the test's timer-invariant assertion.
  final c = ProviderContainer()
    ..listen(timeMapperProvider, (_, _) {})
    ..listen(cursorStateProvider, (_, _) {})
    ..listen(navigationProvider, (_, _) {})
    ..read(timeMapperProvider.notifier).initialize(
      startTime: 0,
      endTime: 10000,
      viewportWidth: 1000,
    );
  return c;
}

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Widget _wrap(Widget child, ProviderContainer container, {Locale? locale}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        locale: locale,
        home: Scaffold(body: child),
      ),
    );

// A coloured box that fills all available space — used as the child of
// WaveformGestureHandler in tests so the widget occupies a non-zero area and
// can be hit-tested. ColoredBox without a child has zero intrinsic size.
const Widget _canvas = SizedBox.expand(
  child: ColoredBox(color: Color(0xFF000000)),
);

// ── inline-overlay fixtures (scrub-through) ────────────────────────────────────

class _MockSource extends Mock implements WaveformDataSource {}

WaveformDataSource _overlaySource() {
  final s = _MockSource();
  when(() => s.startTime).thenReturn(0);
  when(() => s.endTime).thenReturn(10000);
  when(() => s.timescale).thenReturn(null);
  when(() => s.rootScopes).thenReturn([]);
  when(() => s.isSignalLoaded(any())).thenReturn(true);
  when(() => s.changesInRange(any(), any(), any())).thenReturn([]);
  // A wide value so the label truncates → it is rendered as the interactive
  // (translucent, tap-only) GestureDetector, the case that must still let a
  // scrub drag bubble to the handler.
  when(() => s.valueAt(any(), any())).thenReturn(
    'b1010101010101010101010101010101010101010101010101010101010101010',
  );
  return s;
}

class _OverlaySource extends WaveformSourceNotifier {
  _OverlaySource(this._s);
  final WaveformDataSource _s;
  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_s);
}

class _OverlaySignals extends SignalGroupsNotifier {
  @override
  SignalGroup build() => SignalGroup(
    entries: [SignalEntry.signal(signalRef: 'bus', displayName: 'bus')],
  );
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('WaveformGestureHandler', () {
    // ── locale sweep ───────────────────────────────────────────────────────

    for (final locale in _locales) {
      testWidgets('locale sweep — renders in $locale without exception', (
        tester,
      ) async {
        final container = _initContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _wrap(
            const WaveformGestureHandler(child: _canvas),
            container,
            locale: locale,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    // ── left tap → primary cursor ──────────────────────────────────────────

    testWidgets('left tap places primary cursor', (tester) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(const WaveformGestureHandler(child: _canvas), container),
      );
      await tester.pump();

      final centre = tester.getCenter(find.byType(WaveformGestureHandler));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(centre);
      await gesture.up();
      await tester.pump();

      final cursor = container.read(cursorStateProvider);
      expect(cursor.primaryCursorTime, isNotNull);
      expect(cursor.secondaryCursorTime, isNull);
    });

    // ── right tap → secondary cursor ──────────────────────────────────────

    testWidgets('right tap places secondary cursor', (tester) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(const WaveformGestureHandler(child: _canvas), container),
      );
      await tester.pump();

      final centre = tester.getCenter(find.byType(WaveformGestureHandler));
      // tester.tapAt uses PointerDeviceKind.touch by default; use createGesture
      // with explicit mouse kind so _onPointerDown processes it as a mouse event
      // and the secondary-button branch is reached.
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.down(centre);
      await gesture.up();
      await tester.pump();

      final cursor = container.read(cursorStateProvider);
      expect(cursor.secondaryCursorTime, isNotNull);
    });

    // ── scroll wheel → mouse vs trackpad ─────────────────────────────────

    testWidgets(
      'plain mouse scroll does NOT zoom (lets ScrollView handle lanes)',
      (tester) async {
        final container = _initContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _wrap(const WaveformGestureHandler(child: _canvas), container),
        );
        await tester.pump();

        final before = container.read(timeMapperProvider).ticksPerPixel;
        final centre = tester.getCenter(find.byType(WaveformGestureHandler));

        // Plain mouse vertical scroll — should NOT zoom.
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: centre,
            scrollDelta: const Offset(0, -120),
          ),
        );
        await tester.pump();

        final after = container.read(timeMapperProvider).ticksPerPixel;
        expect(
          after,
          equals(before),
          reason:
              "Plain mouse scroll must not zoom — that is the ScrollView's job",
        );
      },
    );

    // Ctrl/Shift+scroll zoom and pan are handled by WaveformScrollModifierInterceptor
    // (tested in waveform_scroll_modifier_interceptor_test.dart). The gesture handler
    // must NOT act on those events — these tests guard against regression.

    testWidgets('ctrl+mouse scroll does NOT zoom via gesture handler', (
      tester,
    ) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(const WaveformGestureHandler(child: _canvas), container),
      );
      await tester.pump();

      final before = container.read(timeMapperProvider).ticksPerPixel;
      final centre = tester.getCenter(find.byType(WaveformGestureHandler));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      addTearDown(() async {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      });

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: centre,
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.pump();

      expect(container.read(timeMapperProvider).ticksPerPixel, equals(before));
    });

    testWidgets('shift+mouse scroll does NOT pan via gesture handler', (
      tester,
    ) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      container.read(navigationProvider.notifier).zoomIn();
      container.read(navigationProvider.notifier).zoomIn();

      await tester.pumpWidget(
        _wrap(const WaveformGestureHandler(child: _canvas), container),
      );
      await tester.pump();

      final before = container.read(timeMapperProvider).panOffsetTicks;
      final centre = tester.getCenter(find.byType(WaveformGestureHandler));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      addTearDown(() async {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      });

      await tester.sendEventToBinding(
        PointerScrollEvent(position: centre, scrollDelta: const Offset(0, 60)),
      );
      await tester.pump();

      expect(container.read(timeMapperProvider).panOffsetTicks, equals(before));
    });

    testWidgets(
      'trackpad vertical scroll forwards delta to onVerticalScroll '
      '(does NOT zoom)',
      (tester) async {
        final container = _initContainer();
        addTearDown(container.dispose);

        final scrollDeltas = <double>[];
        await tester.pumpWidget(
          _wrap(
            WaveformGestureHandler(
              onVerticalScroll: scrollDeltas.add,
              child: _canvas,
            ),
            container,
          ),
        );
        await tester.pump();

        final beforeZoom = container.read(timeMapperProvider).ticksPerPixel;
        final centre = tester.getCenter(find.byType(WaveformGestureHandler));

        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: centre,
            kind: PointerDeviceKind.trackpad,
            scrollDelta: const Offset(0, -120),
          ),
        );
        await tester.pump();

        // Per Issue 4 — vertical trackpad scroll now scrolls the lane list
        // (via the onVerticalScroll callback) instead of zooming.
        final afterZoom = container.read(timeMapperProvider).ticksPerPixel;
        expect(
          afterZoom,
          equals(beforeZoom),
          reason: 'vertical trackpad scroll must not zoom',
        );
        expect(
          scrollDeltas,
          equals([-120.0]),
          reason: 'vertical trackpad scroll forwards dy to the callback',
        );
      },
    );

    testWidgets(
      'trackpad two-finger pan-zoom forwards vertical delta to '
      'onVerticalScroll',
      (tester) async {
        final container = _initContainer();
        addTearDown(container.dispose);

        final scrollDeltas = <double>[];
        await tester.pumpWidget(
          _wrap(
            WaveformGestureHandler(
              onVerticalScroll: scrollDeltas.add,
              child: _canvas,
            ),
            container,
          ),
        );
        await tester.pump();

        final centre = tester.getCenter(find.byType(WaveformGestureHandler));
        const pointer = 99;
        await tester.sendEventToBinding(
          PointerPanZoomStartEvent(pointer: pointer, position: centre),
        );
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(
            pointer: pointer,
            position: centre,
            pan: const Offset(0, 40),
            panDelta: const Offset(0, 40),
          ),
        );
        await tester.pump();

        // Negated to follow natural-scroll convention: panning down on the
        // trackpad scrolls the viewport up (panel content moves down toward
        // the user).
        expect(scrollDeltas, equals([-40.0]));
      },
    );

    // ── left drag → cursor move ───────────────────────────────────────────

    testWidgets('plain left drag moves cursor continuously', (tester) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(const WaveformGestureHandler(child: _canvas), container),
      );
      await tester.pump();

      // Plain left drag should update the primary cursor, NOT pan the view.
      final panBefore = container.read(timeMapperProvider).panOffsetTicks;

      final centre = tester.getCenter(find.byType(WaveformGestureHandler));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(centre);
      // Move far enough to exceed the tap-slop threshold.
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // Pan must NOT have changed.
      final panAfter = container.read(timeMapperProvider).panOffsetTicks;
      expect(panAfter, equals(panBefore));

      // Cursor MUST have moved.
      final cursor = container.read(cursorStateProvider);
      expect(cursor.primaryCursorTime, isNotNull);
    });

    // ── middle mouse drag → pan ───────────────────────────────────────────

    testWidgets('middle mouse button drag pans the time window', (
      tester,
    ) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      // Zoom in so there is room to pan (at fit-all the right limit is 0 and
      // any pan is clamped back to no-op).
      container.read(navigationProvider.notifier).zoomIn();
      container.read(navigationProvider.notifier).zoomIn();

      await tester.pumpWidget(
        _wrap(const WaveformGestureHandler(child: _canvas), container),
      );
      await tester.pump();

      final before = container.read(timeMapperProvider).panOffsetTicks;

      final centre = tester.getCenter(find.byType(WaveformGestureHandler));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await gesture.down(centre);
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final after = container.read(timeMapperProvider).panOffsetTicks;
      expect(after, isNot(equals(before)));
    });

    // ── tap does not pan ──────────────────────────────────────────────────

    testWidgets('tap does not change pan offset', (tester) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(const WaveformGestureHandler(child: _canvas), container),
      );
      await tester.pump();

      final before = container.read(timeMapperProvider).panOffsetTicks;
      final centre = tester.getCenter(find.byType(WaveformGestureHandler));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(centre);
      await gesture.up();
      await tester.pump();

      final after = container.read(timeMapperProvider).panOffsetTicks;
      expect(after, equals(before));
    });

    // ── trackpad pan (PointerPanZoom) ────────────────────────────────────────

    testWidgets('PointerPanZoomUpdate with horizontal pan pans the viewport', (
      tester,
    ) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      // Zoom in so the viewport is not at fit-all and there is room to pan.
      container.read(navigationProvider.notifier).zoomIn();
      container.read(navigationProvider.notifier).zoomIn();

      await tester.pumpWidget(
        _wrap(const WaveformGestureHandler(child: _canvas), container),
      );
      await tester.pump();

      final before = container.read(timeMapperProvider).panOffsetTicks;
      final centre = tester.getCenter(find.byType(WaveformGestureHandler));

      // Simulate trackpad: start, then swipe left (negative dx → forward in time).
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(position: centre),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          position: centre,
          panDelta: const Offset(-50, 0),
        ),
      );
      await tester.pump();

      final after = container.read(timeMapperProvider).panOffsetTicks;
      expect(after, isNot(equals(before)));
    });

    testWidgets('PointerPanZoomUpdate with scale > 1 zooms in', (tester) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(const WaveformGestureHandler(child: _canvas), container),
      );
      await tester.pump();

      final before = container.read(timeMapperProvider).ticksPerPixel;
      final centre = tester.getCenter(find.byType(WaveformGestureHandler));

      // Start at scale=1, then report scale=1.5 (pinch open → zoom in).
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(position: centre),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          position: centre,
          scale: 1.5,
        ),
      );
      await tester.pump();

      final after = container.read(timeMapperProvider).ticksPerPixel;
      expect(after, lessThan(before));
    });

    // ── mouse region for resize cursor ────────────────────────────────────

    testWidgets('contains a MouseRegion for cursor-line hover feedback', (
      tester,
    ) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(const WaveformGestureHandler(child: _canvas), container),
      );
      await tester.pump();

      expect(find.byType(MouseRegion), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });

    // ── tap places cursor at exact time for given x-coordinate ────────────
    //
    // The container is initialized with startTime=0, endTime=10000,
    // viewportWidth=1000 → ticksPerPixel=10.  A tap at x=200 (local) maps to
    // time 200*10 = 2000.  We ask the mapper itself for the expected value so
    // the assertion is self-consistent regardless of rounding.
    testWidgets(
      'left tap places primary cursor at the correct time for the x-coordinate',
      (tester) async {
        final container = _initContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _wrap(const WaveformGestureHandler(child: _canvas), container),
        );
        await tester.pump();

        const tapX = 200.0;
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.down(const Offset(tapX, 300));
        await gesture.up();
        await tester.pump();

        final expectedTime = container
            .read(timeMapperProvider)
            .pixelToTime(tapX);
        final cursor = container.read(cursorStateProvider);
        expect(cursor.primaryCursorTime, equals(expectedTime));
      },
    );

    // ── shift+left drag creates a time-range selection ─────────────────────

    testWidgets('shift+left drag creates a TimeSelection with start < end', (
      tester,
    ) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(const WaveformGestureHandler(child: _canvas), container),
      );
      await tester.pump();

      // Press shift so _shiftPressed is true at pointer-down.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      addTearDown(() async {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      });

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      // Down at x=100 seeds the selection at startTime ≈ 1000.
      await gesture.down(const Offset(100, 300));
      await tester.pump();
      // Move past the tap-slop threshold (8 px) into the drag-select zone.
      await gesture.moveTo(const Offset(300, 300));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final selection = container.read(navigationProvider);
      expect(
        selection,
        isNotNull,
        reason: 'A TimeSelection should be active after shift+drag',
      );
      expect(
        selection!.startTime,
        lessThan(selection.endTime),
        reason: 'Selection should span from drag-start to drag-end',
      );
    });

    // ── onPrimaryTap callback fires with the local position ───────────────

    testWidgets('onPrimaryTap callback fires with the correct tap position', (
      tester,
    ) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      Offset? received;
      await tester.pumpWidget(
        _wrap(
          WaveformGestureHandler(
            onPrimaryTap: (pos) => received = pos,
            child: _canvas,
          ),
          container,
        ),
      );
      await tester.pump();

      const tapOffset = Offset(250, 200);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(tapOffset);
      await gesture.up();
      await tester.pump();

      expect(received, isNotNull, reason: 'onPrimaryTap should have fired');
      expect(received!.dx, closeTo(tapOffset.dx, 1.0));
    });

    // ── horizontal scroll pans the time window ────────────────────────────

    testWidgets('horizontal-only scroll event pans the time window', (
      tester,
    ) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      // Zoom in first so there is room to pan without hitting the bounds.
      container.read(navigationProvider.notifier).zoomIn();
      container.read(navigationProvider.notifier).zoomIn();

      await tester.pumpWidget(
        _wrap(const WaveformGestureHandler(child: _canvas), container),
      );
      await tester.pump();

      final before = container.read(timeMapperProvider).panOffsetTicks;
      final centre = tester.getCenter(find.byType(WaveformGestureHandler));

      // Send scroll with dx only — exercises the horizontal-pan branch in
      // _onPointerSignal (dy == 0 so no zoom is applied).
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: centre,
          scrollDelta: const Offset(60, 0),
        ),
      );
      await tester.pump();

      final after = container.read(timeMapperProvider).panOffsetTicks;
      expect(after, isNot(equals(before)));
    });

    // ── shift+left tap places secondary cursor ────────────────────────────

    testWidgets('shift+left tap places secondary cursor via _wasShiftOnDown', (
      tester,
    ) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(const WaveformGestureHandler(child: _canvas), container),
      );
      await tester.pump();

      // Hold shift so _wasShiftOnDown is recorded as true.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      addTearDown(() async {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      });

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(const Offset(300, 300));
      await gesture.up();
      await tester.pump();

      final cursor = container.read(cursorStateProvider);
      expect(cursor.secondaryCursorTime, isNotNull);
      // Primary cursor should NOT have been placed.
      expect(cursor.primaryCursorTime, isNull);
    });

    // ── sloppy tap fires onPrimaryTap ─────────────────────────────────────
    //
    // On macOS trackpads a physical click can produce small pointer-move events
    // that set _movedSignificantly even for a stationary tap.  The fix checks
    // the distance from pointer-down to pointer-up rather than the intermediate
    // flag, so a tap that briefly exceeds the slop but ends near the start
    // still fires onPrimaryTap.

    testWidgets(
      'sloppy tap (moves past slop then returns) still fires onPrimaryTap',
      (tester) async {
        final container = _initContainer();
        addTearDown(container.dispose);

        Offset? received;
        await tester.pumpWidget(
          _wrap(
            WaveformGestureHandler(
              onPrimaryTap: (pos) => received = pos,
              child: _canvas,
            ),
            container,
          ),
        );
        await tester.pump();

        // Simulate a "sloppy" click: pointer-down, move past the 8-px slop
        // threshold (which would set _movedSignificantly in the old code), then
        // move back to within slop of the starting position, then pointer-up.
        const downPos = Offset(400, 300);
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.down(downPos);
        // Move 10 px (past _tapSlop = 8) — would set _movedSignificantly.
        await gesture.moveTo(downPos + const Offset(10, 0));
        await tester.pump();
        // Move back to 3 px from start — well within _tapSlop.
        await gesture.moveTo(downPos + const Offset(3, 0));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        expect(
          received,
          isNotNull,
          reason:
              'onPrimaryTap must fire even after a sloppy trackpad tap '
              'where pointer moved past slop mid-gesture but ended near the start',
        );
      },
    );

    testWidgets('genuine drag does NOT fire onPrimaryTap', (tester) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      Offset? received;
      await tester.pumpWidget(
        _wrap(
          WaveformGestureHandler(
            onPrimaryTap: (pos) => received = pos,
            child: _canvas,
          ),
          container,
        ),
      );
      await tester.pump();

      // A real drag: move 50 px and stay there before lifting.
      const downPos = Offset(200, 300);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(downPos);
      await gesture.moveTo(downPos + const Offset(50, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(
        received,
        isNull,
        reason:
            'A genuine drag (pointer ends far from start) must NOT fire '
            'onPrimaryTap',
      );
    });

    // ── pointer cancel resets drag state ─────────────────────────────────

    testWidgets('pointer cancel does not leave the widget in an error state '
        'and subsequent tap works normally', (tester) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(const WaveformGestureHandler(child: _canvas), container),
      );
      await tester.pump();

      // Start a drag then cancel it — simulates a system interruption.
      final centre = tester.getCenter(find.byType(WaveformGestureHandler));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(centre);
      await gesture.moveBy(const Offset(30, 0));
      await gesture.cancel();
      await tester.pump();

      expect(tester.takeException(), isNull);

      // After cancel the state should be reset; a new tap must work.
      final gesture2 = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture2.down(centre);
      await gesture2.up();
      await tester.pump();

      expect(tester.takeException(), isNull);
      final cursor = container.read(cursorStateProvider);
      expect(cursor.primaryCursorTime, isNotNull);
    });

    // ── PointerPanZoomEnd resets scale state ───────────────────────────────

    testWidgets(
      'PointerPanZoomEnd fires without error and allows fresh zoom next gesture',
      (tester) async {
        final container = _initContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _wrap(const WaveformGestureHandler(child: _canvas), container),
        );
        await tester.pump();

        final centre = tester.getCenter(find.byType(WaveformGestureHandler));

        // Full trackpad pinch gesture: start → update (zoom in) → end.
        await tester.sendEventToBinding(
          PointerPanZoomStartEvent(position: centre),
        );
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(position: centre, scale: 1.5),
        );
        final ticksAfterZoom = container.read(timeMapperProvider).ticksPerPixel;
        await tester.sendEventToBinding(
          PointerPanZoomEndEvent(position: centre),
        );
        await tester.pump();

        // End must not throw and must not undo the zoom.
        expect(tester.takeException(), isNull);
        expect(
          container.read(timeMapperProvider).ticksPerPixel,
          equals(ticksAfterZoom),
        );
      },
    );

    // ── child rendering ───────────────────────────────────────────────────

    testWidgets('child widget is present in the tree', (tester) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(
          const WaveformGestureHandler(
            child: SizedBox(key: Key('inner'), width: 100, height: 100),
          ),
          container,
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('inner')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // ── inline value overlay pass-through ────────────────────────

    testWidgets(
      'horizontal scrub still pans with the inline value overlay stacked above',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final container =
            ProviderContainer(
                overrides: [
                  signalGroupsProvider.overrideWith(_OverlaySignals.new),
                  waveformSourceProvider.overrideWith(
                    () => _OverlaySource(_overlaySource()),
                  ),
                  deviceClassProvider.overrideWithValue(DeviceClass.phone),
                ],
              )
              ..listen(timeMapperProvider, (_, _) {})
              ..listen(cursorStateProvider, (_, _) {})
              ..listen(navigationProvider, (_, _) {})
              ..listen(signalGroupsProvider, (_, _) {})
              ..listen(waveformSourceProvider, (_, _) {})
              ..read(timeMapperProvider.notifier).initialize(
                startTime: 0,
                endTime: 10000,
                viewportWidth: 1000,
              );
        addTearDown(container.dispose);

        // A primary cursor must exist for the overlay to show labels.
        container.read(cursorStateProvider.notifier).placePrimary(5000);

        await tester.pumpWidget(
          _wrap(
            const WaveformGestureHandler(
              child: Stack(
                children: [
                  _canvas,
                  Positioned.fill(
                    child: InlineCursorValueOverlay(scrollOffset: 0),
                  ),
                ],
              ),
            ),
            container,
          ),
        );
        await tester.pump();

        // Sanity: the interactive (truncated) inline label is actually present
        // and stacked above the canvas, so this exercises the translucent
        // pass-through, not an empty overlay.
        expect(find.byType(InlineCursorValueOverlay), findsOneWidget);

        final before = container.read(cursorStateProvider).primaryCursorTime;
        // A mouse left-drag scrubs the primary cursor. Start it on the label's
        // lane band near the cursor x so the pointer lands on the translucent
        // tap-to-expand surface — the drag must still bubble to the handler and
        // move the cursor (the overlay does not absorb it).
        final start =
            tester.getTopLeft(find.byType(WaveformGestureHandler)) +
            const Offset(600, 20);
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.down(start);
        await gesture.moveBy(
          const Offset(-100, 0),
        ); // beyond the 8 px mouse slop
        await gesture.moveBy(const Offset(-80, 0));
        await gesture.up();
        await tester.pump();

        expect(
          container.read(cursorStateProvider).primaryCursorTime,
          isNot(before),
          reason: 'horizontal scrub must reach the handler through the overlay',
        );
      },
    );
  });
}
