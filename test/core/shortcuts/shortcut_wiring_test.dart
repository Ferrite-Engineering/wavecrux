// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings.dart';
import 'package:wavecrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// End-to-end wiring guard: every keyboard shortcut declared in
/// [defaultBindings] must travel through the real [ShortcutManagerWidget]
/// (Shortcuts → ShortcutActionIntent → Actions) and reach a handler.
///
/// This catches the failure mode that left `Set Marker (M + a–z)` and
/// `Jump to Marker (⇧M + a–z)` advertised in the command palette while no key
/// binding existed — the labels promised a chord the keyboard never fired.
/// A binding that cannot be dispatched (malformed activator, dropped from the
/// shortcuts map) now fails this test instead of silently doing nothing.
void main() {
  // Pressing an activator with its modifier keys held, mirroring what a real
  // keystroke produces. Returns after a pump so the dispatched intent settles.
  Future<void> press(WidgetTester tester, SingleActivator a) async {
    final mods = <LogicalKeyboardKey>[
      if (a.control) LogicalKeyboardKey.control,
      if (a.meta) LogicalKeyboardKey.meta,
      if (a.alt) LogicalKeyboardKey.alt,
      if (a.shift) LogicalKeyboardKey.shift,
    ];
    for (final m in mods) {
      await tester.sendKeyDownEvent(m);
    }
    await tester.sendKeyEvent(a.trigger);
    for (final m in mods.reversed) {
      await tester.sendKeyUpEvent(m);
    }
    await tester.pump();
  }

  testWidgets(
    'every default binding dispatches a ShortcutActionIntent to a handler',
    (tester) async {
      final bindings = defaultBindings();

      // Record the last dispatched action. Register a handler for *every*
      // action so whichever action an activator resolves to is captured. With
      // no default collisions (issue #37 removed the closeFile/closeTab shadow)
      // each default chord resolves to a single action.
      ShortcutAction? last;
      final handlers = <ShortcutAction, VoidCallback>{
        for (final a in ShortcutAction.values) a: () => last = a,
      };

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: ShortcutManagerWidget(
              handlers: handlers,
              child: const Focus(autofocus: true, child: SizedBox.expand()),
            ),
          ),
        ),
      );
      await tester.pump(); // allow autofocus to settle

      for (final entry in bindings.entries) {
        // Bare-key navigation + marker chords are deliberately NOT in the focus
        // Shortcuts layer — the viewer's global HardwareKeyboard handler owns
        // them (see kGlobalKeyHandledActions). Their wiring is covered by the
        // globalKeyHandledActionFor matcher test below.
        if (kGlobalKeyHandledActions.contains(entry.key)) continue;

        final activator = entry.value as SingleActivator;
        last = null;
        await press(tester, activator);

        expect(
          last,
          isNotNull,
          reason:
              '${entry.key.name} (${activator.trigger.keyLabel}) did not '
              'dispatch any action — its binding is not wired up.',
        );
        // The dispatched action must be one that actually carries this
        // activator (robust to any shadowed activator, without hard-coding a
        // pair). SingleActivator has no value equality, so compare its fields
        // rather than the instance.
        final dispatched = bindings[last] as SingleActivator?;
        final sameActivator =
            dispatched != null &&
            dispatched.trigger == activator.trigger &&
            dispatched.control == activator.control &&
            dispatched.meta == activator.meta &&
            dispatched.shift == activator.shift &&
            dispatched.alt == activator.alt;
        expect(
          sameActivator,
          isTrue,
          reason:
              'Pressing the ${entry.key.name} activator dispatched '
              '${last!.name}, which is not bound to that activator.',
        );
      }
    },
  );

  group('global key-handled set (viewer HardwareKeyboard handler)', () {
    final bindings = defaultBindings();

    ShortcutAction? matchActivator(SingleActivator a) =>
        globalKeyHandledActionFor(
          bindings,
          logicalKey: a.trigger,
          isControlPressed: a.control,
          isShiftPressed: a.shift,
          isAltPressed: a.alt,
          isMetaPressed: a.meta,
        );

    test('every global-handled action resolves from its own binding', () {
      // This is the wiring guard for the bare keys that the focus Shortcuts
      // dispatch test above skips: each must be matchable by the global handler.
      for (final action in kGlobalKeyHandledActions) {
        final activator = bindings[action]! as SingleActivator;
        expect(
          matchActivator(activator),
          action,
          reason: '${action.name} is not resolvable by the global key handler',
        );
      }
    });

    test('M arms set-marker; ⇧M arms jump-to-marker (chord wiring)', () {
      expect(
        matchActivator(bindings[ShortcutAction.setMarker]! as SingleActivator),
        ShortcutAction.setMarker,
      );
      expect(
        matchActivator(
          bindings[ShortcutAction.jumpToMarker]! as SingleActivator,
        ),
        ShortcutAction.jumpToMarker,
      );
    });

    test('bare A = panLeft does not match while Shift is held', () {
      // Exact-modifier matching: Shift+A must not fire panLeft (it would be a
      // different binding), so the chord-completion/letter path is unaffected.
      expect(
        globalKeyHandledActionFor(
          bindings,
          logicalKey: LogicalKeyboardKey.keyA,
          isControlPressed: false,
          isShiftPressed: true,
          isAltPressed: false,
          isMetaPressed: false,
        ),
        isNull,
      );
    });

    test('a non-bound bare letter (k) matches nothing', () {
      expect(
        globalKeyHandledActionFor(
          bindings,
          logicalKey: LogicalKeyboardKey.keyK,
          isControlPressed: false,
          isShiftPressed: false,
          isAltPressed: false,
          isMetaPressed: false,
        ),
        isNull,
      );
    });
  });
}
