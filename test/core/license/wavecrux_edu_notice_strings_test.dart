// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/license/wavecrux_edu_notice_strings.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

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

CruxLicenseStatus _status(LicenseTier tier) => CruxLicenseStatus(
  activation: CruxLicenseActivation.active,
  grant: LicenseGrant(
    issuerId: kEduLicenseIssuerId,
    tier: tier,
    products: CruxProduct.values.toSet(),
    licenseId: 'lic-1',
    email: 'student@example.edu',
    expiry: DateTime.utc(2027, 8, 2, 12),
  ),
);

void main() {
  group('WaveCruxEduNoticeStrings', () {
    testWidgets('matches the shared English strings in en', (tester) async {
      final l10n = await _l10nFor(tester, const Locale('en'));
      final strings = WaveCruxEduNoticeStrings(l10n);
      const en = CruxEduNoticeStringsEn();

      expect(strings.statusLabel, en.statusLabel);
      expect(strings.exportMark('WaveCrux'), en.exportMark('WaveCrux'));
      for (final email in [null, 'student@example.edu']) {
        for (final until in [null, '2027-08-02']) {
          expect(
            strings.statusTooltip(email: email, validUntil: until),
            en.statusTooltip(email: email, validUntil: until),
            reason: 'email=$email validUntil=$until',
          );
        }
      }
    });

    testWidgets('the tooltip names the holder, the terms and the expiry', (
      tester,
    ) async {
      final l10n = await _l10nFor(tester, const Locale('en'));
      final tooltip = WaveCruxEduNoticeStrings(
        l10n,
      ).statusTooltip(email: 'a@b.edu', validUntil: '2027-08-02');

      expect(
        tooltip,
        'Educational license for a@b.edu. For non-commercial teaching, '
        'learning and research only. Valid until 2027-08-02.',
      );
    });

    testWidgets('CJK sentences join without a space after a full-width stop', (
      tester,
    ) async {
      final l10n = await _l10nFor(tester, const Locale('ja'));
      final tooltip = WaveCruxEduNoticeStrings(
        l10n,
      ).statusTooltip(email: 'a@b.edu', validUntil: '2027-08-02');

      expect(tooltip, contains('a@b.edu'));
      expect(tooltip, contains('2027-08-02'));
      expect(tooltip, isNot(contains('。 ')));
    });

    for (final locale in _locales) {
      testWidgets('is localized and carries the product name in $locale', (
        tester,
      ) async {
        final l10n = await _l10nFor(tester, locale);
        final strings = WaveCruxEduNoticeStrings(l10n);

        expect(strings.statusLabel, isNotEmpty);
        expect(strings.exportMark('WaveCrux'), contains('WaveCrux'));
        expect(strings.exportMark('WaveCrux'), isNot(contains('—')));
        expect(strings.statusLabel, isNot(contains('—')));
        if (locale.languageCode != 'en') {
          expect(
            strings.statusLabel,
            isNot(const CruxEduNoticeStringsEn().statusLabel),
          );
        }
      });
    }
  });

  group('waveCruxEduExportMark', () {
    testWidgets('marks an educational licence, in WaveCrux’s name', (
      tester,
    ) async {
      final l10n = await _l10nFor(tester, const Locale('en'));

      expect(
        waveCruxEduExportMark(_status(LicenseTier.edu), l10n),
        'Made with WaveCrux Educational · Non-commercial use only',
      );
    });

    testWidgets('is null for open core, Pro and Enterprise', (tester) async {
      final l10n = await _l10nFor(tester, const Locale('en'));

      expect(waveCruxEduExportMark(CruxLicenseStatus.openCore, l10n), isNull);
      expect(waveCruxEduExportMark(_status(LicenseTier.pro), l10n), isNull);
      expect(
        waveCruxEduExportMark(_status(LicenseTier.enterprise), l10n),
        isNull,
      );
    });
  });
}
