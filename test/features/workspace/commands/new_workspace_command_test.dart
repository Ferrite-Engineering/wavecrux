// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/commands/new_workspace_command.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../../../helpers/product_telemetry_config.dart';

Future<T> _withTempDir<T>(Future<T> Function(Directory dir) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_new_cmd_');
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

void main() {
  group('saveCurrentWorkspaceToPathForContainer', () {
    test('returns null on success and writes the named file', () async {
      await _withTempDir((dir) async {
        final namedDir = await Directory.systemTemp.createTemp(
          'wavecrux_new_named_',
        );
        addTearDown(() async {
          try {
            await namedDir.delete(recursive: true);
          } on FileSystemException catch (_) {}
        });
        final namedPath = '${namedDir.path}/team.wavecrux-workspace';

        final c = _container(dir);
        addTearDown(c.dispose);
        // Seed workspace with a tab so the named export has content.
        // TabListNotifier starts empty; explicitly add a tab first.
        final initial = await c.read(workspaceProvider.future);
        await c.wavecruxWorkspace.openFile('/tmp/a.vcd');
        await c.wavecruxWorkspace.addTab(
          buildWorkspaceTab(
            id: c.read(tabListProvider).first.id,
            displayName: 'a.vcd',
            paneId: initial.activePaneId,
            filePath: '/tmp/a.vcd',
          ),
        );

        final err = await saveCurrentWorkspaceToPathForContainer(c, namedPath);
        expect(err, isNull);
        expect(File(namedPath).existsSync(), isTrue);

        // Sanity-check the round-trip — the named file holds the workspace
        // schema, not a per-tab session export.
        final reloaded = await WorkspaceService(
          codec: const WaveCruxWorkspaceCodec(),
          directoryFactory: () async => namedDir,
          logger: (_) {},
        ).load();
        // We loaded from the parent namedDir, not the file, so this just
        // confirms the WorkspaceService is comfortable reading it (the file
        // happens to be the only candidate). The detailed parse-back test
        // belongs to workspace_service_test.dart.
        expect(reloaded.tabs, isA<List<WorkspaceTab>>());
      });
    });

    test(
      'returns the failure reason when the rename target is invalid',
      () async {
        await _withTempDir((dir) async {
          final c = _container(dir);
          addTearDown(c.dispose);
          await c.read(workspaceProvider.future);

          // Target a path whose PARENT is a regular file so the atomic write
          // throws on every platform. A bogus absolute path is not portable —
          // the Windows CI runner resolves "/no/such/directory" to a writable
          // drive-root location, so the save would (wrongly) succeed there.
          final blocker = File('${dir.path}/blocker')..writeAsStringSync('x');
          final bogus = '${blocker.path}/team.wavecrux-workspace';
          final err = await saveCurrentWorkspaceToPathForContainer(c, bogus);
          expect(err, isNotNull);
          // A `FileSystemException` subclass is the observed concrete
          // exception; assert the OS-level error family without locking the
          // platform-specific subclass name. macOS/Linux surface
          // `PathNotFoundException` / "No such file or directory" (the parent
          // is a regular file, not a directory). Windows surfaces
          // `PathExistsException` (errno 183) because the atomic save's
          // recursive mkdir of the parent collides with the existing `blocker`
          // file — same intent, an invalid rename target yields a filesystem
          // failure reason.
          expect(
            err,
            anyOf(
              contains('FileSystemException'),
              contains('PathNotFoundException'),
              contains('No such file or directory'),
              contains('PathExistsException'),
              contains('Cannot create a file when that file already exists'),
            ),
          );
        });
      },
    );
  });

  group('resetWorkspaceForNewWorkspaceContainer', () {
    test('empties tab list and persisted workspace', () async {
      await _withTempDir((dir) async {
        final c = _container(dir);
        addTearDown(c.dispose);
        await c.read(workspaceProvider.future);
        await c.wavecruxWorkspace.openFile('/tmp/a.vcd');

        await resetWorkspaceForNewWorkspaceContainer(c);

        expect(
          c.read(workspaceProvider).requireValue.tabs,
          isEmpty,
        );
        final fromDisk = await WorkspaceService(
          codec: const WaveCruxWorkspaceCodec(),
          directoryFactory: () async => dir,
          logger: (_) {},
        ).load();
        expect(fromDisk.tabs, isEmpty);
      });
    });
  });
}
