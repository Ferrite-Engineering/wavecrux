// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings.dart';
import 'package:wavecrux/core/shortcuts/shortcut_conflicts.dart';

void main() {
  group('resolveShortcutConflicts (issue #36 bugs 1 & 3)', () {
    test('a customized remap wins the chord over the default owner', () {
      // panLeft holds 'A' by default; the user remaps zoomIn (whose real
      // default is a different chord) onto 'A'.
      const a = SingleActivator(LogicalKeyboardKey.keyA);
      final r = resolveShortcutConflicts({
        ShortcutAction.panLeft: a, // == its default → owner
        ShortcutAction.zoomIn: a, // != its default → customized interloper
      });
      // Runtime precedence: the interloper fires; the owner is shadowed.
      expect(r.effectiveBindings.containsKey(ShortcutAction.zoomIn), isTrue);
      expect(r.effectiveBindings.containsKey(ShortcutAction.panLeft), isFalse);
      // Asymmetric UI view: both rows agree zoomIn is the winner.
      expect(
        r.conflicts[ShortcutAction.panLeft]!.winner,
        ShortcutAction.zoomIn,
      );
      expect(r.conflicts[ShortcutAction.zoomIn]!.winner, ShortcutAction.zoomIn);
      expect(r.conflictChordCount, 1);
    });

    test('the default keymap has no collisions (every chord is unique)', () {
      // Guards against re-introducing a default collision like the
      // closeFile/closeTab Cmd/Ctrl+W overlap removed in issue #37.
      final r = resolveShortcutConflicts(defaultBindings());
      expect(r.conflicts, isEmpty);
      expect(r.conflictChordCount, 0);
    });
  });
}
