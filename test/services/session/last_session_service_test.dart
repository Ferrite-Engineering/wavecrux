// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/last_session_manifest.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/session/last_session_service.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import '../../helpers/in_memory_workspace_service.dart';
import '../../helpers/product_telemetry_config.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

/// Runs [fn] with a fresh temp directory and cleans up afterwards.
Future<T> _withTempDir<T>(Future<T> Function(Directory dir) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_last_session_');
  try {
    return await fn(dir);
  } finally {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }
}

LastSessionService _serviceFor(Directory dir) =>
    LastSessionService(directoryFactory: () async => dir);

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('LastSessionService — save / load / clear round-trip', () {
    const tab1 = LastSessionTab(filePath: '/workspace/dump.vcd');
    const tab2 = LastSessionTab(
      filePath: '/workspace/bfst.fst',
      sessionFilePath: '/workspace/bfst.wavecrux',
    );

    test('saved manifest can be loaded back', () async {
      await _withTempDir((dir) async {
        final service = _serviceFor(dir);
        const manifest = LastSessionManifest(tabs: [tab1, tab2]);

        await service.save(manifest);
        final loaded = await service.load();

        expect(loaded, equals(manifest));
      });
    });

    test('load returns empty when no file exists', () async {
      await _withTempDir((dir) async {
        final service = _serviceFor(dir);
        final result = await service.load();
        expect(result, equals(LastSessionManifest.empty));
      });
    });

    test('clear removes the manifest file', () async {
      await _withTempDir((dir) async {
        final service = _serviceFor(dir);
        const manifest = LastSessionManifest(tabs: [tab1]);

        await service.save(manifest);
        await service.clear();
        final result = await service.load();

        expect(result, equals(LastSessionManifest.empty));
      });
    });

    test('clear is a no-op when no file exists', () async {
      await _withTempDir((dir) async {
        final service = _serviceFor(dir);
        // Should complete without throwing.
        await service.clear();
        final result = await service.load();
        expect(result, equals(LastSessionManifest.empty));
      });
    });

    test('second save overwrites the first', () async {
      await _withTempDir((dir) async {
        final service = _serviceFor(dir);
        const first = LastSessionManifest(tabs: [tab1]);
        const second = LastSessionManifest(tabs: [tab2]);

        await service.save(first);
        await service.save(second);
        final loaded = await service.load();

        expect(loaded, equals(second));
      });
    });

    test('save empty manifest and load returns empty', () async {
      await _withTempDir((dir) async {
        final service = _serviceFor(dir);

        await service.save(LastSessionManifest.empty);
        final loaded = await service.load();

        expect(loaded, equals(LastSessionManifest.empty));
      });
    });

    test('file contains valid JSON after save', () async {
      await _withTempDir((dir) async {
        final service = _serviceFor(dir);
        const manifest = LastSessionManifest(tabs: [tab1]);

        await service.save(manifest);

        final file = File('${dir.path}/last_session.json');
        expect(file.existsSync(), isTrue);
        final contents = file.readAsStringSync();
        expect(contents, contains('"filePath"'));
        expect(contents, contains('/workspace/dump.vcd'));
      });
    });
  });

  group('startup tab restoration', () {
    test('restores 2 tabs from saved manifest', () async {
      await _withTempDir((dir) async {
        // Persist a 2-tab manifest to the temp dir.
        final service = _serviceFor(dir);
        const manifest = LastSessionManifest(
          tabs: [
            LastSessionTab(filePath: '/workspace/a.fst'),
            LastSessionTab(filePath: '/workspace/b.vcd'),
          ],
        );
        await service.save(manifest);

        // Replicate _restoreLastSession logic from app.dart:
        // load the manifest, then call openFile for each recorded tab.
        final loaded = await service.load();

        final tcm = TabContainerManager();
        final container = ProviderContainer(
          overrides: [
            productTelemetryConfig,
            tabContainerManagerProvider.overrideWithValue(tcm),
            ...testWorkspaceOverrides(),
          ],
        );
        tcm.init(container);
        addTearDown(tcm.dispose);
        addTearDown(container.dispose);

        final notifier = container.wavecruxWorkspace;
        for (final tab in loaded.tabs) {
          await notifier.openFile(tab.filePath);
        }

        final tabs = container.read(tabListProvider);
        expect(tabs.length, equals(2));
        expect(tabs[0].isPlaceholder, isFalse);
        expect(tabs[0].filePath, equals('/workspace/a.fst'));
        expect(tabs[1].isPlaceholder, isFalse);
        expect(tabs[1].filePath, equals('/workspace/b.vcd'));
      });
    });
  });

  group('LastSessionService — graceful degradation', () {
    test('load returns empty when directory factory throws', () async {
      final service = LastSessionService(
        directoryFactory: () async => throw Exception('no platform channel'),
      );
      final result = await service.load();
      expect(result, equals(LastSessionManifest.empty));
    });

    test(
      'save completes without throwing when directory factory throws',
      () async {
        final service = LastSessionService(
          directoryFactory: () async => throw Exception('no platform channel'),
        );
        const manifest = LastSessionManifest(
          tabs: [LastSessionTab(filePath: '/x')],
        );
        await expectLater(service.save(manifest), completes);
      },
    );

    test(
      'clear completes without throwing when directory factory throws',
      () async {
        final service = LastSessionService(
          directoryFactory: () async => throw Exception('no platform channel'),
        );
        await expectLater(service.clear(), completes);
      },
    );

    test('load returns empty when file contains invalid JSON', () async {
      await _withTempDir((dir) async {
        // Write garbage bytes to where the manifest file would be.
        final file = File('${dir.path}/last_session.json');
        await file.writeAsString('not valid json {{{');

        final service = _serviceFor(dir);
        final result = await service.load();

        expect(result, equals(LastSessionManifest.empty));
      });
    });

    test(
      'load returns empty when file contains a JSON array (wrong type)',
      () async {
        await _withTempDir((dir) async {
          final file = File('${dir.path}/last_session.json');
          await file.writeAsString('[1, 2, 3]');

          final service = _serviceFor(dir);
          final result = await service.load();

          expect(result, equals(LastSessionManifest.empty));
        });
      },
    );
  });
}
