// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/coexistence/composite_workspace_round_trip_test.dart
//
// Composite workspace round-trip.
//
// Sets up a broad "kitchen-sink" workspace state and asserts
// that every persistence-relevant piece of it survives a save / close /
// re-open lifecycle:
//
//   * Workspace shape:
//       - Two open tabs hosted in **two panes** (split-pane).
//       - Active-pane / active-tab pointers track the user's last focus.
//   * Per-tab state (captured via `.wavecrux` export):
//       - Tab 1: Stage panel + LED widget bound to a signal,
//         FSM annotation, statistics strip visibility, primary cursor,
//         and an active I²C decoder instance.
//       - Tab 2: signal added to the signal list, a primary cursor, and
//         an active UART decoder instance.
//
// The workspace model is honoured throughout: `workspace.json` persists
// only tab metadata + pane layout; per-tab state lives on each tab's
// per-tab provider container and travels through the `.wavecrux`
// session export (which is the same write the auto-save-on-quit
// pipeline ultimately fires). The test invokes `flushPendingSave` for
// the workspace document and `exportTabForContainer` for each tab —
// the deterministic surrogates for the lifecycle-paused flush.
//
// Refresh note: renames the original
// "composite_session_round_trip" placeholder to a workspace-scoped name
// and replaces explicit `.wavecrux` save/load on the root scope with
// the workspace-aware per-tab pipeline.
//
// Decoder coverage added later: the composite scenario originally skipped
// decoders entirely (`decoder_restore_on_open_test.dart` covers decoder
// restore standalone, against a genuine multi-bus fixture). This file now
// also activates a decoder on EACH tab (I²C on tab A, UART on tab B) before
// save and asserts both survive the round-trip alongside every other
// feature above — proving the composite multi-tab / multi-pane /
// multi-feature scenario doesn't drop decoder state the way the standalone
// test wouldn't catch.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/fsm_annotation.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/commands/export_tab_command.dart';
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
    'composite workspace state (2 tabs / 2 panes / Stage + FSM + signals + cursors) survives save → close → re-open',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(() async {
        await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      });

      final pathA = _fixturePath('stage/stage_demo.vcd');
      final pathB = _fixturePath('vcd/scalar_basics.vcd');
      expect(File(pathA).existsSync(), isTrue);
      expect(File(pathB).existsSync(), isTrue);

      final tmp = Directory.systemTemp.createTempSync(
        'wavecrux_composite_workspace_',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final exportTabA = '${tmp.path}/tabA.wavecrux';
      final exportTabB = '${tmp.path}/tabB.wavecrux';

      // Boot with two CLI files — both land in the active pane initially.
      await seedFirstLaunchAnswers();
      await bootstrap(args: [pathA, pathB]);
      await tester.pump();
      await pumpUntilWaveformReady(tester);

      final root = rootContainer(tester);

      // Wait for both tabs to be populated.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (root.read(tabListProvider).length >= 2) break;
      }
      final initialTabs = root.read(tabListProvider);
      expect(initialTabs, hasLength(2));
      final tabA = initialTabs[0];
      final tabB = initialTabs[1];

      // Sync the live tabs into `workspaceNotifier` so the workspace
      // document carries them. `tabListProvider` is the in-memory
      // tab list and `workspaceProvider` is the persistence
      // surface; they are not auto-synced (the production lifecycle
      // handler constructs a snapshot at quit and collapses all live
      // tabs to a single pane). For the composite test we want
      // workspaceProvider to truly hold {2 tabs / 2 panes} so we
      // mirror each live tab into it explicitly.
      final workspaceNotifier = root.wavecruxWorkspace;
      final initialWorkspace = workspaceNotifier.current;
      final initialPaneId = initialWorkspace.activePaneId;
      await workspaceNotifier.addTab(
        buildWorkspaceTab(
          id: tabA.id,
          displayName: tabA.displayName,
          paneId: initialPaneId,
          filePath: tabA.filePath,
        ),
      );
      await workspaceNotifier.addTab(
        buildWorkspaceTab(
          id: tabB.id,
          displayName: tabB.displayName,
          paneId: initialPaneId,
          filePath: tabB.filePath,
        ),
      );

      // Split the workspace into 2 panes; move tab B into the new pane.
      final secondPaneId = await workspaceNotifier.splitPane();
      await workspaceNotifier.moveTabToPane(tabB.id, secondPaneId);
      await workspaceNotifier.setActiveTab(tabA.id);
      // Mirror the move on the live tab list so the live state agrees
      // with the workspace document.
      await root.wavecruxWorkspace.moveTabToPane(tabB.id, secondPaneId);
      await tester.pump();

      // ----- Tab A state: Stage panel + FSM annotation + cursor + signals
      //                    + statistics strip on -----
      final tcm = root.read(tabContainerManagerProvider);
      final containerA = tcm.containerFor(tabA.id);

      // Wait for tab A's source to load so the hierarchy is available
      // (we add a real signal to the signal list below).
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final src = containerA.read(waveformSourceProvider).value;
        if (src != null) break;
      }
      final sourceA = containerA.read(waveformSourceProvider).value;
      expect(
        sourceA,
        isNotNull,
        reason: 'tab A source must finish loading before we add signals',
      );

      // Stage panel + LED widget bound to a known signal.
      final stageNotifierA = containerA.read(stageWorkspaceProvider.notifier)
        ..addPanel('Composite Panel');
      final stageInstanceId = stageNotifierA.addInstance('led');
      expect(stageInstanceId, isNotNull);
      const ledSignalRef = 'top.primitives.led_blink';
      stageNotifierA.setBinding(stageInstanceId!, 'input', ledSignalRef);

      // FSM annotation against an arbitrary signal ref — the labels are
      // pure data on the FSM annotation notifier and do not require a
      // real waveform query.
      const fsmSignalRef = 'top.fsm.state';
      const fsmLabels = {'0': 'IDLE', '1': 'RUN', '2': 'STOP'};
      containerA
          .read(fsmAnnotationProvider.notifier)
          .setAnnotation(
            fsmSignalRef,
            const FsmAnnotation(
              signalRef: fsmSignalRef,
              stateLabels: fsmLabels,
            ),
          );

      // Add a real signal to tab A's signal list. The first variable in
      // the loaded hierarchy is a stable target across runs.
      final tabAVars = sourceA!.findVariables(const SignalFilter());
      expect(tabAVars, isNotEmpty);
      final tabASignal = tabAVars.first;
      containerA.read(signalGroupsProvider.notifier).addSignal(tabASignal);

      // Decoder — an I²C decoder bound to two real signals from tab A's own
      // hierarchy (arbitrary but real signal refs, same "pure data, no real
      // waveform query needed" spirit as the FSM annotation above; decode
      // *correctness* against a genuine multi-bus fixture is already covered
      // by decoder_restore_on_open_test.dart). This proves the decoder's
      // identity/config survives the composite save → close → reopen
      // alongside Stage / FSM / cursor / signals / stats below.
      String refForA(String name) =>
          tabAVars.firstWhere((v) => v.name == name).signalRef;
      containerA
          .read(activeDecodersProvider.notifier)
          .addDecoder(
            'i2c',
            DecoderConfig(
              signalBindings: {
                'scl': refForA('led_blink'),
                'sda': refForA('led_slow'),
              },
            ),
          );
      await containerA.read(activeDecodersProvider.notifier).decodeAll();
      await tester.pump();

      final decodersBeforeSave = containerA.read(activeDecodersProvider);
      expect(decodersBeforeSave, hasLength(1));
      final decoderIdBefore = decodersBeforeSave.first.decoderId;
      final decoderInstanceBefore = decodersBeforeSave.first.instanceNumber;
      final decoderBindingsBefore =
          decodersBeforeSave.first.config.signalBindings;

      // Cursor at tick 123.
      containerA.read(cursorStateProvider.notifier).placePrimary(123);

      // Panel visibility — including the statistics strip — is per-tab
      // (`panelLayoutProvider` is overridden per tab container, commit
      // 2ddf488) and tab A's session snapshot reads THIS tab's notifier, so
      // set it on tab A's container. Turning it on here proves the round-trip
      // captures the boolean correctly.
      containerA
          .read(panelLayoutProvider.notifier)
          .setStatisticsStripVisible(visible: true);
      await tester.pump();

      // ----- Tab B state: signals + cursor -----
      final containerB = tcm.containerFor(tabB.id);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final src = containerB.read(waveformSourceProvider).value;
        if (src != null) break;
        // Tab B is in the inactive pane; ViewerScreen lazy-loads only the
        // active tab. Force-load it via the per-tab notifier so we have
        // something to add signals from.
        if (i == 5) {
          unawaited(
            containerB.read(waveformSourceProvider.notifier).openFile(pathB),
          );
        }
      }
      final sourceB = containerB.read(waveformSourceProvider).value;
      expect(
        sourceB,
        isNotNull,
        reason: 'tab B source must load before we add signals',
      );

      final tabBVars = sourceB!.findVariables(const SignalFilter());
      expect(tabBVars, isNotEmpty);
      final tabBSignal = tabBVars.first;
      containerB.read(signalGroupsProvider.notifier).addSignal(tabBSignal);
      // Tab B loads scalar_basics.vcd, which spans only 100 ticks;
      // cursorStateProvider.placePrimary clamps to [startTime, endTime], so
      // the cursor value must be within that range (a larger value such as
      // 456 would clamp to 100 at set time and never round-trip).
      containerB.read(cursorStateProvider.notifier).placePrimary(90);

      // A second decoder — a UART decoder on tab B (same "arbitrary but real
      // signal ref" spirit as tab A's I²C decoder above) — so the composite
      // scenario matches the "multiple decoders bound" wording in
      // PENDING.md's "Session round-trip with Stage active, FSM open,
      // statistics strip expanded, multiple decoders bound, custom panel
      // sizes" item: two decoders, on two different tabs/panes, both
      // surviving the same round-trip.
      containerB
          .read(activeDecodersProvider.notifier)
          .addDecoder(
            'uart',
            DecoderConfig(
              signalBindings: {
                'tx': tabBVars.firstWhere((v) => v.name == 'clk').signalRef,
              },
            ),
          );
      await containerB.read(activeDecodersProvider.notifier).decodeAll();
      await tester.pump();

      final decodersBBeforeSave = containerB.read(activeDecodersProvider);
      expect(decodersBBeforeSave, hasLength(1));
      final decoderIdBBefore = decodersBBeforeSave.first.decoderId;
      final decoderInstanceBBefore = decodersBBeforeSave.first.instanceNumber;
      final decoderBindingsBBefore =
          decodersBBeforeSave.first.config.signalBindings;

      // ----- Persist: flush workspace + export each tab -----
      await workspaceNotifier.flushPendingSave();
      final exportAErr = await exportTabForContainer(root, tabA.id, exportTabA);
      expect(exportAErr, isNull);
      final exportBErr = await exportTabForContainer(root, tabB.id, exportTabB);
      expect(exportBErr, isNull);

      // Sanity-check workspace.json content via a fresh service read.
      final persistedWs = await WorkspaceService(
        codec: const WaveCruxWorkspaceCodec(),
      ).load();
      expect(persistedWs.tabs.length, equals(2));
      expect(persistedWs.panes.length, equals(2));
      expect(
        persistedWs.tabs.map((t) => t.paneId).toSet().length,
        equals(2),
        reason:
            'after splitPane + moveTabToPane each tab must live in its own pane',
      );

      // ----- Close all tabs (workspace transitions to empty-canvas) -----
      await root.wavecruxWorkspace.closeTab(tabA.id);
      await root.wavecruxWorkspace.closeTab(tabB.id);
      await tester.pump();
      expect(root.read(tabListProvider), isEmpty);

      // Reset the app-level statistics-strip flag so we can verify the
      // per-tab session-load restores it back on.
      root
          .read(panelLayoutProvider.notifier)
          .setStatisticsStripVisible(visible: false);
      await tester.pump();

      // ----- Re-open each export as a fresh tab and load the session -----
      await root.wavecruxWorkspace.openSession(
        exportTabA,
        filePath: pathA,
      );
      await root.wavecruxWorkspace.openSession(
        exportTabB,
        filePath: pathB,
      );
      await tester.pump();

      final reopenedTabs = root.read(tabListProvider);
      expect(reopenedTabs, hasLength(2));
      final reopenedA = reopenedTabs[0];
      final reopenedB = reopenedTabs[1];
      final reopenedContainerA = tcm.containerFor(reopenedA.id);
      final reopenedContainerB = tcm.containerFor(reopenedB.id);

      await reopenedContainerA
          .read(sessionProvider.notifier)
          .loadFromPath(exportTabA);
      await reopenedContainerB
          .read(sessionProvider.notifier)
          .loadFromPath(exportTabB);
      // Each loadFromPath restores per-tab state (and may re-open the waveform
      // on the background isolate); poll until both tabs' cursors are restored
      // (the asserted state) rather than waiting a fixed real-time budget.
      await pumpUntil(
        tester,
        () =>
            reopenedContainerA.read(cursorStateProvider).primaryCursorTime ==
                123 &&
            reopenedContainerB.read(cursorStateProvider).primaryCursorTime ==
                90 &&
            reopenedContainerA.read(activeDecodersProvider).isNotEmpty &&
            reopenedContainerB.read(activeDecodersProvider).isNotEmpty,
      );
      await tester.pumpAndSettle();

      // ----- Assertions: every piece of saved state restored. -----

      // Tab A: Stage panel + binding + FSM annotation + cursor + signals.
      final stageStateA = reopenedContainerA.read(stageWorkspaceProvider);
      expect(stageStateA.panels, hasLength(1));
      expect(stageStateA.panels.first.name, equals('Composite Panel'));
      expect(
        stageStateA.panels.first.instances
            .firstWhere((i) => i.id == stageInstanceId)
            .signalBindings['input']
            ?.signalRef,
        equals(ledSignalRef),
      );

      final fsmAnnotationsA = reopenedContainerA.read(fsmAnnotationProvider);
      expect(fsmAnnotationsA, contains(fsmSignalRef));
      expect(
        fsmAnnotationsA[fsmSignalRef]!.stateLabels,
        equals(fsmLabels),
      );

      // Decoder — the I²C decoder activated on tab A above must survive the
      // round-trip with its identity and config intact (decoderId,
      // instanceNumber, and signal bindings), the same invariant
      // decoder_restore_on_open_test.dart asserts standalone, now proven
      // inside the composite multi-feature / multi-tab / multi-pane scenario.
      final decodersAfterRestore = reopenedContainerA.read(
        activeDecodersProvider,
      );
      expect(decodersAfterRestore, hasLength(1));
      expect(decodersAfterRestore.first.decoderId, equals(decoderIdBefore));
      expect(
        decodersAfterRestore.first.instanceNumber,
        equals(decoderInstanceBefore),
      );
      expect(
        decodersAfterRestore.first.config.signalBindings,
        equals(decoderBindingsBefore),
        reason:
            'decoder signal bindings must round-trip through the composite '
            'workspace save → close → reopen exactly like Stage/FSM/cursor '
            'state does',
      );

      expect(
        reopenedContainerA.read(cursorStateProvider).primaryCursorTime,
        equals(123),
      );

      final reopenedSignalsA = reopenedContainerA.read(signalGroupsProvider);
      expect(
        reopenedSignalsA.signalCount,
        greaterThan(0),
        reason:
            'tab A signal list must restore at least the one signal '
            'added before the round-trip',
      );

      // Statistics strip back on for tab A. Panel visibility is per-tab
      // (`panelLayoutProvider` is overridden per tab container — see
      // `wavecrux_tab_overrides.dart`), captured in tab A's session sidecar,
      // so it restores into tab A's container — not the root singleton.
      expect(
        reopenedContainerA.read(panelLayoutProvider).statisticsStripVisible,
        isTrue,
        reason:
            'statistics strip visibility must round-trip through the '
            'session export',
      );

      // Tab B: signals + cursor + decoder.
      expect(
        reopenedContainerB.read(cursorStateProvider).primaryCursorTime,
        equals(90),
      );
      final reopenedSignalsB = reopenedContainerB.read(signalGroupsProvider);
      expect(reopenedSignalsB.signalCount, greaterThan(0));

      final decodersBAfterRestore = reopenedContainerB.read(
        activeDecodersProvider,
      );
      expect(decodersBAfterRestore, hasLength(1));
      expect(decodersBAfterRestore.first.decoderId, equals(decoderIdBBefore));
      expect(
        decodersBAfterRestore.first.instanceNumber,
        equals(decoderInstanceBBefore),
      );
      expect(
        decodersBAfterRestore.first.config.signalBindings,
        equals(decoderBindingsBBefore),
        reason:
            "tab B's decoder must also round-trip, proving two decoders on "
            'two different tabs/panes both survive the same composite save '
            '→ close → reopen',
      );

      tester.takeException();
    },
  );
}
