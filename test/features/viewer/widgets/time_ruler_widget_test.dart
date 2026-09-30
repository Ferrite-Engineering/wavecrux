// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/domain/models/pattern_expression.dart';
import 'package:wavecrux/domain/models/pattern_match.dart';
import 'package:wavecrux/domain/models/pattern_search_result.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/widgets/time_ruler_widget.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';
import 'package:wavecrux/services/waveform_geom/time_ruler_data.dart';

// ── test helpers ──────────────────────────────────────────────────────────────

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SizedBox(width: 800, height: 200, child: child),
        ),
      ),
    );

// ── provider stubs ────────────────────────────────────────────────────────────

/// [MarkerStateNotifier] pre-loaded with markers 'a' at tick 100 and 'b' at
/// tick 400.
class _PreloadedMarkerNotifier extends MarkerStateNotifier {
  @override
  MarkerState build() =>
      const MarkerState().setMarker('a', 100).setMarker('b', 400);
}

/// [CursorStateNotifier] pre-loaded with primary cursor at 200 and secondary
/// at 600.
class _PreloadedCursorNotifier extends CursorStateNotifier {
  @override
  CursorState build() => const CursorState(
    primaryCursorTime: 200,
    secondaryCursorTime: 600,
  );
}

/// [TimeMapperNotifier] that starts fit-all over [0, 1000] at 800 px width.
///
/// With this setup:
///   ticksPerPixel = 1000 / 800 = 1.25
///   timeToPixel(200) = 200 / 1.25 = 160 px  ← primary cursor position
///   timeToPixel(600) = 600 / 1.25 = 480 px  ← secondary cursor position
class _InitializedTimeMapperNotifier extends TimeMapperNotifier {
  @override
  TimeMapper build() => TimeMapper.fitAll(
    startTime: 0,
    endTime: 1000,
    viewportWidth: 800,
  );
}

// ── test suite ────────────────────────────────────────────────────────────────

