// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/restore_split_pane_test.dart
//
// Workspace round-trip for a split-pane arrangement:
// two tabs, one in each pane, surviving an `AppLifecycleState.detached`
// quit with `activePaneId` and per-pane `activeTabId` pointers intact.
//
// The Flutter framework forbids invoking `runApp` more than once per
// test process, so the "quit + relaunch" round-trip is implemented by
// flushing live state through the same code path the production
// lifecycle handler runs (`_WaveCruxAppState._flushWorkspace`) and then
// reading the workspace document back through a fresh
// [WorkspaceService] instance. The workspace document is
// the canonical source for tab-to-pane membership, so verifying the
// post-flush JSON is equivalent to verifying what the next cold-start
// restore would consume.
//
// Pane / tab arrangement under test:
//
//   - Boot two CLI fixtures (file A and file B) → live tab list has
//     both tabs in the workspace's single starting pane (pane A).
//   - Split right via `WorkspaceNotifier.splitPane()` (open-core empty-
//     new-pane semantic — the workspace grows to two panes, the active
//     pane pointer moves to the new one). This is the same notifier
//     call `ViewerScreen._splitPaneRight` invokes from the UI.
//   - Move tab B into the new pane via `TabListNotifier.moveTabToPane`.
//   - Flush the workspace.
//   - Read the persisted workspace.json back through a fresh service
//     instance and assert each pane carries the expected tab and the
//     `activePaneId` matches the right pane.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../helpers/workspace_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'split-pane round-trip: two panes with the correct tab in each pane plus the activePaneId pointer all survive a flush',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(() async {
        await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      });

      final pathA = fixturePath('vcd/scalar_basics.vcd');
      final pathB = fixturePath('vcd/vector_formats.vcd');
      expect(File(pathA).existsSync(), isTrue);
      expect(File(pathB).existsSync(), isTrue);

      await seedFirstLaunchAnswers();
      await bootstrap(args: [pathA, pathB]);
      await tester.pump();
      await pumpUntilWaveformReady(tester);

      final root = rootContainer(tester);

      // Wait for the post-frame additional-file open to populate the tab
      // list with both CLI files.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (root.read(tabListProvider).length >= 2) break;
      }
      await tester.pumpAndSettle();

      final tabs = root.read(tabListProvider);
      expect(tabs, hasLength(2));
      final tabA = tabs[0];
      final tabB = tabs[1];
      expect(tabA.filePath, equals(pathA));
      expect(tabB.filePath, equals(pathB));

      await root.read(appSettingsProvider.future);

      // The starting workspace is single-pane with both tabs hosted by
      // pane A. Capture pane A's id before we split.
      final leftPaneId = root.read(workspaceProvider).value!.activePaneId;
      expect(
        root.read(workspaceProvider).value!.panes,
        hasLength(1),
        reason: 'CLI-opened tabs land in the single starting pane',
      );

      // ----- Split + move (mirrors the production ViewerScreen flow) -----
      //
      // The WaveCrux `splitPane()` wrapper preserves the pre-migration
      // empty-new-pane semantic: it adds a second pane and shifts focus
      // to it WITHOUT moving the active tab. The UI then explicitly
      // calls `moveTabToPane(tabId, newPaneId)` to relocate tab B
      // (see `ViewerScreen._splitPaneRight`).
      final wsNotifier = root.wavecruxWorkspace;
      final rightPaneId = await wsNotifier.splitPane();
      expect(
        rightPaneId,
        isNot(equals(leftPaneId)),
        reason: 'splitPane must allocate a fresh pane id',
      );
      await root.wavecruxWorkspace.moveTabToPane(tabB.id, rightPaneId);
      // The TabListNotifier mirrors the move into the workspace async —
      // await the queued mirror so the workspace reflects the move
      // before we flush.
      await root.read(workspaceProvider.future);
      await tester.pump();

      // Sanity check the live tab list: tab A still in the left pane,
      // tab B now in the right pane.
      final movedTabs = root.read(tabListProvider);
      expect(
        movedTabs.firstWhere((t) => t.id == tabA.id).paneId,
        equals(leftPaneId),
      );
      expect(
        movedTabs.firstWhere((t) => t.id == tabB.id).paneId,
        equals(rightPaneId),
      );

      // ----- Flush (simulate detached) -----
      await flushLiveWorkspace(root);

      // ----- Verify the persisted workspace document -----
      final persisted = await WorkspaceService(
        codec: const WaveCruxWorkspaceCodec(),
      ).load();
      expect(
        persisted.panes,
        hasLength(2),
        reason: 'split-pane quit must persist the two-pane layout',
      );
      expect(
        persisted.tabs,
        hasLength(2),
        reason: 'both open tabs must round-trip through the flush',
      );

      final paneIds = persisted.panes.map((p) => p.id).toSet();
      expect(
        paneIds,
        containsAll(<Object>[leftPaneId, rightPaneId]),
        reason:
            'pane ids must round-trip — relaunch reuses them to '
            'reattach the live ProviderContainers',
      );

      final persistedA = persisted.tabs.firstWhere((t) => t.id == tabA.id);
      final persistedB = persisted.tabs.firstWhere((t) => t.id == tabB.id);
      expect(
        persistedA.paneId,
        equals(leftPaneId),
        reason: 'tab A must stay in the left pane',
      );
      expect(
        persistedA.filePath,
        equals(pathA),
        reason: 'tab A must still point at fixture A',
      );
      expect(
        persistedB.paneId,
        equals(rightPaneId),
        reason: 'tab B must persist in the new right pane',
      );
      expect(
        persistedB.filePath,
        equals(pathB),
        reason: 'tab B must still point at fixture B',
      );

      expect(
        persisted.activePaneId,
        equals(rightPaneId),
        reason:
            'activePaneId must follow the focus shift from splitPane — '
            'the right pane was made active by the split',
      );
      final rightPane = persisted.panes.firstWhere((p) => p.id == rightPaneId);
      expect(
        rightPane.activeTabId,
        equals(tabB.id),
        reason:
            'right pane must record tab B as its active tab after the '
            'move; without this the relaunch would render an empty pane '
            'next to a populated one',
      );
      final leftPane = persisted.panes.firstWhere((p) => p.id == leftPaneId);
      expect(
        leftPane.activeTabId,
        equals(tabA.id),
        reason:
            'left pane must keep tab A as its active tab — the sole '
            'remaining tab in a pane is always its active one',
      );

      tester.takeException();
    },
  );
}
