// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/features/workspace/providers/recent_workspaces_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RecentWorkspacesNotifier', () {
    test('starts empty when no persisted value', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final list = await container.read(recentWorkspacesProvider.future);
      expect(list, isEmpty);
    });

    test('addWorkspace prepends and persists', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(recentWorkspacesProvider.future);

      await container
          .read(recentWorkspacesProvider.notifier)
          .addWorkspace('/tmp/a.wavecrux-workspace');
      await container
          .read(recentWorkspacesProvider.notifier)
          .addWorkspace('/tmp/b.wavecrux-workspace');

      expect(
        container.read(recentWorkspacesProvider).value,
        equals([
          '/tmp/b.wavecrux-workspace',
          '/tmp/a.wavecrux-workspace',
        ]),
      );

      // Verify persistence by spinning up a fresh container.
      final fresh = ProviderContainer();
      addTearDown(fresh.dispose);
      final restored = await fresh.read(recentWorkspacesProvider.future);
      expect(
        restored,
        equals([
          '/tmp/b.wavecrux-workspace',
          '/tmp/a.wavecrux-workspace',
        ]),
      );
    });

    test('addWorkspace dedupes by moving existing entry to top', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(recentWorkspacesProvider.future);
      final notifier = container.read(recentWorkspacesProvider.notifier);

      await notifier.addWorkspace('/tmp/a.wavecrux-workspace');
      await notifier.addWorkspace('/tmp/b.wavecrux-workspace');
      await notifier.addWorkspace('/tmp/c.wavecrux-workspace');
      // Re-add 'a' — should move to the top, not appear twice.
      await notifier.addWorkspace('/tmp/a.wavecrux-workspace');

      expect(
        container.read(recentWorkspacesProvider).value,
        equals([
          '/tmp/a.wavecrux-workspace',
          '/tmp/c.wavecrux-workspace',
          '/tmp/b.wavecrux-workspace',
        ]),
      );
    });

    test('cap at 10 entries', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(recentWorkspacesProvider.future);
      final notifier = container.read(recentWorkspacesProvider.notifier);

      for (var i = 0; i < 15; i++) {
        await notifier.addWorkspace('/tmp/w$i.wavecrux-workspace');
      }
      final list = container.read(recentWorkspacesProvider).value!;
      expect(list.length, 10);
      // Most recent (w14) is first; oldest survivor is w5.
      expect(list.first, '/tmp/w14.wavecrux-workspace');
      expect(list.last, '/tmp/w5.wavecrux-workspace');
    });

    test('removeWorkspace drops the path and persists', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(recentWorkspacesProvider.future);
      final notifier = container.read(recentWorkspacesProvider.notifier);

      await notifier.addWorkspace('/tmp/a.wavecrux-workspace');
      await notifier.addWorkspace('/tmp/b.wavecrux-workspace');
      await notifier.removeWorkspace('/tmp/a.wavecrux-workspace');

      expect(
        container.read(recentWorkspacesProvider).value,
        equals(['/tmp/b.wavecrux-workspace']),
      );
    });

    test('removeWorkspace is a no-op for unknown paths', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(recentWorkspacesProvider.future);
      final notifier = container.read(recentWorkspacesProvider.notifier);

      await notifier.addWorkspace('/tmp/a.wavecrux-workspace');
      await notifier.removeWorkspace('/never/added.wavecrux-workspace');
      expect(
        container.read(recentWorkspacesProvider).value,
        equals(['/tmp/a.wavecrux-workspace']),
      );
    });

    test('clear empties the list', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(recentWorkspacesProvider.future);
      final notifier = container.read(recentWorkspacesProvider.notifier);

      await notifier.addWorkspace('/tmp/a.wavecrux-workspace');
      await notifier.addWorkspace('/tmp/b.wavecrux-workspace');
      await notifier.clear();
      expect(
        container.read(recentWorkspacesProvider).value,
        isEmpty,
      );
    });
  });
}
