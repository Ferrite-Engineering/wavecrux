// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/router.dart' show rootNavigatorKey;
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/workspace/providers/startup_recovery_providers.dart';
import 'package:wavecrux/features/workspace/widgets/recovery_banner_host.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

void main() {
  group('RecoveryBannerHost — locale sweep', () {
    for (final locale in _locales) {
      testWidgets('renders the reset banner in $locale without exceptions', (
        tester,
      ) async {
        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              deviceClassProvider.overrideWithValue(DeviceClass.desktop),
            ],
            child: MaterialApp(
              locale: locale,
              navigatorKey: rootNavigatorKey,
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              builder: (context, child) => RecoveryBannerHost(
                child: child ?? const SizedBox.shrink(),
              ),
              home: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const Scaffold(body: SizedBox.shrink());
                },
              ),
            ),
          ),
        );

        container
            .read(startupRecoveryProvider.notifier)
            .configure(
              const StartupRecoveryState(
                reason: StartupRecoveryReason.interrupted,
              ),
            );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });

  // Regression: RecoveryBannerHost renders above the app's Navigator (it wraps
  // the routed content in MaterialApp.builder), so its own context has no
  // Navigator ancestor. Tapping "Reset" called showDialog with that context and
  // threw "Navigator operation requested with a context that does not include a
  // Navigator", so the button did nothing. The host now drives the confirmation
  // from rootNavigatorKey.currentContext, which is inside the Navigator.
  testWidgets(
    'Reset shows the confirmation dialog when the host is above the Navigator',
    (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            // Mirror production: the host wraps the routed content (the
            // Navigator) rather than sitting inside it.
            builder: (context, child) => RecoveryBannerHost(
              child: child ?? const SizedBox.shrink(),
            ),
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const Scaffold(body: SizedBox.shrink());
              },
            ),
          ),
        ),
      );

      // Put the launch into the interrupted recovery posture so the banner —
      // and its Reset action — render.
      container
          .read(startupRecoveryProvider.notifier)
          .configure(
            const StartupRecoveryState(
              reason: StartupRecoveryReason.interrupted,
            ),
          );
      await tester.pumpAndSettle();

      final l10n = await L10N.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.recoveryBannerResetAction));
      await tester.pumpAndSettle();

      // The confirmation dialog must appear — no Navigator exception thrown.
      expect(tester.takeException(), isNull);
      expect(find.text(l10n.resetWorkspaceDialogTitle), findsOneWidget);

      // Cancel so the test does not run the actual reset machinery.
      await tester.tap(find.text(l10n.resetWorkspaceDialogCancel));
      await tester.pumpAndSettle();
      expect(find.text(l10n.resetWorkspaceDialogTitle), findsNothing);
    },
  );
}
