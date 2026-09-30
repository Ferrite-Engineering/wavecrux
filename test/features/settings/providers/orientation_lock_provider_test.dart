// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/settings/providers/orientation_lock_provider.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/services/platform/orientation_lock_service.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

class _MockSettingsService extends Mock implements WaveCruxSettingsService {}

class _RecordingService extends OrientationLockService {
  _RecordingService(this.captures)
    : super(
        setOrientations: (orientations) async {
          captures.add(orientations);
        },
      );

  final List<List<DeviceOrientation>> captures;
}

void main() {
  setUpAll(() {
    registerFallbackValue(const AppSettings());
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('orientationLockSyncProvider', () {
    test(
      'applies the persisted orientation mode after settings load',
      () async {
        final mock = _MockSettingsService();
        when(mock.load).thenAnswer(
          (_) async => const AppSettings().copyWith(
            orientationLockMode: OrientationLockMode.landscapeLock,
          ),
        );
        when(() => mock.save(any())).thenAnswer((_) async {});

        final captures = <List<DeviceOrientation>>[];
        final recording = _RecordingService(captures);

        final container = ProviderContainer(
          overrides: [
            settingsServiceProvider.overrideWithValue(mock),
            orientationLockServiceProvider.overrideWithValue(recording),
          ],
        );
        addTearDown(container.dispose);

        await container.read(appSettingsProvider.future);
        final mode = container.read(orientationLockSyncProvider);
        expect(mode, OrientationLockMode.landscapeLock);

        await Future<void>.delayed(Duration.zero);
        expect(captures, isNotEmpty);
        expect(
          captures.last,
          unorderedEquals(<DeviceOrientation>[
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]),
        );
      },
    );

    test('returns null while settings async value is still loading', () async {
      final mock = _MockSettingsService();
      final completer = Completer<AppSettings>();
      when(mock.load).thenAnswer((_) => completer.future);

      final captures = <List<DeviceOrientation>>[];
      final container = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWithValue(mock),
          orientationLockServiceProvider.overrideWithValue(
            _RecordingService(captures),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(orientationLockSyncProvider), isNull);
      completer.complete(const AppSettings());
    });

    test('reapplies when the orientation preference changes', () async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer((_) async => const AppSettings());
      when(() => mock.save(any())).thenAnswer((_) async {});

      final captures = <List<DeviceOrientation>>[];
      final container = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWithValue(mock),
          orientationLockServiceProvider.overrideWithValue(
            _RecordingService(captures),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(appSettingsProvider.future);
      final sub = container.listen(orientationLockSyncProvider, (_, _) {});
      addTearDown(sub.close);

      await Future<void>.delayed(Duration.zero);
      final initialCount = captures.length;

      await container
          .read(appSettingsProvider.notifier)
          .setOrientationLockMode(OrientationLockMode.portraitLock);
      await Future<void>.delayed(Duration.zero);

      expect(captures.length, greaterThan(initialCount));
      expect(captures.last, contains(DeviceOrientation.portraitUp));
    });
  });
}
