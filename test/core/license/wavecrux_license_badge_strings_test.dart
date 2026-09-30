// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/license/wavecrux_license_badge_strings.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

Future<L10N> _l10nFor(WidgetTester tester, Locale locale) async {
  late L10N captured;
  await tester.pumpWidget(
    Localizations(
      locale: locale,
      delegates: const [
        ...L10N.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: Builder(
        builder: (context) {
          captured = L10N.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  group('WaveCruxLicenseBadgeStrings', () {
    testWidgets(
      'routes every chip-string getter to the L10N equivalent in en',
      (tester) async {
        final l10n = await _l10nFor(tester, const Locale('en'));
        final strings = WaveCruxLicenseBadgeStrings(l10n);

        expect(strings.tierBadgePro, l10n.tierBadgePro);
        expect(strings.tierBadgeProSemantic, l10n.tierBadgeProSemantic);
        expect(strings.tierBadgeEnterprise, l10n.tierBadgeEnterprise);
        expect(
          strings.tierBadgeEnterpriseSemantic,
          l10n.tierBadgeEnterpriseSemantic,
        );
        expect(strings.tierBadgeEdu, l10n.tierBadgeEdu);
        expect(strings.tierBadgeEduSemantic, l10n.tierBadgeEduSemantic);
      },
    );

    testWidgets('returns localized values in zh_CN', (tester) async {
      final l10n = await _l10nFor(
        tester,
        const Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
      );
      final strings = WaveCruxLicenseBadgeStrings(l10n);

      // We don't pin the exact translation here — that belongs in the ARB
      // diffs — but we do assert the adapter routes through L10N rather
      // than baking in English defaults.
      expect(strings.tierBadgeEdu, l10n.tierBadgeEdu);
      expect(strings.tierBadgeEduSemantic, l10n.tierBadgeEduSemantic);
    });
  });
}