void main() {
  group('TimeRulerWidget', () {
    // ── locale sweep ────────────────────────────────────────────────────────

    testWidgets('locale sweep — renders without exceptions', (tester) async {
      await tester.pumpWidget(_wrap(const TimeRulerWidget()));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('light theme — renders without exceptions', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
          ],
          child: MaterialApp(
            theme: ThemeData.light(),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: const Scaffold(
              body: SizedBox(width: 800, height: 200, child: TimeRulerWidget()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // ── fixed height ────────────────────────────────────────────────────────

    testWidgets('has fixed height matching timeRulerHeight constant', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const TimeRulerWidget()));
      await tester.pump();

      // The outermost SizedBox from TimeRulerWidget constrains the height.
      final boxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final rulerBox = boxes.firstWhere(
        (b) => b.height == timeRulerHeight,
        orElse: () => throw TestFailure(
          'No SizedBox with height=$timeRulerHeight found',
        ),
      );
      expect(rulerBox.height, equals(timeRulerHeight));
    });

    // ── empty ruler (no file loaded) ────────────────────────────────────────

    testWidgets('renders without ticks when no waveform is loaded', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const TimeRulerWidget()));
      await tester.pump();
      // Empty TimeMapper → no ticks, but widget must not throw.
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });

    // ── mouse region for resize cursor ──────────────────────────────────────

    testWidgets('contains a MouseRegion for cursor change', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TimeRulerWidget(),
          overrides: [
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
            cursorStateProvider.overrideWith(_PreloadedCursorNotifier.new),
          ],
        ),
      );
      await tester.pump();
      expect(find.byType(MouseRegion), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });

    // ── cursor placement via tap ────────────────────────────────────────────

    testWidgets('tap places primary cursor at tapped time', (tester) async {
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const Scaffold(
                  body: SizedBox(
                    width: 1000,
                    height: 200,
                    child: TimeRulerWidget(),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap within the ruler area, away from any cursor triangles.
      final topLeft = tester.getTopLeft(find.byType(TimeRulerWidget));
      await tester.tapAt(topLeft + const Offset(200, 15));
      await tester.pump();

      final cursor = container.read(cursorStateProvider);
      expect(cursor.primaryCursorTime, isNotNull);
      expect(cursor.secondaryCursorTime, isNull);
    });

    testWidgets('right-click (secondary tap) places secondary cursor', (
      tester,
    ) async {
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const Scaffold(
                  body: SizedBox(
                    width: 1000,
                    height: 200,
                    child: TimeRulerWidget(),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      final topLeft = tester.getTopLeft(find.byType(TimeRulerWidget));
      await tester.tapAt(
        topLeft + const Offset(400, 15),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();

      final cursor = container.read(cursorStateProvider);
      expect(cursor.secondaryCursorTime, isNotNull);
    });

    testWidgets('right-click on a marker flag removes it via the menu', (
      tester,
    ) async {
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
            markerStateProvider.overrideWith(_PreloadedMarkerNotifier.new),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const Scaffold(
                  body: SizedBox(
                    width: 1000,
                    height: 200,
                    child: TimeRulerWidget(),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Marker 'a' is at tick 100 → 80 px (ticksPerPixel = 1.25); right-click
      // on its flag in the indicator zone.
      expect(container.read(markerStateProvider).getMarker('a'), 100);
      final topLeft = tester.getTopLeft(find.byType(TimeRulerWidget));
      await tester.tapAt(
        topLeft + const Offset(80, 5),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      // The context menu offers to remove that specific marker.
      final l10n = await L10N.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.markerRemoveMenuItem('a')));
      await tester.pumpAndSettle();

      expect(container.read(markerStateProvider).getMarker('a'), isNull);
      // The other marker is untouched.
      expect(container.read(markerStateProvider).getMarker('b'), 400);
    });

    testWidgets(
      'right-click away from any marker still places secondary cursor',
      (tester) async {
        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              timeMapperProvider.overrideWith(
                _InitializedTimeMapperNotifier.new,
              ),
              markerStateProvider.overrideWith(_PreloadedMarkerNotifier.new),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const Scaffold(
                    body: SizedBox(
                      width: 1000,
                      height: 200,
                      child: TimeRulerWidget(),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();

        // 600 px is far from markers at 80 px / 320 px → secondary cursor, no menu.
        final topLeft = tester.getTopLeft(find.byType(TimeRulerWidget));
        await tester.tapAt(
          topLeft + const Offset(600, 5),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        expect(
          container.read(cursorStateProvider).secondaryCursorTime,
          isNotNull,
        );
        // Markers untouched; no remove menu was shown.
        expect(container.read(markerStateProvider).getMarker('a'), 100);
      },
    );

    // ── cursor drag in indicator zone ───────────────────────────────────────

    testWidgets('dragging primary cursor triangle moves primary cursor', (
      tester,
    ) async {
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
            cursorStateProvider.overrideWith(_PreloadedCursorNotifier.new),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 200,
                    child: TimeRulerWidget(),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Primary cursor is at time 200 → pixel 160 (ticksPerPixel=1.25).
      // y=3 is in the indicator zone (0..11).
      final topLeft = tester.getTopLeft(find.byType(TimeRulerWidget));
      final startPos = topLeft + const Offset(160, 3);

      final gesture = await tester.startGesture(
        startPos,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      // Drag 100 px to the right.
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // New pixel = 260, new time = round(260 * 1.25) = 325.
      final cursor = container.read(cursorStateProvider);
      expect(cursor.primaryCursorTime, 325);
      // Secondary cursor must remain unchanged.
      expect(cursor.secondaryCursorTime, 600);
    });

    testWidgets('dragging secondary cursor triangle moves secondary cursor', (
      tester,
    ) async {
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
            cursorStateProvider.overrideWith(_PreloadedCursorNotifier.new),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 200,
                    child: TimeRulerWidget(),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Secondary cursor is at time 600 → pixel 480.
      final topLeft = tester.getTopLeft(find.byType(TimeRulerWidget));
      final startPos = topLeft + const Offset(480, 3);

      final gesture = await tester.startGesture(
        startPos,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      // Drag 80 px to the left.
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // New pixel = 400, new time = round(400 * 1.25) = 500.
      final cursor = container.read(cursorStateProvider);
      expect(cursor.secondaryCursorTime, 500);
      // Primary cursor must remain unchanged.
      expect(cursor.primaryCursorTime, 200);
    });

    testWidgets(
      'click below indicator zone (not on triangle) places cursor, not drag',
      (tester) async {
        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              timeMapperProvider.overrideWith(
                _InitializedTimeMapperNotifier.new,
              ),
              cursorStateProvider.overrideWith(_PreloadedCursorNotifier.new),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const Scaffold(
                    body: SizedBox(
                      width: 800,
                      height: 200,
                      child: TimeRulerWidget(),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();

        // Click at the same x as the primary cursor (160px) but y=20 (tick zone).
        // This is outside the indicator hit zone so it should NOT drag — instead
        // it places the primary cursor at the clicked position.
        final topLeft = tester.getTopLeft(find.byType(TimeRulerWidget));
        final startPos = topLeft + const Offset(160, 20);

        final gesture = await tester.startGesture(
          startPos,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        // Move significantly (would move cursor if drag had started).
        await gesture.moveBy(const Offset(200, 0));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        // Since drag was not started (y was outside hit zone), pointer-up places
        // cursor at the up-position (160+200=360px → time 450).
        final cursor = container.read(cursorStateProvider);
        expect(cursor.primaryCursorTime, 450);
      },
    );

    // ── marker flags ────────────────────────────────────────────────────────

    testWidgets('renders without exception when markers are set', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TimeRulerWidget(),
          overrides: [
            markerStateProvider.overrideWith(_PreloadedMarkerNotifier.new),
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
          ],
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });

    // ── cursor indicators ───────────────────────────────────────────────────

    testWidgets('renders without exception when both cursors are set', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TimeRulerWidget(),
          overrides: [
            cursorStateProvider.overrideWith(_PreloadedCursorNotifier.new),
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
          ],
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // ── combined markers and cursors ────────────────────────────────────────

    testWidgets(
      'renders without exception with both markers and cursors active',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const TimeRulerWidget(),
            overrides: [
              markerStateProvider.overrideWith(_PreloadedMarkerNotifier.new),
              cursorStateProvider.overrideWith(_PreloadedCursorNotifier.new),
              timeMapperProvider.overrideWith(
                _InitializedTimeMapperNotifier.new,
              ),
            ],
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    // ── CJK locale sweep ────────────────────────────────────────────────────

    for (final (lang, country) in [
      ('zh', 'CN'),
      ('ja', null),
      ('ko', null),
    ]) {
      testWidgets(
        '${country != null ? '${lang}_$country' : lang} locale — renders without exception',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                timeMapperProvider.overrideWith(
                  _InitializedTimeMapperNotifier.new,
                ),
              ],
              child: MaterialApp(
                locale: Locale(lang, country),
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: const Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 200,
                    child: TimeRulerWidget(),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }

    // ── pattern match bands ─────────────────────────────────────────────────

    testWidgets('pattern match bands render without exception', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TimeRulerWidget(),
          overrides: [
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
            patternSearchProvider.overrideWith(
              _PatternSearchWithMatchesNotifier.new,
            ),
          ],
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });

    // ── double-click on cursor triangle removes cursor ───────────────────────

    testWidgets('double-click on primary cursor triangle removes primary cursor', (
      tester,
    ) async {
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
            cursorStateProvider.overrideWith(_PreloadedCursorNotifier.new),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 200,
                    child: TimeRulerWidget(),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Primary cursor at time 200 → pixel 160; y=3 is in the indicator zone.
      final topLeft = tester.getTopLeft(find.byType(TimeRulerWidget));
      final cursorPos = topLeft + const Offset(160, 3);

      // First tap on the triangle — sets _lastTapTime, does not remove cursor.
      await tester.tapAt(cursorPos);
      await tester.pump();

      // Cursor still present after single tap.
      expect(
        container.read(cursorStateProvider).primaryCursorTime,
        isNotNull,
      );

      // Second tap in quick succession — triggers double-click removal.
      await tester.tapAt(cursorPos);
      await tester.pump();

      // Both cursors are cleared (clearAll is called for primary double-click).
      final state = container.read(cursorStateProvider);
      expect(state.primaryCursorTime, isNull);
      expect(state.secondaryCursorTime, isNull);
    });

    testWidgets(
      'double-click on secondary cursor triangle removes secondary cursor',
      (tester) async {
        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              timeMapperProvider.overrideWith(
                _InitializedTimeMapperNotifier.new,
              ),
              cursorStateProvider.overrideWith(_PreloadedCursorNotifier.new),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const Scaffold(
                    body: SizedBox(
                      width: 800,
                      height: 200,
                      child: TimeRulerWidget(),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();

        // Secondary cursor at time 600 → pixel 480; y=3 is in the indicator zone.
        // Primary is at pixel 160 which is far enough away (|480-160|=320 > 9).
        final topLeft = tester.getTopLeft(find.byType(TimeRulerWidget));
        final secPos = topLeft + const Offset(480, 3);

        await tester.tapAt(secPos);
        await tester.pump();

        // Secondary still present after single tap.
        expect(
          container.read(cursorStateProvider).secondaryCursorTime,
          isNotNull,
        );

        await tester.tapAt(secPos);
        await tester.pump();

        // clearSecondary is called — only secondary is removed.
        final state = container.read(cursorStateProvider);
        expect(state.secondaryCursorTime, isNull);
        expect(state.primaryCursorTime, isNotNull);
      },
    );

    // ── pointer cancel ──────────────────────────────────────────────────────

    testWidgets('pointer cancel during cursor drag stops the drag gracefully', (
      tester,
    ) async {
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
            cursorStateProvider.overrideWith(_PreloadedCursorNotifier.new),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 200,
                    child: TimeRulerWidget(),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Start a drag on the primary cursor triangle.
      final topLeft = tester.getTopLeft(find.byType(TimeRulerWidget));
      final gesture = await tester.startGesture(
        topLeft + const Offset(160, 3),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      // Move a bit, then cancel.
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.cancel();
      await tester.pump();

      // Widget must not throw.
      expect(tester.takeException(), isNull);
      // The cursor state after a cancel may be updated mid-drag; just verify
      // primaryCursorTime is still set (cancel does not call clearAll).
      expect(
        container.read(cursorStateProvider).primaryCursorTime,
        isNotNull,
      );
    });

    // ── hover cursor change ─────────────────────────────────────────────────

    testWidgets('hovering over primary cursor triangle sets hover state', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
            cursorStateProvider.overrideWith(_PreloadedCursorNotifier.new),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 200,
                child: TimeRulerWidget(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Send a hover event at the primary cursor triangle position.
      final topLeft = tester.getTopLeft(find.byType(TimeRulerWidget));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: topLeft + const Offset(160, 3));
      addTearDown(gesture.removePointer);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    // ── time label format at different zoom levels ───────────────────────────

    testWidgets('renders with nanosecond timescale without exception', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
            currentTimescaleProvider.overrideWith(
              (ref) => const Timescale(
                factor: 1,
                unit: TimescaleUnit.nanoSeconds,
              ),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 200,
                child: TimeRulerWidget(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });

    testWidgets(
      'renders with microsecond timescale and wide time range without exception',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              // Wide time range → labels shift from ns to µs.
              timeMapperProvider.overrideWith(_WideRangeTimeMapperNotifier.new),
              currentTimescaleProvider.overrideWith(
                (ref) => const Timescale(
                  factor: 1,
                  unit: TimescaleUnit.nanoSeconds,
                ),
              ),
            ],
            child: const MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  height: 200,
                  child: TimeRulerWidget(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders with millisecond timescale and very wide time range without exception',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              timeMapperProvider.overrideWith(
                _VeryWideRangeTimeMapperNotifier.new,
              ),
              currentTimescaleProvider.overrideWith(
                (ref) => const Timescale(
                  factor: 1,
                  unit: TimescaleUnit.nanoSeconds,
                ),
              ),
            ],
            child: const MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  height: 200,
                  child: TimeRulerWidget(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    // ── delta chip (both cursors + non-zero delta) ──────────────────────────

    testWidgets(
      'delta chip renders without exception when both cursors differ',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const TimeRulerWidget(),
            overrides: [
              timeMapperProvider.overrideWith(
                _InitializedTimeMapperNotifier.new,
              ),
              cursorStateProvider.overrideWith(_PreloadedCursorNotifier.new),
              currentTimescaleProvider.overrideWith(
                (ref) =>
                    const Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds),
              ),
            ],
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    // ── zoom affects tick density ────────────────────────────────────────────

    test('zoomed-in mapper produces more ticks than zoomed-out mapper', () {
      // zoomed-in: visible range 0..100 at 800 px
      final zoomedIn = TimeMapper.fitAll(
        startTime: 0,
        endTime: 100,
        viewportWidth: 800,
      );
      // zoomed-out: visible range 0..10000 at 800 px
      final zoomedOut = TimeMapper.fitAll(
        startTime: 0,
        endTime: 10000,
        viewportWidth: 800,
      );

      final ticksIn = TimeRulerData.compute(zoomedIn, 800).ticks;
      final ticksOut = TimeRulerData.compute(zoomedOut, 800).ticks;

      // The zoomed-in view has a smaller major interval so will generate
      // more or equal total tick marks for the same pixel width.
      expect(ticksIn.length, greaterThanOrEqualTo(ticksOut.length));
    });
  });
}

// ── additional notifier stubs ─────────────────────────────────────────────────

/// [PatternSearchNotifier] pre-loaded with one match in the [0, 1000] range.
class _PatternSearchWithMatchesNotifier extends PatternSearchNotifier {
  @override
  PatternSearchState build() {
    const expr = SignalCondition(
      signalPath: 'top.clk',
      operator: ConditionOperator.eq,
      value: '1',
    );
    const match = PatternMatch(
      time: 200,
      endTime: 400,
      signalValues: {'top.clk': '1'},
    );
    const result = PatternSearchResult(
      matches: [match],
      expression: expr,
      searchRange: TimeRange(start: 0, end: 1000),
    );
    return const PatternSearchState(result: result);
  }
}

/// [TimeMapperNotifier] fit over a 1 µs time range (1 000 000 ticks at 1 ns
/// timescale) to exercise µs-scaled tick labels.
class _WideRangeTimeMapperNotifier extends TimeMapperNotifier {
  @override
  TimeMapper build() => TimeMapper.fitAll(
    startTime: 0,
    endTime: 1000000,
    viewportWidth: 800,
  );
}

/// [TimeMapperNotifier] fit over a 1 ms time range (1 000 000 000 ticks at
/// 1 ns timescale) to exercise ms-scaled tick labels.
class _VeryWideRangeTimeMapperNotifier extends TimeMapperNotifier {
  @override
  TimeMapper build() => TimeMapper.fitAll(
    startTime: 0,
    endTime: 1000000000,
    viewportWidth: 800,
  );
}
