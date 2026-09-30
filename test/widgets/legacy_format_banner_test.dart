// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/enums/waveform_format.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/settings/settings_service.dart';
import 'package:wavecrux/services/waveform/legacy_conversion_controller.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/widgets/legacy_format_banner.dart';

class _MockSettingsService extends Mock implements WaveCruxSettingsService {}

Future<void> _pumpBanner(
  WidgetTester tester, {
  required Locale locale,
  required ProviderContainer container,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(body: LegacyFormatBanner()),
      ),
    ),
  );
}

ProviderContainer _container({
  required AppSettings settings,
}) {
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final mockService = _MockSettingsService();
  when(mockService.load).thenAnswer((_) async => settings);
  when(() => mockService.save(any())).thenAnswer((_) async {});
  return ProviderContainer(
    overrides: [
      deviceClassProvider.overrideWith((ref) => DeviceClass.desktop),
      settingsServiceProvider.overrideWithValue(mockService),
    ],
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const AppSettings());
  });

  group('LegacyFormatBanner', () {
    testWidgets('renders nothing when no fresh-conversion event is present', (
      tester,
    ) async {
      final container = _container(settings: const AppSettings());
      addTearDown(container.dispose);
      // Drive the AppSettings load.
      await container.read(appSettingsProvider.future);

      await _pumpBanner(
        tester,
        locale: const Locale('en'),
        container: container,
      );
      await tester.pump();

      expect(find.byType(MaterialBanner), findsNothing);
    });

    testWidgets('renders the banner on a fresh LXT2 conversion event with the '
        'cached FST path and the LXT2 acronym', (tester) async {
      final container = _container(settings: const AppSettings());
      addTearDown(container.dispose);
      await container.read(appSettingsProvider.future);

      await _pumpBanner(
        tester,
        locale: const Locale('en'),
        container: container,
      );

      container
          .read(legacyConversionEventProvider.notifier)
          .emit(
            origin: WaveformFormat.lxt2,
            fstPath: '/tmp/example.lxt2.fst',
          );
      await tester.pumpAndSettle();

      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(
        find.text(
          'Opened from legacy LXT2 format. Converted to FST and cached at '
          '/tmp/example.lxt2.fst.',
        ),
        findsOneWidget,
      );
      expect(find.text("Don't show again"), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
    });

    testWidgets(
      'banner is suppressed when AppSettings.suppressLegacyFormatBanner '
      'is true, even when an event is present',
      (tester) async {
        final container = _container(
          settings: const AppSettings(suppressLegacyFormatBanner: true),
        );
        addTearDown(container.dispose);
        await container.read(appSettingsProvider.future);

        container
            .read(legacyConversionEventProvider.notifier)
            .emit(
              origin: WaveformFormat.lxt2,
              fstPath: '/tmp/a.fst',
            );

        await _pumpBanner(
          tester,
          locale: const Locale('en'),
          container: container,
        );
        await tester.pumpAndSettle();

        expect(find.byType(MaterialBanner), findsNothing);
      },
    );

    testWidgets(
      '"Don\'t show again" persists the suppress flag and clears the event',
      (tester) async {
        final mockService = _MockSettingsService();
        when(mockService.load).thenAnswer((_) async => const AppSettings());
        when(() => mockService.save(any())).thenAnswer((_) async {});
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWith((ref) => DeviceClass.desktop),
            settingsServiceProvider.overrideWithValue(mockService),
          ],
        );
        addTearDown(container.dispose);
        await container.read(appSettingsProvider.future);

        await _pumpBanner(
          tester,
          locale: const Locale('en'),
          container: container,
        );

        container
            .read(legacyConversionEventProvider.notifier)
            .emit(
              origin: WaveformFormat.lxt2,
              fstPath: '/tmp/a.fst',
            );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('legacyFormatBannerDontShowAgainButton')),
        );
        await tester.pumpAndSettle();

        // Event sink cleared → banner gone.
        expect(
          container.read(legacyConversionEventProvider),
          isNull,
        );
        expect(find.byType(MaterialBanner), findsNothing);

        // suppressLegacyFormatBanner flipped in the in-memory state…
        expect(
          container.read(appSettingsProvider).value!.suppressLegacyFormatBanner,
          isTrue,
        );
        // …and persisted through the settings service.
        verify(
          () => mockService.save(
            any(
              that: predicate<AppSettings>(
                (s) => s.suppressLegacyFormatBanner,
              ),
            ),
          ),
        ).called(1);
      },
    );

    testWidgets(
      'Dismiss clears the current event without touching the suppress flag',
      (tester) async {
        final container = _container(settings: const AppSettings());
        addTearDown(container.dispose);
        await container.read(appSettingsProvider.future);

        await _pumpBanner(
          tester,
          locale: const Locale('en'),
          container: container,
        );

        container
            .read(legacyConversionEventProvider.notifier)
            .emit(
              origin: WaveformFormat.lxt2,
              fstPath: '/tmp/dismiss.fst',
            );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('legacyFormatBannerDismissButton')),
        );
        await tester.pumpAndSettle();

        expect(container.read(legacyConversionEventProvider), isNull);
        expect(
          container.read(appSettingsProvider).value!.suppressLegacyFormatBanner,
          isFalse,
        );
      },
    );

    testWidgets('"Don\'t show again" button is at least 44×44 dp (touch-target '
        'compliance)', (tester) async {
      final container = _container(settings: const AppSettings());
      addTearDown(container.dispose);
      await container.read(appSettingsProvider.future);

      await _pumpBanner(
        tester,
        locale: const Locale('en'),
        container: container,
      );

      container
          .read(legacyConversionEventProvider.notifier)
          .emit(
            origin: WaveformFormat.lxt2,
            fstPath: '/tmp/touch.fst',
          );
      await tester.pumpAndSettle();

      final dontShowAgainSize = tester.getSize(
        find.byKey(const Key('legacyFormatBannerDontShowAgainButton')),
      );
      expect(dontShowAgainSize.width, greaterThanOrEqualTo(44));
      expect(dontShowAgainSize.height, greaterThanOrEqualTo(44));

      final dismissSize = tester.getSize(
        find.byKey(const Key('legacyFormatBannerDismissButton')),
      );
      expect(dismissSize.width, greaterThanOrEqualTo(44));
      expect(dismissSize.height, greaterThanOrEqualTo(44));
    });

    group('locale sweep', () {
      for (final locale in const [
        Locale('en'),
        Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
        Locale.fromSubtags(languageCode: 'zh'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        testWidgets('renders in ${locale.toLanguageTag()} without exceptions', (
          tester,
        ) async {
          final container = _container(settings: const AppSettings());
          addTearDown(container.dispose);
          await container.read(appSettingsProvider.future);

          await _pumpBanner(tester, locale: locale, container: container);

          container
              .read(legacyConversionEventProvider.notifier)
              .emit(
                origin: WaveformFormat.lxt2,
                fstPath: '/tmp/${locale.toLanguageTag()}.fst',
              );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        });
      }
    });
  });
}
