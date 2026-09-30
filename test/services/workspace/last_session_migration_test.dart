// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/last_session_manifest.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart'
    show WorkspaceService;
import 'package:wavecrux/services/session/last_session_service.dart';
import 'package:wavecrux/services/workspace/last_session_migration.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

Future<T> _withTempDir<T>(Future<T> Function(Directory dir) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_migration_');
  try {
    return await fn(dir);
  } finally {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }
}

({
  LastSessionService legacy,
  WorkspaceService workspace,
  LastSessionMigration migration,
})
_wire(Directory dir, {void Function(String)? logger}) {
  final legacy = LastSessionService(directoryFactory: () async => dir);
  final workspace = WorkspaceService(
    codec: const WaveCruxWorkspaceCodec(),
    directoryFactory: () async => dir,
    logger: (_) {},
  );
  final migration = LastSessionMigration(
    lastSessionService: legacy,
    workspaceService: workspace,
    logger: logger ?? (_) {},
  );
  return (legacy: legacy, workspace: workspace, migration: migration);
}

void main() {
  group('LastSessionMigration — happy path', () {
    test('converts a 2-tab last_session.json into a workspace.json', () async {
      await _withTempDir((dir) async {
        final w = _wire(dir);
        await w.legacy.save(
          const LastSessionManifest(
            tabs: [
              LastSessionTab(filePath: '/workspace/a.fst'),
              LastSessionTab(
                filePath: '/workspace/b.vcd',
                sessionFilePath: '/workspace/b.wavecrux',
              ),
            ],
          ),
        );

        final ran = await w.migration.run();
        expect(ran, isTrue);

        final loaded = await w.workspace.load();
        expect(loaded.tabs, hasLength(2));
        expect(loaded.tabs[0].filePath, equals('/workspace/a.fst'));
        expect(loaded.tabs[0].displayName, equals('a.fst'));
        expect(loaded.tabs[1].filePath, equals('/workspace/b.vcd'));
        expect(
          loaded.tabs[1].payload.sessionExportPath,
          equals('/workspace/b.wavecrux'),
        );

        // All tabs in the same (single) pane, first tab is the active tab.
        expect(loaded.panes, hasLength(1));
        expect(loaded.panes.first.activeTabId, equals(loaded.tabs.first.id));
        expect(loaded.activePaneId, equals(loaded.panes.first.id));

        // Legacy file is gone — migration is one-shot.
        final legacyAfter = await w.legacy.load();
        expect(legacyAfter, equals(LastSessionManifest.empty));
      });
    });
  });

  group('LastSessionMigration — no-op cases', () {
    test('does nothing when no legacy file exists', () async {
      await _withTempDir((dir) async {
        final w = _wire(dir);
        final ran = await w.migration.run();
        expect(ran, isFalse);
        expect(
          File('${dir.path}/${w.workspace.fileName}').existsSync(),
          isFalse,
        );
      });
    });

    test('does nothing when workspace.json already has content', () async {
      await _withTempDir((dir) async {
        final w = _wire(dir);
        // Pre-populate workspace.json directly via the service.
        await w.legacy.save(
          const LastSessionManifest(
            tabs: [LastSessionTab(filePath: '/workspace/a.fst')],
          ),
        );
        // Run once → workspace is created.
        expect(await w.migration.run(), isTrue);
        // Drop a fresh legacy file alongside the now-existing workspace.
        await w.legacy.save(
          const LastSessionManifest(
            tabs: [LastSessionTab(filePath: '/workspace/clobber.vcd')],
          ),
        );
        // Second run: workspace already populated → migration is a no-op
        // and the second legacy file is discarded.
        expect(await w.migration.run(), isFalse);
        final loaded = await w.workspace.load();
        expect(loaded.tabs.first.filePath, equals('/workspace/a.fst'));
        expect(await w.legacy.load(), equals(LastSessionManifest.empty));
      });
    });

    test(
      'idempotent: re-running after a successful migration is a no-op',
      () async {
        await _withTempDir((dir) async {
          final w = _wire(dir);
          await w.legacy.save(
            const LastSessionManifest(
              tabs: [LastSessionTab(filePath: '/workspace/a.fst')],
            ),
          );
          expect(await w.migration.run(), isTrue);
          expect(await w.migration.run(), isFalse);
        });
      },
    );

    test('corrupt last_session.json is skipped, not deleted', () async {
      await _withTempDir((dir) async {
        final logs = <String>[];
        final w = _wire(dir, logger: logs.add);
        // Hand-write garbage into the legacy file.
        await File(
          '${dir.path}/last_session.json',
        ).writeAsString('not even json');
        final ran = await w.migration.run();
        expect(ran, isFalse);
        // Service.load() returns empty on parse errors, but the file itself
        // must remain so the user can recover it.
        expect(File('${dir.path}/last_session.json').existsSync(), isTrue);
      });
    });
  });
}
