// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/panes/providers/active_pane_id_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../../../helpers/product_telemetry_config.dart';

class _InMemoryWorkspaceService implements WorkspaceService {
  _InMemoryWorkspaceService(this._initial);

  Workspace _initial;
  final List<Workspace> saves = [];

  @override
  WaveCruxWorkspaceCodec get codec => const WaveCruxWorkspaceCodec();

  @override
  String get fileName => 'workspace.json';

  @override
  Future<Workspace> load() async => _initial;

  @override
  Future<Workspace> loadFromPath(String path) async => _initial;

  @override
  Future<void> save(Workspace workspace) async {
    _initial = workspace;
    saves.add(workspace);
  }

  @override
  Future<void> saveToPath(String path, Workspace workspace) async {
    saves.add(workspace);
  }

  @override
  Future<void> clear() async {
    _initial = Workspace.empty();
  }

  @override
  Future<void> clearAllSidecars() async {}

  @override
  Future<String?> sidecarPathFor(
    String tabId, {
    String extension = '.json',
  }) async => null;

  @override
  Future<void> deleteSidecar(
    String tabId, {
    String extension = '.json',
  }) async {}

  @override
  WorkspaceRecovery? takeRecovery() => null;
}

ProviderContainer _makeContainer(Workspace initial) {
  return ProviderContainer(
    overrides: [
      productTelemetryConfig,
      workspaceServiceProvider.overrideWithValue(
        _InMemoryWorkspaceService(initial),
      ),
    ],
  );
}

void main() {
  group('activePaneIdProvider', () {
    test('falls back to PaneId.primary before workspace hydrates', () async {
      final container = ProviderContainer(overrides: [productTelemetryConfig]);
      addTearDown(container.dispose);
      expect(container.read(activePaneIdProvider), equals(PaneId.primary));
    });

    test('returns the workspace activePaneId once hydrated', () async {
      final empty = Workspace.empty();
      final container = _makeContainer(empty);
      addTearDown(container.dispose);
      await container.read(workspaceProvider.future);
      expect(
        container.read(activePaneIdProvider),
        equals(empty.activePaneId),
      );
    });

    test(
      'updates when splitPane creates a second pane and focuses it',
      () async {
        final empty = Workspace.empty();
        final container = _makeContainer(empty);
        addTearDown(container.dispose);
        await container.read(workspaceProvider.future);
        final notifier = container.wavecruxWorkspace;
        final newPaneId = await notifier.splitPane();
        expect(container.read(activePaneIdProvider), equals(newPaneId));
        expect(notifier.current.panes.length, 2);
      },
    );

    test(
      'closePane merges tabs and falls back to the surviving pane',
      () async {
        final empty = Workspace.empty();
        final container = _makeContainer(empty);
        addTearDown(container.dispose);
        await container.read(workspaceProvider.future);
        final notifier = container.wavecruxWorkspace;
        final secondPane = await notifier.splitPane();
        // Active pane is now the new pane. Close it; survivor is the original.
        await notifier.closePane(secondPane);
        expect(notifier.current.panes.length, 1);
        expect(
          container.read(activePaneIdProvider),
          equals(notifier.current.panes.single.id),
        );
      },
    );

    test('setActivePane to non-existent id is a no-op', () async {
      final empty = Workspace.empty();
      final container = _makeContainer(empty);
      addTearDown(container.dispose);
      await container.read(workspaceProvider.future);
      final notifier = container.wavecruxWorkspace;
      final originalActive = notifier.current.activePaneId;
      await notifier.setActivePane(PaneId.generate());
      expect(notifier.current.activePaneId, equals(originalActive));
    });
  });
}
