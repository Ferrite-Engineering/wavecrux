// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/workspace/providers/startup_recovery_providers.dart';
import 'package:wavecrux/features/workspace/widgets/recovery_banner.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Widget _wrap({
  required StartupRecoveryReason reason,
  required bool canResume,
  Locale locale = const Locale('en'),
  DeviceClass deviceClass = DeviceClass.phone,
  VoidCallback? onResume,
  VoidCallback? onReset,
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
      body: RecoveryBanner(
        reason: reason,
        deviceClass: deviceClass,
        canResume: canResume,
        onResume: onResume ?? () {},
        onReset: onReset ?? () {},
        onDismiss: onDismiss ?? () {},
      ),
    ),
  );
}

/// Pumps [child] with the inherited widgets the banner needs (localizations,
/// directionality, media query, a Theme) but deliberately **no `Overlay`** —
/// reproducing the production placement where the banner is a sibling *above*
/// the app's Navigator/Overlay in `MaterialApp.builder`. Any `Overlay`-
/// dependent widget (a `Tooltip`) in the banner throws here, exactly as it did
/// on the recovery launch.
Widget _wrapNoOverlay({
  required StartupRecoveryReason reason,
  required bool canResume,
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
          child: RecoveryBanner(
            reason: reason,
            deviceClass: deviceClass,
            canResume: canResume,
            onResume: () {},
            onReset: () {},
            onDismiss: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('RecoveryBanner renders without an Overlay ancestor', () {
    // Regression: the banner shows above the Navigator (no Overlay ancestor);
    // a Tooltip on the dismiss button threw "No Overlay widget found" the
    // instant a recovery launch tried to render the strip.
    for (final reason in const [
      StartupRecoveryReason.interrupted,
      StartupRecoveryReason.workspaceCorrupt,
    ]) {
      testWidgets('no Overlay error: $reason', (tester) async {
        await tester.pumpWidget(
          _wrapNoOverlay(reason: reason, canResume: true),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.close), findsOneWidget);
      });
    }
  });

  group('RecoveryBanner locale sweep', () {
    for (final locale in _locales) {
      for (final reason in const [
        StartupRecoveryReason.interrupted,
        StartupRecoveryReason.workspaceCorrupt,
      ]) {
        testWidgets('renders without exceptions: $reason in $locale', (
          tester,
        ) async {
          await tester.pumpWidget(
            _wrap(reason: reason, canResume: true, locale: locale),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  testWidgets('interrupted + canResume shows Open last session, Reset, close', (
    tester,
  ) async {
    final l10n = await _l10n();
    await tester.pumpWidget(
      _wrap(reason: StartupRecoveryReason.interrupted, canResume: true),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.recoveryBannerResumeAction), findsOneWidget);
    expect(find.text(l10n.recoveryBannerResetAction), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('workspaceCorrupt (no resume) hides Open last session', (
    tester,
  ) async {
    final l10n = await _l10n();
    await tester.pumpWidget(
      _wrap(reason: StartupRecoveryReason.workspaceCorrupt, canResume: false),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.recoveryBannerResumeAction), findsNothing);
    expect(find.text(l10n.recoveryBannerResetAction), findsOneWidget);
  });

  testWidgets('canResume false hides the resume action even when interrupted', (
    tester,
  ) async {
    final l10n = await _l10n();
    await tester.pumpWidget(
      _wrap(reason: StartupRecoveryReason.interrupted, canResume: false),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.recoveryBannerResumeAction), findsNothing);
  });

  testWidgets('actions fire their callbacks', (tester) async {
    final l10n = await _l10n();
    var resumed = 0;
    var reset = 0;
    var dismissed = 0;
    await tester.pumpWidget(
      _wrap(
        reason: StartupRecoveryReason.interrupted,
        canResume: true,
        onResume: () => resumed++,
        onReset: () => reset++,
        onDismiss: () => dismissed++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.recoveryBannerResumeAction));
    await tester.tap(find.text(l10n.recoveryBannerResetAction));
    await tester.tap(find.byIcon(Icons.close));
    expect(resumed, 1);
    expect(reset, 1);
    expect(dismissed, 1);
  });

  testWidgets('dismiss close button meets the 44dp touch target on phone', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(reason: StartupRecoveryReason.interrupted, canResume: true),
    );
    await tester.pumpAndSettle();

    final closeButton = find.ancestor(
      of: find.byIcon(Icons.close),
      matching: find.byType(IconButton),
    );
    final size = tester.getSize(closeButton);
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });
}

Future<L10N> _l10n() => L10N.delegate.load(const Locale('en'));
