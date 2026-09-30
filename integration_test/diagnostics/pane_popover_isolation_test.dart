// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/diagnostics/pane_popover_isolation_test.dart
//
// end-to-end coverage of the per-pane isolation contract
// that backs [PaneRenderStatsPopover].
//
// The popover's display logic is fully covered by its widget-level test
// in `test/features/diagnostics/widgets/pane_render_stats_popover_test.dart`
// — including the "switching active pane does not swap content" assertion
// and the locale sweep. The integration-tier contract this file pins is
// strictly the plumbing layer: under a real `bootstrap()`, a real
// workspace split, and a real `tabListProvider.moveTabToPane`, each
// pane's [ProviderContainer] (obtained through
// `paneContainerManagerProvider`) must hold its own independent
// [PaneRenderStatsNotifier] state, and active-pane changes must not
// mutate either pane's state.
//
// Why we exercise the provider layer directly instead of opening the
// real popover UI: opening the popover anchors a Material/Tooltip
// subtree inside an [OverlayEntry] that, on the integration_test
// binding's LiveTestWidgetsFlutterBinding base, can leave
// [SemanticsHandle] instances outstanding past the end of the test body
// (the framework's `_verifySemanticsHandlesWereDisposed` then trips).
// The widget test covers the UI path; this test covers the bootstrap +
// workspace + split-pane + container-manager seam end-to-end.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/render_pipeline_stats.dart';
import 'package:wavecrux/features/panes/providers/pane_render_stats_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
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
    'each split pane gets an isolated paneRenderStatsProvider; '
    'active-pane changes do not mutate either pane state',
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
      await pumpUntilWaveformReady(tester);

      final root = rootContainer(tester);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (root.read(tabListProvider).length >= 2) break;
      }
      await tester.pumpAndSettle();

      final tabs = root.read(tabListProvider);
      expect(tabs, hasLength(2));
      final tabB = tabs[1];

      // Split right and move tab B into the new pane so each pane has its
      // own canvas. Mirrors `ViewerScreen._splitPaneRight`.
      final wsNotifier = root.wavecruxWorkspace;
      final leftPaneId = wsNotifier.current.activePaneId;
      final rightPaneId = await wsNotifier.splitPane();
      await root.wavecruxWorkspace.moveTabToPane(tabB.id, rightPaneId);
      await root.read(workspaceProvider.future);
      await tester.pumpAndSettle();

      // Resolve the per-pane containers through the production
      // [paneContainerManagerProvider]. Each `containerFor(id)` call
      // lazily creates (and then caches) a child container — calling
      // twice for the same id returns the same instance.
      final pcm = root.read(paneContainerManagerProvider);
      final leftContainer = pcm.containerFor(leftPaneId);
      final rightContainer = pcm.containerFor(rightPaneId);
      expect(
        leftContainer,
        isNot(same(rightContainer)),
        reason:
            'each pane must own a distinct ProviderContainer for true per-pane isolation',
      );

      // Resolve [paneRenderStatsProvider] in each pane container. They
      // must be distinct notifier *instances* (per the override factory
      // in `PaneContainerManager._composeOverrides`).
      final leftNotifier = leftContainer.read(paneRenderStatsProvider.notifier);
      final rightNotifier = rightContainer.read(
        paneRenderStatsProvider.notifier,
      );
      expect(
        leftNotifier,
        isNot(same(rightNotifier)),
        reason:
            'each pane container overrides paneRenderStatsProvider '
            'with a fresh PaneRenderStatsNotifier',
      );

      // Switch active pane to the left side first (sequence: change focus,
      // THEN write the sentinel, THEN read synchronously — no pump
      // between record/read since the production
      // `RenderStatsCollector → paneRenderStatsProvider` bridge fires on
      // every canvas paint and would otherwise overwrite the sentinel
      // with the live frame's stats).
      await wsNotifier.setActivePane(leftPaneId);
      await tester.pump();
      // Re-seed BOTH panes' notifiers and immediately cross-read.
      leftNotifier.record(_seedStats(visibleTransitions: 111));
      rightNotifier.record(_seedStats(visibleTransitions: 444));
      expect(
        leftContainer.read(paneRenderStatsProvider).latest!.visibleTransitions,
        equals(111),
        reason:
            "left pane container's paneRenderStatsProvider holds the left sentinel "
            'after the active pane was set to LEFT — proves per-pane isolation '
            'is independent of active-pane state',
      );
      expect(
        rightContainer.read(paneRenderStatsProvider).latest!.visibleTransitions,
        equals(444),
        reason:
            "right pane container's paneRenderStatsProvider holds the right sentinel "
            'while LEFT is active — active-pane identity must not influence which '
            "pane's container holds which value",
      );

      // Now switch focus to the RIGHT side and repeat the cross-read.
      // The contract is symmetric: active-pane identity is irrelevant to
      // container-state ownership.
      await wsNotifier.setActivePane(rightPaneId);
      await tester.pump();
      leftNotifier.record(_seedStats(visibleTransitions: 222));
      rightNotifier.record(_seedStats(visibleTransitions: 555));
      expect(
        leftContainer.read(paneRenderStatsProvider).latest!.visibleTransitions,
        equals(222),
        reason: "left pane's notifier remains writeable while RIGHT is active",
      );
      expect(
        rightContainer.read(paneRenderStatsProvider).latest!.visibleTransitions,
        equals(555),
        reason:
            "right pane's notifier holds its own sentinel while it's "
            'the active pane',
      );

      // Final cross-isolation check: mutate only one pane's notifier and
      // assert the other is unchanged. Reads are issued synchronously
      // after the write to avoid any pump→canvas-paint→bridge cycle.
      leftNotifier.record(_seedStats(visibleTransitions: 333));
      expect(
        leftContainer.read(paneRenderStatsProvider).latest!.visibleTransitions,
        equals(333),
      );
      expect(
        rightContainer.read(paneRenderStatsProvider).latest!.visibleTransitions,
        equals(555),
        reason:
            "mutating pane L's notifier must not bleed into pane R's "
            'container',
      );
    },
  );
}

/// Constructs a minimal [RenderPipelineStats] snapshot with [visibleTransitions]
/// driven to a known sentinel so the test can assert against it.
RenderPipelineStats _seedStats({required int visibleTransitions}) =>
    RenderPipelineStats(
      visibleSignalRows: 4,
      visibleTransitions: visibleTransitions,
      lineSegmentsDrawn: 999,
      layoutTimeUs: 500,
      scalarPaintTimeUs: 1500,
      vectorPaintTimeUs: 1000,
      analogPaintTimeUs: 300,
      cursorPaintTimeUs: 100,
      transactionPaintTimeUs: 100,
      totalPaintTimeUs: 4500,
      canvasWidth: 800,
      canvasHeight: 600,
    );
