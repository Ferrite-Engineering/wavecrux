// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/commands/save_workspace_as_command.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../../../helpers/product_telemetry_config.dart';

Future<T> _withTempDir<T>(Future<T> Function(Directory dir) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_saveas_');
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
  group('saveWorkspaceAsForContainer', () {
    test('writes a valid Workspace JSON document to the picked path', () async {
      await _withTempDir((dir) async {
        final namedDir = await Directory.systemTemp.createTemp(
          'wavecrux_saveas_named_',
        );
        addTearDown(() async {
          try {
            await namedDir.delete(recursive: true);
          } on FileSystemException catch (_) {}
        });
        final namedPath = '${namedDir.path}/share.wavecrux-workspace';

        final c = _container(dir);
        addTearDown(c.dispose);

        // Seed workspace with a tab so the named export has content.
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

        final err = await saveWorkspaceAsForContainer(c, namedPath);
        expect(err, isNull);
        expect(File(namedPath).existsSync(), isTrue);

        // Confirm the saved file is a valid named workspace (round-trip via
        // WorkspaceService.load against its parent dir is the simplest probe;
        // the service's load() is exercised in detail by its own tests).
        final reloaded = await WorkspaceService(
          codec: const WaveCruxWorkspaceCodec(),
          directoryFactory: () async => namedDir,
          logger: (_) {},
        ).load();
        expect(reloaded.tabs, isA<List<WorkspaceTab>>());
      });
    });

    test('does NOT reset the workspace after success', () async {
      await _withTempDir((dir) async {
        final namedDir = await Directory.systemTemp.createTemp(
          'wavecrux_saveas_keep_',
        );
        addTearDown(() async {
          try {
            await namedDir.delete(recursive: true);
          } on FileSystemException catch (_) {}
        });
        final namedPath = '${namedDir.path}/keep.wavecrux-workspace';

        final c = _container(dir);
        addTearDown(c.dispose);
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

        final err = await saveWorkspaceAsForContainer(c, namedPath);
        expect(err, isNull);

        // Critical contract: Save As does NOT reset like New Workspace does.
        expect(
          c.read(workspaceProvider).requireValue.tabs.length,
          1,
          reason: 'Save Workspace As must preserve the working workspace',
        );
        expect(c.read(tabListProvider).length, 1);
      });
    });

    test(
      'returns the failure reason when the rename target is invalid',
      () async {
        await _withTempDir((dir) async {
          final c = _container(dir);
          addTearDown(c.dispose);
          await c.read(workspaceProvider.future);

          // Parent is a regular file → the atomic write throws on every
          // platform. A bogus absolute path is not portable: the Windows CI
          // runner resolves "/no/such/directory" to a writable drive-root
          // location, so the save would (wrongly) succeed there.
          final blocker = File('${dir.path}/blocker')..writeAsStringSync('x');
          final bogus = '${blocker.path}/share.wavecrux-workspace';
          final err = await saveWorkspaceAsForContainer(c, bogus);
          expect(err, isNotNull);
          // A `FileSystemException` subclass is the observed concrete
          // exception; assert the OS-level error family without locking the
          // platform-specific subclass name. macOS/Linux surface
          // `PathNotFoundException` / "No such file or directory"; Windows
          // surfaces `PathExistsException` (errno 183) because the atomic
          // save's recursive mkdir of the parent collides with the existing
          // `blocker` file — same intent either way.
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
}
