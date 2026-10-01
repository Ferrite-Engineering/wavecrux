// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_category.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// Surface membership / visibility / enablement used to live here
// (kMenuHiddenActions / menuVisibleActions / groupedActions). That logic now
// lives in the single source of truth `action_descriptors.dart` and is covered
// by `action_descriptors_test.dart`. This file only covers what remains in
// `action_category.dart`: the category assignment and the localized labels.

void main() {
  group('ShortcutActionCategory', () {
    test('every ShortcutAction has a category assignment', () {
      for (final action in ShortcutAction.values) {
        // .category uses an exhaustive switch — this call would throw at
        // compile time if any action were missing.  The loop documents intent.
        expect(
          action.category,
          isA<ActionCategory>(),
          reason: '${action.name} has no category',
        );
      }
    });

    test('every ActionCategory value is reachable', () {
      // `ActionCategory.edit` is populated because annotation
      // authoring is WaveCrux's first action that *creates* something the user
      // then owns, edits and deletes, so it claims the category the shared
      // vocabulary always had for it. An empty category collapses away rather
      // than rendering a blank menu, so this assertion flipping is the visible
      // half of "WaveCrux grew an Edit menu".
      final assigned = ShortcutAction.values.map((a) => a.category).toSet();
      expect(assigned, containsAll(ActionCategory.values));
      expect(
        ShortcutAction.values.where((a) => a.category == ActionCategory.edit),
        [
          // The third occupant, deliberately: removing the selected signals
          // is an edit of the canvas the user curated, and the Signals
          // list's Delete key needs a by-name route. (Enum order, not menu
          // order — the menu groups it after annotation authoring.)
          ShortcutAction.removeSelectedSignals,
          ShortcutAction.addAnnotationAtCursor,
          ShortcutAction.annotateSelectedRange,
        ],
        reason:
            'the Edit menu holds annotation authoring and signal removal — '
            'a further occupant should be a deliberate decision, not a drift',
      );
    });
  });

  group('ActionCategoryLabel locale sweep', () {
    for (final localeName in ['en', 'ja', 'ko', 'zh']) {
      testWidgets('label() returns non-empty strings in $localeName', (
        tester,
      ) async {
        late L10N l10n;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(localeName),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Builder(
              builder: (context) {
                l10n = L10N.of(context);
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        for (final cat in ActionCategory.values) {
          final label = cat.label(l10n);
          expect(
            label,
            isNotEmpty,
            reason: '${cat.name}.label() was empty in $localeName',
          );
        }
      });
    }
  });

  group('ActionCategory.acceleratorLabel (Alt mnemonics)', () {
    // The six top-level menus on the Windows/Linux in-window menu bar.
    const topLevel = [
      ActionCategory.file,
      ActionCategory.view,
      ActionCategory.navigate,
      ActionCategory.search,
      ActionCategory.tools,
      ActionCategory.help,
    ];

    for (final localeName in ['en', 'ja', 'ko', 'zh']) {
      testWidgets('top-level menus have unique, marked mnemonics in '
          '$localeName', (tester) async {
        late L10N l10n;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(localeName),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Builder(
              builder: (context) {
                l10n = L10N.of(context);
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final mnemonics = <String>[];
        for (final cat in topLevel) {
          final accel = cat.acceleratorLabel(l10n);
          // Carries an '&' accelerator marker...
          expect(
            accel,
            contains('&'),
            reason: '${cat.name} mnemonic label missing & in $localeName',
          );
          // ...and strips to non-empty display text.
          expect(
            MenuAcceleratorLabel.stripAcceleratorMarkers(accel),
            isNotEmpty,
          );
          // Capture the char after '&' (the accelerator key).
          final idx = accel.indexOf('&');
          mnemonics.add(accel[idx + 1].toUpperCase());
        }

        // No two top-level menus share a mnemonic key (F/V/N/S/T/H).
        expect(
          mnemonics.toSet().length,
          mnemonics.length,
          reason: 'duplicate mnemonic in $localeName: $mnemonics',
        );
      });
    }

    testWidgets('the app category has no mnemonic (never a top-level menu)', (
      tester,
    ) async {
      late L10N l10n;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) {
              l10n = L10N.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        ActionCategory.app.acceleratorLabel(l10n),
        equals(ActionCategory.app.label(l10n)),
      );
    });
  });
}
