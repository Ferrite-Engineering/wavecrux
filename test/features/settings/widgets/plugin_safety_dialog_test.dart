// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/settings/widgets/plugin_safety_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

class _MockSettingsService extends Mock implements WaveCruxSettingsService {}

Widget _wrap({
  required WaveCruxSettingsService service,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      settingsServiceProvider.overrideWithValue(service),
    ],
    child: MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ],
      locale: locale,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => PluginSafetyDialog.show(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const AppSettings());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ── Locale sweep ───────────────────────────────────────────────────────────

  group('PluginSafetyDialog locale sweep', () {
    for (final locale in const <Locale>[
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders without exceptions in $locale', (tester) async {
        final mock = _MockSettingsService();
        when(mock.load).thenAnswer((_) async => const AppSettings());
        when(() => mock.save(any())).thenAnswer((_) async {});

        await tester.pumpWidget(_wrap(service: mock, locale: locale));
        await tester.pumpAndSettle();

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── Continue button acknowledges ───────────────────────────────────────────

  testWidgets('continue button persists pluginSafetyAcknowledged=true', (
    tester,
  ) async {
    final mock = _MockSettingsService();
    when(mock.load).thenAnswer((_) async => const AppSettings());
    when(() => mock.save(any())).thenAnswer((_) async {});

    await tester.pumpWidget(_wrap(service: mock));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final l10n = await L10N.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.pluginSafetyDialogContinue));
    await tester.pumpAndSettle();

    verify(
      () => mock.save(
        any(
          that: predicate<AppSettings>(
            (s) => s.pluginSafetyAcknowledged && !s.pluginLoadingDisabled,
          ),
        ),
      ),
    ).called(1);
  });

  // ── Disable button flips loading off ───────────────────────────────────────

  testWidgets('disable button persists pluginLoadingDisabled=true', (
    tester,
  ) async {
    final mock = _MockSettingsService();
    when(mock.load).thenAnswer((_) async => const AppSettings());
    when(() => mock.save(any())).thenAnswer((_) async {});

    await tester.pumpWidget(_wrap(service: mock));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final l10n = await L10N.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.pluginSafetyDialogDisable));
    await tester.pumpAndSettle();

    verify(
      () => mock.save(
        any(
          that: predicate<AppSettings>(
            (s) => s.pluginLoadingDisabled && !s.pluginSafetyAcknowledged,
          ),
        ),
      ),
    ).called(1);
  });

  // ── Returns true / false correctly ─────────────────────────────────────────

  testWidgets('show() returns true when continue is pressed', (tester) async {
    final mock = _MockSettingsService();
    when(mock.load).thenAnswer((_) async => const AppSettings());
    when(() => mock.save(any())).thenAnswer((_) async {});

    bool? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWithValue(mock),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await PluginSafetyDialog.show(ctx);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final l10n = await L10N.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.pluginSafetyDialogContinue));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('show() returns false when disable is pressed', (tester) async {
    final mock = _MockSettingsService();
    when(mock.load).thenAnswer((_) async => const AppSettings());
    when(() => mock.save(any())).thenAnswer((_) async {});

    bool? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWithValue(mock),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await PluginSafetyDialog.show(ctx);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final l10n = await L10N.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.pluginSafetyDialogDisable));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  // ── Enterprise governance bypass ──────────────────────────────────────────

  testWidgets(
    'enterpriseGovernanceBypass auto-acknowledges and pops with true',
    (tester) async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      bool? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsServiceProvider.overrideWithValue(mock),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Builder(
              builder: (ctx) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showDialog<bool>(
                      context: ctx,
                      barrierDismissible: false,
                      builder: (_) => const PluginSafetyDialog(
                        enterpriseGovernanceBypass: true,
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      verify(
        () => mock.save(
          any(
            that: predicate<AppSettings>(
              (s) => s.pluginSafetyAcknowledged,
            ),
          ),
        ),
      ).called(1);
    },
  );
}
