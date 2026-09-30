// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/beta_expiry/widgets/beta_expiry_strings.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

/// The banner as `BetaExpiryGate` builds it: `crux_license`'s shared widget
/// bound to WaveCrux's ARB and to a sizing derived from [MobileMetrics].
///
/// These tests deliberately exercise the *binding*, not the widget — the strip
/// itself is covered by `crux_license`'s own suite. What is WaveCrux's to prove
/// is that the ARB plural resolves in every locale, that the device-class
/// sizing still clears the 44 dp touch-target floor, and that the strip still
/// renders with no `Overlay` ancestor.
Widget _banner(
  BuildContext context,
  int days,
  DeviceClass deviceClass, {
  VoidCallback? onDownload,
  VoidCallback? onDismiss,
}) {
  final metrics = MobileMetrics.of(context, deviceClass);
  return CruxBetaExpiryBanner(
    daysRemaining: days,
    onDownload: onDownload ?? () {},
    onDismiss: onDismiss ?? () {},
    strings: WavecruxBetaExpiryStrings(L10N.of(context)),
    sizing: CruxBetaExpirySizing(
      iconSize: metrics.iconSize,
      touchTarget: metrics.touchTarget,
      bodyTextSize: metrics.bodyText,
    ),
  );
}

Widget _wrap({
  required int days,
  Locale locale = const Locale('en'),
  DeviceClass deviceClass = DeviceClass.phone,
  VoidCallback? onDownload,
  VoidCallback? onDismiss,
}) {
  return MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ],
    locale: locale,
    home: Scaffold(
      body: Builder(
        builder: (context) => _banner(
          context,
          days,
          deviceClass,
          onDownload: onDownload,
          onDismiss: onDismiss,
        ),
      ),
    ),
  );
}

/// Pumps the banner with the inherited widgets it needs but deliberately **no
/// `Overlay`** — reproducing the production placement where the banner is a
/// sibling *above* the app's Navigator/Overlay in `MaterialApp.builder`
/// (`BetaExpiryGate`). Any `Overlay`-dependent widget (a `Tooltip`) in the
/// banner throws here, exactly as it would on a real expiring-soon launch.
Widget _wrapNoOverlay({
  required int days,
  Locale locale = const Locale('en'),
  DeviceClass deviceClass = DeviceClass.phone,
}) {
  return Localizations(
    locale: locale,
    delegates: L10N.localizationsDelegates,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Theme(
          data: ThemeData(),
          child: Builder(
            builder: (context) => _banner(context, days, deviceClass),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders without an Overlay ancestor (no Tooltip)', (
    tester,
  ) async {
    // Regression: the banner shows above the Navigator (no Overlay ancestor);
    // a Tooltip on the dismiss button threw "No Overlay widget found" the
    // instant an expiring-soon launch tried to render the strip.
    await tester.pumpWidget(_wrapNoOverlay(days: 5));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('dismiss button carries an accessible name from the ARB', (
    tester,
  ) async {
    // The Semantics wrapper is the only accessible name this control has —
    // a Tooltip is impossible here. Assert the WaveCrux ARB reaches it.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(days: 5));
    await tester.pumpAndSettle();

    final l10n = L10N.of(
      tester.element(find.byType(CruxBetaExpiryBanner)),
    );
    expect(
      find.bySemanticsLabel(l10n.betaExpiryDismissLabel),
      findsOneWidget,
    );
    handle.dispose();
  });

  group('CruxBetaExpiryBanner locale sweep', () {
    for (final locale in _locales) {
      testWidgets('renders without exceptions in $locale', (tester) async {
        await tester.pumpWidget(_wrap(days: 5, locale: locale));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('shows the localized expiry message for the day count', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(days: 5));
    await tester.pumpAndSettle();

    expect(find.textContaining('5'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('download action fires onDownload', (tester) async {
    var downloads = 0;
    await tester.pumpWidget(_wrap(days: 3, onDownload: () => downloads++));
    await tester.pumpAndSettle();

    // The banner's only TextButton is the inline "Download" action.
    await tester.tap(find.byType(TextButton));
    expect(downloads, 1);
  });

  testWidgets('close button fires onDismiss', (tester) async {
    var dismissals = 0;
    await tester.pumpWidget(_wrap(days: 3, onDismiss: () => dismissals++));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    expect(dismissals, 1);
  });

  testWidgets('dismiss button meets the 44x44 touch-target minimum', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(days: 3));
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byType(IconButton));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });
}
