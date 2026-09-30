// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/web/web_command_palette_test.dart
//
// Command palette on Flutter Web.
//
// Verifies that the command palette (Ctrl+Shift+P / Cmd+Shift+P) opens
// in Chrome, accepts a partial action label, surfaces the matching
// entry, executes it on Enter, and dismisses cleanly. The browser
// context menu must NOT intercept the shortcut — that is the
// `BrowserContextMenu.disableContextMenu()` call in `bootstrap()`.
//
// The test uses [ShortcutAction.toggleTheme] as a representative action
// because (a) its label is stable across releases, (b) it works on the
// welcome screen with no file loaded, and (c) the side effect (the active
// color-theme preset's brightness flipping in `cruxColorThemeProvider`) is
// directly observable through a provider read — no UI ambiguity.
//
// Gated to web only via `skip: !kIsWeb`. On non-web hosts the test is
// skipped — the web suite deliberately covers the web entry point, while the
// underlying palette widget is already exercised by widget tests on
// desktop.
//
// Run with:
//   flutter drive --target=integration_test/web/web_command_palette_test.dart \
//     -d chrome

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';

import 'package:wavecrux/features/command_palette/widgets/command_palette_dialog.dart';
import 'web_app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'Ctrl+Shift+P opens the palette; typing filters; Enter runs the action',
    (tester) async {
      // Boot the app with no CLI args — lands on the welcome screen.
      // The shortcut handler for openCommandPalette is registered at
      // the `ShortcutManagerWidget` level in app.dart, which is mounted
      // above any route, so the palette is reachable from welcome.
      await seedFirstLaunchAnswers();
      await bootstrap();
      await tester.pump();
      // The empty canvas hosts the indefinitely-animating GlowingAppIcon, so
      // pumpAndSettle would time out. Settle bounded frames instead.
      await settleEmptyCanvas(tester);

      final root = rootContainer(tester);

      // Capture the starting brightness so we can assert the flip later.
      // The active color-theme preset drives brightness; it seeds to the
      // WaveCrux Dark preset and re-derives once settings load. Settle a few
      // frames so the post-load value is the one we compare against.
      var startBrightness = root.read(cruxColorThemeProvider).brightness;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        startBrightness = root.read(cruxColorThemeProvider).brightness;
      }

      // ── Open the palette via keyboard shortcut ─────────────────────────
      // On web `defaultTargetPlatform` reports `TargetPlatform.macOS`,
      // `linux`, or `windows` depending on the user-agent. The binding is
      // `SingleActivator(keyP, meta: isMac, control: !isMac, shift: true)`,
      // and SingleActivator matches modifiers by *equality* — it rejects the
      // combo if an unwanted modifier is also down. So we must press exactly
      // the platform's primary modifier (meta on Mac, control elsewhere),
      // never both. This mirrors the same `isMac` switch the binding uses.
      final isMac = defaultTargetPlatform == TargetPlatform.macOS;
      final primaryModifier = isMac
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(primaryModifier);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(primaryModifier);
      // Glow animates on the welcome screen → pumpAndSettle never settles.
      // Poll until the palette dialog mounts instead.
      await pumpUntil(
        tester,
        () => find.byType(CommandPaletteDialog).evaluate().isNotEmpty,
      );

      // The palette dialog must be on screen.
      expect(
        find.byType(CommandPaletteDialog),
        findsOneWidget,
        reason: 'Ctrl/Cmd+Shift+P must open the command palette on web',
      );

      // ── Type a partial action label ─────────────────────────────────────
      // "toggle the" is a fuzzy match for "Toggle Theme". A non-trivial
      // substring proves the fuzzy-match path runs and that the search
      // field captured keyboard focus.
      final searchField = find.descendant(
        of: find.byType(CommandPaletteDialog),
        matching: find.byType(TextField),
      );
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'toggle the');
      // Poll for the filtered result rather than pumpAndSettle (the welcome
      // screen's GlowingAppIcon animates indefinitely).
      await pumpUntil(
        tester,
        () => find.text('Toggle Theme').evaluate().isNotEmpty,
      );

      // The Toggle Theme item must be visible after filtering. Match on
      // the English label — the welcome screen runs in 'en' by default.
      expect(
        find.text('Toggle Theme'),
        findsWidgets,
        reason: 'filtered palette must surface the Toggle Theme entry',
      );

      // ── Execute the action ─────────────────────────────────────────────
      // Enter on the focused TextField fires the palette's onKeyEvent
      // handler, which pops the dialog and dispatches the
      // ShortcutAction.toggleTheme intent up to the
      // ShortcutManagerWidget's handler in app.dart. That handler flips the
      // brightness by activating the opposite-brightness default preset.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      // Poll for dismissal (welcome screen glow animates indefinitely).
      await pumpUntil(
        tester,
        () => find.byType(CommandPaletteDialog).evaluate().isEmpty,
      );

      // Palette dismissed.
      expect(
        find.byType(CommandPaletteDialog),
        findsNothing,
        reason: 'palette must dismiss after Enter selects an action',
      );

      // Brightness actually flipped — observable side effect proves end-to-end
      // dispatch. Toggle activates the opposite-brightness default preset.
      var endBrightness = startBrightness;
      for (var i = 0; i < 20; i++) {
        endBrightness = root.read(cruxColorThemeProvider).brightness;
        if (endBrightness != startBrightness) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        endBrightness,
        isNot(equals(startBrightness)),
        reason: 'Toggle Theme command-palette dispatch must flip brightness',
      );

      expect(tester.takeException(), isNull);
    },
    skip: !kIsWeb,
  );
}
