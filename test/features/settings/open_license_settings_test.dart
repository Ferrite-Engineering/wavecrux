// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/core/router.dart' show rootNavigatorKey;
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/settings/open_license_settings.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

import '../../helpers/cxp_test_overrides.dart';

class _MockSettingsService extends Mock implements WaveCruxSettingsService {}

void main() {
  setUpAll(() => registerFallbackValue(const AppSettings()));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('openLicenseSettings', () {
    testWidgets('is a no-op while no root navigator is mounted', (
      tester,
    ) async {
      expect(rootNavigatorKey.currentContext, isNull);
      openLicenseSettings();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens Settings at the License category', (tester) async {
      final service = _MockSettingsService();
      when(service.load).thenAnswer((_) async => const AppSettings());
      when(() => service.save(any())).thenAnswer((_) async {});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...cxpTestOverrides,
            settingsServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      openLicenseSettings();
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<CruxSettingsInitialCategory>(
              find.byType(CruxSettingsInitialCategory),
            )
            .id,
        kCruxLicenseCategoryId,
      );
      expect(tester.takeException(), isNull);
    }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));
  });
}
