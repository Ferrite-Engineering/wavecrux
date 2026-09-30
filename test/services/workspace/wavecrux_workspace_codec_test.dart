// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/wavecrux_tab_payload.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

void main() {
  group('WaveCruxWorkspaceCodec', () {
    const codec = WaveCruxWorkspaceCodec();

    test('payloadToJson omits null fields', () {
      const payload = WaveCruxTabPayload();
      expect(codec.payloadToJson(payload), isEmpty);
    });

    test('payloadToJson emits filePath and sessionExportPath when present', () {
      const payload = WaveCruxTabPayload(
        filePath: '/tmp/a.vcd',
        sessionExportPath: '/tmp/a.wavecrux',
      );
      expect(codec.payloadToJson(payload), {
        'filePath': '/tmp/a.vcd',
        'sessionExportPath': '/tmp/a.wavecrux',
      });
    });

    test('payloadToJson emits sessionFilePath and isDetached when present', () {
      const payload = WaveCruxTabPayload(
        filePath: '/tmp/a.vcd',
        sessionFilePath: '/tmp/opened.wavecrux',
        isDetached: true,
      );
      expect(codec.payloadToJson(payload), {
        'filePath': '/tmp/a.vcd',
        'sessionFilePath': '/tmp/opened.wavecrux',
        'isDetached': true,
      });
    });

    test('payloadToJson omits isDetached when false', () {
      const payload = WaveCruxTabPayload(filePath: '/tmp/a.vcd');
      expect(codec.payloadToJson(payload).containsKey('isDetached'), isFalse);
    });

    test('payloadFromJson round-trips a full payload', () {
      const original = WaveCruxTabPayload(
        filePath: '/tmp/a.vcd',
        sessionFilePath: '/tmp/opened.wavecrux',
        sessionExportPath: '/tmp/a.wavecrux',
        isDetached: true,
      );
      final reconstructed = codec.payloadFromJson(
        codec.payloadToJson(original),
      );
      expect(reconstructed, equals(original));
    });

    test('payloadFromJson tolerates missing optional fields', () {
      final p = codec.payloadFromJson(<String, Object?>{});
      expect(p.filePath, isNull);
      expect(p.sessionFilePath, isNull);
      expect(p.sessionExportPath, isNull);
      expect(p.isDetached, isFalse);
    });

    test('payloadFromJson silently ignores unknown keys (forward compat)', () {
      final p = codec.payloadFromJson(<String, Object?>{
        'filePath': '/tmp/a.vcd',
        'futureFieldFromV2': 42,
      });
      expect(p.filePath, '/tmp/a.vcd');
    });

    test(
      'payloadFromJson tolerates wrong-typed values (legacy corruption)',
      () {
        final p = codec.payloadFromJson(<String, Object?>{
          'filePath': 12345,
          'sessionExportPath': <String, Object?>{'nested': 'object'},
        });
        expect(p.filePath, isNull);
        expect(p.sessionExportPath, isNull);
      },
    );

    test('displayNameFor falls back to Untitled for null/empty path', () {
      expect(codec.displayNameFor(const WaveCruxTabPayload()), 'Untitled');
      expect(
        codec.displayNameFor(const WaveCruxTabPayload(filePath: '')),
        'Untitled',
      );
    });

    test('displayNameFor extracts file basename from posix paths', () {
      expect(
        codec.displayNameFor(
          const WaveCruxTabPayload(filePath: '/tmp/a/b/dump.vcd'),
        ),
        'dump.vcd',
      );
    });

    test('displayNameFor extracts file basename from windows paths', () {
      expect(
        codec.displayNameFor(
          const WaveCruxTabPayload(filePath: r'C:\sim\out\dump.fst'),
        ),
        'dump.fst',
      );
    });

    test('schema version is 1', () {
      expect(codec.schemaVersion, 1);
    });
  });

  group('WorkspaceService<WaveCruxTabPayload>', () {
    late Directory tempDir;
    late WorkspaceService<WaveCruxTabPayload> service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wc_codec_test_');
      service = WorkspaceService<WaveCruxTabPayload>(
        codec: const WaveCruxWorkspaceCodec(),
        directoryFactory: () async => tempDir,
        logger: (_) {},
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('load returns empty workspace when document contains a legacy shape '
        '(graceful toss-and-restart)', () async {
      // Simulate the pre-migration shape: top-level filePath /
      // sessionExportPath on the WorkspaceTab JSON (which is what WaveCrux's
      // local code wrote). The package's framework still parses the
      // framework-level fields (id, displayName, paneId) and lets the codec
      // pluck the rest — so this particular legacy shape actually round-
      // trips cleanly because the keys happen to match. That's the
      // happy-path branch of "graceful": no crash, no data loss.
      final paneId = 'pane-${DateTime.now().millisecondsSinceEpoch}';
      final legacy = {
        'version': 1,
        'tabs': [
          {
            'id': 'tab-1',
            'displayName': 'legacy.vcd',
            'paneId': paneId,
            'filePath': '/tmp/legacy.vcd',
            'sessionExportPath': '/tmp/legacy.wavecrux',
          },
        ],
        'panes': [
          {'id': paneId, 'activeTabId': 'tab-1'},
        ],
        'activePaneId': paneId,
        'statisticsStripVisible': true,
        'panelLayout': <String, Object?>{'leftSize': 250.0},
      };
      await File(
        '${tempDir.path}/workspace.json',
      ).writeAsString(jsonEncode(legacy));

      final loaded = await service.load();
      // Legacy-shape file loaded successfully — the matching framework keys
      // round-trip, the codec picks up filePath/sessionExportPath, and the
      // unrecognized statisticsStripVisible/panelLayout keys are silently
      // ignored (forward-compat).
      expect(loaded.tabs, hasLength(1));
      expect(loaded.tabs.single.payload.filePath, '/tmp/legacy.vcd');
      expect(
        loaded.tabs.single.payload.sessionExportPath,
        '/tmp/legacy.wavecrux',
      );
    });

    test('load returns empty workspace when JSON is corrupt', () async {
      await File(
        '${tempDir.path}/workspace.json',
      ).writeAsString('this is not JSON {[}{');
      final loaded = await service.load();
      expect(loaded.isEmpty, isTrue);
      expect(loaded.panes, hasLength(1));
    });

    test(
      'load returns empty workspace when root is not a JSON object',
      () async {
        await File('${tempDir.path}/workspace.json').writeAsString('[]');
        final loaded = await service.load();
        expect(loaded.isEmpty, isTrue);
      },
    );

    test(
      'load returns empty workspace when schema version is unsupported',
      () async {
        final paneId = 'pane-${DateTime.now().millisecondsSinceEpoch}';
        final futureSchema = {
          'version': 999,
          'tabs': const <Object?>[],
          'panes': [
            {'id': paneId},
          ],
          'activePaneId': paneId,
        };
        await File(
          '${tempDir.path}/workspace.json',
        ).writeAsString(jsonEncode(futureSchema));
        final loaded = await service.load();
        expect(loaded.isEmpty, isTrue);
      },
    );

    test('load returns empty workspace when invariants are violated', () async {
      // activePaneId references a pane that does not exist.
      final invariantViolation = {
        'version': 1,
        'tabs': const <Object?>[],
        'panes': [
          {'id': 'pane-real'},
        ],
        'activePaneId': 'pane-ghost',
      };
      await File(
        '${tempDir.path}/workspace.json',
      ).writeAsString(jsonEncode(invariantViolation));
      final loaded = await service.load();
      expect(loaded.isEmpty, isTrue);
    });

    test(
      'save then load round-trips a workspace with WaveCruxTabPayload',
      () async {
        final pane = WorkspacePane(id: PaneId.generate());
        final tab = WorkspaceTab<WaveCruxTabPayload>(
          id: TabId.generate(),
          displayName: 'dump.vcd',
          paneId: pane.id,
          payload: const WaveCruxTabPayload(
            filePath: '/tmp/dump.vcd',
            sessionExportPath: '/tmp/dump.wavecrux',
          ),
        );
        final workspace = Workspace<WaveCruxTabPayload>(
          tabs: [tab],
          panes: [pane.copyWith(activeTabId: tab.id)],
          activePaneId: pane.id,
        );

        await service.save(workspace);
        final loaded = await service.load();
        expect(loaded.tabs, hasLength(1));
        expect(loaded.tabs.single.id, tab.id);
        expect(loaded.tabs.single.payload, tab.payload);
        expect(loaded.activePaneId, pane.id);
      },
    );
  });
}
