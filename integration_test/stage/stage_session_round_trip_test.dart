// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/stage/stage_session_round_trip_test.dart
//
// Stage workspace state round-trips through the
// quit → relaunch lifecycle.
//
// In the workspace model, Stage panel state lives on the active tab's
// per-tab [stageWorkspaceProvider]. That state is NOT serialized
// into the auto-managed `workspace.json` (the workspace document records
// only tab file paths + pane layout); instead it travels through the
// per-tab `.wavecrux` session export the workspace points at via
// [WorkspaceTab.sessionExportPath].
//
// This test exercises the round-trip by:
//
//   1. Loading the `stage/stage_demo.vcd` fixture so the tab has signals
//      to bind against.
//   2. Adding a Stage panel + one LED widget instance with a signal
//      binding.
//   3. Driving the same "Export Tab as Session…" code path the menu /
//      palette action uses, then closing the tab to clear the in-memory
//      Stage state.
//   4. Opening the exported `.wavecrux` file via [TabListNotifier.openSession]
//      + [SessionNotifier.loadFromPath] — the path a fresh launch would
//      take when restoring a workspace whose tab carried a `sessionExportPath`.
//   5. Asserting the Stage panel + binding survives the cycle.
//
// Refresh note: the legacy test reached into
// [SessionNotifier.saveToPath] / [SessionNotifier.loadFromPath] on the
// root scope. The active tab owns its own
// [stageWorkspaceProvider] inside a per-tab container, so the
// save and load both go through the active tab's container resolved via
// [TabContainerManager.containerFor].

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/workspace/commands/export_tab_command.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart'
    show WaveCruxWorkspaceContainerX, WorkspaceService;
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
    'Stage panel + binding survives the quit → relaunch tab lifecycle',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Clean app-support workspace.json so this test does not leak into
      // the user-facing app or pick up state from a prior run.
      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(() async {
        await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      });

      final fixture = _fixturePath('stage/stage_demo.vcd');
      expect(File(fixture).existsSync(), isTrue);

      final tmp = Directory.systemTemp.createTempSync(
        'wavecrux_stage_session_',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final exportPath = '${tmp.path}/stage.wavecrux';

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
      final initialTab = tabs.first;

      final tcm = root.read(tabContainerManagerProvider);
      final initialContainer = tcm.containerFor(initialTab.id);

      // Build a Stage panel with one LED binding on the active tab's
      // own stageWorkspace notifier.
      final stageNotifier = initialContainer.read(
        stageWorkspaceProvider.notifier,
      )..addPanel('My Panel');
      final instanceId = stageNotifier.addInstance('led');
      expect(instanceId, isNotNull);
      const signalRef = 'top.primitives.led_blink';
      stageNotifier.setBinding(instanceId!, 'input', signalRef);
      await tester.pump();

      // Drive the same "Export Tab as Session…" code path the menu/palette
      // action invokes. This is the workspace-aware replacement for the
      // legacy root-scope saveToPath('stage.wavecrux') call.
      final error = await exportTabForContainer(
        root,
        initialTab.id,
        exportPath,
      );
      expect(error, isNull, reason: 'tab export must succeed: $error');
      expect(File(exportPath).existsSync(), isTrue);

      // Quit-simulation: close the only tab so the live Stage workspace
      // state is gone. After this the workspace would render the empty
      // canvas — analogous to the state a freshly relaunched app would
      // see before the per-tab session export gets loaded.
      await root.wavecruxWorkspace.closeTab(initialTab.id);
      await tester.pump();
      expect(root.read(tabListProvider), isEmpty);

      // Relaunch-simulation: open the exported `.wavecrux` as a fresh
      // session-typed tab and then trigger the per-tab SessionNotifier
      // load (which restores the Stage workspace via
      // stageWorkspaceProvider.restoreFromSession).
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
      // loadFromPath restores the Stage workspace via
      // stageWorkspaceProvider.restoreFromSession; poll for the restored panel
      // (the asserted state) rather than waiting a fixed real-time budget.
      await pumpUntil(
        tester,
        () => reopenedContainer.read(stageWorkspaceProvider).panels.isNotEmpty,
      );
      await tester.pumpAndSettle();

      // The reopened tab's Stage workspace must hold exactly the panel +
      // binding the original tab had before export.
      final reopenedState = reopenedContainer.read(stageWorkspaceProvider);
      expect(reopenedState.panels, hasLength(1));
      expect(reopenedState.panels.first.name, equals('My Panel'));

      final reopenedInstance = reopenedState.panels.first.instances.firstWhere(
        (i) => i.id == instanceId,
      );
      expect(
        reopenedInstance.signalBindings['input']?.signalRef,
        equals(signalRef),
        reason:
            'Stage signal binding must round-trip through the per-tab '
            'session export (and would round-trip a real quit → relaunch '
            'when the workspace points the restored tab at the same path).',
      );

      tester.takeException();
    },
  );
}
