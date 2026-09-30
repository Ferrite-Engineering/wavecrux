// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/features/update/providers/observed_server_time_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('ObservedServerTimeStore', () {
    test('starts null with no persisted value', () async {
      final container = makeContainer()
        ..read(observedServerTimeStoreProvider); // build + async load
      await Future<void>.delayed(Duration.zero);
      expect(container.read(observedServerTimeStoreProvider), isNull);
    });

    test('record advances the state and persists it', () async {
      final container = makeContainer();
      final notifier = container.read(observedServerTimeStoreProvider.notifier);

      final t = DateTime.utc(2026, 9, 15, 12);
      await notifier.record(t);

      expect(container.read(observedServerTimeStoreProvider), t);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(ObservedServerTimeStore.prefsKey),
        t.toIso8601String(),
      );
    });

    test('record is monotonic — an earlier time is ignored', () async {
      final container = makeContainer();
      final notifier = container.read(observedServerTimeStoreProvider.notifier);

      final later = DateTime.utc(2026, 9, 15, 12);
      final earlier = DateTime.utc(2026, 9);
      await notifier.record(later);
      await notifier.record(earlier);

      expect(container.read(observedServerTimeStoreProvider), later);
    });

    test('loads a persisted value on build', () async {
      final persisted = DateTime.utc(2026, 8, 1, 9).toIso8601String();
      SharedPreferences.setMockInitialValues({
        ObservedServerTimeStore.prefsKey: persisted,
      });

      final container = makeContainer()
        ..read(observedServerTimeStoreProvider); // build + async load
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(observedServerTimeStoreProvider),
        DateTime.parse(persisted),
      );
    });
  });

  group('root override wiring (store -> crux_license)', () {
    test('observedServerTimeProvider reflects the persisted store', () async {
      final container = ProviderContainer(
        overrides: [
          observedServerTimeProvider.overrideWith(
            (ref) => ref.watch(observedServerTimeStoreProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(observedServerTimeStoreProvider.notifier);

      expect(container.read(observedServerTimeProvider), isNull);

      final t = DateTime.utc(2026, 9, 15, 12);
      await notifier.record(t);

      expect(container.read(observedServerTimeProvider), t);
    });
  });
}
