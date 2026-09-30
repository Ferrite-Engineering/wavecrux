// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/session/session_lifecycle_test.dart
//
// Workspace round-trip + "Export Tab as Session…" export
// integration test, for the workspace model where:
//
//   * `workspace.json` (auto-managed in `{appSupportDir}/`) is the persistent
//     session — closing the tabs / quitting / re-launching restores them.
//   * `.wavecrux` is an **export** format produced by "Export Tab as
//     Session…", consumed by opening the exported file (which appends a
//     new tab to the current workspace).
//
// One `testWidgets` exercises both halves of the lifecycle end-to-end:
//
//   1. **Auto-save round-trip.** Open a fixture VCD, mutate the tab's
//      per-tab state (primary cursor at tick 50), simulate the lifecycle
//      `paused` flush via [WorkspaceNotifier.flushPendingSave], read
//      `workspace.json` back through a fresh [WorkspaceService.load], and
//      assert the on-disk workspace records the tab pointing at the same
//      fixture path with the same tab id.
//
//   2. **Export-tab round-trip.** Run "Export Tab as Session…" to a temp
//      `.wavecrux` path, close the tab so the workspace is empty, open
//      the exported file via [TabListNotifier.openSession] +
//      [SessionNotifier.loadFromPath], and assert the cursor placed
//      before export survives the round-trip — proving the export format
//      captures the per-tab state that the workspace document does not.
//
// Cleanup: the test deletes the real `{appSupportDir}/workspace.json`
// (and the temp `.wavecrux` export file) on tear-down so it does not
// leak into subsequent runs or the user-facing app-support directory.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/workspace/commands/export_tab_command.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';
import '../helpers/app_driver.dart';

/// Mirrors the private `_WaveCruxAppState._flushWorkspace` lifecycle hook:
/// snapshots the live tab list into a fresh [Workspace] and writes it
/// atomically via [WorkspaceService]. This is the exact code path the
/// production `AppLifecycleState.detached` handler runs through, and it
/// is the only path that pulls tabs out of `tabListProvider`
/// into `workspace.json` — `WorkspaceNotifier.flushPendingSave` writes
/// the notifier's *own* in-memory state, which is not auto-synced from
/// the live tab list.
Future<void> _flushLiveWorkspace(ProviderContainer root) async {
  final base = root.wavecruxWorkspace.current;
  final tabs = root.read(tabListProvider);
  final activeTabId = root.read(activeTabIdProvider);
  final paneId = base.activePaneId;
  final wsTabs = <WorkspaceTab>[
    for (final t in tabs)
      if (t.filePath != null)
        buildWorkspaceTab(
          id: t.id,
          displayName: t.displayName,
          paneId: paneId,
          filePath: t.filePath,
          sessionExportPath: t.sessionFilePath,
        ),
  ];
  final activeForPane = wsTabs.any((wt) => wt.id == activeTabId)
      ? activeTabId
      : (wsTabs.isNotEmpty ? wsTabs.first.id : null);
  final panes = <WorkspacePane>[
    for (final p in base.panes)
      if (p.id != paneId)
        p
      else if (activeForPane == null)
        WorkspacePane(id: paneId)
      else
        WorkspacePane(id: paneId, activeTabId: activeForPane),
  ];
  final snapshot = Workspace(
    tabs: wsTabs,
    panes: panes,
    activePaneId: paneId,
  );
  await root.read(workspaceServiceProvider).save(snapshot);
}

