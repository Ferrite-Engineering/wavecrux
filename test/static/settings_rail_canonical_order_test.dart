// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/settings/screens/settings_screen.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

/// Asserts the Settings screen's rendered category rail follows
/// `CruxSettingsCategoryId.canonicalOrder` (`package:crux_settings_ui`).
///
/// ## Why this exists
///
/// Every product in the suite presents its Settings rail in one shared
/// order, so a user moving between them finds General first, then
/// Appearance, then the product's own defaults, and so on down to Keyboard
/// Shortcuts. `CruxSettingsCategoryId` gives each category a stable,
/// non-localized id precisely so that order can be asserted rather than
/// merely written down, and its own doc comment says each product asserts
/// it against [CruxSettingsCategoryId.canonicalOrder]. WaveCrux did not:
/// `settings_screen.dart` builds its list in the canonical order, but
/// nothing failed if someone reordered it.
///
/// Categories contributed through `extraSettingsCategoriesProvider` (the
/// Pro overlay's extension seam) always follow these and are asserted by
/// the overlay's own tests, not here. This test covers the open-core rail
/// only.
///
/// ## What this checks, precisely
///
/// This builds the real [SettingsScreen] (not a hand-copied list) and reads
/// the actual [CruxSettingsMasterDetail.categories] it hands to the shared
/// shell — so a future reordering in `settings_screen.dart` is caught
/// whether or not anyone remembers this test exists. The rendered ids are
/// filtered to members of [CruxSettingsCategoryId.canonicalOrder] (a
/// category WaveCrux does not implement — `detectors`, SimCrux-only — is
/// simply absent, which is correct per the canonical order's own doc
/// comment) and then checked to be a strictly-increasing-index subsequence
/// of it: each rendered id's position in the canonical list must be greater
/// than the previous rendered id's position. This tolerates gaps (WaveCrux
/// skips `detectors`) without tolerating a swap.
///
/// This harness does not enable the Privacy or AI conditional categories
/// (both need extra provider wiring — see the Privacy group in
/// `settings_screen_test.dart` for what that involves) or a mobile device
/// class (`orientation`), so those three canonical ids are never present
/// here. That is a real, disclosed gap: an ordering regression that only
/// shows up among those three conditional categories would not be caught by
/// this test. The 9 ids it does check (general, appearance, productDefaults,
/// fileHandling, editors, remoteControl, cxp, extensions, shortcuts) are
/// exactly WaveCrux's unconditional rail.
class _MockSettingsService extends Mock implements WaveCruxSettingsService {}

void main() {
  setUpAll(() {
    registerFallbackValue(const AppSettings());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Settings rail category order is a subsequence of '
    'CruxSettingsCategoryId.canonicalOrder',
    (tester) async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsServiceProvider.overrideWithValue(mock)],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final masterDetail = tester.widget<CruxSettingsMasterDetail>(
        find.byType(CruxSettingsMasterDetail),
      );
      final renderedIds = masterDetail.categories
          .map((c) => c.id)
          .toList(growable: false);

      const canonical = CruxSettingsCategoryId.canonicalOrder;
      final renderedCanonicalIds = renderedIds
          .where(canonical.contains)
          .toList(growable: false);

      // Fails loudly rather than vacuously: if the Settings screen changes
      // shape such that no canonical-order ids render at all (e.g. the
      // shell stops exposing `categories`, or every category loses its id),
      // this catches it instead of the subsequence check passing on an
      // empty list.
      expect(
        renderedCanonicalIds.length,
        greaterThanOrEqualTo(5),
        reason:
            'expected at least 5 canonical-order categories to render '
            "(WaveCrux's unconditional rail alone has 9); found "
            '${renderedCanonicalIds.length}: $renderedCanonicalIds — is '
            'CruxSettingsMasterDetail no longer reachable, or has every '
            'category lost its CruxSettingsCategoryId?',
      );

      var lastIndex = -1;
      final outOfOrder = <String>[];
      for (final id in renderedCanonicalIds) {
        final index = canonical.indexOf(id);
        if (index <= lastIndex) {
          outOfOrder.add(
            '$id (canonical index $index) does not come after the '
            'previous rendered category (canonical index $lastIndex)',
          );
        }
        lastIndex = index;
      }

      expect(
        outOfOrder,
        isEmpty,
        reason:
            'Settings rail rendered order: $renderedCanonicalIds\n'
            'CruxSettingsCategoryId.canonicalOrder: $canonical\n\n'
            '${outOfOrder.join('\n')}',
      );
    },
  );
}
