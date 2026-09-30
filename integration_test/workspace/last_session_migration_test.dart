// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/last_session_migration_test.dart
//
// One-shot migration from the legacy `last_session.json`
// manifest to the `workspace.json` document.
//
// The migration runs once on the first launch after upgrading to a build
// that contains `LastSessionMigration`. After it succeeds the legacy file
// is deleted so subsequent launches skip migration entirely (idempotent).
//
// What this test pins down:
//
//   * `last_session.json` is present and `workspace.json` is absent on
//     launch.
//   * After bootstrap (which invokes `LastSessionMigration` synchronously
//     before the first frame), `workspace.json` exists with the right
//     schema version and the same tab paths as the legacy manifest.
//   * `last_session.json` no longer exists on disk — the migration owns
//     its cleanup.
//   * The restored tabs land in a single pane (per the migration
//     contract: "all tabs in one pane; the first tab is the active tab").
//
// We seed the legacy manifest directly via `LastSessionService.save` —
// the same code path the legacy lifecycle handler wrote through —
// rather than hand-build the JSON, so the test stays insulated from
// `LastSessionManifest.toJson` shape tweaks.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/last_session_manifest.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/session/last_session_service.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../helpers/workspace_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'last_session.json → workspace.json one-shot migration runs during bootstrap and deletes the legacy file',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const lastSessionService = LastSessionService();
      final workspaceService = WorkspaceService(
        codec: const WaveCruxWorkspaceCodec(),
      );

      // Belt-and-braces: clear both files on entry AND on tear-down. The
      // migration is idempotent but the assertion contract requires a
      // known starting state (legacy present, workspace absent).
      await workspaceService.clear();
      await lastSessionService.clear();
      addTearDown(() async {
        await workspaceService.clear();
        await lastSessionService.clear();
      });

      final pathA = fixturePath('vcd/scalar_basics.vcd');
      final pathB = fixturePath('vcd/vector_formats.vcd');
      expect(File(pathA).existsSync(), isTrue);
      expect(File(pathB).existsSync(), isTrue);

      // ----- Pre-seed the legacy manifest -----
      final seed = LastSessionManifest(
        tabs: [
          LastSessionTab(filePath: pathA),
          LastSessionTab(filePath: pathB),
        ],
      );
      await lastSessionService.save(seed);

      // Confirm the starting state matches the migration's input contract:
      // legacy present, workspace absent.
      final appSupport = await getApplicationSupportDirectory();
      final legacyFile = File('${appSupport.path}/last_session.json');
      final workspaceFile = File('${appSupport.path}/workspace.json');
      expect(
        legacyFile.existsSync(),
        isTrue,
        reason:
            'legacy manifest must be on disk so the migration has '
            'something to convert',
      );
      expect(
        workspaceFile.existsSync(),
        isFalse,
        reason:
            'workspace.json must be absent so the migration runs '
            'instead of preferring the existing workspace',
      );

      // ----- Bootstrap (runs the migration synchronously) -----
      //
      // `LastSessionMigration` runs in `bootstrap()` before workspace
      // hydration, so by the time runApp returns the migration has
      // already either converted or no-op'd.
      await seedFirstLaunchAnswers();
      await bootstrap();
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // ----- The migration deleted the legacy file -----
      expect(
        legacyFile.existsSync(),
        isFalse,
        reason:
            'legacy last_session.json must be deleted after a '
            'successful migration so subsequent launches skip migration '
            'entirely',
      );

      // ----- workspace.json now exists with the right shape -----
      expect(
        workspaceFile.existsSync(),
        isTrue,
        reason:
            'migration must create workspace.json from the legacy '
            'manifest contents',
      );

      final migrated = await workspaceService.load();
      expect(
        migrated.version,
        equals(kWorkspaceSchemaVersion),
        reason:
            'migrated workspace must carry the current schema version '
            'so it round-trips through fromJson on subsequent loads',
      );
      expect(
        migrated.tabs,
        hasLength(2),
        reason:
            'every tab in the legacy manifest must survive the '
            'conversion',
      );
      expect(
        migrated.tabs.map((t) => t.filePath).toList(),
        equals([pathA, pathB]),
        reason: 'tab order and file paths must be preserved verbatim',
      );
      expect(
        migrated.panes,
        hasLength(1),
        reason:
            'migration produces a single-pane workspace — split-pane '
            'state is a workspace addition not present in legacy manifests',
      );
      expect(
        migrated.tabs.every((t) => t.paneId == migrated.activePaneId),
        isTrue,
        reason:
            'every restored tab must belong to the single pane the '
            'migration created',
      );
      expect(
        migrated.activePane.activeTabId,
        equals(migrated.tabs.first.id),
        reason:
            'the first tab from the legacy manifest must become the '
            'active tab — preserves the "front tab" user perception '
            'across the migration',
      );

      // ----- Cross-check via the live workspace provider -----
      //
      // bootstrap() hydrates workspaceProvider from the migrated
      // workspace.json before the first frame, so the in-memory state
      // must agree with what we just read off disk.
      final root = rootContainer(tester);
      final hydrated = root.read(workspaceProvider).value;
      expect(hydrated, isNotNull);
      expect(hydrated!.tabs, hasLength(2));
      expect(
        hydrated.tabs.map((t) => t.filePath).toList(),
        equals([pathA, pathB]),
      );

      tester.takeException();
    },
  );
}
