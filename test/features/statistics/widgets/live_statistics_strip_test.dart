// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_stats_strip/crux_stats_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/memory_stats.dart';
import 'package:wavecrux/domain/models/render_pipeline_stats.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/diagnostics/providers/memory_stats_provider.dart';
import 'package:wavecrux/features/panes/providers/pane_render_stats_provider.dart';
import 'package:wavecrux/features/statistics/widgets/live_statistics_strip.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../../../helpers/product_telemetry_config.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

MemoryStats _memory({
  int wellenEstimateBytes = 0,
  int loadedSignalCount = 0,
  int totalSignalCount = 0,
  int dartProcessRssBytes = 0,
}) => MemoryStats(
  wellenEstimateBytes: wellenEstimateBytes,
  loadedSignalCount: loadedSignalCount,
  totalSignalCount: totalSignalCount,
  dartProcessRssBytes: dartProcessRssBytes,
);

RenderPipelineStats _render({
  int visibleSignalRows = 10,
  int visibleTransitions = 500,
  int lineSegmentsDrawn = 1200,
  int layoutTimeUs = 500,
  int scalarPaintTimeUs = 2000,
  int vectorPaintTimeUs = 1500,
  int analogPaintTimeUs = 800,
  int cursorPaintTimeUs = 100,
  int transactionPaintTimeUs = 200,
  int totalPaintTimeUs = 5100,
  double canvasWidth = 1920,
  double canvasHeight = 600,
}) => RenderPipelineStats(
  visibleSignalRows: visibleSignalRows,
  visibleTransitions: visibleTransitions,
  lineSegmentsDrawn: lineSegmentsDrawn,
  layoutTimeUs: layoutTimeUs,
  scalarPaintTimeUs: scalarPaintTimeUs,
  vectorPaintTimeUs: vectorPaintTimeUs,
  analogPaintTimeUs: analogPaintTimeUs,
  cursorPaintTimeUs: cursorPaintTimeUs,
  transactionPaintTimeUs: transactionPaintTimeUs,
  totalPaintTimeUs: totalPaintTimeUs,
  canvasWidth: canvasWidth,
  canvasHeight: canvasHeight,
);

class _FakeMemoryStatsNotifier extends MemoryStatsNotifier {
  _FakeMemoryStatsNotifier(this._value);
  final MemoryStats? _value;

  @override
  MemoryStats? build() => _value;
}

/// Swallows the strip's RSS-poll request so the shared collector's two-second
/// timer never starts.
///
/// These tests are about what the strip renders, and every one of them ends
/// with the strip still expanded — a live poll would be reported, correctly,
/// as a timer outliving the widget tree. The polling contract itself is
/// covered by crux_stats_strip's own tests, and the strip's end of it by the
/// "poll demand" group below, which uses the real notifier.
class _NoPollRequests extends CruxMemoryPollRequestNotifier {
  @override
  void request(String tag) {}
}

/// Workspace service stub that always returns [workspace] from `load()` and
/// silently accepts saves. Bypasses the on-disk JSON store so widget tests
/// can drive a deterministic workspace state.
class _StubWorkspaceService implements WorkspaceService {
  _StubWorkspaceService(this.workspace);
  final Workspace workspace;

  @override
  WaveCruxWorkspaceCodec get codec => const WaveCruxWorkspaceCodec();

  @override
  String get fileName => 'workspace.json';

  @override
  Future<Workspace> load() async => workspace;

  @override
  Future<Workspace> loadFromPath(String path) async => workspace;

  @override
  Future<void> save(Workspace ws) async {}

  @override
  Future<void> saveToPath(String path, Workspace ws) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> clearAllSidecars() async {}

  @override
  Future<String?> sidecarPathFor(
    String tabId, {
    String extension = '.json',
  }) async => null;

  @override
  Future<void> deleteSidecar(
    String tabId, {
    String extension = '.json',
  }) async {}

  @override
  WorkspaceRecovery? takeRecovery() => null;
}

