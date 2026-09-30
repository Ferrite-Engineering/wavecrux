// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/tab_export_import_test.dart
//
// Tab export to `.wavecrux` and re-import.
//
// Exercises the §22.9.5 user flow. Under the workspace model `.wavecrux`
// is an **export format only** — produced by "Export Tab as Session…"
// and consumed by opening a `.wavecrux` (which appends a new tab to the
// current workspace with the exported per-tab state restored). This test
// pins the contract that the export round-trips both the file binding
// and the per-tab state (cursor placement).
//
// Flow:
//   1. Open fixture A as tab 1 via CLI args.
//   2. Place the primary cursor at a known tick so the per-tab snapshot
//      carries non-default state.
//   3. Run the export-tab command via its testable seam — writes a
//      `.wavecrux` session sidecar at a temp path.
//   4. Close the tab so the workspace transitions to the empty state.
//   5. Open the exported `.wavecrux` via the same code path the OS file-
//      picker entry uses (`TabListNotifier.openSession` followed by the
//      per-tab `SessionNotifier.loadFromPath`).
//   6. Assert the re-imported tab points at fixture A AND carries the
//      cursor placement from before export — proving the export captured
//      the per-tab state, not just the file path.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/workspace/commands/export_tab_command.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../helpers/workspace_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'Export Tab as Session… writes a .wavecrux that re-imports as a new tab with the exported state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(() async {
        await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      });

      final fixture = fixturePath('vcd/scalar_basics.vcd');
      expect(File(fixture).existsSync(), isTrue);

      final tmp = Directory.systemTemp.createTempSync(
        'wavecrux_tab_export_',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final exportPath = '${tmp.path}/exported.wavecrux';

      await seedFirstLaunchAnswers();
      await bootstrap(args: [fixture]);
      await tester.pump();
      await pumpUntilWaveformReady(tester);

      final root = rootContainer(tester);

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (root.read(tabListProvider).isNotEmpty) break;
      }
      expect(root.read(tabListProvider), hasLength(1));
      final originalTab = root.read(tabListProvider).first;
      expect(originalTab.filePath, equals(fixture));

      await root.read(appSettingsProvider.future);

      // ----- Step 1: Mutate per-tab state to non-default cursor -----
      const cursorTick = 42;
      final tcm = root.read(tabContainerManagerProvider);
      final originalContainer = tcm.containerFor(originalTab.id);
      originalContainer
          .read(cursorStateProvider.notifier)
          .placePrimary(cursorTick);
      await tester.pump();

      // ----- Step 2: Export Tab as Session… -----
      final exportError = await exportTabForContainer(
        root,
        originalTab.id,
        exportPath,
      );
      expect(
        exportError,
        isNull,
        reason:
            'export must succeed for a writable temp path; got: '
            '$exportError',
      );
      expect(
        File(exportPath).existsSync(),
        isTrue,
        reason: 'export must create the .wavecrux file at the picked path',
      );

      // ----- Step 3: Close the source tab -----
      await root.wavecruxWorkspace.closeTab(originalTab.id);
      await root.read(workspaceProvider.future);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(root.read(tabListProvider), isEmpty);

      // ----- Step 4: Open the exported .wavecrux -----
      //
      // Match the production document-open flow: append a session-typed
      // tab via TabListNotifier.openSession, then invoke the per-tab
      // SessionNotifier.loadFromPath to restore the snapshot. The two-
      // step is intentional: openSession assigns a new tab id and
      // creates the per-tab container; loadFromPath replays the exported
      // state into that container.
      await root.wavecruxWorkspace.openSession(
        exportPath,
        filePath: fixture,
      );
      await tester.pump();
      final reopened = root.read(tabListProvider);
      expect(
        reopened,
        hasLength(1),
        reason:
            'opening a .wavecrux must append exactly one new tab to the '
            'workspace, even after the source tab was closed',
      );
      final reopenedTab = reopened.first;
      expect(
        reopenedTab.id,
        isNot(equals(originalTab.id)),
        reason:
            'a re-import is a new tab — TabListNotifier.openSession '
            'generates a fresh TabId rather than re-using the closed-tab id',
      );

      final reopenedContainer = tcm.containerFor(reopenedTab.id);
      await reopenedContainer
          .read(sessionProvider.notifier)
          .loadFromPath(exportPath);
      // loadFromPath restores per-tab state and may re-open the waveform on the
      // background isolate; poll for the restored cursor (the asserted state)
      // rather than waiting a fixed real-time budget.
      await pumpUntil(
        tester,
        () =>
            reopenedContainer.read(cursorStateProvider).primaryCursorTime ==
            cursorTick,
      );
      await tester.pumpAndSettle();

      // ----- Assertions: file + per-tab state survived export round-trip -----
      expect(
        reopenedTab.filePath,
        equals(fixture),
        reason:
            'the re-imported tab must point at the same fixture the '
            'export was taken from',
      );
      expect(
        reopenedContainer.read(cursorStateProvider).primaryCursorTime,
        equals(cursorTick),
        reason:
            'cursor placement must round-trip through the .wavecrux '
            'export — proving the export carries per-tab state, not just '
            'the file path',
      );

      tester.takeException();
    },
  );
}
