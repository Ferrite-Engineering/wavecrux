// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/app_info/application_build_info.dart';
import 'package:wavecrux/core/app_info/application_build_info_provider.dart';
import 'package:wavecrux/domain/models/file_stats.dart';
import 'package:wavecrux/domain/models/memory_stats.dart';
import 'package:wavecrux/domain/models/pane_id.dart';
import 'package:wavecrux/domain/models/pane_render_stats.dart';
import 'package:wavecrux/domain/models/render_pipeline_stats.dart';
import 'package:wavecrux/domain/models/signal_integrity_report.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/domain/models/wavecrux_tab.dart';
import 'package:wavecrux/features/diagnostics/providers/file_stats_provider.dart';
import 'package:wavecrux/features/diagnostics/providers/memory_stats_provider.dart';
import 'package:wavecrux/features/diagnostics/providers/signal_integrity_provider.dart';
import 'package:wavecrux/features/panes/providers/active_pane_id_provider.dart';
import 'package:wavecrux/features/panes/providers/pane_render_stats_provider.dart';
import 'package:wavecrux/services/diagnostics/app_diagnostics_report_service.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

// ── seeded fake notifiers ─────────────────────────────────────────────────────
//
// The report aggregates per-tab providers (memory, file stats, signal
// integrity) and active-pane render stats. Each is overridden inside the
// relevant container with a seeded value so the populated branches of the
// report are exercised without a real waveform load.

class _SeededMemoryNotifier extends MemoryStatsNotifier {
  _SeededMemoryNotifier(this._value);
  final MemoryStats? _value;
  @override
  MemoryStats? build() => _value;
}

class _SeededIntegrityNotifier extends SignalIntegrityNotifier {
  _SeededIntegrityNotifier(this._value);
  final SignalIntegrityReport? _value;
  @override
  AsyncValue<SignalIntegrityReport?> build() => AsyncData(_value);
}

class _SeededPaneRenderStatsNotifier extends PaneRenderStatsNotifier {
  _SeededPaneRenderStatsNotifier(this._value);
  final PaneRenderStats _value;
  @override
  PaneRenderStats build() => _value;
}

// ── shared fixtures ───────────────────────────────────────────────────────────

const _memory = MemoryStats(
  wellenEstimateBytes: 12 * 1024 * 1024,
  loadedSignalCount: 40,
  totalSignalCount: 320,
  dartProcessRssBytes: 256 * 1024 * 1024,
);

const _fileStats = FileStats(
  filePath: '/sim/dump.vcd',
  fileSizeBytes: 5 * 1024 * 1024,
  formatName: 'VCD',
  parseTimeMs: 321,
  totalSignals: 320,
  scalarCount: 280,
  vectorCount: 38,
  realCount: 2,
  inputCount: 10,
  outputCount: 20,
  inoutCount: 1,
  unknownDirectionCount: 289,
  totalTransitions: 1400000,
  hierarchyDepth: 5,
  scopeCount: 12,
  startTime: 0,
  endTime: 100000,
  timescaleDisplay: '1 ns',
);

const _integrity = SignalIntegrityReport(
  constantSignalPaths: ['top.const_a', 'top.const_b'],
  xzOnlySignalPaths: ['top.unconnected'],
  glitchSignals: <String, int>{},
  detectedClocks: [
    ClockInfo(
      signalRef: 'C',
      signalPath: 'top.clk',
      periodTicks: 10,
      dutyCyclePercent: 50,
      estimatedFrequency: '100 MHz',
    ),
  ],
  stuckAtResetPaths: [],
  analysisTimeMs: 50,
  signalsAnalyzed: 320,
);

const _renderStats = RenderPipelineStats(
  visibleSignalRows: 42,
  visibleTransitions: 18400,
  lineSegmentsDrawn: 3600,
  layoutTimeUs: 200,
  scalarPaintTimeUs: 3000,
  vectorPaintTimeUs: 1500,
  analogPaintTimeUs: 500,
  cursorPaintTimeUs: 100,
  transactionPaintTimeUs: 0,
  totalPaintTimeUs: 8200,
  canvasWidth: 1200,
  canvasHeight: 800,
);

