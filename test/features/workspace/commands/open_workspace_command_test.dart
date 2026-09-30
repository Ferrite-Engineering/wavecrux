// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/commands/open_workspace_command.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../../../helpers/product_telemetry_config.dart';

Future<T> _withTempDir<T>(Future<T> Function(Directory dir) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_openws_');
  try {
    return await fn(dir);
  } finally {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }
}

ProviderContainer _container(Directory dir) => ProviderContainer(
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

/// Hand-crafted "team workspace" written to [path]. Two tabs sharing a single
/// pane; the second tab is the active one. Returns the [Workspace] for
/// equality assertions.
Future<Workspace> _writeTeamWorkspace(String path) async {
  final paneId = PaneId.generate();
  final tabAId = TabId.generate();
  final tabBId = TabId.generate();
  final ws = Workspace(
    tabs: [
      buildWorkspaceTab(
        id: tabAId,
        displayName: 'a.vcd',
        paneId: paneId,
        filePath: '/tmp/a.vcd',
      ),
      buildWorkspaceTab(
        id: tabBId,
        displayName: 'b.fst',
        paneId: paneId,
        filePath: '/tmp/b.fst',
      ),
    ],
    panes: [WorkspacePane(id: paneId, activeTabId: tabBId)],
    activePaneId: paneId,
  );
  await File(path).writeAsString(
    const JsonEncoder.withIndent(
      '  ',
    ).convert(ws.toJson(const WaveCruxWorkspaceCodec())),
  );
  return ws;
}

void main() {
  group('openWorkspaceFromPathForContainer', () {
    test('loads a valid workspace and replaces the current one', () async {
      await _withTempDir((dir) async {
        final namedDir = await Directory.systemTemp.createTemp(
          'wavecrux_openws_named_',
        );
        addTearDown(() async {
          try {
            await namedDir.delete(recursive: true);
          } on FileSystemException catch (_) {}
        });
        final namedPath = '${namedDir.path}/team.wavecrux-workspace';
        final expected = await _writeTeamWorkspace(namedPath);

        final c = _container(dir);
        addTearDown(c.dispose);
        await c.read(workspaceProvider.future);

        // Seed an existing tab so the test exercises the "close live tabs"
        // branch as well as the workspace replacement.
        await c.wavecruxWorkspace.openFile('/tmp/existing.vcd');

        final err = await openWorkspaceFromPathForContainer(c, namedPath);
        expect(err, isNull);

        final replaced = c.read(workspaceProvider).requireValue;
        expect(replaced.tabs.length, 2);
        expect(replaced.activePaneId, expected.activePaneId);
        expect(
          replaced.tabs.map((t) => t.filePath).toList(),
          equals(['/tmp/a.vcd', '/tmp/b.fst']),
        );
        // The live tab list now derives from the workspace document, so after
        // the load it reflects exactly the loaded workspace's tabs.
        expect(
          c.read(tabListProvider).map((t) => t.filePath).toList(),
          equals(['/tmp/a.vcd', '/tmp/b.fst']),
        );
      });
    });

    test('rejects an invalid schema version with a non-null error', () async {
      await _withTempDir((dir) async {
        final namedDir = await Directory.systemTemp.createTemp(
          'wavecrux_openws_bad_',
        );
        addTearDown(() async {
          try {
            await namedDir.delete(recursive: true);
          } on FileSystemException catch (_) {}
        });
        final namedPath = '${namedDir.path}/bogus.wavecrux-workspace';

        // version: 9999 is not a supported schema → load rejected.
        await File(namedPath).writeAsString(
          jsonEncode({
            'version': 9999,
            'tabs': <Map<String, Object?>>[],
            'panes': [
              {'id': PaneId.generate().value},
            ],
            'activePaneId': PaneId.generate().value,
          }),
        );

        final c = _container(dir);
        addTearDown(c.dispose);
        await c.read(workspaceProvider.future);

        final err = await openWorkspaceFromPathForContainer(c, namedPath);
        expect(err, isNotNull);
        expect(err, contains('WorkspaceSchemaVersionException'));
      });
    });

    test('rejects a non-JSON-object root', () async {
      await _withTempDir((dir) async {
        final namedDir = await Directory.systemTemp.createTemp(
          'wavecrux_openws_rootarr_',
        );
        addTearDown(() async {
          try {
            await namedDir.delete(recursive: true);
          } on FileSystemException catch (_) {}
        });
        final namedPath = '${namedDir.path}/array.wavecrux-workspace';
        await File(namedPath).writeAsString('[]');

        final c = _container(dir);
        addTearDown(c.dispose);
        await c.read(workspaceProvider.future);

        final err = await openWorkspaceFromPathForContainer(c, namedPath);
        expect(err, isNotNull);
        expect(err, contains('JSON object'));
      });
    });

    test('rejects a missing file with a non-null error', () async {
      await _withTempDir((dir) async {
        final c = _container(dir);
        addTearDown(c.dispose);
        await c.read(workspaceProvider.future);

        final err = await openWorkspaceFromPathForContainer(
          c,
          '/no/such/path.wavecrux-workspace',
        );
        expect(err, isNotNull);
      });
    });
  });
}
