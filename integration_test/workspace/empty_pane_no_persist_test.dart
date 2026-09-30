// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/empty_pane_no_persist_test.dart
//
// End-to-end regression test for the user-reported "phantom empty pane"
// defect: the app booted with two panes when only one tab was open, and
// the empty pane had no UI affordance to close it.
//
// Two failure modes are covered:
//
//   1. **Load sanitization.** A workspace.json on disk that records a
//      populated pane alongside an empty sibling pane must be normalized
//      to a single populated pane on cold start. Previously the loader
//      hydrated the document as-is, which surfaced the phantom pane.
//
//   2. **Flush sanitization.** Closing the only tab in one of two panes
//      and then flushing through the production lifecycle path must
//      persist a single-pane workspace, even when the live-tab →
//      workspace mirror has not yet run its auto-collapse step. The
//      previous `_flushWorkspace` snapshot construction preserved any
//      pane present in `base.panes`, including empty ones — so a flush
//      that raced the mirror would write the empty pane back to disk.
//
// The Flutter framework forbids invoking `runApp` more than once per
// test process, so we test the two halves back-to-back inside one boot:
// inject a corrupt workspace.json, boot, assert the loader collapsed it,
// then drive a close + flush and assert the persisted document is clean.

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
    'load + flush both refuse to surface or persist an empty sibling pane',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = WorkspaceService(codec: const WaveCruxWorkspaceCodec());
      await service.clear();
      addTearDown(() async {
        await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      });

      // ── Step 1: inject a corrupt workspace.json with an empty sibling pane ──
      //
      // Reproduces the on-disk state a previous flush race or boot-race
      // could leave behind: one populated pane and one stranded empty pane.
      final pathA = fixturePath('vcd/scalar_basics.vcd');
      expect(File(pathA).existsSync(), isTrue);
      final populated = PaneId.generate();
      final stranded = PaneId.generate();
      final tabAid = TabId.generate();
      await service.save(
        Workspace(
          tabs: [
            buildWorkspaceTab(
              id: tabAid,
              displayName: 'scalar_basics.vcd',
              paneId: populated,
              filePath: pathA,
            ),
          ],
          panes: [
            WorkspacePane(id: populated, activeTabId: tabAid),
            WorkspacePane(id: stranded),
          ],
          activePaneId: stranded,
        ),
      );

      // ── Step 2: boot the app and verify the loader collapsed the empty pane ──
      await seedFirstLaunchAnswers();
      await bootstrap();
      await tester.pump();
      await pumpUntilWaveformReady(tester);

      final root = rootContainer(tester);
      await root.read(appSettingsProvider.future);

      final ws = await root.read(workspaceProvider.future);
      expect(
        ws.panes,
        hasLength(1),
        reason:
            'the loader must drop the stranded empty pane on hydration '
            '— a 2-pane workspace where only one pane is populated is the '
            'phantom-pane defect the user reported',
      );
      expect(
        ws.panes.single.id,
        equals(populated),
        reason:
            'the surviving pane must be the populated one, not the empty '
            'one that originally held the activePaneId pointer',
      );
      expect(
        ws.activePaneId,
        equals(populated),
        reason:
            'activePaneId must fall back to the surviving pane when the '
            'persisted active pane was dropped',
      );
      expect(ws.tabs, hasLength(1));
      expect(ws.tabs.single.paneId, equals(populated));

      // ── Step 3: open a second fixture and split + move so two populated
      //           panes exist in the live state.
      final pathB = fixturePath('vcd/vector_formats.vcd');
      expect(File(pathB).existsSync(), isTrue);
      await root.wavecruxWorkspace.openFile(pathB);
      await root.read(workspaceProvider.future);
      await tester.pump();

      final wsNotifier = root.wavecruxWorkspace;
      final rightPaneId = await wsNotifier.splitPane();
      final tabB = root
          .read(tabListProvider)
          .firstWhere((t) => t.filePath == pathB);
      await root.wavecruxWorkspace.moveTabToPane(tabB.id, rightPaneId);
      await root.read(workspaceProvider.future);
      await tester.pump();

      final twoPaneWs = root.read(workspaceProvider).requireValue;
      expect(
        twoPaneWs.panes,
        hasLength(2),
        reason:
            'precondition: a real two-populated-pane state, not a '
            'phantom — both panes must hold a tab',
      );

      // ── Step 4: close the only tab in one pane and IMMEDIATELY flush ──
      //
      // We intentionally do NOT await `pendingWorkspaceMirror` here — the
      // production `_flushWorkspace` runs from a lifecycle callback that
      // races the mirror. The flush's snapshot must enforce the
      // "no empty siblings" invariant on its own.
      await root.wavecruxWorkspace.closeTab(tabB.id);
      await flushLiveWorkspace(root);

      // ── Step 5: re-read the persisted document and assert no empty pane ──
      final persisted = await WorkspaceService(
        codec: const WaveCruxWorkspaceCodec(),
      ).load();
      expect(
        persisted.panes,
        hasLength(1),
        reason:
            'closing the last tab in a pane and flushing immediately must '
            'NOT persist the stranded empty pane — the flush must enforce the '
            'no-empty-siblings invariant regardless of mirror timing',
      );
      expect(persisted.tabs, hasLength(1));
      expect(
        persisted.tabs.single.paneId,
        equals(persisted.panes.single.id),
        reason: 'the surviving tab must live in the surviving pane',
      );
      expect(
        persisted.activePaneId,
        equals(persisted.panes.single.id),
        reason:
            'activePaneId must point at the surviving pane after the flush '
            '(the previously-active right pane was dropped along with its tab)',
      );

      tester.takeException();
    },
  );
}
