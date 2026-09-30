// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/menu_bar/desktop_menu_bar_test.dart
//
// Per-platform desktop smoke test for the action-discovery menu bar.
//
// Why this is an integration test and not (only) a widget test: the widget
// tests in `test/features/menu_bar/widgets/desktop_menu_bar_test.dart` pump
// `DesktopMenuBar` with a *simulated* platform (`ThemeData(platform: …)`). The
// bug this guards against was platform-real: Flutter's `PlatformMenuBar` only
// bridges to a native menu on macOS, so on Windows and Linux it rendered NOTHING
// at all. Only a real launch — where `defaultTargetPlatform` is genuinely the
// host OS and the app comes up through the real `bootstrap()` — proves the menu
// bar actually appears. On a desktop CI host the physical screen (e.g. the
// 1920×1080 xvfb Linux runner) resolves `deviceClassProvider` to
// `DeviceClass.desktop`, so the menu bar is gated on.
//
// Coverage asymmetry (intentional):
//   • Windows / Linux → the in-window Material `MenuBar` is a real Flutter
//     widget, so we assert it is present, populated, and dispatches an action
//     end-to-end (open View → tap Toggle Theme → the active preset's brightness
//     flips). THIS is the path that regressed to "no menus".
//   • macOS → the native `PlatformMenuBar` renders through an AppKit `NSMenu`
//     OUTSIDE the Flutter view; its items can't be found or tapped from the
//     test harness. We assert only that the bridge widget is present; driving
//     the native menu stays a manual verification step (§21.3).

import 'dart:io';

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/core/shortcuts/action_category.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'the desktop menu bar renders in the live app on the host platform',
    (tester) async {
      // Force a desktop-class logical size up front. Under the live
      // integration binding `deviceClassProvider` follows the real view's
      // logical size (physicalSize ÷ devicePixelRatio), so on a Retina dev
      // machine the default window is ~640 dp wide → tablet, which gates the
      // menu bar off. Pinning the view to 1600×1000 @1× makes the desktop path
      // run deterministically on any host (the 1920×1080 Linux CI runner is
      // already desktop-class, so this is a no-op there). The defensive skip
      // below stays as a backstop in case a host ignores the override.
      tester.view
        ..devicePixelRatio = 1.0
        ..physicalSize = const Size(1600, 1000);
      addTearDown(() {
        tester.view
          ..resetPhysicalSize()
          ..resetDevicePixelRatio();
      });

      // A tiny fixture gives a deterministic, fully-up viewer (the menu bar is
      // present with or without a file, but a loaded viewer avoids the
      // empty-canvas branding PNGs that don't resolve in the headless bundle).
      await loadFixtureVcd(tester, 'vcd/scalar_basics.vcd');

      final root = rootContainer(tester);

      // The menu bar only renders at desktop device class. On a desktop CI host
      // the physical screen dominates and this is reliably desktop; bail out
      // defensively if a small host window classified otherwise so we never
      // emit a false failure.
      final deviceClass = root.read(deviceClassProvider);
      if (deviceClass != DeviceClass.desktop) {
        markTestSkipped(
          'host window classified as ${deviceClass.name}, not desktop — the '
          'menu bar is gated off below desktop class',
        );
        return;
      }

      if (Platform.isMacOS) {
        // Native system menu bar. The NSMenu is out-of-view AppKit, so assert
        // only the bridge widget; contents/clicks are manual (§21.3).
        expect(
          find.byType(PlatformMenuBar),
          findsOneWidget,
          reason: 'macOS must render the native PlatformMenuBar',
        );
        expect(
          find.byType(MenuBar),
          findsNothing,
          reason: 'macOS uses the native menu, not the in-window Material bar',
        );
      } else {
        // Windows / Linux: PlatformMenuBar is a silent no-op, so DesktopMenuBar
        // renders an in-window Material MenuBar instead. This is the exact path
        // that regressed to showing no menus at all.
        expect(
          find.byType(PlatformMenuBar),
          findsNothing,
          reason:
              'PlatformMenuBar is a no-op on ${Platform.operatingSystem}; '
              'it must not be used there',
        );
        expect(
          find.byType(MenuBar),
          findsOneWidget,
          reason:
              '${Platform.operatingSystem} must render an in-window '
              'Material MenuBar (regression: it previously showed no menus)',
        );

        final l10n = L10N.of(tester.element(find.byType(MenuBar)));

        // End-to-end dispatch: open the View menu and tap Toggle Theme. This
        // action has an observable in-app effect and triggers no platform
        // dialog (unlike Open File…), so it is safe under headless CI. Toggle
        // Theme flips the active color-theme preset's brightness.
        final before = root.read(cruxColorThemeProvider).brightness;

        await tester.tap(
          find.descendant(
            of: find.byType(MenuBar),
            matching: find.text(ActionCategory.view.label(l10n)),
          ),
        );
        await tester.pumpAndSettle();

        // The opened submenu's items render in a MenuAnchor overlay (not under
        // the MenuBar subtree), so match the label globally.
        await tester.tap(
          find.text(ShortcutAction.toggleTheme.label(l10n)).last,
        );

        final advanced = await pumpUntil(
          tester,
          () => root.read(cruxColorThemeProvider).brightness != before,
          timeout: const Duration(seconds: 5),
        );
        expect(
          advanced,
          isTrue,
          reason:
              'tapping Toggle Theme in the in-window menu bar must dispatch '
              'the action and flip the active preset brightness',
        );
      }

      tester.takeException();
    },
  );
}
