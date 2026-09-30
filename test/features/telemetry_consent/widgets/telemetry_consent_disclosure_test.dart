// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_strings.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// The disclosure widget itself now lives in `crux_telemetry`, and its own
// behaviour — the callbacks, the pre-armed toggle, the 44 dp floor, the
// PopScope — is tested there. What is left here is the *binding*, which is the
// part that is genuinely WaveCrux's:
//
//  * `WavecruxTelemetryStrings` maps every member of `CruxTelemetryStrings`
//    onto a real ARB entry, in all five shipped locales. A missing or empty
//    mapping is the failure this file exists to catch, and the package cannot
//    catch it — it carries no ARB files.
//  * `DeviceClass.isPhoneClass` is what `app.dart` hands the gate as
//    `isPhoneLayout`, and it must keep picking the sheet for a phone in
//    landscape.

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

late List<bool> decisions;
late int learnMoreTaps;

Widget _wrap(
  DeviceClass deviceClass, {
  Locale? locale,
  bool initialEnabled = true,
}) {
  decisions = <bool>[];
  learnMoreTaps = 0;
  return MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    locale: locale,
    home: Builder(
      builder: (context) {
        // The same three values `app.dart` computes and hands the gate.
        final metrics = MobileMetrics.of(context, deviceClass);
        return TelemetryConsentDisclosure(
          strings: WavecruxTelemetryStrings(L10N.of(context)),
          initialEnabled: initialEnabled,
          isPhoneLayout: deviceClass.isPhoneClass,
          metrics: CruxTelemetryConsentMetrics(
            touchTarget: metrics.touchTarget,
            iconSize: metrics.iconSize,
            bodyFontSize: metrics.bodyText,
          ),
          onContinue: decisions.add,
          onLearnMore: () => learnMoreTaps++,
        );
      },
    ),
  );
}

void main() {
  testWidgets('states the ask and routes to the full list, from the ARB', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(DeviceClass.desktop));
    await tester.pumpAndSettle();
    final l10n = await L10N.delegate.load(const Locale('en'));

    // The exhaustive lists live on the suite telemetry page. What has
    // to be on screen is the ask, the never-collect claim, and a live route to
    // the page that substantiates it — a dialog with the ask and no route is
    // an advertisement.
    expect(find.text(l10n.telemetryConsentTitle), findsOneWidget);
    expect(find.text(l10n.telemetryConsentBody), findsOneWidget);
    expect(find.text(l10n.telemetryConsentLearnMore), findsOneWidget);
    expect(find.text(l10n.telemetryConsentToggleLabel), findsOneWidget);
    expect(find.text(l10n.telemetryConsentContinue), findsOneWidget);
  });

  test('the adapter maps every member to a non-empty string', () async {
    // Cheap, but it is the exact defect the package cannot see: an adapter
    // getter wired to the wrong — or an unfilled — ARB entry.
    for (final locale in _locales) {
      final strings = WavecruxTelemetryStrings(
        await L10N.delegate.load(locale),
      );
      for (final value in <String>[
        strings.consentTitle,
        strings.consentBody,
        strings.learnMore,
        strings.consentToggleLabel,
        strings.consentContinue,
        strings.settingsToggleLabel,
        strings.settingsToggleDescription,
        strings.settingsDocsLabel,
        strings.settingsDocsDescription,
      ]) {
        expect(value.trim(), isNotEmpty, reason: 'empty string in $locale');
      }
    }
  });

  testWidgets('an untouched opt-in prompt reports a refusal', (tester) async {
    // WaveCrux's half of counsel's 2026-08-06 ruling: the app wires the gate,
    // the gate reads the region, and what reaches this widget is a `false`
    // that must survive to the callback untouched.
    await tester.pumpWidget(_wrap(DeviceClass.desktop, initialEnabled: false));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('telemetryConsentContinueButton')));

    expect(decisions, [false]);
  });

  testWidgets('reports the decision the toggle was left in', (tester) async {
    await tester.pumpWidget(_wrap(DeviceClass.desktop));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('telemetryConsentSwitch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('telemetryConsentContinueButton')));

    expect(decisions, [false]);
  });

  testWidgets('reports the link tap without reporting a decision', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(DeviceClass.desktop));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('telemetryConsentLearnMoreButton')));
    await tester.pumpAndSettle();

    expect(learnMoreTaps, 1);
    expect(decisions, isEmpty);
  });

  // phoneLandscape is the class a phone crosses into on rotation; it must get
  // the sheet, not a dialog squeezed into 380 dp of height.
  for (final deviceClass in DeviceClass.values) {
    testWidgets(
      '$deviceClass picks '
      '${deviceClass.isPhoneClass ? 'the sheet' : 'the dialog'}',
      (tester) async {
        await tester.pumpWidget(_wrap(deviceClass));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('telemetryConsentSheet')),
          deviceClass.isPhoneClass ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('telemetryConsentDialog')),
          deviceClass.isPhoneClass ? findsNothing : findsOneWidget,
        );
      },
    );
  }

  for (final locale in _locales) {
    testWidgets('locale sweep — renders in $locale without exceptions', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(DeviceClass.tablet, locale: locale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