Widget _wrap({
  required ProviderContainer container,
  Locale locale = const Locale('en'),
  double width = 1280,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [LiveStatisticsStrip()],
          ),
        ),
      ),
    ),
  );
}

/// Builds a [ProviderContainer] with overrides that simulate the root scope
/// the strip normally runs inside (memory, root-scope render, workspace,
/// pane container manager). [setupContainers] is invoked once the container
/// is built so tests can seed per-pane render-stats notifiers.
///
/// The strip is expanded by default here. In production it opens collapsed
/// to its disclosure row, but a test that wants to read a segment wants the
/// segments on screen; the collapsed case has its own tests below.
ProviderContainer _buildContainer({
  required Workspace workspace,
  required PaneContainerManager pcm,
  MemoryStats? memory,
  bool expanded = true,
  bool pollMemory = false,
  void Function(ProviderContainer)? setupContainers,
}) {
  final container = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      if (!pollMemory)
        cruxMemoryPollRequestProvider.overrideWith(_NoPollRequests.new),
      // The shared collector reads the REAL process RSS otherwise, which
      // would drown out the fixture's memory value.
      cruxResidentBytesReaderProvider.overrideWithValue(() => 0),
      memoryStatsProvider.overrideWith(
        () => _FakeMemoryStatsNotifier(memory),
      ),
      workspaceServiceProvider.overrideWithValue(
        _StubWorkspaceService(workspace),
      ),
      paneContainerManagerProvider.overrideWithValue(pcm),
    ],
  );
  pcm.init(container);
  container
      .read(panelLayoutProvider.notifier)
      .setStatisticsStripVisible(visible: expanded);
  if (setupContainers != null) setupContainers(container);
  return container;
}