String _fixturePath(String relative) => [
  Directory.current.path,
  'verification',
  'fixtures',
  relative,
].join(Platform.pathSeparator);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'workspace auto-save and Export Tab as Session… cover the two halves of the workspace lifecycle',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Start from a clean slate AND always clean up the real app-support
      // workspace.json so this test does not pick up stale state from a
      // prior run and does not leak into subsequent tests or the user-facing
      // app. `getApplicationSupportDirectory()` resolves to the real
      // per-user directory in an integration_test runner — the same
      // pattern startup_restoration_test uses.
      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(() async {
        await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      });

      final fixture = _fixturePath('vcd/scalar_basics.vcd');
      expect(File(fixture).existsSync(), isTrue);

      final tmp = Directory.systemTemp.createTempSync(
        'wavecrux_session_lifecycle_',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final exportPath = '${tmp.path}/exported.wavecrux';

      await seedFirstLaunchAnswers();
      await bootstrap(args: [fixture]);
      await tester.pump();
      await pumpUntilWaveformReady(tester);

      final root = rootContainer(tester);

      // Wait for the active tab to be populated by ViewerScreen's
      // initState post-frame _openPath flow.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (root.read(tabListProvider).isNotEmpty) break;
      }

      final tabs = root.read(tabListProvider);
      expect(tabs, hasLength(1));
      final tab = tabs.first;

      // Modify the active tab's per-tab state — cursor at tick 50.
      final tcm = root.read(tabContainerManagerProvider);
      final tabContainer = tcm.containerFor(tab.id);
      tabContainer.read(cursorStateProvider.notifier).placePrimary(50);
      await tester.pump();

      // ----- Part 1: auto-save round-trip -----
      //
      // Force-resolve settings so the lifecycle snapshot helper sees the
      // same gate the production `_flushWorkspace` does
      // (`restoreTabsOnLaunch`).
      await root.read(appSettingsProvider.future);

      // Flush the workspace synchronously — mirrors what
      // [_WaveCruxAppState.didChangeAppLifecycleState] does on
      // `AppLifecycleState.detached`. The lifecycle handler snapshots
      // the live tab list (not the workspace notifier's in-memory tabs)
      // into a fresh [Workspace] and writes it via [WorkspaceService.save].
      await _flushLiveWorkspace(root);

      // Read workspace.json back through a fresh service instance — this is
      // what a cold-start re-bootstrap would observe.
      final persisted = await WorkspaceService(
        codec: const WaveCruxWorkspaceCodec(),
      ).load();
      expect(persisted.tabs, hasLength(1));
      expect(
        persisted.tabs.first.filePath,
        equals(fixture),
        reason:
            'workspace.json must record the live tab as pointing at '
            'the same fixture path the user opened.',
      );
      expect(
        persisted.tabs.first.id,
        equals(tab.id),
        reason:
            'tab identity must round-trip through workspace.json so '
            "the per-tab session export's tab id stays stable across "
            'restarts.',
      );

      // ----- Part 2: export-tab round-trip -----
      //
      // Run the export-tab command using its testable seam. This is the
      // same code path the menu / palette "Export Tab as Session…" action
      // invokes after the user picks a path in the OS save dialog.
      final error = await exportTabForContainer(root, tab.id, exportPath);
      expect(error, isNull, reason: 'tab export must succeed: $error');
      expect(File(exportPath).existsSync(), isTrue);

      // Close the only tab — workspace transitions to empty-canvas state.
      await root.wavecruxWorkspace.closeTab(tab.id);
      await tester.pump();
      expect(root.read(tabListProvider), isEmpty);

      // Open the exported .wavecrux file — same path the document open
      // flow takes when the user picks a `.wavecrux` in the OS file
      // picker: append a session-typed tab, then invoke the per-tab
      // SessionNotifier.loadFromPath to restore the snapshot.
      await root.wavecruxWorkspace.openSession(
        exportPath,
        filePath: fixture,
      );
      await tester.pump();

      final reopenedTabs = root.read(tabListProvider);
      expect(reopenedTabs, hasLength(1));
      final reopenedTab = reopenedTabs.first;
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
            reopenedContainer.read(cursorStateProvider).primaryCursorTime == 50,
      );
      await tester.pumpAndSettle();

      // The exported per-tab state must be restored: cursor at tick 50.
      expect(
        reopenedContainer.read(cursorStateProvider).primaryCursorTime,
        equals(50),
        reason:
            'Export Tab as Session… must round-trip the primary cursor '
            'position through the `.wavecrux` export.',
      );

      tester.takeException();
    },
  );
}
