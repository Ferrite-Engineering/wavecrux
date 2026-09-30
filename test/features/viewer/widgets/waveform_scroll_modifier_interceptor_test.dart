// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_scroll_modifier_interceptor.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

ProviderContainer _initContainer({bool wheelNavigatesTime = false}) {
  final c =
      ProviderContainer(
          overrides: [
            // Pin the wheel-direction setting so the interceptor never has to build
            // the async appSettings graph (which would hit SharedPreferences).
            wheelNavigatesTimeProvider.overrideWithValue(wheelNavigatesTime),
          ],
        )
        ..listen(timeMapperProvider, (_, _) {})
        ..listen(navigationProvider, (_, _) {})
        ..read(timeMapperProvider.notifier).initialize(
          startTime: 0,
          endTime: 10000,
          viewportWidth: 1000,
        );
  return c;
}

// A uniquely-keyed box so the child-rendered test can find exactly one widget.
const Key _contentKey = Key('interceptor_content');

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Widget _wrap(
  ProviderContainer container, {
  void Function(double delta)? onVerticalScroll,
  Locale? locale,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    locale: locale,
    home: Scaffold(
      body: WaveformScrollModifierInterceptor(
        onVerticalScroll: onVerticalScroll,
        child: const SizedBox.expand(
          child: ColoredBox(key: _contentKey, color: Color(0xFF000000)),
        ),
      ),
    ),
  ),
);

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('WaveformScrollModifierInterceptor', () {
    for (final locale in _locales) {
      testWidgets('locale sweep — renders in $locale without exception', (
        tester,
      ) async {
        final container = _initContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(_wrap(container, locale: locale));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('plain mouse scroll does NOT zoom', (tester) async {
      final container = _initContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      final before = container.read(timeMapperProvider).ticksPerPixel;
      final centre = tester.getCenter(
        find.byType(WaveformScrollModifierInterceptor),
      );

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: centre,
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.pump();

      expect(container.read(timeMapperProvider).ticksPerPixel, equals(before));
    });

    testWidgets('plain mouse scroll does NOT pan in default mode', (
      tester,
    ) async {
      final container = _initContainer();
      addTearDown(container.dispose);
      container.read(navigationProvider.notifier).zoomIn();
      container.read(navigationProvider.notifier).zoomIn();
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      final before = container.read(timeMapperProvider).panOffsetTicks;
      final centre = tester.getCenter(
        find.byType(WaveformScrollModifierInterceptor),
      );

      await tester.sendEventToBinding(
        PointerScrollEvent(position: centre, scrollDelta: const Offset(0, 60)),
      );
      await tester.pump();

      // Plain wheel falls through to native list scroll — time is untouched.
      expect(
        container.read(timeMapperProvider).panOffsetTicks,
        equals(before),
      );
    });

    testWidgets('ctrl+scroll up zooms in', (tester) async {
      final container = _initContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      final before = container.read(timeMapperProvider).ticksPerPixel;
      final centre = tester.getCenter(
        find.byType(WaveformScrollModifierInterceptor),
      );

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

      expect(
        container.read(timeMapperProvider).ticksPerPixel,
        lessThan(before),
      );
    });

    testWidgets('ctrl+scroll down zooms out', (tester) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      container.read(navigationProvider.notifier).zoomIn();
      container.read(navigationProvider.notifier).zoomIn();

      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      final before = container.read(timeMapperProvider).ticksPerPixel;
      final centre = tester.getCenter(
        find.byType(WaveformScrollModifierInterceptor),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      addTearDown(() async {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      });

      await tester.sendEventToBinding(
        PointerScrollEvent(position: centre, scrollDelta: const Offset(0, 120)),
      );
      await tester.pump();

      expect(
        container.read(timeMapperProvider).ticksPerPixel,
        greaterThan(before),
      );
    });

    testWidgets('shift+scroll pans the time window', (tester) async {
      final container = _initContainer();
      addTearDown(container.dispose);

      container.read(navigationProvider.notifier).zoomIn();
      container.read(navigationProvider.notifier).zoomIn();

      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      final before = container.read(timeMapperProvider).panOffsetTicks;
      final centre = tester.getCenter(
        find.byType(WaveformScrollModifierInterceptor),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      addTearDown(() async {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      });

      await tester.sendEventToBinding(
        PointerScrollEvent(position: centre, scrollDelta: const Offset(0, 60)),
      );
      await tester.pump();

      expect(
        container.read(timeMapperProvider).panOffsetTicks,
        isNot(equals(before)),
      );
    });

    testWidgets('trackpad scroll does not zoom (non-mouse kind ignored)', (
      tester,
    ) async {
      final container = _initContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      final before = container.read(timeMapperProvider).ticksPerPixel;
      final centre = tester.getCenter(
        find.byType(WaveformScrollModifierInterceptor),
      );

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: centre,
          kind: PointerDeviceKind.trackpad,
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.pump();

      // Trackpad scroll is not claimed by the interceptor.
      expect(container.read(timeMapperProvider).ticksPerPixel, equals(before));
    });

    testWidgets('child widget is rendered', (tester) async {
      final container = _initContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      expect(find.byKey(_contentKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ── navigate-time mode (GTKWave-style wheel) ──────────────────────────────
  group('WaveformScrollModifierInterceptor — navigate-time mode', () {
    testWidgets('plain mouse scroll pans the time window', (tester) async {
      final container = _initContainer(wheelNavigatesTime: true);
      addTearDown(container.dispose);
      container.read(navigationProvider.notifier).zoomIn();
      container.read(navigationProvider.notifier).zoomIn();
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      final before = container.read(timeMapperProvider).panOffsetTicks;
      final centre = tester.getCenter(
        find.byType(WaveformScrollModifierInterceptor),
      );

      await tester.sendEventToBinding(
        PointerScrollEvent(position: centre, scrollDelta: const Offset(0, 60)),
      );
      await tester.pump();

      expect(
        container.read(timeMapperProvider).panOffsetTicks,
        isNot(equals(before)),
      );
    });

    testWidgets('shift+scroll drives the list (does not pan time)', (
      tester,
    ) async {
      final container = _initContainer(wheelNavigatesTime: true);
      addTearDown(container.dispose);
      container.read(navigationProvider.notifier).zoomIn();
      container.read(navigationProvider.notifier).zoomIn();

      var scrolled = 0.0;
      await tester.pumpWidget(
        _wrap(container, onVerticalScroll: (delta) => scrolled += delta),
      );
      await tester.pump();

      final beforePan = container.read(timeMapperProvider).panOffsetTicks;
      final centre = tester.getCenter(
        find.byType(WaveformScrollModifierInterceptor),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      addTearDown(() async {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      });

      await tester.sendEventToBinding(
        PointerScrollEvent(position: centre, scrollDelta: const Offset(0, 48)),
      );
      await tester.pump();

      expect(scrolled, equals(48));
      expect(
        container.read(timeMapperProvider).panOffsetTicks,
        equals(beforePan),
      );
    });

    testWidgets('ctrl+scroll still zooms', (tester) async {
      final container = _initContainer(wheelNavigatesTime: true);
      addTearDown(container.dispose);
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      final before = container.read(timeMapperProvider).ticksPerPixel;
      final centre = tester.getCenter(
        find.byType(WaveformScrollModifierInterceptor),
      );

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

      expect(
        container.read(timeMapperProvider).ticksPerPixel,
        lessThan(before),
      );
    });
  });
}
