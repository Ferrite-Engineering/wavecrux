// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/cli_append_test.dart
//
// CLI multi-file append into an existing workspace's
// active pane.
//
// §22.8.5 extension: a user with a saved workspace launches
// `wavecrux a.fst b.vcd`. The two CLI files must append to the
// workspace's active pane as new tabs; the original tab from the
// saved workspace must survive (not be replaced).
//
// Code path under test: `TabListNotifier.openFile`. The production
// CLI-args post-frame callback in `_WaveCruxAppState.initState` does
// exactly this — for each additional path, call `notifier.openFile`,
// then restore the original active-tab pointer. This test pre-seeds
// the workspace with one tab to represent the "user had a saved
// workspace" precondition, then drives the same `notifier.openFile`
// code path twice to represent the additional CLI args.
//
// Scope: this test pins the notifier-level invariants of the append
// (append-to-active-pane, original-tab-survives, active-tab-preserved) by
// driving `notifier.openFile` directly. The end-to-end bootstrap-time flow —
// launching `wavecrux a.vcd` with a saved workspace, which now restores the
// saved tabs AND opens the CLI file(s) on top (de-duplicated, file active) —
// is covered by `integration_test/workspace/cli_file_merges_workspace_test.dart`.
// `_WaveCruxAppState._restoreFromWorkspace` runs on every cold start (it no
// longer skips when a CLI file is present) and `ViewerScreen` opens the file
// after it via the `startupReconcileProvider` barrier.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    'CLI multi-file append: two new tabs land in the active pane while the '
    'restored original tab survives',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final wsService = WorkspaceService(codec: const WaveCruxWorkspaceCodec());
      await wsService.clear();
      addTearDown(() async {
        await wsService.clear();
      });

      final pathOriginal = fixturePath('vcd/scalar_basics.vcd');
      final pathAppendA = fixturePath('vcd/vector_formats.vcd');
      final pathAppendB = fixturePath('vcd/deep_hierarchy.vcd');
      expect(File(pathOriginal).existsSync(), isTrue);
      expect(File(pathAppendA).existsSync(), isTrue);
      expect(File(pathAppendB).existsSync(), isTrue);

      // Pre-seed workspace.json with one tab — the "saved workspace"
      // precondition from §22.8.5 extension.
      final paneId = PaneId.generate();
      final originalTabId = TabId.generate();
      final seed = Workspace(
        tabs: [
          buildWorkspaceTab(
            id: originalTabId,
            displayName: 'scalar_basics.vcd',
            paneId: paneId,
            filePath: pathOriginal,
          ),
        ],
        panes: [WorkspacePane(id: paneId, activeTabId: originalTabId)],
        activePaneId: paneId,
      );
      await wsService.save(seed);

      SharedPreferences.setMockInitialValues({
        'settings.restoreTabsOnLaunch': true,
      });

      // Boot with no CLI args so the restoration path activates and the
      // original tab loads.
      await seedFirstLaunchAnswers();
      await bootstrap();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final root = rootContainer(tester);

      await root.read(appSettingsProvider.future);

      // Wait for the restored tab to populate.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (root.read(tabListProvider).isNotEmpty) break;
      }
      expect(
        root.read(tabListProvider),
        hasLength(1),
        reason: 'workspace restore must reopen the single pre-seeded tab',
      );
      expect(root.read(tabListProvider).single.id, equals(originalTabId));
      expect(
        root.read(activeTabIdProvider),
        equals(originalTabId),
        reason:
            'the restored tab must be the active tab — `_restoreFromWorkspace` '
            'calls `activeTabIdProvider.notifier.activate(resolvedActive)` so this is '
            'a contractual starting state for the CLI-append flow',
      );

      // ----- Simulate the CLI additional-files post-frame callback -----
      //
      // The production callback (in `_WaveCruxAppState.initState`):
      //   1. Captures the current active tab id.
      //   2. Calls `notifier.openFile(path)` for each additional path.
      //   3. Re-activates the captured original active tab so the FIRST
      //      CLI file (or in this test, the restored original) is the
      //      one the user sees on launch.
      //
      // We replicate the same three-step sequence here so the assertions
      // pin down the exact behavior contract — append, preserve focus,
      // land in the active pane.
      final notifier = root.wavecruxWorkspace;
      final originalActiveId = root.read(activeTabIdProvider);
      await notifier.openFile(pathAppendA);
      await notifier.openFile(pathAppendB);
      root.read(activeTabIdProvider.notifier).activate(originalActiveId);
      // Drain the queued workspace-mirror writes before asserting on the
      // workspace document. `pendingWorkspaceMirror` covers the openFile
      // mirrors (add/move/remove); `activeTabIdProvider.pendingMirror`
      // covers the activate() → setActiveTab mirror so a subsequent
      // workspace.activeTabId read sees the test's re-activation rather
      // than the LAST openFile's mid-burst mirror state.
      await root.read(workspaceProvider.future);
      await root.read(workspaceProvider.future);
      await tester.pump();

      // ----- Assertions: original survives, two appended, focus preserved -----
      final tabs = root.read(tabListProvider);
      expect(
        tabs,
        hasLength(3),
        reason:
            'append must add exactly two new tabs without replacing '
            'the original',
      );
      expect(
        tabs[0].id,
        equals(originalTabId),
        reason:
            'original tab must keep its position and id — appending '
            'never reorders existing tabs',
      );
      expect(tabs[0].filePath, equals(pathOriginal));
      expect(tabs[1].filePath, equals(pathAppendA));
      expect(tabs[2].filePath, equals(pathAppendB));
      expect(
        root.read(activeTabIdProvider),
        equals(originalTabId),
        reason:
            'the active tab pointer must survive the append — '
            'openFile activates each new tab, so without the explicit '
            're-activate step the LAST appended tab would win, contradicting '
            'the user-visible "land on the first file" contract',
      );
      expect(
        tabs.every((t) => t.paneId == paneId),
        isTrue,
        reason:
            "every appended tab must land in the workspace's active "
            'pane — TabListNotifier.openFile defaults paneId to the '
            "workspace's activePaneId",
      );

      // ----- Workspace document agrees with the live tab list -----
      final workspace = root.read(workspaceProvider).value;
      expect(workspace, isNotNull);
      expect(
        workspace!.tabs,
        hasLength(3),
        reason: 'workspace document must mirror the three live tabs',
      );
      expect(
        workspace.panes,
        hasLength(1),
        reason: 'CLI append must not implicitly split the workspace',
      );
      for (final wt in workspace.tabs) {
        expect(
          wt.paneId,
          equals(paneId),
          reason: 'every appended tab must persist under the active pane',
        );
      }
      expect(
        workspace.activeTabId,
        equals(originalTabId),
        reason:
            'workspace.activeTabId must match the live active tab so '
            'the next cold start opens to the same view',
      );

      tester.takeException();
    },
  );
}
