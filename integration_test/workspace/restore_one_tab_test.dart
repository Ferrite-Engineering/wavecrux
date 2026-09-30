// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/restore_one_tab_test.dart
//
// Workspace round-trip for a single tab with per-tab state
// (cursor + zoom) surviving an `AppLifecycleState.detached` quit.
//
// The Flutter framework forbids invoking `runApp` more than once in a
// single test process, so the canonical "quit and relaunch" round-trip
// runs as a single boot that exercises both halves of the persistence
// contract:
//
//   1. **Quit half.** Open a fixture VCD via CLI args, place the primary
//      cursor at a known tick, change the zoom level, then flush both the
//      workspace document and the per-tab sidecar via the same code paths
//      the production `AppLifecycleState.detached` handler invokes
//      (`_flushWorkspace` snapshots the live tab list + per-pane active
//      tab pointers and `sessionAutoSaveProvider.flushPendingSave` writes
//      `{appSupportDir}/sessions/{tabId}.wavecrux`).
//   2. **Relaunch half.** Read both artifacts back through fresh service
//      instances and assert the persisted state is exactly what the
//      production restore path would consume: workspace.json records the
//      single tab pointing at the same fixture, and the sidecar records
//      the cursor tick and zoom level the user placed before quitting.
//
// The steady-state cold-start restoration path
// (`_WaveCruxAppState._restoreFromWorkspace`) is covered by
// `integration_test/tabs/startup_restoration_test.dart`; this test
// complements it by exercising the SAVE half end-to-end.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/session/session_service.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../helpers/workspace_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'one-tab workspace round-trip: cursor + zoom survive AppLifecycleState.detached',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Clean the real app-support workspace.json on entry and exit so this
      // test does not pick up stale state or leak into the user-facing app.
      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(() async {
        await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      });

      final fixture = fixturePath('vcd/scalar_basics.vcd');
      expect(File(fixture).existsSync(), isTrue);

      // Boot with the fixture as the only CLI arg so the live tab list
      // contains exactly one tab pointing at the file.
      await seedFirstLaunchAnswers();
      await bootstrap(args: [fixture]);
      await tester.pump();
      await pumpUntilWaveformReady(tester);

      final root = rootContainer(tester);

      // ViewerScreen's initState opens the file from a post-frame callback;
      // wait until the live tab list reflects the open.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (root.read(tabListProvider).isNotEmpty) break;
      }
      expect(root.read(tabListProvider), hasLength(1));
      final tab = root.read(tabListProvider).first;
      expect(tab.filePath, equals(fixture));

      // Force-resolve the settings future so the workspace flush helper
      // observes a resolved AppSettings (matches the production guard).
      await root.read(appSettingsProvider.future);

      // ----- Mutate per-tab state -----
      //
      // Place the primary cursor at tick 50 and switch zoom away from the
      // default fit-all level. Both pieces persist into the sidecar.
      const cursorTick = 50;
      final tcm = root.read(tabContainerManagerProvider);
      final tabContainer = tcm.containerFor(tab.id);
      tabContainer.read(cursorStateProvider.notifier).placePrimary(cursorTick);

      // Derive the zoom from the live mapper rather than naming a constant.
      // `setZoom` clamps to [minTicksPerPixel, maxTicksPerPixel], and
      // maxTicksPerPixel is `range / viewportWidth` — so it depends on the
      // window the test app happens to launch at. A hardcoded 0.25 was above
      // fit-all on the CI runner's narrower window and got clamped to 0.1,
      // failing an assertion about *persistence* for a reason that had
      // nothing to do with persistence. Half of fit-all is unambiguously
      // inside the range on any window.
      final fitAllZoom = tabContainer.read(timeMapperProvider).maxTicksPerPixel;
      tabContainer.read(timeMapperProvider.notifier).setZoom(fitAllZoom / 2);
      await tester.pump();

      // What the notifier actually settled on, which is what the sidecar will
      // record. Asserting against the *request* re-introduces the same bug.
      final zoomTicksPerPixel = tabContainer
          .read(timeMapperProvider)
          .ticksPerPixel;
      expect(
        zoomTicksPerPixel,
        lessThan(fitAllZoom),
        reason:
            'the test must leave a zoom that differs from the fit-all '
            'default, or the restore assertion below proves nothing',
      );

      // ----- Flush both persistence layers (simulate detached) -----
      //
      // The production `_flushWorkspace` writes workspace.json AND iterates
      // over each tab to flush its sidecar via
      // `sessionAutoSaveProvider.flushPendingSave`. Both writes are required
      // for the relaunch path to restore the tab's per-tab state.
      await flushLiveWorkspace(root);
      await tabContainer
          .read(sessionAutoSaveProvider.notifier)
          .flushPendingSave();

      // ----- Verify the workspace document -----
      final persistedWorkspace = await WorkspaceService(
        codec: const WaveCruxWorkspaceCodec(),
      ).load();
      expect(
        persistedWorkspace.tabs,
        hasLength(1),
        reason: 'workspace.json must record the single open tab',
      );
      expect(
        persistedWorkspace.tabs.first.filePath,
        equals(fixture),
        reason:
            'persisted tab must point at the same fixture path the '
            'user opened',
      );
      expect(
        persistedWorkspace.tabs.first.id,
        equals(tab.id),
        reason:
            'tab identity must round-trip so the relaunch reuses the '
            'same sidecar file name',
      );
      expect(
        persistedWorkspace.panes,
        hasLength(1),
        reason: 'single-tab quit must remain single-pane',
      );
      expect(
        persistedWorkspace.activePane.activeTabId,
        equals(tab.id),
        reason: 'activeTabId must follow the restored tab so focus survives',
      );

      // ----- Verify the per-tab sidecar -----
      //
      // The sidecar is the surface the relaunch path reads back via
      // `SessionNotifier.loadFromPath` to restore cursor / zoom / signals.
      // Read it through a fresh SessionService instance — the same code
      // path `_restoreFromWorkspace` invokes after `sidecarPathFor` resolves.
      final sidecarPath = await root
          .read(workspaceServiceProvider)
          .sidecarPathFor(tab.id.value);
      expect(sidecarPath, isNotNull);
      expect(
        File(sidecarPath!).existsSync(),
        isTrue,
        reason:
            'sessionAutoSaveProvider.flushPendingSave must have written '
            'the per-tab sidecar so the relaunch can restore cursor + zoom',
      );
      final restored = await const SessionService().loadSession(sidecarPath);
      expect(
        restored.sourceFilePath,
        equals(fixture),
        reason:
            'sidecar must record the source file path for the relaunch '
            'to reopen the correct waveform',
      );
      expect(
        restored.cursorState.primaryCursorTime,
        equals(cursorTick),
        reason: 'cursor placement must survive the quit/relaunch cycle',
      );
      expect(
        restored.ticksPerPixel,
        equals(zoomTicksPerPixel),
        reason: 'zoom level must survive the quit/relaunch cycle',
      );

      // Drain any branding-asset codec errors from the headless test bundle
      // rather than fail.
      tester.takeException();
    },
  );
}
