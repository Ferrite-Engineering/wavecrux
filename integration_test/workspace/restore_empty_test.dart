// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/restore_empty_test.dart
//
// Workspace round-trip for the empty-canvas state. Closing
// the last open tab must (1) leave the live tab list empty, (2) cause
// the workspace document to flush with zero tabs and a single empty
// pane, and (3) render the [EmptyCanvasState] widget.
//
// Closing the last tab once spawned a Welcome tab; that surface is
// retired — closing-all must land on `EmptyCanvasState`
// (anchored by `Key('empty_canvas_state')`) without ever creating a
// `welcome` kind. This test pins both halves: the on-disk workspace
// shape after the flush AND the live widget tree rendering the empty
// state.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../helpers/workspace_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'closing the last tab flushes an empty workspace and renders EmptyCanvasState',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(() async {
        await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      });

      final fixture = fixturePath('vcd/scalar_basics.vcd');
      expect(File(fixture).existsSync(), isTrue);

      await seedFirstLaunchAnswers();
      await bootstrap(args: [fixture]);
      await tester.pump();
      await pumpUntilWaveformReady(tester);

      final root = rootContainer(tester);

      // Wait for the tab to populate from ViewerScreen's post-frame open.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (root.read(tabListProvider).isNotEmpty) break;
      }
      expect(root.read(tabListProvider), hasLength(1));
      final tab = root.read(tabListProvider).first;

      await root.read(appSettingsProvider.future);

      // ----- Close the only tab -----
      //
      // closeTab() collapses the live tab list to empty AND mirrors the
      // close into the workspace via the fire-and-forget queue, so we
      // await the mirror's pending future before flushing.
      await root.wavecruxWorkspace.closeTab(tab.id);
      await root.read(workspaceProvider.future);
      // Empty-canvas branding PNGs are not resolvable in the headless
      // test bundle — drain fixed frames rather than pumpAndSettle.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(root.read(tabListProvider), isEmpty);

      // The EmptyCanvasState widget must render once the tab list goes
      // empty. The widget exposes a stable `Key('empty_canvas_state')`
      // anchor; no `WelcomeScreen` ever exists.
      //
      // Poll rather than trust the fixed drain above: the same fixed-loop
      // flake this codebase documents in the layout_phone/layout_tablet
      // journeys bit both of them on the 2026-09-06 sweep. Returns the
      // instant the key mounts, so it is normally faster than the drain.
      await pumpUntil(
        tester,
        () => find.byKey(const Key('empty_canvas_state')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
      );
      expect(
        find.byKey(const Key('empty_canvas_state')),
        findsOneWidget,
        reason:
            'closing the last tab must render EmptyCanvasState; the '
            'the legacy Welcome tab is retired',
      );

      // ----- Flush (simulate detached) -----
      await flushLiveWorkspace(root);

      // ----- Verify the persisted workspace document -----
      final persisted = await WorkspaceService(
        codec: const WaveCruxWorkspaceCodec(),
      ).load();
      expect(
        persisted.tabs,
        isEmpty,
        reason:
            'workspace.json must record zero tabs after the close-all + '
            'flush so the next cold start lands directly on EmptyCanvasState',
      );
      expect(
        persisted.panes,
        hasLength(1),
        reason:
            'an empty workspace keeps a single empty pane — the canonical '
            'Workspace.empty() shape — never zero panes',
      );
      expect(
        persisted.panes.single.activeTabId,
        isNull,
        reason:
            'the lone pane must have no active tab pointer when it hosts '
            'no tabs',
      );

      tester.takeException();
    },
  );
}
