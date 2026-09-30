// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/app_info/application_edition_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Pumps a minimal app and exposes the edition string via [onEdition].
Future<void> _pumpAndRead(
  WidgetTester tester, {
  required void Function(String edition) onEdition,
  String locale = 'en',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Consumer(
          builder: (ctx, ref, _) {
            final l10n = L10N.of(ctx);
            final edition = ref.watch(applicationEditionProvider(l10n));
            onEdition(edition);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('applicationEditionProvider', () {
    // ── default behaviour ────────────────────────────────────────────────────

    testWidgets('default returns non-empty edition string in en', (
      tester,
    ) async {
      String? edition;
      await _pumpAndRead(tester, onEdition: (e) => edition = e);

      expect(edition, isNotNull);
      expect(edition, isNotEmpty);
    });

    testWidgets('default returns "Open Core" label in en', (tester) async {
      String? edition;
      await _pumpAndRead(tester, onEdition: (e) => edition = e);

      // The open-core default must surface the "Open Core" string (English).
      expect(edition, equals('Open Core'));
    });

    // ── tier-switch paths ────────────────────────────────────────────────────
    // The provider derives the label from licenseTierProvider so these paths
    // are covered here without needing a Pro overlay.

    for (final (tier, expected) in [
      (LicenseTier.edu, 'EDU'),
      (LicenseTier.pro, 'Pro'),
      (LicenseTier.enterprise, 'Enterprise'),
    ]) {
      testWidgets('returns "$expected" when tier is $tier', (tester) async {
        String? edition;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              licenseTierProvider.overrideWith((_) => tier),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Consumer(
                builder: (ctx, ref, _) {
                  final l10n = L10N.of(ctx);
                  edition = ref.watch(applicationEditionProvider(l10n));
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(edition, equals(expected));
      });
    }

    // The Pro overlay's end-to-end override is tested in the Pro overlay.

    // ── locale sweep ─────────────────────────────────────────────────────────

    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Consumer(
                builder: (ctx, ref, _) {
                  final l10n = L10N.of(ctx);
                  ref.watch(applicationEditionProvider(l10n));
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
