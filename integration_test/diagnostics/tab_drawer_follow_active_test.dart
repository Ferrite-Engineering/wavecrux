// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/diagnostics/tab_drawer_follow_active_test.dart
//
// end-to-end coverage of the [TabDiagnosticsDrawer]
// "follow-the-active-tab" contract.
//
// The drawer's UI follow-active-tab behavior is fully covered by its
// widget-level test in
// `test/features/diagnostics/widgets/tab_diagnostics_drawer_test.dart` —
// open the drawer, switch the active tab, assert the subtitle + embedded
// per-tab scope key change. The integration tier here exercises the
// underlying plumbing through a real `bootstrap()`: the live
// `activeTabIdProvider` notifier mirrors into `workspaceProvider`'s
// `setActiveTab`, and the per-tab `TabContainerManager` resolves to a
// distinct container per tab so the drawer's per-tab UncontrolledProviderScope
// is wired to the active tab's container.
//
// Why we don't open the real drawer UI: under the integration_test
// binding's LiveTestWidgetsFlutterBinding base, the drawer's
// `SlideTransition` AnimationController + embedded panels' provider
// subscriptions cause `tester.pump()` to never complete the third frame
// — the test hangs at "did not complete". The widget test covers the UI
// path; this test covers the bootstrap + workspace + active-tab +
// per-tab-container seam end-to-end.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
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
    'activeTabIdProvider switch propagates through bootstrap + per-tab container plumbing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(() async {
        await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      });

      final pathA = _fixturePath('vcd/scalar_basics.vcd');
      final pathB = _fixturePath('vcd/vector_formats.vcd');
      expect(File(pathA).existsSync(), isTrue);
      expect(File(pathB).existsSync(), isTrue);

      await seedFirstLaunchAnswers();
      await bootstrap(args: [pathA, pathB]);
      await tester.pump();
      // Bounded pumps — `pumpAndSettle` hangs against the live app's
      // continuous frame scheduling (LiveStatisticsStrip + the per-tab
      // MemoryStatsNotifier `Timer.periodic`).
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      final root = rootContainer(tester);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (root.read(tabListProvider).length >= 2) break;
      }

      final tabs = root.read(tabListProvider);
      expect(
        tabs,
        hasLength(2),
        reason: 'bootstrap must load both CLI fixtures into the tab list',
      );
      final tabA = tabs[0];
      final tabB = tabs[1];
      expect(tabA.filePath, equals(pathA));
      expect(tabB.filePath, equals(pathB));

      // Force tabA active first — the order of openFile mirroring after
      // bootstrap doesn't strictly determine the active pointer.
      root.read(activeTabIdProvider.notifier).activate(tabA.id);
      await root.read(workspaceProvider.future);
      expect(root.read(activeTabIdProvider), equals(tabA.id));
      expect(
        root.read(workspaceProvider).value!.activeTabId,
        equals(tabA.id),
        reason:
            'activate() must mirror through to workspace.activeTab — without '
            'this the drawer that watches activeTabIdProvider would update '
            'its subtitle but the per-tab UncontrolledProviderScope keyed by '
            'this id would race the workspace state on the next cold start',
      );

      // Resolve the per-tab container the drawer would mount its
      // UncontrolledProviderScope against. The drawer's
      // `tcm.containerFor(_targetTabId)` MUST return distinct containers
      // for each tab so the embedded FileInfoPanel / SignalHealthPanel /
      // ParserBenchmarkRunner subtree reads the right tab's
      // per-tab providers.
      final tcm = root.read(tabContainerManagerProvider);
      final containerA = tcm.containerFor(tabA.id);
      final containerB = tcm.containerFor(tabB.id);
      expect(
        containerA,
        isNot(same(containerB)),
        reason:
            'per-tab containers must be distinct instances so the '
            'drawer subtree, keyed by active tab id, gets the right '
            'tab-scoped providers on each tab switch',
      );

      // Switch active tab to tabB — assert the live + workspace state both
      // follow. This is the contract the drawer's `ref.watch(activeTabIdProvider)`
      // build path depends on.
      root.read(activeTabIdProvider.notifier).activate(tabB.id);
      await root.read(workspaceProvider.future);
      expect(root.read(activeTabIdProvider), equals(tabB.id));
      expect(
        root.read(workspaceProvider).value!.activeTabId,
        equals(tabB.id),
        reason:
            'workspace must follow the active-tab change end-to-end after '
            'bootstrap — so quit + relaunch restores to the right tab',
      );
    },
  );
}
