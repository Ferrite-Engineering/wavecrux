// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/tabs/multi_tab_pane_stress_test.dart
//
// Multi-tab / multi-pane restoration stress test.
//
// Restores a 2-pane workspace with 10 tabs each (20 files total) on cold start
// and exercises the lazy-mount + deferred-load path that fixes the
// concurrent-GPU-init crash on Windows + Intel integrated graphics
// (see docs/flutter-windows-gpu-crash-issue.md in the Pro overlay).
//
// It asserts:
//   1. All 20 tab entries restore (chips), in two panes of 10.
//   2. DEFERRED LOAD — right after restore only the per-pane active tabs are
//      loaded; the other 18 are not (their waveformSource is still null).
//   3. LAZY MOUNT + load-on-activation — visiting every tab loads it on demand,
//      displays ALL of its signals, and every panel (signal tree, value column,
//      waveform canvas, status bar) renders without throwing.
//   4. The whole 20-tab sweep completes without the process dying — the
//      regression guard for the GPU crash, which on the real Windows engine
//      would terminate the run.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/signal_list_panel.dart';
import 'package:wavecrux/features/viewer/widgets/status_bar.dart';
import 'package:wavecrux/features/viewer/widgets/value_column_panel.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
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
    '2 panes x 10 tabs (20 files): deferred load, lazy mount, all signals '
    'displayed, every panel renders without error',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1800, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final svc = WorkspaceService(codec: const WaveCruxWorkspaceCodec());
      await svc.clear();
      addTearDown(svc.clear);

      // Source fixtures (varied: scalars, vectors, deep hierarchy, reals) so the
      // sweep covers different signal shapes / panel content.
      final fixtures = <String>[
        _fixturePath('vcd/scalar_basics.vcd'),
        _fixturePath('vcd/vector_formats.vcd'),
        _fixturePath('vcd/deep_hierarchy.vcd'),
        _fixturePath('vcd/analog_real.vcd'),
      ];
      for (final f in fixtures) {
        expect(File(f).existsSync(), isTrue, reason: 'missing fixture $f');
      }

      // Materialize 20 distinct files on disk (the workspace tab list needs
      // distinct paths). Copies of the fixtures, round-robined.
      final tmp = Directory.systemTemp.createTempSync('wcrux_stress_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } on Object {
          /* best-effort */
        }
      });
      final paths = <String>[
        for (var i = 0; i < 20; i++)
          (File('${tmp.path}${Platform.pathSeparator}tab_$i.vcd')
                ..writeAsBytesSync(
                  File(fixtures[i % fixtures.length]).readAsBytesSync(),
                ))
              .path,
      ];

      // Build a 2-pane workspace, 10 tabs each.
      final paneL = PaneId.generate();
      final paneR = PaneId.generate();
      final tabIds = [for (var i = 0; i < 20; i++) TabId.generate()];
      final seed = Workspace(
        tabs: [
          for (var i = 0; i < 20; i++)
            buildWorkspaceTab(
              id: tabIds[i],
              displayName: 'tab_$i.vcd',
              paneId: i < 10 ? paneL : paneR,
              filePath: paths[i],
            ),
        ],
        panes: [
          WorkspacePane(id: paneL, activeTabId: tabIds[0]),
          WorkspacePane(id: paneR, activeTabId: tabIds[10]),
        ],
        activePaneId: paneL,
      );
      await svc.save(seed);
      SharedPreferences.setMockInitialValues({
        'settings.restoreTabsOnLaunch': true,
      });

      await seedFirstLaunchAnswers();
      await bootstrap();

      // Pump initial frames so the root UncontrolledProviderScope is mounted
      // before reaching for the root container.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final root = rootContainer(tester);
      // Force-resolve settings so the post-frame restore (which awaits them)
      // can run.
      await root.read(appSettingsProvider.future);

      // Pump until all 20 tab entries are restored.
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (root.read(tabListProvider).length >= 20) break;
      }
      expect(
        root.read(tabListProvider).length,
        20,
        reason: '20-tab workspace must restore 20 tab entries',
      );

      final tcm = root.read(tabContainerManagerProvider);
      bool isLoaded(TabId id) =>
          tcm.containerFor(id).read(waveformSourceProvider).value != null;
      int loadedCount() => tabIds.where(isLoaded).length;

      // (2) DEFERRED LOAD: let the per-pane active tabs finish loading, then
      // assert the other 18 are still NOT loaded.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (isLoaded(tabIds[0]) && isLoaded(tabIds[10])) break;
      }
      expect(
        loadedCount(),
        lessThanOrEqualTo(2),
        reason:
            'deferred load: only the two per-pane active tabs load at restore',
      );
      // The 18 background tabs must be unloaded.
      for (final i in [1, 5, 9, 11, 15, 19]) {
        expect(
          isLoaded(tabIds[i]),
          isFalse,
          reason: 'background tab $i must NOT be loaded at restore',
        );
      }
      // Panels render for the restored active tabs without exception.
      expect(find.byType(WaveformCanvas), findsWidgets);
      expect(find.byType(StatusBar), findsWidgets);
      tester.takeException(); // drain headless branding-asset codec failures

      // (3) Visit every tab: activate -> load-on-demand -> show ALL signals ->
      // verify panels render with no exception.
      for (var i = 0; i < 20; i++) {
        final id = tabIds[i];
        root.read(activeTabIdProvider.notifier).activate(id);

        final loaded = await pumpUntil(
          tester,
          () => isLoaded(id),
          timeout: const Duration(seconds: 8),
        );
        expect(loaded, isTrue, reason: 'tab $i must load when first activated');

        // Display ALL signals for this tab in its own container.
        final container = tcm.containerFor(id);
        final source = container.read(waveformSourceProvider).value!;
        final allVars = source.findVariables(const SignalFilter());
        expect(allVars, isNotEmpty, reason: 'fixture for tab $i has signals');
        container.read(signalGroupsProvider.notifier).addSignals(allVars);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        // No panel threw while rendering all signals for this tab.
        expect(
          tester.takeException(),
          isNull,
          reason: 'tab $i: a panel threw while displaying all signals',
        );

        // Every primary panel is present and rendering.
        expect(
          find.byType(WaveformCanvas),
          findsWidgets,
          reason: 'tab $i: waveform canvas',
        );
        expect(
          find.byType(SignalListPanel),
          findsWidgets,
          reason: 'tab $i: signal tree panel',
        );
        expect(
          find.byType(ValueColumnPanel),
          findsWidgets,
          reason: 'tab $i: value column panel',
        );
        expect(
          find.byType(StatusBar),
          findsWidgets,
          reason: 'tab $i: status bar',
        );
      }

      // (4) After visiting all tabs, every one is loaded — the sweep completed
      // without the process dying.
      expect(
        loadedCount(),
        20,
        reason: 'every visited tab loaded; no crash across the 20-tab sweep',
      );
    },
    // Generous: 20 file loads + all-signal renders on a headless device.
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
