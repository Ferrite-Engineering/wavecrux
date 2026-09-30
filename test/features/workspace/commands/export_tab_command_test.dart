// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/commands/export_tab_command.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import '../../../helpers/in_memory_workspace_service.dart';
import '../../../helpers/product_telemetry_config.dart';

Future<T> _withTempDir<T>(Future<T> Function(Directory dir) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_exporttab_');
  try {
    return await fn(dir);
  } finally {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }
}

({ProviderContainer root, TabContainerManager tcm}) _bootstrap() {
  final tcm = TabContainerManager();
  final root = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      tabContainerManagerProvider.overrideWithValue(tcm),
      ...testWorkspaceOverrides(),
    ],
  );
  tcm.init(root);
  return (root: root, tcm: tcm);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Stub SharedPreferences so the recentFilesProvider (touched by
    // SessionNotifier.saveToPath) doesn't hit the missing platform channel.
    SharedPreferences.setMockInitialValues({});
  });

  group('exportTabForContainer', () {
    test(
      'writes a session export to the picked path and stamps the tab',
      () async {
        await _withTempDir((dir) async {
          final path = '${dir.path}/tab.wavecrux';
          final boot = _bootstrap();
          addTearDown(boot.root.dispose);
          addTearDown(boot.tcm.dispose);

          // Create a tab whose session export we'll write.
          await boot.root.wavecruxWorkspace.openFile('/tmp/a.vcd');
          final id = boot.root.read(tabListProvider).first.id;

          // Materialize the tab container so its sessionNotifier is alive.
          boot.tcm.containerFor(id);

          final err = await exportTabForContainer(boot.root, id, path);
          expect(err, isNull);
          expect(File(path).existsSync(), isTrue);

          // The export contains a JSON object — minimal check; the SessionService
          // round-trip is exercised in detail by session_service_test.dart.
          final raw = await File(path).readAsString();
          final decoded = jsonDecode(raw);
          expect(decoded, isA<Map<String, Object?>>());
          expect((decoded as Map<String, Object?>)['version'], isNotNull);

          // The tab's sessionFilePath was stamped so subsequent exports default
          // back to this location.
          final stamped = boot.root
              .read(tabListProvider)
              .firstWhere((t) => t.id == id);
          expect(stamped.sessionFilePath, equals(path));
        });
      },
    );

    test('returns failure reason when the path is unwritable', () async {
      await _withTempDir((dir) async {
        final boot = _bootstrap();
        addTearDown(boot.root.dispose);
        addTearDown(boot.tcm.dispose);

        await boot.root.wavecruxWorkspace.openFile('/tmp/a.vcd');
        final id = boot.root.read(tabListProvider).first.id;
        boot.tcm.containerFor(id);

        // Target a path whose PARENT is a regular file: writing under a file
        // fails on every platform. A bogus absolute path is not portable —
        // the Windows CI runner resolves "/no/such/directory" to a writable
        // drive-root location, so the export would (wrongly) succeed there.
        final blocker = File('${dir.path}/blocker')..writeAsStringSync('x');
        final bogus = '${blocker.path}/tab.wavecrux';
        final err = await exportTabForContainer(boot.root, id, bogus);
        expect(err, isNotNull);
      });
    });

    test('returns null on unknown tab id (caller guarded earlier)', () async {
      // The public runExportTabCommand guards on tab existence before the
      // file picker; the helper still tolerates a stale id by short-circuiting
      // through TabContainerManager (it would lazily create a fresh container
      // — irrelevant to the contract here). What we DO care about: this
      // exported helper must not throw for an arbitrary tab id input.
      await _withTempDir((dir) async {
        final boot = _bootstrap();
        addTearDown(boot.root.dispose);
        addTearDown(boot.tcm.dispose);

        final id = TabId.generate();
        boot.tcm.containerFor(id);
        final path = '${dir.path}/stale.wavecrux';
        final err = await exportTabForContainer(boot.root, id, path);
        // The lazily-created container's session has no real signals; the
        // save itself succeeds (it's a JSON snapshot of the defaults).
        expect(err, isNull);
        expect(File(path).existsSync(), isTrue);
      });
    });
  });
}
