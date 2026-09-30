// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/shared/widgets/platform_context_menu.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
  TargetPlatform platform = TargetPlatform.macOS,
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    // PlatformContextMenu reads Theme.of(context).platform to decide
    // whether long-press fires a context menu. Default to a desktop OS
    // so the desktop-class tests behave as if running on real desktop.
    theme: ThemeData(platform: platform),
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  ),
);

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('PlatformContextMenu', () {
    testWidgets('renders child widget without exceptions', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PlatformContextMenu(
            onContextMenu: (_) {},
            child: const Text('target'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('target'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // ── right-click (secondary tap) ───────────────────────────────────────────

    testWidgets('right-click fires callback on desktop', (tester) async {
      const childKey = Key('target');
      Offset? received;
      await tester.pumpWidget(
        _wrap(
          PlatformContextMenu(
            onContextMenu: (pos) => received = pos,
            child: const SizedBox(key: childKey, width: 100, height: 100),
          ),
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(childKey)),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(received, isNotNull);
    });

    testWidgets('right-click fires callback on phone', (tester) async {
      const childKey = Key('target');
      Offset? received;
      await tester.pumpWidget(
        _wrap(
          PlatformContextMenu(
            onContextMenu: (pos) => received = pos,
            child: const SizedBox(key: childKey, width: 100, height: 100),
          ),
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.phone),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(childKey)),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(received, isNotNull);
    });

    // ── long-press ────────────────────────────────────────────────────────────

    testWidgets('long-press fires callback on phone', (tester) async {
      const childKey = Key('target');
      var called = false;
      await tester.pumpWidget(
        _wrap(
          PlatformContextMenu(
            onContextMenu: (_) => called = true,
            child: const SizedBox(key: childKey, width: 100, height: 100),
          ),
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.phone),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Use longPressAt to avoid hit-test warning: SizedBox isn't in the
      // hit-test chain but the wrapping GestureDetector (translucent) is.
      await tester.longPressAt(tester.getCenter(find.byKey(childKey)));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    });

    testWidgets('long-press fires callback on phoneLandscape', (tester) async {
      const childKey = Key('target');
      var called = false;
      await tester.pumpWidget(
        _wrap(
          PlatformContextMenu(
            onContextMenu: (_) => called = true,
            child: const SizedBox(key: childKey, width: 100, height: 100),
          ),
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.phoneLandscape),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Use longPressAt to avoid hit-test warning: SizedBox isn't in the
      // hit-test chain but the wrapping GestureDetector (translucent) is.
      await tester.longPressAt(tester.getCenter(find.byKey(childKey)));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    });

    testWidgets('long-press fires callback on tablet', (tester) async {
      const childKey = Key('target');
      var called = false;
      await tester.pumpWidget(
        _wrap(
          PlatformContextMenu(
            onContextMenu: (_) => called = true,
            child: const SizedBox(key: childKey, width: 100, height: 100),
          ),
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.tablet),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Use longPressAt to avoid hit-test warning: SizedBox isn't in the
      // hit-test chain but the wrapping GestureDetector (translucent) is.
      await tester.longPressAt(tester.getCenter(find.byKey(childKey)));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    });

    testWidgets(
      'long-press does NOT fire callback on desktop class + desktop platform',
      (tester) async {
        // Long-press is only suppressed when both the device class is desktop
        // AND the host OS is a true desktop OS (Linux/macOS/Windows). On iPad
        // at desktop class, long-press still fires — see the next test.
        const childKey = Key('target');
        var called = false;
        await tester.pumpWidget(
          _wrap(
            PlatformContextMenu(
              onContextMenu: (_) => called = true,
              child: const SizedBox(key: childKey, width: 100, height: 100),
            ),
            overrides: [
              deviceClassProvider.overrideWithValue(DeviceClass.desktop),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.longPressAt(tester.getCenter(find.byKey(childKey)));
        await tester.pumpAndSettle();

        expect(called, isFalse);
      },
    );

    testWidgets(
      'long-press fires on desktop class when host platform is iOS '
      '(e.g. iPad Pro 12.9" landscape)',
      (tester) async {
        const childKey = Key('target');
        var called = false;
        await tester.pumpWidget(
          _wrap(
            PlatformContextMenu(
              onContextMenu: (_) => called = true,
              child: const SizedBox(key: childKey, width: 100, height: 100),
            ),
            overrides: [
              deviceClassProvider.overrideWithValue(DeviceClass.desktop),
            ],
            platform: TargetPlatform.iOS,
          ),
        );
        await tester.pumpAndSettle();

        await tester.longPressAt(tester.getCenter(find.byKey(childKey)));
        await tester.pumpAndSettle();

        expect(called, isTrue);
      },
    );

    test('shouldEnableLongPressContextMenu honours device class', () {
      const desktop = TargetPlatform.macOS;
      expect(
        shouldEnableLongPressContextMenu(DeviceClass.phone, desktop),
        isTrue,
      );
      expect(
        shouldEnableLongPressContextMenu(DeviceClass.phoneLandscape, desktop),
        isTrue,
      );
      expect(
        shouldEnableLongPressContextMenu(DeviceClass.tablet, desktop),
        isTrue,
      );
      expect(
        shouldEnableLongPressContextMenu(DeviceClass.desktop, desktop),
        isFalse,
      );
    });

    test(
      'shouldEnableLongPressContextMenu enables long-press on iOS desktop',
      () {
        expect(
          shouldEnableLongPressContextMenu(
            DeviceClass.desktop,
            TargetPlatform.iOS,
          ),
          isTrue,
        );
      },
    );

    // ── CJK locale sweep ──────────────────────────────────────────────────────

    for (final locale in ['zh_CN', 'ja', 'ko']) {
      testWidgets('renders in $locale without exceptions', (tester) async {
        final parts = locale.split('_');
        final loc = parts.length == 2
            ? Locale(parts[0], parts[1])
            : Locale(parts[0]);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: loc,
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: PlatformContextMenu(
                  onContextMenu: (_) {},
                  child: const Text('test'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
