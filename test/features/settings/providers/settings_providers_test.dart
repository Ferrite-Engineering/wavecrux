// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/log_verbosity.dart';

import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

// ── Mock ─────────────────────────────────────────────────────────────────────

class _MockSettingsService extends Mock implements WaveCruxSettingsService {}

// ── Helpers ──────────────────────────────────────────────────────────────────

ProviderContainer _makeContainer({required WaveCruxSettingsService service}) {
  final container = ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUpAll(() {
    registerFallbackValue(const AppSettings());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppSettingsNotifier', () {
    test('build loads settings from service', () async {
      final mock = _MockSettingsService();
      final loaded = const AppSettings().copyWith(
        themeMode: AppThemeMode.system,
      );
      when(mock.load).thenAnswer((_) async => loaded);
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      final settings = await container.read(appSettingsProvider.future);
      expect(settings, loaded);
      verify(mock.load).called(1);
    });

    test('setThemeMode updates state and persists', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);

      await container
          .read(appSettingsProvider.notifier)
          .setThemeMode(AppThemeMode.light);

      final result = container.read(appSettingsProvider).value!;
      expect(result.themeMode, AppThemeMode.light);
      verify(
        () => mock.save(
          any(
            that: predicate<AppSettings>(
              (s) => s.themeMode == AppThemeMode.light,
            ),
          ),
        ),
      ).called(1);
    });

    test('setWheelNavigatesTime updates state and persists', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);

      // Default-false propagates to the derived selector.
      expect(container.read(wheelNavigatesTimeProvider), isFalse);

      await container
          .read(appSettingsProvider.notifier)
          .setWheelNavigatesTime(enabled: true);

      expect(
        container.read(appSettingsProvider).value!.wheelNavigatesTime,
        isTrue,
      );
      expect(container.read(wheelNavigatesTimeProvider), isTrue);
      verify(
        () => mock.save(
          any(
            that: predicate<AppSettings>(
              (s) => s.wheelNavigatesTime,
            ),
          ),
        ),
      ).called(1);
    });

    test(
      'setBroadcastSelectionOnCrossProbe updates state and persists',
      () async {
        final mock = _MockSettingsService();
        when(mock.load).thenAnswer((_) async => const AppSettings());
        when(() => mock.save(any())).thenAnswer((_) async {});

        final container = _makeContainer(service: mock);
        await container.read(appSettingsProvider.future);

        // Defaults on (live cross-probe from launch).
        expect(
          container
              .read(appSettingsProvider)
              .value!
              .broadcastSelectionOnCrossProbe,
          isTrue,
        );

        await container
            .read(appSettingsProvider.notifier)
            .setBroadcastSelectionOnCrossProbe(enabled: false);

        expect(
          container
              .read(appSettingsProvider)
              .value!
              .broadcastSelectionOnCrossProbe,
          isFalse,
        );
        verify(
          () => mock.save(
            any(
              that: predicate<AppSettings>(
                (s) => !s.broadcastSelectionOnCrossProbe,
              ),
            ),
          ),
        ).called(1);
      },
    );

    test('setLogVerbosity updates state and persists', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);

      // Default is Normal.
      expect(
        container.read(appSettingsProvider).value!.logVerbosity,
        LogVerbosity.normal,
      );

      await container
          .read(appSettingsProvider.notifier)
          .setLogVerbosity(LogVerbosity.verbose);

      expect(
        container.read(appSettingsProvider).value!.logVerbosity,
        LogVerbosity.verbose,
      );
      verify(
        () => mock.save(
          any(
            that: predicate<AppSettings>(
              (s) => s.logVerbosity == LogVerbosity.verbose,
            ),
          ),
        ),
      ).called(1);
    });

    test('setWaveformFontSize updates state and persists', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);

      await container
          .read(appSettingsProvider.notifier)
          .setWaveformFontSize(18);

      final result = container.read(appSettingsProvider).value!;
      expect(result.waveformFontSize, 18);
    });

    test('setDefaultDisplayFormat updates state and persists', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);

      await container
          .read(appSettingsProvider.notifier)
          .setDefaultDisplayFormat(DisplayFormat.binary);

      final result = container.read(appSettingsProvider).value!;
      expect(result.defaultDisplayFormat, DisplayFormat.binary);
    });

    test('setDefaultLaneHeight updates state and persists', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);

      await container
          .read(appSettingsProvider.notifier)
          .setDefaultLaneHeight(50);

      final result = container.read(appSettingsProvider).value!;
      expect(result.defaultLaneHeight, 50);
    });

    test('setAutoReloadMode updates state and persists', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);

      await container
          .read(appSettingsProvider.notifier)
          .setAutoReloadMode(AutoReloadMode.off);

      final result = container.read(appSettingsProvider).value!;
      expect(result.autoReloadMode, AutoReloadMode.off);
    });

    test('setAutoSaveIntervalSeconds updates state and persists', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);

      await container
          .read(appSettingsProvider.notifier)
          .setAutoSaveIntervalSeconds(180);

      final result = container.read(appSettingsProvider).value!;
      expect(result.autoSaveIntervalSeconds, 180);
    });

    test('setAutoConvertLargeVcd updates state and persists', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);

      await container
          .read(appSettingsProvider.notifier)
          .setAutoConvertLargeVcd(enabled: false);

      final result = container.read(appSettingsProvider).value!;
      expect(result.autoConvertLargeVcd, isFalse);
    });

    test('multiple mutations accumulate correctly', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);
      final notifier = container.read(appSettingsProvider.notifier);

      await notifier.setThemeMode(AppThemeMode.light);
      await notifier.setWaveformFontSize(20);
      await notifier.setAutoReloadMode(AutoReloadMode.auto);

      final result = container.read(appSettingsProvider).value!;
      expect(result.themeMode, AppThemeMode.light);
      expect(result.waveformFontSize, 20);
      expect(result.autoReloadMode, AutoReloadMode.auto);
    });

    test('setDiagnosticsEnabled updates state and persists', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);

      await container
          .read(appSettingsProvider.notifier)
          .setDiagnosticsEnabled(enabled: true);

      final result = container.read(appSettingsProvider).value!;
      expect(result.diagnosticsEnabled, isTrue);
      verify(
        () => mock.save(
          any(
            that: predicate<AppSettings>(
              (s) => s.diagnosticsEnabled,
            ),
          ),
        ),
      ).called(1);
    });

    test(
      'state remains consistent after multiple sequential awaited updates',
      () async {
        final mock = _MockSettingsService();
        when(mock.load).thenAnswer((_) async => const AppSettings());
        when(() => mock.save(any())).thenAnswer((_) async {});

        final container = _makeContainer(service: mock);
        await container.read(appSettingsProvider.future);
        final notifier = container.read(appSettingsProvider.notifier);

        await notifier.setThemeMode(AppThemeMode.system);
        await notifier.setDefaultLaneHeight(40);

        final result = container.read(appSettingsProvider).value!;
        expect(result.themeMode, AppThemeMode.system);
        expect(result.defaultLaneHeight, 40);
      },
    );

    test('setOrientationLockMode updates state and persists', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);

      await container
          .read(appSettingsProvider.notifier)
          .setOrientationLockMode(OrientationLockMode.landscapeLock);

      final result = container.read(appSettingsProvider).value!;
      expect(result.orientationLockMode, OrientationLockMode.landscapeLock);
      verify(
        () => mock.save(
          any(
            that: predicate<AppSettings>(
              (s) => s.orientationLockMode == OrientationLockMode.landscapeLock,
            ),
          ),
        ),
      ).called(1);
    });

    test('setAutoHideChromeSeconds clamps and persists', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);

      final notifier = container.read(appSettingsProvider.notifier);

      await notifier.setAutoHideChromeSeconds(15);
      expect(
        container.read(appSettingsProvider).value?.autoHideChromeSeconds,
        15,
      );

      // Out-of-range values are clamped.
      await notifier.setAutoHideChromeSeconds(0);
      expect(
        container.read(appSettingsProvider).value?.autoHideChromeSeconds,
        1,
      );

      await notifier.setAutoHideChromeSeconds(9999);
      expect(
        container.read(appSettingsProvider).value?.autoHideChromeSeconds,
        30,
      );
    });

    // ── Plugin settings ─────────────────────────────────────────────────────

    test('setPluginSafetyAcknowledged updates state and persists', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);

      await container
          .read(appSettingsProvider.notifier)
          .setPluginSafetyAcknowledged(acknowledged: true);

      final result = container.read(appSettingsProvider).value!;
      expect(result.pluginSafetyAcknowledged, isTrue);
      verify(
        () => mock.save(
          any(
            that: predicate<AppSettings>(
              (s) => s.pluginSafetyAcknowledged,
            ),
          ),
        ),
      ).called(1);
    });

    test('setPluginLoadingDisabled updates state and persists', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);

      await container
          .read(appSettingsProvider.notifier)
          .setPluginLoadingDisabled(disabled: true);

      final result = container.read(appSettingsProvider).value!;
      expect(result.pluginLoadingDisabled, isTrue);
    });

    test('addUserPluginDirectory appends and is idempotent', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);
      final notifier = container.read(appSettingsProvider.notifier);

      await notifier.addUserPluginDirectory('/opt/plugins');
      expect(
        container.read(appSettingsProvider).value?.userPluginDirectories,
        <String>['/opt/plugins'],
      );

      // Adding the same path again is a no-op.
      await notifier.addUserPluginDirectory('/opt/plugins');
      expect(
        container.read(appSettingsProvider).value?.userPluginDirectories,
        <String>['/opt/plugins'],
      );

      await notifier.addUserPluginDirectory('/var/plugins');
      expect(
        container.read(appSettingsProvider).value?.userPluginDirectories,
        <String>['/opt/plugins', '/var/plugins'],
      );
    });

    test('removeUserPluginDirectory removes and is idempotent', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer(
        (_) async => const AppSettings().copyWith(
          userPluginDirectories: <String>['/a', '/b', '/c'],
        ),
      );
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);
      final notifier = container.read(appSettingsProvider.notifier);

      await notifier.removeUserPluginDirectory('/b');
      expect(
        container.read(appSettingsProvider).value?.userPluginDirectories,
        <String>['/a', '/c'],
      );

      // Removing a non-existent path is a no-op.
      await notifier.removeUserPluginDirectory('/missing');
      expect(
        container.read(appSettingsProvider).value?.userPluginDirectories,
        <String>['/a', '/c'],
      );
    });

    test('setPluginDisabled adds and removes per-plugin entries', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);
      final notifier = container.read(appSettingsProvider.notifier);

      await notifier.setPluginDisabled('/foo.so', disabled: true);
      expect(
        container.read(appSettingsProvider).value?.perPluginDisabled,
        <String, bool>{'/foo.so': true},
      );

      // Re-enabling removes the entry rather than setting it false.
      await notifier.setPluginDisabled('/foo.so', disabled: false);
      expect(
        container.read(appSettingsProvider).value?.perPluginDisabled,
        isEmpty,
      );
    });

    test('setAutoCheckForUpdates updates state', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final container = _makeContainer(service: mock);
      await container.read(appSettingsProvider.future);

      // Default value is true before any change.
      expect(
        container.read(appSettingsProvider).value?.autoCheckForUpdates,
        isTrue,
      );

      await container
          .read(appSettingsProvider.notifier)
          .setAutoCheckForUpdates(enabled: false);

      expect(
        container.read(appSettingsProvider).value?.autoCheckForUpdates,
        isFalse,
      );
    });
  });
}
