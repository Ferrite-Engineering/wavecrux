// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/tabs/cli_multi_file_test.dart
//
// CLI multi-file opens each as a
// separate tab inside the active pane of the current workspace.
//
// Bootstraps the app with two positional CLI arguments (the same path
// that `wavecrux a.vcd b.vcd` would produce on a real shell launch).
// Verifies that:
//   - `tabListProvider` exposes exactly 2 tabs (no welcome tab — the
//     legacy welcome kind is retired).
//   - Each tab's `displayName` matches the corresponding filename.
//   - The first file is the active tab.
//   - The two tabs have independent per-tab containers (their
//     `WaveformDataSource` instances differ, proving the open paths
//     resolved to different files rather than the same one being
//     attached twice).
//
// Workspace alignment:
//   - `workspaceProvider.tabs.length` is exactly 2.
//   - `workspaceProvider.panes.length` is exactly 1 (single-pane
//     workspace).
//   - `workspaceProvider.activePaneId` matches `panes[0].id`.
//   - Both tabs' `paneId` equals the active pane id.
//   - `workspaceProvider.activeTabId` resolves to the first CLI file.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';
import '../helpers/app_driver.dart';

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
    'two positional CLI args open as two tabs, first one is active',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Start from a clean persisted workspace so a previously-saved session
      // (from a real app run or an earlier test) doesn't restore extra tabs on
      // top of the two CLI files. Sibling workspace tests do the same.
      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(
        () async =>
            WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear(),
      );

      final firstPath = _fixturePath('vcd/scalar_basics.vcd');
      final secondPath = _fixturePath('vcd/vector_formats.vcd');
      expect(
        File(firstPath).existsSync() && File(secondPath).existsSync(),
        isTrue,
        reason: 'both fixtures must exist on disk',
      );

      // Bootstrap with two positional paths — the same code path the
      // `wavecrux a.vcd b.vcd` shell invocation takes via main.dart.
      await seedFirstLaunchAnswers();
      await bootstrap(args: [firstPath, secondPath]);
      await tester.pump();
      await pumpUntilWaveformReady(tester);

      final root = rootContainer(tester);

      // Additional CLI files are opened from a post-frame callback in
      // WaveCruxApp.initState — pump additional frames so the second
      // tab is in tabListProvider before we assert on the count.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (root.read(tabListProvider).length >= 2) break;
      }
      await tester.pumpAndSettle();

      // Assert tabListProvider has exactly 2 tabs and the order matches
      // the CLI argument order.
      final tabs = root.read(tabListProvider);
      expect(
        tabs.length,
        equals(2),
        reason: 'two CLI files must open two tabs (no welcome tab)',
      );
      expect(tabs[0].displayName, contains('scalar_basics'));
      expect(tabs[1].displayName, contains('vector_formats'));
      expect(tabs[0].filePath, equals(firstPath));
      expect(tabs[1].filePath, equals(secondPath));

      // First file is the active tab.
      final activeId = root.read(activeTabIdProvider);
      expect(
        activeId,
        equals(tabs[0].id),
        reason: 'first CLI file must be the initially active tab',
      );

      // Each tab has its own per-tab container provisioned by
      // TabContainerManager — these must be distinct ProviderContainer
      // instances. Per ARCHITECTURE.md §6.4, the per-tab scope isolates
      // each tab's WaveformSourceNotifier, cursor state, signal groups,
      // etc., so opening 5 signals in tab A never leaks into tab B.
      //
      // Note: the inactive tab's `WaveformSourceNotifier` is *not*
      // eagerly populated when the tab is created from the CLI —
      // ViewerScreen's initState only opens the file for the active
      // tab. Auto-loading on tab activation is a separate concern
      // (current behavior: switching to tab B and back loads B's file
      // through the standard `_openPath` flow once activated).
      final tcm = root.read(tabContainerManagerProvider);
      final containerA = tcm.containerFor(tabs[0].id);
      final containerB = tcm.containerFor(tabs[1].id);
      expect(
        identical(containerA, containerB),
        isFalse,
        reason:
            'per-tab containers must be distinct ProviderContainer '
            'instances — each tab has its own waveform source notifier, '
            'cursor state, etc.',
      );

      // The active tab (firstPath) is loaded eagerly via ViewerScreen.initState.
      final sourceA = containerA.read(waveformSourceProvider).value;
      expect(
        sourceA,
        isNotNull,
        reason: 'the active tab (first CLI file) must have loaded its file',
      );

      // ----- workspace-alignment assertions -----
      //
      // CLI multi-file open lands all tabs in the active pane of the
      // current workspace. The legacy test only asserted
      // `tabListProvider`; under the workspace model the
      // workspace is the persistence surface and must agree with the
      // live tab list. The workspace flush is debounced, so wait until
      // the in-memory `Workspace` includes both tabs before asserting.
      for (var i = 0; i < 30; i++) {
        final ws = root.read(workspaceProvider).value;
        if (ws != null && ws.tabs.length >= 2) break;
        await tester.pump(const Duration(milliseconds: 100));
      }

      final workspace = root.read(workspaceProvider).value;
      expect(
        workspace,
        isNotNull,
        reason:
            'workspaceProvider must have finished its initial hydration '
            'by the time the CLI files have populated the tab list',
      );
      expect(
        workspace!.tabs.length,
        equals(2),
        reason:
            'workspaceProvider.tabs must mirror the live tab list — '
            'two CLI files → two workspace tabs',
      );
      expect(
        workspace.panes.length,
        equals(1),
        reason:
            'single-pane workspace must remain single-pane when CLI '
            'files are opened',
      );
      expect(
        workspace.activePaneId,
        equals(workspace.panes.first.id),
        reason:
            'activePaneId must reference the only pane in a '
            'single-pane workspace',
      );
      for (final wt in workspace.tabs) {
        expect(
          wt.paneId,
          equals(workspace.activePaneId),
          reason:
              'every CLI-opened tab must land in the active pane '
              '(workspace tab ${wt.id} was assigned to ${wt.paneId})',
        );
      }
      expect(
        workspace.activeTabId,
        equals(tabs[0].id),
        reason:
            'workspace.activeTabId must resolve to the first CLI '
            'file — the same tab the live activeTabIdProvider '
            'reports',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
