// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:wavecrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// NOTE: These tests exercise the focus-based [ShortcutManagerWidget] mechanism
// (dispatch, text-input guard, remapping, conflict precedence, global-handler
// fall-through). They use NON-[kGlobalKeyHandledActions] actions as fixtures —
// the bare-key navigation + marker-chord set is deliberately routed through the
// viewer's global HardwareKeyboard handler instead of this manager, so using
// e.g. panLeft here would (correctly) never dispatch. `openSearch` / `closeTab`
// are representative actions that remain in the manager; we remap them onto bare
// keys via the provider when a bare-letter keystroke is integral to the test.

Widget _buildApp({
  Map<ShortcutAction, VoidCallback> handlers = const {},
  Widget? child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: ShortcutManagerWidget(
        handlers: handlers,
        // Focus(autofocus: true) ensures a focused widget exists so Shortcuts fires.
        child: child ?? const Focus(autofocus: true, child: SizedBox.expand()),
      ),
    ),
  );
}

void _setBinding(
  WidgetTester tester,
  ShortcutAction action,
  SingleActivator activator,
) {
  ProviderScope.containerOf(
    tester.element(find.byType(ShortcutManagerWidget)),
  ).read(shortcutBindingsProvider.notifier).setBinding(action, activator);
}

void main() {
  group('ShortcutManagerWidget — locale sweep', () {
    testWidgets('renders in en without exception', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('ShortcutManagerWidget — handler dispatch', () {
    testWidgets('fires registered handler when matching key is pressed', (
      tester,
    ) async {
      var fired = false;
      await tester.pumpWidget(
        _buildApp(handlers: {ShortcutAction.openSearch: () => fired = true}),
      );
      await tester.pump(); // allow autofocus to settle
      _setBinding(
        tester,
        ShortcutAction.openSearch,
        const SingleActivator(LogicalKeyboardKey.keyA),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      expect(fired, isTrue);
    });

    testWidgets('does not fire when a non-matching key is pressed', (
      tester,
    ) async {
      var fired = false;
      await tester.pumpWidget(
        _buildApp(handlers: {ShortcutAction.openSearch: () => fired = true}),
      );
      await tester.pump();
      _setBinding(
        tester,
        ShortcutAction.openSearch,
        const SingleActivator(LogicalKeyboardKey.keyA),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pump();

      expect(fired, isFalse);
    });

    testWidgets('fires correct handler among multiple registered actions', (
      tester,
    ) async {
      var searchFired = false;
      var saveFired = false;
      await tester.pumpWidget(
        _buildApp(
          handlers: {
            ShortcutAction.openSearch: () => searchFired = true,
            ShortcutAction.saveSession: () => saveFired = true,
          },
        ),
      );
      await tester.pump();
      _setBinding(
        tester,
        ShortcutAction.openSearch,
        const SingleActivator(LogicalKeyboardKey.keyA),
      );
      _setBinding(
        tester,
        ShortcutAction.saveSession,
        const SingleActivator(LogicalKeyboardKey.keyD),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.pump();

      expect(searchFired, isFalse);
      expect(saveFired, isTrue);
    });
  });

  group('ShortcutManagerWidget — unhandled-intent fall-through (macOS menu)', () {
    // The global catch-all must NOT consume a chord it has no handler for.
    // On macOS that consumption suppresses the native PlatformMenuBar
    // key-equivalent (AppKit walks FlutterView.performKeyEquivalent: before the
    // main menu), so menu-bound shortcuts silently do nothing while menu clicks
    // still work. The bug reproduces as: an ancestor key handler never sees a
    // chord that the manager swallowed.
    testWidgets('lets a chord with no global handler propagate to ancestors', (
      tester,
    ) async {
      var ancestorSawKeyDown = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Focus(
              onKeyEvent: (_, event) {
                // Filter to key-down: the key-up always propagates and would
                // mask whether the down event was swallowed.
                if (event is KeyDownEvent) ancestorSawKeyDown = true;
                return KeyEventResult.ignored;
              },
              // openSearch is deliberately NOT in the (default-empty) handlers
              // map, so its intent has no global handler and must fall through.
              child: const ShortcutManagerWidget(
                child: Focus(autofocus: true, child: SizedBox.expand()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // Remap onto a bare key so a single keydown (no modifier of its own) is
      // the thing under test — a bare letter that produces an intent with no
      // handler must propagate.
      _setBinding(
        tester,
        ShortcutAction.openSearch,
        const SingleActivator(LogicalKeyboardKey.keyA),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      expect(
        ancestorSawKeyDown,
        isTrue,
        reason:
            'an unhandled ShortcutActionIntent must fall through, not be '
            'swallowed — otherwise the native macOS menu key-equivalent is '
            'suppressed',
      );
    });

    testWidgets('still consumes a chord it DOES have a global handler for', (
      tester,
    ) async {
      var ancestorSawKeyDown = false;
      var fired = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Focus(
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent) ancestorSawKeyDown = true;
                return KeyEventResult.ignored;
              },
              child: ShortcutManagerWidget(
                handlers: {ShortcutAction.openSearch: () => fired = true},
                child: const Focus(autofocus: true, child: SizedBox.expand()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // Bare key so the single keydown under test is fully consumed (a modifier
      // chord's own modifier keydown would propagate and mask the result).
      _setBinding(
        tester,
        ShortcutAction.openSearch,
        const SingleActivator(LogicalKeyboardKey.keyA),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      expect(fired, isTrue);
      expect(
        ancestorSawKeyDown,
        isFalse,
        reason: 'a handled chord is consumed and must not propagate',
      );
    });
  });

  group('ShortcutManagerWidget — text-input guard', () {
    testWidgets('bare key is suppressed when a TextField has focus', (
      tester,
    ) async {
      var fired = false;
      await tester.pumpWidget(
        _buildApp(
          handlers: {ShortcutAction.openSearch: () => fired = true},
          child: const Scaffold(body: TextField(autofocus: true)),
        ),
      );
      await tester.pumpAndSettle();
      // Bind openSearch onto a bare letter, then verify the TextField absorbs it.
      _setBinding(
        tester,
        ShortcutAction.openSearch,
        const SingleActivator(LogicalKeyboardKey.keyA),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      expect(fired, isFalse);
    });

    testWidgets('modifier+key shortcut fires even when a TextField has focus', (
      tester,
    ) async {
      var fired = false;
      await tester.pumpWidget(
        _buildApp(
          handlers: {ShortcutAction.openSearch: () => fired = true},
          child: const Scaffold(body: TextField(autofocus: true)),
        ),
      );
      await tester.pumpAndSettle();

      // openSearch is Ctrl+F (non-Mac) — modifier combos must not be blocked.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      expect(fired, isTrue);
    });
  });

  group('ShortcutManagerWidget — provider integration', () {
    testWidgets('uses updated binding after setBinding()', (tester) async {
      var fired = false;
      await tester.pumpWidget(
        _buildApp(handlers: {ShortcutAction.openSearch: () => fired = true}),
      );
      await tester.pump();
      // Start on a bare 'A' binding.
      _setBinding(
        tester,
        ShortcutAction.openSearch,
        const SingleActivator(LogicalKeyboardKey.keyA),
      );
      await tester.pump();

      // Remap openSearch from A → B.
      _setBinding(
        tester,
        ShortcutAction.openSearch,
        const SingleActivator(LogicalKeyboardKey.keyB),
      );
      await tester.pump();

      // Old key no longer fires.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(fired, isFalse);

      // New key fires.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pump();
      expect(fired, isTrue);
    });

    testWidgets('all bindings restored after resetAll()', (tester) async {
      var fired = false;
      await tester.pumpWidget(
        _buildApp(handlers: {ShortcutAction.openSearch: () => fired = true}),
      );
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShortcutManagerWidget)),
      );
      container
          .read(shortcutBindingsProvider.notifier)
          .setBinding(
            ShortcutAction.openSearch,
            const SingleActivator(LogicalKeyboardKey.keyZ),
          );
      await tester.pump();
      container.read(shortcutBindingsProvider.notifier).resetAll();
      await tester.pump();

      // Default binding (Ctrl+F) should fire again.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();
      expect(fired, isTrue);
    });
  });

  group('ShortcutManagerWidget — conflict precedence (issue #36 bug 3)', () {
    testWidgets(
      'a freshly remapped (customized) action wins the chord it collides with',
      (tester) async {
        var searchFired = false;
        var saveFired = false;
        await tester.pumpWidget(
          _buildApp(
            handlers: {
              ShortcutAction.openSearch: () => searchFired = true,
              ShortcutAction.saveSession: () => saveFired = true,
            },
          ),
        );
        await tester.pump();

        // openSearch holds its DEFAULT chord (Ctrl/Cmd+F). Remap saveSession
        // ONTO that same chord, making saveSession the customized interloper.
        final isMac =
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.iOS;
        _setBinding(
          tester,
          ShortcutAction.saveSession,
          SingleActivator(
            LogicalKeyboardKey.keyF,
            meta: isMac,
            control: !isMac,
          ),
        );
        await tester.pump();

        if (isMac) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
        } else {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        if (isMac) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
        } else {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        }
        await tester.pump();

        // The user's customized remap wins; the default owner is shadowed.
        expect(saveFired, isTrue);
        expect(searchFired, isFalse);
      },
    );
  });
}
