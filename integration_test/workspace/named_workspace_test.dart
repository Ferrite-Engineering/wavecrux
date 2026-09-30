// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/named_workspace_test.dart
//
// Named workspace save / reset / open round-trip.
//
// Exercises the §22.9.4 user flow:
//
//   1. Open three files in three tabs (the working state).
//   2. "Save Workspace As…" → write a `.wavecrux-workspace` document
//      to a temp path. The auto-managed `workspace.json` continues to
//      track the current arrangement (save-as is the share / VCS flow,
//      not a destructive transfer).
//   3. "Reset Workspace" → close every tab and replace the workspace
//      with the canonical empty shape; the empty-canvas state must
//      render and the live tab list must be empty.
//   4. "Open Workspace…" with the saved path → the three tabs reopen
//      with their original pane assignment, the original active pane,
//      and the original active tab.
//
// The test drives the data-plane test seams the production commands
// expose (`saveWorkspaceAsForContainer`, `resetWorkspaceStateForContainer`,
// `openWorkspaceFromPathForContainer`) so the assertions stay focused on
// the workspace state transitions and don't reach into the file picker
// or dialog UI. The same seams are exercised by the per-command widget
// tests; this test is the end-to-end glue covering the three-command
// sequence under a real running app.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/commands/open_workspace_command.dart';
import 'package:wavecrux/features/workspace/commands/reset_workspace_command.dart';
import 'package:wavecrux/features/workspace/commands/save_workspace_as_command.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../helpers/workspace_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'Save Workspace As… + Reset + Open Workspace… round-trips the three-tab arrangement',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(() async {
        await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      });

      final pathA = fixturePath('vcd/scalar_basics.vcd');
      final pathB = fixturePath('vcd/vector_formats.vcd');
      final pathC = fixturePath('vcd/deep_hierarchy.vcd');
      expect(File(pathA).existsSync(), isTrue);
      expect(File(pathB).existsSync(), isTrue);
      expect(File(pathC).existsSync(), isTrue);

      final tmp = Directory.systemTemp.createTempSync(
        'wavecrux_named_workspace_',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final savePath = '${tmp.path}/team-debug.wavecrux-workspace';

      // Boot with the three fixtures so the live tab list has three tabs.
      await seedFirstLaunchAnswers();
      await bootstrap(args: [pathA, pathB, pathC]);
      await tester.pump();
      await pumpUntilWaveformReady(tester);

      final root = rootContainer(tester);

      // Wait for the post-frame additional-file opens to settle.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (root.read(tabListProvider).length >= 3) break;
      }
      await tester.pumpAndSettle();
      expect(root.read(tabListProvider), hasLength(3));

      await root.read(appSettingsProvider.future);

      // Snapshot the persisted-tab identities and active-tab id so we can
      // assert restoration matches the pre-save arrangement. The CLI
      // entry path lands all three tabs in the same pane.
      final beforeTabs = root.read(tabListProvider);
      final tabAId = beforeTabs[0].id;
      final tabBId = beforeTabs[1].id;
      final tabCId = beforeTabs[2].id;
      final paneId = root.read(workspaceProvider).value!.activePaneId;
      final activeTabBeforeSave = root.read(activeTabIdProvider);
      // The CLI restore step explicitly re-activates the first file
      // (`originalActiveId`); pin that as the expected active tab so the
      // post-restore assertion has a stable target.
      expect(activeTabBeforeSave, equals(tabAId));

      // ----- Step 1: Save Workspace As… -----
      final saveError = await saveWorkspaceAsForContainer(root, savePath);
      expect(
        saveError,
        isNull,
        reason: 'Save Workspace As… must succeed for a writable temp path',
      );
      expect(File(savePath).existsSync(), isTrue);
      // The auto-managed workspace must remain populated — save-as is
      // share, not handoff.
      expect(root.read(tabListProvider), hasLength(3));

      // ----- Step 2: Reset Workspace -----
      await resetWorkspaceStateForContainer(root);
      await root.read(workspaceProvider.future);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        root.read(tabListProvider),
        isEmpty,
        reason: 'Reset Workspace must close every live tab',
      );
      expect(
        root.read(workspaceProvider).value!.tabs,
        isEmpty,
        reason: 'Reset Workspace must wipe the persisted workspace tabs',
      );
      // Bounded poll before asserting — the widget mount trails the
      // provider state, and a fixed pump budget is the flake the
      // layout_phone/layout_tablet journeys hit on the 2026-09-06 sweep.
      await pumpUntil(
        tester,
        () => find.byKey(const Key('empty_canvas_state')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
      );
      expect(
        find.byKey(const Key('empty_canvas_state')),
        findsOneWidget,
        reason:
            'an empty workspace must render EmptyCanvasState; the '
            'the legacy Welcome surface is retired',
      );

      // ----- Step 3: Open Workspace… -----
      final openError = await openWorkspaceFromPathForContainer(root, savePath);
      expect(
        openError,
        isNull,
        reason: 'Open Workspace… must accept the freshly-written document',
      );

      // The open path replaces workspaceProvider; the live tab list still
      // needs the next frame to settle. Pump until the workspace surfaces
      // the three tabs (the live tab list mirrors the workspace via the
      // notifier's restore — but for now this test asserts only on the
      // workspace document, which is the persistence surface).
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (root.read(workspaceProvider).value!.tabs.length == 3) break;
      }

      // ----- Assertions: workspace fully restored -----
      final restored = root.read(workspaceProvider).value!;
      expect(
        restored.tabs,
        hasLength(3),
        reason: 'Open Workspace… must restore all three persisted tabs',
      );
      expect(
        restored.tabs.map((t) => t.id).toList(),
        equals([tabAId, tabBId, tabCId]),
        reason:
            'tab identity and order must round-trip — relaunch reuses '
            'the ids to re-attach per-tab sidecars',
      );
      expect(
        restored.tabs.map((t) => t.filePath).toList(),
        equals([pathA, pathB, pathC]),
      );
      expect(
        restored.panes,
        hasLength(1),
        reason:
            'three CLI tabs share one pane — that arrangement must '
            'survive Save/Reset/Open',
      );
      expect(
        restored.tabs.every((t) => t.paneId == paneId),
        isTrue,
        reason: 'every tab must restore into its original pane',
      );
      expect(restored.activePaneId, equals(paneId));
      expect(
        restored.activePane.activeTabId,
        equals(activeTabBeforeSave),
        reason:
            'active-tab pointer must round-trip so focus does not jump '
            'on restore',
      );

      tester.takeException();
    },
  );
}
