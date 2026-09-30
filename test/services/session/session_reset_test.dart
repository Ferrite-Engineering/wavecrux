// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart'
    show WorkspaceService;
import 'package:wavecrux/services/session/last_session_service.dart';
import 'package:wavecrux/services/session/session_reset.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

void main() {
  group('resetPersistedSessionData', () {
    late Directory tempDir;
    late WorkspaceService workspaceService;
    late LastSessionService lastSessionService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('session_reset_test_');
      workspaceService = WorkspaceService(
        codec: const WaveCruxWorkspaceCodec(),
        directoryFactory: () async => tempDir,
      );
      lastSessionService = LastSessionService(
        directoryFactory: () async => tempDir,
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('removes workspace.json, sidecars, and the legacy manifest', () async {
      // Seed all three on-disk artifacts.
      final workspaceFile = File('${tempDir.path}/workspace.json')
        ..writeAsStringSync('{"tabs":[]}');
      final manifestFile = File('${tempDir.path}/last_session.json')
        ..writeAsStringSync('{"tabs":[]}');
      final sessionsDir = Directory('${tempDir.path}/sessions')
        ..createSync(recursive: true);
      final sidecarA = File('${sessionsDir.path}/tab-a.wavecrux')
        ..writeAsStringSync('{}');
      final sidecarB = File('${sessionsDir.path}/tab-b.wavecrux')
        ..writeAsStringSync('{}');

      await resetPersistedSessionData(
        workspaceService,
        lastSessionService: lastSessionService,
      );

      expect(workspaceFile.existsSync(), isFalse);
      expect(manifestFile.existsSync(), isFalse);
      expect(sessionsDir.existsSync(), isFalse);
      expect(sidecarA.existsSync(), isFalse);
      expect(sidecarB.existsSync(), isFalse);
    });

    test('is a no-op (does not throw) when nothing is persisted', () async {
      await expectLater(
        resetPersistedSessionData(
          workspaceService,
          lastSessionService: lastSessionService,
        ),
        completes,
      );
      expect(Directory('${tempDir.path}/sessions').existsSync(), isFalse);
    });

    test('does not touch unrelated files in the support directory', () async {
      // Settings / keymap / recent-files live alongside but must survive a
      // session reset — --reset recovers a wedged session, not a factory reset.
      final settings = File('${tempDir.path}/app_settings.json')
        ..writeAsStringSync('{"theme":"dark"}');
      final keymap = File('${tempDir.path}/keymap.crux-keymap')
        ..writeAsStringSync('{}');

      await resetPersistedSessionData(
        workspaceService,
        lastSessionService: lastSessionService,
      );

      expect(settings.existsSync(), isTrue);
      expect(keymap.existsSync(), isTrue);
    });
  });
}