void main() {
  const service = AppDiagnosticsReportService();
  final fixedNow = DateTime.utc(2026, 4, 23, 14, 30);

  // Runs [body] with a WidgetRef resolved against a ProviderScope whose root
  // overrides supply the active pane + pane-container manager, returning the
  // generated report string.
  Future<String> buildReport(
    WidgetTester tester, {
    required List<WavecruxTab> tabs,
    required TabId activeTabId,
    required TabContainerManager tcm,
    WavecruxTab? activeTab,
    PaneContainerManager? pcm,
    PaneId? activePane,
    List<double>? frameTimes,
    int overruns = 0,
    ApplicationBuildInfo? buildInfo,
  }) async {
    late String report;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (buildInfo != null)
            applicationBuildInfoProvider.overrideWithValue(
              AsyncData(buildInfo),
            ),
          if (activePane != null)
            activePaneIdProvider.overrideWithValue(activePane),
          if (pcm != null) paneContainerManagerProvider.overrideWithValue(pcm),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            report = service.generate(
              read: ref.read,
              tabs: tabs,
              activeTabId: activeTabId,
              activeTab: activeTab,
              tabContainerManager: tcm,
              recentFrameTimesMs: frameTimes,
              frameBudgetOverruns: overruns,
              lastFrameTimestamp: frameTimes == null
                  ? null
                  : DateTime.utc(2026, 4, 23, 14, 31),
              now: fixedNow,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    // Reading providers via container.read enqueues zero-duration Riverpod
    // dispose-scheduler timers; pump so they fire before the test ends.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    return report;
  }

  group('AppDiagnosticsReportService — header & static sections', () {
    testWidgets("states the running build's version, not a constant", (
      tester,
    ) async {
      final tcm = TabContainerManager();
      final root = ProviderContainer(
        overrides: [tabContainerManagerProvider.overrideWithValue(tcm)],
      );
      tcm.init(root);
      addTearDown(() {
        tcm.dispose();
        root.dispose();
      });

      final report = await buildReport(
        tester,
        tabs: const [],
        activeTabId: TabId.fromString('tab-1'),
        tcm: tcm,
        buildInfo: const ApplicationBuildInfo(
          version: '9.8.7',
          buildNumber: '42',
          gitSha: 'abc1234',
          os: 'Linux',
          architecture: 'x64',
          flutterVersion: '3.0.0',
          dartVersion: '3.0.0',
        ),
      );

      // The report used to print a hardcoded 0.1.0 whatever the build was,
      // and it is what users paste into bug reports.
      expect(report, contains('App Version: 9.8.7'));
    });

    testWidgets('always writes the header, platform, and closing marker', (
      tester,
    ) async {
      final tcm = TabContainerManager();
      final root = ProviderContainer(
        overrides: [tabContainerManagerProvider.overrideWithValue(tcm)],
      );
      tcm.init(root);
      addTearDown(() {
        tcm.dispose();
        root.dispose();
      });

      final report = await buildReport(
        tester,
        tabs: const [],
        activeTabId: TabId.fromString('tab-1'),
        tcm: tcm,
      );

      expect(report, contains('=== WaveCrux Full Diagnostics Report ==='));
      expect(report, contains('Generated: 2026-04-23T14:30:00.000Z'));
      expect(report, contains('App Version:'));
      expect(report, contains('--- Platform ---'));
      expect(report, contains('--- App Memory ---'));
      expect(report, contains('--- Frame Stats ---'));
      expect(report, contains('--- Per-Tab Breakdown ---'));
      expect(report.trimRight(), endsWith('==='));
    });

    testWidgets('empty tab list reports the (no tabs) breakdown', (
      tester,
    ) async {
      final tcm = TabContainerManager();
      final root = ProviderContainer(
        overrides: [tabContainerManagerProvider.overrideWithValue(tcm)],
      );
      tcm.init(root);
      addTearDown(() {
        tcm.dispose();
        root.dispose();
      });

      final report = await buildReport(
        tester,
        tabs: const [],
        activeTabId: TabId.fromString('tab-1'),
        tcm: tcm,
      );
      expect(report, contains('(no tabs are loaded)'));
      expect(report, contains('Active Tab Name: (unknown)'));
    });

    testWidgets('no active pane prints the (no active pane) line', (
      tester,
    ) async {
      final tcm = TabContainerManager();
      final root = ProviderContainer(
        overrides: [tabContainerManagerProvider.overrideWithValue(tcm)],
      );
      tcm.init(root);
      addTearDown(() {
        tcm.dispose();
        root.dispose();
      });

      // No paneContainerManager / activePane override: the report's
      // active-pane section gracefully degrades.
      final report = await buildReport(
        tester,
        tabs: const [],
        activeTabId: TabId.fromString('tab-1'),
        tcm: tcm,
      );
      expect(report, contains('--- Active Pane Render Stats ---'));
      // activePaneIdProvider falls back to PaneId.primary, but with no pane
      // container manager wired the report prints the unavailable line.
      expect(report, contains('pane container manager unavailable'));
    });
  });

  group('AppDiagnosticsReportService — frame stats', () {
    testWidgets('no frames recorded prints the placeholder', (tester) async {
      final tcm = TabContainerManager();
      final root = ProviderContainer(
        overrides: [tabContainerManagerProvider.overrideWithValue(tcm)],
      );
      tcm.init(root);
      addTearDown(() {
        tcm.dispose();
        root.dispose();
      });

      final report = await buildReport(
        tester,
        tabs: const [],
        activeTabId: TabId.fromString('t'),
        tcm: tcm,
      );
      expect(report, contains('(no frames recorded yet)'));
      expect(report, contains('Frame budget overruns: 0'));
    });

    testWidgets('populated frame times compute FPS / avg / worst', (
      tester,
    ) async {
      final tcm = TabContainerManager();
      final root = ProviderContainer(
        overrides: [tabContainerManagerProvider.overrideWithValue(tcm)],
      );
      tcm.init(root);
      addTearDown(() {
        tcm.dispose();
        root.dispose();
      });

      final report = await buildReport(
        tester,
        tabs: const [],
        activeTabId: TabId.fromString('t'),
        tcm: tcm,
        frameTimes: const [10, 20, 30],
        overruns: 2,
      );
      expect(report, contains('FPS:'));
      expect(report, contains('ms avg'));
      expect(report, contains('ms worst'));
      expect(report, contains('Frame budget overruns: 2'));
      expect(report, contains('Last frame: 2026-04-23T14:31:00.000Z'));
    });
  });

  group('AppDiagnosticsReportService — populated per-tab breakdown', () {
    testWidgets('writes file stats, memory, and signal integrity per tab', (
      tester,
    ) async {
      final tabId = TabId.fromString('tab-populated');
      final tab = WavecruxTab(
        id: tabId,
        displayName: 'dump.vcd',
        filePath: '/sim/dump.vcd',
      );

      // Seed the per-tab providers with populated snapshots.
      final tcm = TabContainerManager(
        extraTabOverrides: [
          memoryStatsProvider.overrideWith(
            () => _SeededMemoryNotifier(_memory),
          ),
          fileStatsProvider.overrideWithValue(_fileStats),
          signalIntegrityProvider.overrideWith(
            () => _SeededIntegrityNotifier(_integrity),
          ),
        ],
      );
      final root = ProviderContainer(
        overrides: [tabContainerManagerProvider.overrideWithValue(tcm)],
      );
      tcm.init(root);
      addTearDown(() {
        tcm.dispose();
        root.dispose();
      });

      final report = await buildReport(
        tester,
        tabs: [tab],
        activeTabId: tabId,
        activeTab: tab,
        tcm: tcm,
      );

      // App-memory aggregate rolls up the per-tab memory stats.
      expect(report, contains('Process RSS:'));
      expect(report, contains('Decompressed Signals: 40 / 320'));
      // Per-tab section.
      expect(report, contains('* Tab: dump.vcd'));
      expect(report, contains('File: /sim/dump.vcd'));
      expect(report, contains('Format: VCD'));
      expect(report, contains('Parse Time: 321.0 ms'));
      expect(report, contains('Signals: 320 (280 scalar, 38 vector, 2 real)'));
      expect(report, contains('Timescale: 1 ns'));
      expect(report, contains('Wellen DB:'));
      expect(report, contains('Signals Analyzed: 320'));
      expect(report, contains('Constant: 2'));
      expect(report, contains('X/Z-Only: 1'));
      expect(report, contains('Detected Clocks: 1'));
      expect(report, contains('Active Tab Name: dump.vcd'));
    });

    testWidgets('tab with no file loaded prints the (no file loaded) line', (
      tester,
    ) async {
      final tabId = TabId.fromString('tab-empty');
      final tab = WavecruxTab(
        id: tabId,
        displayName: 'Untitled',
      );

      // fileStats null, memory/integrity null → unpopulated branches.
      // Override memory with a seeded (null) notifier so the real notifier's
      // periodic polling timer never starts under the widget tester.
      final tcm = TabContainerManager(
        extraTabOverrides: [
          fileStatsProvider.overrideWithValue(null),
          memoryStatsProvider.overrideWith(() => _SeededMemoryNotifier(null)),
          signalIntegrityProvider.overrideWith(
            () => _SeededIntegrityNotifier(null),
          ),
        ],
      );
      final root = ProviderContainer(
        overrides: [tabContainerManagerProvider.overrideWithValue(tcm)],
      );
      tcm.init(root);
      addTearDown(() {
        tcm.dispose();
        root.dispose();
      });

      final report = await buildReport(
        tester,
        tabs: [tab],
        activeTabId: tabId,
        activeTab: tab,
        tcm: tcm,
      );
      expect(report, contains('* Tab: Untitled'));
      expect(report, contains('(no file loaded)'));
    });
  });

  group('AppDiagnosticsReportService — active pane render stats', () {
    testWidgets('populated pane render stats are written', (tester) async {
      const pane = PaneId.primary;
      final tcm = TabContainerManager();

      // Seed the pane's render-stats notifier with a latest frame.
      final pcm = PaneContainerManager(
        extraPaneOverrides: [
          paneRenderStatsProvider.overrideWith(
            () => _SeededPaneRenderStatsNotifier(
              const PaneRenderStats(latest: _renderStats),
            ),
          ),
        ],
      );
      final root = ProviderContainer(
        overrides: [
          tabContainerManagerProvider.overrideWithValue(tcm),
          paneContainerManagerProvider.overrideWithValue(pcm),
          activePaneIdProvider.overrideWithValue(pane),
        ],
      );
      tcm.init(root);
      pcm.init(root);
      addTearDown(() {
        pcm.dispose();
        tcm.dispose();
        root.dispose();
      });

      final report = await buildReport(
        tester,
        tabs: const [],
        activeTabId: TabId.fromString('t'),
        tcm: tcm,
        pcm: pcm,
        activePane: pane,
      );
      expect(report, contains('Pane Id: ${pane.value}'));
      expect(report, contains('Canvas: 1200×800 px'));
      expect(report, contains('Visible signals: 42'));
      expect(report, contains('Visible transitions: 18400'));
      expect(report, contains('Line segments: 3600'));
      expect(report, contains('Total paint:'));
      expect(report, contains('Paint breakdown:'));
    });

    testWidgets('pane with no painted frame prints the placeholder', (
      tester,
    ) async {
      const pane = PaneId.primary;
      final tcm = TabContainerManager();
      // Default (unseeded) pane render stats: latest == null.
      final pcm = PaneContainerManager();
      final root = ProviderContainer(
        overrides: [
          tabContainerManagerProvider.overrideWithValue(tcm),
          paneContainerManagerProvider.overrideWithValue(pcm),
          activePaneIdProvider.overrideWithValue(pane),
        ],
      );
      tcm.init(root);
      pcm.init(root);
      addTearDown(() {
        pcm.dispose();
        tcm.dispose();
        root.dispose();
      });

      final report = await buildReport(
        tester,
        tabs: const [],
        activeTabId: TabId.fromString('t'),
        tcm: tcm,
        pcm: pcm,
        activePane: pane,
      );
      expect(report, contains('(no frames painted in this pane yet)'));
    });
  });
}
