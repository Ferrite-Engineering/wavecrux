// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wavecrux/features/beta_expiry/widgets/beta_expiry_blocking_overlay.dart';
import 'package:wavecrux/features/beta_expiry/widgets/beta_expiry_gate.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

Widget _wrap({
  required BetaExpiryStatus status,
  int? daysRemaining,
}) {
  return ProviderScope(
    overrides: [
      betaExpiryStatusProvider.overrideWithValue(status),
      if (daysRemaining != null)
        betaExpiryDaysRemainingProvider.overrideWithValue(daysRemaining),
    ],
    child: const MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ],
      home: Scaffold(
        body: BetaExpiryGate(child: Text('viewer-content')),
      ),
    ),
  );
}

void main() {
  var quits = 0;

  setUp(() {
    betaExpiryLaunchUrl = (_) async => true;
    // Never let a test reach the real exit(0) — it would kill the runner.
    quits = 0;
    betaExpiryExitApp = () => quits++;
  });

  tearDown(() {
    betaExpiryLaunchUrl = launchUrl;
  });

  testWidgets('notApplicable renders the child untouched', (tester) async {
    await tester.pumpWidget(_wrap(status: BetaExpiryStatus.notApplicable));
    await tester.pumpAndSettle();

    expect(find.text('viewer-content'), findsOneWidget);
    expect(find.byType(CruxBetaExpiryBanner), findsNothing);
    expect(find.byType(BetaExpiryBlockingOverlay), findsNothing);
  });

  testWidgets('active renders the child untouched', (tester) async {
    await tester.pumpWidget(_wrap(status: BetaExpiryStatus.active));
    await tester.pumpAndSettle();

    expect(find.text('viewer-content'), findsOneWidget);
    expect(find.byType(CruxBetaExpiryBanner), findsNothing);
    expect(find.byType(BetaExpiryBlockingOverlay), findsNothing);
  });

  testWidgets('expiringSoon shows the banner above the child', (tester) async {
    await tester.pumpWidget(
      _wrap(status: BetaExpiryStatus.expiringSoon, daysRemaining: 4),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CruxBetaExpiryBanner), findsOneWidget);
    expect(find.text('viewer-content'), findsOneWidget);
    expect(find.byType(BetaExpiryBlockingOverlay), findsNothing);
  });

  testWidgets('dismissing the banner hides it for the session', (tester) async {
    await tester.pumpWidget(
      _wrap(status: BetaExpiryStatus.expiringSoon, daysRemaining: 4),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(CruxBetaExpiryBanner), findsNothing);
    expect(find.text('viewer-content'), findsOneWidget);
  });

  testWidgets('banner download action launches the download URL', (
    tester,
  ) async {
    Uri? launched;
    betaExpiryLaunchUrl = (uri) async {
      launched = uri;
      return true;
    };

    await tester.pumpWidget(
      _wrap(status: BetaExpiryStatus.expiringSoon, daysRemaining: 4),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextButton));
    await tester.pump();

    expect(launched, isNotNull);
    expect(launched!.toString(), contains('download'));
  });

  testWidgets('expired shows the blocking overlay', (tester) async {
    await tester.pumpWidget(_wrap(status: BetaExpiryStatus.expired));
    await tester.pumpAndSettle();

    expect(find.byType(BetaExpiryBlockingOverlay), findsOneWidget);
    expect(find.byType(CruxBetaExpiryBanner), findsNothing);
    // The child remains in the tree, blocked behind the modal barrier.
    expect(find.text('viewer-content'), findsOneWidget);
  });

  testWidgets('expired overlay download action launches the download URL', (
    tester,
  ) async {
    Uri? launched;
    betaExpiryLaunchUrl = (uri) async {
      launched = uri;
      return true;
    };

    await tester.pumpWidget(_wrap(status: BetaExpiryStatus.expired));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(launched, isNotNull);
    expect(launched!.toString(), contains('download'));
  });

  testWidgets('expired overlay quit action exits via betaExpiryExitApp', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(status: BetaExpiryStatus.expired));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextButton));
    await tester.pump();

    expect(quits, 1);
  });
}
