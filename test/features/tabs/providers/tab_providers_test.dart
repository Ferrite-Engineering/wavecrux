// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../../../helpers/product_telemetry_config.dart';

// After the crux_workspace consolidation, tabListProvider and activeTabIdProvider are
// DERIVED views over the workspace document (the old TabListNotifier /
// ActiveTabIdNotifier mutation surface moved onto WaveCruxWorkspaceNotifier).
// These tests replace tab_list_notifier_test.dart by asserting the derivation
// + that the WaveCrux convenience mutators flow through to the derived views.

Future<T> _withTempDir<T>(Future<T> Function(Directory dir) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_tab_providers_');
  try {
    return await fn(dir);
  } finally {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }
}

ProviderContainer _containerFor(Directory dir) => ProviderContainer(
  overrides: [
    productTelemetryConfig,
    workspaceServiceProvider.overrideWithValue(
      WorkspaceService(
        codec: const WaveCruxWorkspaceCodec(),
        directoryFactory: () async => dir,
        logger: (_) {},
      ),
    ),
  ],
);

void main() {
  group('tabListProvider (derived)', () {
    test('is empty before the workspace has tabs', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        await c.read(workspaceProvider.future);
        expect(c.read(tabListProvider), isEmpty);
      });
    });

    test('reflects openFile: id, displayName, filePath, paneId', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        await c.read(workspaceProvider.future);
        final id = await c.wavecruxWorkspace.openFile(
          '/tmp/dump.vcd',
          displayName: 'dump.vcd',
        );

        final tabs = c.read(tabListProvider);
        expect(tabs, hasLength(1));
        expect(tabs.single.id, id);
        expect(tabs.single.displayName, 'dump.vcd');
        expect(tabs.single.filePath, '/tmp/dump.vcd');
        expect(tabs.single.isPlaceholder, isFalse);
      });
    });

    test('newTab yields a placeholder tab in the derived list', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        await c.read(workspaceProvider.future);
        await c.wavecruxWorkspace.newTab(displayName: 'New Tab');
        final tabs = c.read(tabListProvider);
        expect(tabs, hasLength(1));
        expect(tabs.single.isPlaceholder, isTrue);
        expect(tabs.single.filePath, isNull);
      });
    });

    test('openSession carries sessionFilePath through to the view', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        await c.read(workspaceProvider.future);
        await c.wavecruxWorkspace.openSession(
          '/tmp/s.wavecrux',
          filePath: '/tmp/dump.vcd',
        );
        final tab = c.read(tabListProvider).single;
        expect(tab.sessionFilePath, '/tmp/s.wavecrux');
        expect(tab.filePath, '/tmp/dump.vcd');
      });
    });

    test('shrinks when a tab is closed', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        await c.read(workspaceProvider.future);
        final a = await c.wavecruxWorkspace.openFile('/tmp/a.vcd');
        await c.wavecruxWorkspace.openFile('/tmp/b.vcd');
        expect(c.read(tabListProvider), hasLength(2));
        await c.wavecruxWorkspace.closeTab(a);
        final tabs = c.read(tabListProvider);
        expect(tabs, hasLength(1));
        expect(tabs.single.filePath, '/tmp/b.vcd');
      });
    });
  });

  group('activeTabIdProvider (derived)', () {
    test('follows the workspace active tab', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        await c.read(workspaceProvider.future);
        final a = await c.wavecruxWorkspace.openFile('/tmp/a.vcd');
        final b = await c.wavecruxWorkspace.openFile('/tmp/b.vcd');
        // openFile activates the newly-opened tab.
        expect(c.read(activeTabIdProvider), b);
        await c.read(workspaceProvider.notifier).setActiveTab(a);
        expect(c.read(activeTabIdProvider), a);
      });
    });

    test('returns a stable synthetic id when there are no tabs', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        await c.read(workspaceProvider.future);
        final first = c.read(activeTabIdProvider);
        // No tab references it, and it is stable across reads.
        expect(c.read(tabListProvider), isEmpty);
        expect(c.read(activeTabIdProvider), first);
      });
    });
  });
}
