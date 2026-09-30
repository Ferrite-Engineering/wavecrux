// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_menu_bar/crux_menu_bar.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_descriptor.dart';
import 'package:wavecrux/core/shortcuts/action_descriptors.dart';
import 'package:wavecrux/core/shortcuts/menu_layout.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';

void main() {
  group('kMenuLayout', () {
    test('covers exactly the menu-visible action set', () {
      // Every action placed in the layout table, plus the two app-folded items
      // (Settings / Quit) the shared menu bar positions per-platform (macOS
      // application menu / bottom of the File menu on Windows & Linux).
      final placed = <ShortcutAction>{
        ...cruxMenuLayoutActions(kMenuLayout),
        ...kAppMenuActions.desktopFolded,
      };
      // Every action whose descriptor lists the menu surface.
      final menuVisible = ShortcutAction.values
          .where((a) => descriptorFor(a).surfaces.contains(ActionSurface.menu))
          .toSet();
      expect(
        placed,
        equals(menuVisible),
        reason:
            'A menu-visible action is missing from kMenuLayout (or the '
            'table places an action that is no longer menu-visible). Place it '
            'in the appropriate category group in menu_layout.dart so it gets '
            'a home in the menu bar.',
      );
    });

    test('leads View with the command palette and Help with Documentation', () {
      // The suite-wide canonical order: VS Code puts the palette opener at the
      // top of View, and every product's Help menu leads with Documentation.
      expect(
        kMenuLayout[ActionCategory.view]!.first,
        [ShortcutAction.openCommandPalette],
      );
      expect(
        kMenuLayout[ActionCategory.help]!.first,
        [ShortcutAction.openDocumentation],
      );
      // …and About is the last thing in Help on Windows/Linux.
      expect(kMenuLayout[ActionCategory.help]!.last, [
        ShortcutAction.openAbout,
      ]);
    });

    test('ends Tools with the diagnostics group', () {
      expect(
        kMenuLayout[ActionCategory.tools]!.last,
        contains(ShortcutAction.openAppDiagnostics),
      );
    });

    test('declares an Edit menu holding annotation authoring', () {
      // Annotation authoring is WaveCrux's first create action. The
      // create action is deliberately not filed under View — that menu is
      // visibility toggles — nor under Navigate, whose annotation group is the
      // walkthrough, which is reading rather than writing.
      expect(kMenuLayout[ActionCategory.edit], [
        [
          ShortcutAction.addAnnotationAtCursor,
          ShortcutAction.annotateSelectedRange,
        ],
      ]);
    });

    test('places no action more than once', () {
      final seen = <ShortcutAction>{};
      for (final groups in kMenuLayout.values) {
        for (final group in groups) {
          for (final action in group) {
            expect(
              seen.add(action),
              isTrue,
              reason: '$action appears more than once in kMenuLayout',
            );
          }
        }
      }
    });

    test('does not place the app-folded actions (Settings / Quit)', () {
      // Settings and Quit have platform-specific placement that the table
      // cannot express, so DesktopMenuBar positions them directly. They must
      // not also appear in a layout group, or they would render twice.
      final placed = cruxMenuLayoutActions(kMenuLayout);
      for (final action in kAppMenuActions.desktopFolded) {
        expect(placed, isNot(contains(action)));
      }
      // About and Check for Updates, by contrast, MUST be in the layout: they
      // stay in Help on Windows/Linux and only macOS hoists them.
      expect(placed, contains(kAppMenuActions.about));
      expect(placed, contains(kAppMenuActions.checkForUpdates));
    });

    test('every placed action keeps the menu surface in its descriptor', () {
      for (final groups in kMenuLayout.values) {
        for (final group in groups) {
          for (final action in group) {
            expect(
              descriptorFor(action).surfaces.contains(ActionSurface.menu),
              isTrue,
              reason:
                  '$action is placed in the menu layout but its descriptor '
                  'does not list ActionSurface.menu',
            );
          }
        }
      }
    });

    test('places each action in the category its descriptor declares', () {
      // The layout groups an action under a top-level menu by map key; that key
      // must match the action\'s own category, or the menu bar would render the
      // item under a heading that disagrees with every other surface.
      kMenuLayout.forEach((category, groups) {
        for (final group in groups) {
          for (final action in group) {
            expect(
              action.category,
              category,
              reason:
                  '$action is placed under $category but its category is '
                  '${action.category}',
            );
          }
        }
      });
    });
  });
}
