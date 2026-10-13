// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/beta_expiry/widgets/beta_expiry_strings.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// The expired-beta modal is crux_license's CruxBetaExpiredOverlay (its own
// tests cover the barrier, focus trap and actions). What WaveCrux owns is the
// binding of its four ARB keys, checked here in every shipped locale.

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Widget _wrap(Locale locale) => MaterialApp(
  localizationsDelegates: L10N.localizationsDelegates,
  supportedLocales: L10N.supportedLocales,
  locale: locale,
  home: Builder(
    builder: (context) => Scaffold(
      body: CruxBetaExpiredOverlay(
        onDownload: () {},
        onQuit: () {},
        strings: WavecruxBetaExpiredStrings(L10N.of(context)),
        child: const Text('viewer-content'),
      ),
    ),
  ),
);

void main() {
  for (final locale in _locales) {
    testWidgets('the expired modal shows WaveCrux strings in $locale', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(locale));
      await tester.pumpAndSettle();

      final l10n = L10N.of(tester.element(find.byType(CruxBetaExpiredOverlay)));
      expect(find.text(l10n.betaExpiryExpiredTitle), findsOneWidget);
      expect(find.text(l10n.betaExpiryExpiredBody), findsOneWidget);
      expect(find.text(l10n.betaExpiryExpiredAction), findsOneWidget);
      expect(find.text(l10n.betaExpiryExpiredQuit), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