/// The value rendered beneath the segment captioned [label].
///
/// A segment cell is a Column of caption, then value — so the second Text
/// under the caption's own Column is the reading.
String _valueUnder(WidgetTester tester, String label) {
  final cell = find
      .ancestor(of: find.text(label), matching: find.byType(Column))
      .first;
  final texts = tester
      .widgetList<Text>(find.descendant(of: cell, matching: find.byType(Text)))
      .toList();
  return texts[1].data!;
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  final paneL = PaneId.fromString('00000000-0000-0000-0000-0000000000aa');
  final paneR = PaneId.fromString('00000000-0000-0000-0000-0000000000bb');
  final singlePaneWorkspace = Workspace(
    tabs: const [],
    panes: [WorkspacePane(id: paneL)],
    activePaneId: paneL,
  );
  // Each pane carries a tab so the two-pane layout survives the load-time
  // empty-sibling-pane sanitization in WaveCruxWorkspaceNotifier.build()
  // (a workspace whose panes hold no tabs collapses to a single pane). A
  // genuinely populated split is what exercises the L:/R: pane indicators.
  final tabL = buildWorkspaceTab(
    id: TabId.generate(),
    displayName: 'left.vcd',
    paneId: paneL,
    filePath: '/tmp/left.vcd',
  );
  final tabR = buildWorkspaceTab(
    id: TabId.generate(),
    displayName: 'right.vcd',
    paneId: paneR,
    filePath: '/tmp/right.vcd',
  );
  final splitWorkspace = Workspace(
    tabs: [tabL, tabR],
    panes: [
      WorkspacePane(id: paneL, activeTabId: tabL.id),
      WorkspacePane(id: paneR, activeTabId: tabR.id),
    ],
    activePaneId: paneL,
  );

  group('LiveStatisticsStrip — locale sweep', () {
    for (final locale in [
      const Locale('en'),
      const Locale('zh', 'CN'),
      const Locale('ja'),
      const Locale('ko'),
    ]) {
      testWidgets('renders without exception in $locale', (tester) async {
        final pcm = PaneContainerManager();
        final c = _buildContainer(
          memory: _memory(
            wellenEstimateBytes: 50 * 1024 * 1024,
            loadedSignalCount: 85,
            totalSignalCount: 3200,
            dartProcessRssBytes: 142 * 1024 * 1024,
          ),
          workspace: singlePaneWorkspace,
          pcm: pcm,
        );
        addTearDown(c.dispose);
        addTearDown(pcm.dispose);

        await tester.pumpWidget(_wrap(container: c, locale: locale));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(LiveStatisticsStrip), findsOneWidget);
      });
    }
  });

  group('LiveStatisticsStrip — null/loading state', () {
    testWidgets('renders without exception when both providers are null', (
      tester,
    ) async {
      final pcm = PaneContainerManager();
      final c = _buildContainer(
        workspace: singlePaneWorkspace,
        pcm: pcm,
      );
      addTearDown(c.dispose);
      addTearDown(pcm.dispose);

      await tester.pumpWidget(_wrap(container: c));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('LiveStatisticsStrip — memory display', () {
    testWidgets('displays memory value when memoryStatsProvider has data', (
      tester,
    ) async {
      final pcm = PaneContainerManager();
      final c = _buildContainer(
        memory: _memory(dartProcessRssBytes: 142 * 1024 * 1024),
        workspace: singlePaneWorkspace,
        pcm: pcm,
      );
      addTearDown(c.dispose);
      addTearDown(pcm.dispose);

      await tester.pumpWidget(_wrap(container: c));
      await tester.pump();
      expect(find.textContaining('142 MB'), findsOneWidget);
    });

    testWidgets(
      'displays decompressed signal count in "{loaded} / {total}" format',
      (tester) async {
        final pcm = PaneContainerManager();
        final c = _buildContainer(
          memory: _memory(loadedSignalCount: 85, totalSignalCount: 3200),
          workspace: singlePaneWorkspace,
          pcm: pcm,
        );
        addTearDown(c.dispose);
        addTearDown(pcm.dispose);

        await tester.pumpWidget(_wrap(container: c));
        await tester.pump();
        expect(find.textContaining('85 / 3200'), findsOneWidget);
      },
    );
  });

  group('LiveStatisticsStrip — per-pane render stats', () {
    testWidgets('reads paint time from the active pane container', (
      tester,
    ) async {
      final pcm = PaneContainerManager();
      final c = _buildContainer(
        workspace: splitWorkspace,
        pcm: pcm,
        setupContainers: (root) {
          pcm
              .containerFor(paneL)
              .read(paneRenderStatsProvider.notifier)
              .record(_render(totalPaintTimeUs: 8000));
          pcm
              .containerFor(paneR)
              .read(paneRenderStatsProvider.notifier)
              .record(_render(totalPaintTimeUs: 12000));
        },
      );
      addTearDown(c.dispose);
      addTearDown(pcm.dispose);

      await tester.pumpWidget(_wrap(container: c));
      await tester.pump();
      // Active is paneL — 8.0 ms, under a caption prefixed with "L: " in
      // split-pane mode.
      expect(find.text('L: Paint'), findsOneWidget);
      expect(find.text('8.0 ms'), findsOneWidget);
    });

    testWidgets('swaps paint-time sparkline content when active pane changes', (
      tester,
    ) async {
      final pcm = PaneContainerManager();
      final c = _buildContainer(
        workspace: splitWorkspace,
        pcm: pcm,
        setupContainers: (root) {
          // Seed distinct, multi-sample histories so each pane's buffer is
          // visually distinguishable. [SparklineWidget] only renders when
          // there are ≥ 2 samples.
          pcm.containerFor(paneL).read(paneRenderStatsProvider.notifier)
            ..record(_render(totalPaintTimeUs: 5000))
            ..record(_render(totalPaintTimeUs: 6000))
            ..record(_render(totalPaintTimeUs: 7000));
          pcm.containerFor(paneR).read(paneRenderStatsProvider.notifier)
            ..record(_render(totalPaintTimeUs: 15000))
            ..record(_render(totalPaintTimeUs: 16000))
            ..record(_render(totalPaintTimeUs: 17000));
        },
      );
      addTearDown(c.dispose);
      addTearDown(pcm.dispose);

      await tester.pumpWidget(_wrap(container: c));
      await tester.pump();
      expect(find.text('L: Paint'), findsOneWidget);
      expect(find.text('7.0 ms'), findsOneWidget);

      // Switch active pane → strip swaps to pane R's notifier.
      final notifier = c.wavecruxWorkspace;
      await notifier.setActivePane(paneR);
      await tester.pump();
      expect(find.text('R: Paint'), findsOneWidget);
      expect(find.text('17.0 ms'), findsOneWidget);
      // Pane L's history is preserved in its own notifier — switching back
      // immediately restores the L sparkline data.
      await notifier.setActivePane(paneL);
      await tester.pump();
      expect(find.text('L: Paint'), findsOneWidget);
      expect(find.text('7.0 ms'), findsOneWidget);
      // The workspace notifier schedules a debounced save timer on every
      // mutation; flush it so the widget tree teardown does not see a
      // pending Timer.
      await notifier.flushPendingSave();
    });

    testWidgets('memory and FPS stay continuous across pane focus changes '
        'while paint follows the active pane', (tester) async {
      // Memory and FPS are app-level — memory from the shared RSS collector
      // (falling back to WaveCrux's own reading until the first sample),
      // FPS from the shared frame-timing collector. Neither is a property of
      // a pane, so neither may move when focus does. FPS used to be
      // 1e6/paintMicroseconds of the focused pane, which made it swap here
      // and read a pinned "999" in the app.
      final pcm = PaneContainerManager();
      final c = _buildContainer(
        memory: _memory(dartProcessRssBytes: 222 * 1024 * 1024),
        workspace: splitWorkspace,
        pcm: pcm,
        setupContainers: (root) {
          pcm
              .containerFor(paneL)
              .read(paneRenderStatsProvider.notifier)
              .record(_render(totalPaintTimeUs: 5000));
          pcm
              .containerFor(paneR)
              .read(paneRenderStatsProvider.notifier)
              .record(_render(totalPaintTimeUs: 10000));
        },
      );
      addTearDown(c.dispose);
      addTearDown(pcm.dispose);

      await tester.pumpWidget(_wrap(container: c));
      await tester.pump();
      expect(find.textContaining('222 MB'), findsOneWidget);
      expect(find.text('L: Paint'), findsOneWidget);
      expect(find.text('5.0 ms'), findsWidgets);
      final fpsBefore = _valueUnder(tester, 'FPS');

      final notifier = c.wavecruxWorkspace;
      await notifier.setActivePane(paneR);
      await tester.pump();
      // App-level: unchanged.
      expect(find.textContaining('222 MB'), findsOneWidget);
      expect(_valueUnder(tester, 'FPS'), fpsBefore);
      // Per-pane: followed the focus.
      expect(find.text('R: Paint'), findsOneWidget);
      expect(find.text('10.0 ms'), findsWidgets);
      await notifier.flushPendingSave();
    });

    testWidgets('reports dropped frames as its own segment', (tester) async {
      final pcm = PaneContainerManager();
      final c = _buildContainer(workspace: singlePaneWorkspace, pcm: pcm);
      addTearDown(c.dispose);
      addTearDown(pcm.dispose);

      await tester.pumpWidget(_wrap(container: c));
      await tester.pump();
      // Present in its suite-standard position, between FPS and the
      // product's own readings. Average FPS hides stutter; this does not.
      expect(find.text('Dropped'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Dropped')).dx,
        greaterThan(tester.getTopLeft(find.text('FPS')).dx),
      );
      expect(
        tester.getTopLeft(find.text('Dropped')).dx,
        lessThan(tester.getTopLeft(find.text('Paint')).dx),
      );
    });

    // Explicit app-level invariance: the decompressed-signal
    // count comes from the root-scope `memoryStatsProvider` (app-wide
    // aggregate, not per-pane). Switching the active pane must leave the
    // "loaded / total" segment unchanged. Paired with the FPS/Paint swap
    // assertions above, this pins both contracts:
    //   - per-pane segments (paint time, render time) follow active pane
    //   - app-level segments (memory, decompressed signal aggregate) do not
    testWidgets(
      'decompressed signal aggregate stays constant across pane focus changes',
      (tester) async {
        final pcm = PaneContainerManager();
        final c = _buildContainer(
          memory: _memory(loadedSignalCount: 85, totalSignalCount: 3200),
          workspace: splitWorkspace,
          pcm: pcm,
          setupContainers: (root) {
            pcm
                .containerFor(paneL)
                .read(paneRenderStatsProvider.notifier)
                .record(_render(totalPaintTimeUs: 5000));
            pcm
                .containerFor(paneR)
                .read(paneRenderStatsProvider.notifier)
                .record(_render(totalPaintTimeUs: 10000));
          },
        );
        addTearDown(c.dispose);
        addTearDown(pcm.dispose);

        await tester.pumpWidget(_wrap(container: c));
        await tester.pump();
        expect(find.textContaining('85 / 3200'), findsOneWidget);

        final notifier = c.wavecruxWorkspace;
        await notifier.setActivePane(paneR);
        await tester.pump();
        // Decompressed signal aggregate is rooted in memoryStatsProvider, not
        // a per-pane notifier — pane focus changes must leave it intact.
        expect(
          find.textContaining('85 / 3200'),
          findsOneWidget,
          reason:
              'decompressed-signal-count is app-level and must not swap with focus',
        );
        await notifier.flushPendingSave();
      },
    );

    testWidgets('omits pane indicator when only one pane exists', (
      tester,
    ) async {
      final pcm = PaneContainerManager();
      final c = _buildContainer(
        workspace: singlePaneWorkspace,
        pcm: pcm,
        setupContainers: (root) {
          pcm
              .containerFor(paneL)
              .read(paneRenderStatsProvider.notifier)
              .record(_render(totalPaintTimeUs: 4200));
        },
      );
      addTearDown(c.dispose);
      addTearDown(pcm.dispose);

      await tester.pumpWidget(_wrap(container: c));
      await tester.pump();
      // Bare "Paint" caption — no "L:" prefix without a second pane.
      expect(find.text('Paint'), findsOneWidget);
      expect(find.text('4.2 ms'), findsOneWidget);
      expect(find.textContaining('L: Paint'), findsNothing);
      expect(find.textContaining('R: Paint'), findsNothing);
    });
  });

  group('LiveStatisticsStrip — sparkline', () {
    testWidgets('contains a CruxSparkline once there is a trend to draw', (
      tester,
    ) async {
      final pcm = PaneContainerManager();
      final c = _buildContainer(
        workspace: singlePaneWorkspace,
        pcm: pcm,
        setupContainers: (root) {
          // Two samples minimum: the shared cell draws no sparkline for a
          // single point, since one reading is not a trend.
          pcm.containerFor(paneL).read(paneRenderStatsProvider.notifier)
            ..record(_render(totalPaintTimeUs: 4000))
            ..record(_render(totalPaintTimeUs: 5000));
        },
      );
      addTearDown(c.dispose);
      addTearDown(pcm.dispose);

      await tester.pumpWidget(_wrap(container: c));
      await tester.pump();
      expect(find.byType(CruxSparkline), findsOneWidget);
    });
  });

  group('LiveStatisticsStrip — height', () {
    testWidgets('strip has the expected height', (tester) async {
      final pcm = PaneContainerManager();
      final c = _buildContainer(
        workspace: singlePaneWorkspace,
        pcm: pcm,
      );
      addTearDown(c.dispose);
      addTearDown(pcm.dispose);

      await tester.pumpWidget(_wrap(container: c));
      await tester.pump();

      final size = tester.getSize(find.byType(LiveStatisticsStrip));
      expect(
        size.height,
        kCruxStatsStripHeight + kCruxStatsStripCollapsedHeight,
        reason: 'expanded strip is the segment area plus its disclosure row',
      );
    });

    testWidgets('collapses to just the disclosure row', (tester) async {
      final pcm = PaneContainerManager();
      final c = _buildContainer(
        workspace: singlePaneWorkspace,
        pcm: pcm,
        expanded: false,
      );
      addTearDown(c.dispose);
      addTearDown(pcm.dispose);

      await tester.pumpWidget(_wrap(container: c));
      await tester.pump();

      final size = tester.getSize(find.byType(LiveStatisticsStrip));
      expect(size.height, kCruxStatsStripCollapsedHeight);
      // The row itself stays — that is what makes the feature discoverable.
      expect(find.text('Stats'), findsOneWidget);
      expect(find.text('Memory'), findsNothing);
    });

    testWidgets('expected height is in the documented 80-120 px band', (
      tester,
    ) async {
      expect(kCruxStatsStripHeight, greaterThanOrEqualTo(80));
      expect(kCruxStatsStripHeight, lessThanOrEqualTo(120));
    });
  });

  group('LiveStatisticsStrip — disclosure', () {
    testWidgets("tapping the row flips this tab's persisted strip state", (
      tester,
    ) async {
      final pcm = PaneContainerManager();
      final c = _buildContainer(
        workspace: singlePaneWorkspace,
        pcm: pcm,
        expanded: false,
      );
      addTearDown(c.dispose);
      addTearDown(pcm.dispose);

      await tester.pumpWidget(_wrap(container: c));
      await tester.pump();

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();
      // The strip drives WaveCrux's own per-tab flag, not the shared
      // provider — that is what survives a restart via the session sidecar.
      expect(c.read(panelLayoutProvider).statisticsStripVisible, isTrue);
      expect(c.read(cruxStatsStripExpandedProvider), isFalse);
      expect(find.text('Memory'), findsOneWidget);

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();
      expect(c.read(panelLayoutProvider).statisticsStripVisible, isFalse);
      expect(find.text('Memory'), findsNothing);
    });
  });

  group('LiveStatisticsStrip — memory poll demand', () {
    testWidgets('holds a poll tag while expanded and gives it back on '
        'collapse', (tester) async {
      // The shared RSS collector samples only while something says it is
      // being watched, and it takes that cue from the shared expanded
      // provider — which WaveCrux does not use, because its disclosure state
      // is per tab and persisted. Without this the Memory segment would sit
      // on a single stale reading with a flat sparkline forever.
      // Driven through the provider rather than by tapping the row: a tap
      // arms the disclosure Tooltip's own timer, which outlives the pumps
      // and would be reported here as the leak this test watches for.
      final pcm = PaneContainerManager();
      final c = _buildContainer(
        workspace: singlePaneWorkspace,
        pcm: pcm,
        expanded: false,
        pollMemory: true,
      );
      addTearDown(c.dispose);
      addTearDown(pcm.dispose);
      final panels = c.read(panelLayoutProvider.notifier);

      await tester.pumpWidget(_wrap(container: c));
      await tester.pumpAndSettle();
      expect(c.read(cruxMemoryPollRequestProvider), isEmpty);

      panels.setStatisticsStripVisible(visible: true);
      await tester.pumpAndSettle();
      expect(c.read(cruxMemoryPollRequestProvider), isNotEmpty);

      // Collapsing releases it — otherwise the two-second poll would run
      // for the rest of the session behind a 24 px caption.
      panels.setStatisticsStripVisible(visible: false);
      await tester.pumpAndSettle();
      expect(c.read(cruxMemoryPollRequestProvider), isEmpty);

      // And so does going away entirely (tab closed, window torn down).
      panels.setStatisticsStripVisible(visible: true);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(c.read(cruxMemoryPollRequestProvider), isEmpty);
    });
  });

  group('LiveStatisticsStrip — title', () {
    testWidgets('labels the strip for screen readers', (tester) async {
      final pcm = PaneContainerManager();
      final c = _buildContainer(
        workspace: singlePaneWorkspace,
        pcm: pcm,
      );
      addTearDown(c.dispose);
      addTearDown(pcm.dispose);

      await tester.pumpWidget(_wrap(container: c));
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Statistics',
        ),
        findsOneWidget,
        reason:
            'the visible caption is now the shared "Stats" disclosure row; '
            'the fuller name survives as the accessibility label',
      );
    });
  });
}
