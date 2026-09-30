// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/file_stats.dart';
import 'package:wavecrux/domain/models/signal_integrity_report.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/domain/models/wavecrux_tab.dart';
import 'package:wavecrux/features/diagnostics/providers/dev_tools_provider.dart';
import 'package:wavecrux/features/diagnostics/providers/file_stats_provider.dart';
import 'package:wavecrux/features/diagnostics/providers/signal_integrity_provider.dart';
import 'package:wavecrux/services/diagnostics/tab_diagnostics_report_service.dart';

// ── seeded fake notifiers ─────────────────────────────────────────────────────
//
// generate() reads three per-tab providers directly (no TabContainerManager
// scoping needed for this service itself — the drawer supplies an
// already-tab-scoped ref); each is overridden with a seeded value so both the
// populated and unpopulated branches of the report are exercised.

class _SeededIntegrityNotifier extends SignalIntegrityNotifier {
  _SeededIntegrityNotifier(this._value);
  final SignalIntegrityReport? _value;
  @override
  AsyncValue<SignalIntegrityReport?> build() => AsyncData(_value);
}

class _SeededDevToolsNotifier extends DevToolsNotifier {
  _SeededDevToolsNotifier(this._value);
  final DevToolsState _value;
  @override
  DevToolsState build() => _value;
}

// ── shared fixtures ───────────────────────────────────────────────────────────

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
  glitchSignals: <String, int>{'top.glitchy': 3},
  detectedClocks: [
    ClockInfo(
      signalRef: 'C',
      signalPath: 'top.clk',
      periodTicks: 10,
      dutyCyclePercent: 50,
      estimatedFrequency: '100 MHz',
    ),
  ],
  stuckAtResetPaths: ['top.rst_n'],
  analysisTimeMs: 50,
  signalsAnalyzed: 320,
);

const _benchmark = BenchmarkResult(
  fileSizeBytes: 10 * 1024 * 1024,
  signalCount: 500,
  parseMs: 200,
);

void main() {
  const service = TabDiagnosticsReportService();
  final fixedNow = DateTime.utc(2026, 4, 23, 14, 30);

  // Runs generate() with a WidgetRef resolved against a ProviderScope whose
  // three per-tab providers are seeded with the given fixture values,
  // returning the generated report string.
  Future<String> buildReport(
    WidgetTester tester, {
    required TabId tabId,
    WavecruxTab? tab,
    FileStats? fileStats,
    SignalIntegrityReport? integrity,
    DevToolsState devTools = const DevToolsState(),
  }) async {
    late String report;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileStatsProvider.overrideWithValue(fileStats),
          signalIntegrityProvider.overrideWith(
            () => _SeededIntegrityNotifier(integrity),
          ),
          devToolsProvider.overrideWith(
            () => _SeededDevToolsNotifier(devTools),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            report = service.generate(
              ref: ref,
              tabId: tabId,
              tab: tab,
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
    return report;
  }

  group('TabDiagnosticsReportService — header & unpopulated sections', () {
    testWidgets('writes the header, tab id, and closing marker', (
      tester,
    ) async {
      final tabId = TabId.fromString('tab-1');
      final report = await buildReport(tester, tabId: tabId);

      expect(report, contains('=== WaveCrux Tab Diagnostics Report ==='));
      expect(report, contains('Generated: 2026-04-23T14:30:00.000Z'));
      expect(report, contains('Tab Id: ${tabId.value}'));
      expect(report, contains('--- File Info ---'));
      expect(report, contains('--- Signal Health ---'));
      expect(report, contains('--- Benchmark This File ---'));
      expect(report.trimRight(), endsWith('==='));
    });

    testWidgets('no tab supplied prints (unknown) name and no file', (
      tester,
    ) async {
      final report = await buildReport(
        tester,
        tabId: TabId.fromString('tab-1'),
      );

      expect(report, contains('Tab Name: (unknown)'));
      expect(report, contains('File: (no file loaded)'));
      expect(report, contains('(no file loaded in this tab)'));
    });

    testWidgets(
      'tab supplied but no analysis run yet: unpopulated placeholders',
      (tester) async {
        final tabId = TabId.fromString('tab-2');
        final tab = WavecruxTab(
          id: tabId,
          displayName: 'Untitled',
        );
        final report = await buildReport(tester, tabId: tabId, tab: tab);

        expect(report, contains('Tab Name: Untitled'));
        expect(report, contains('(no file loaded in this tab)'));
        expect(report, contains('(analysis not run for this tab)'));
        expect(report, contains('(benchmark not run for this tab)'));
      },
    );
  });

  group('TabDiagnosticsReportService — populated sections', () {
    testWidgets('writes file stats when a file is loaded', (tester) async {
      final tabId = TabId.fromString('tab-populated');
      final tab = WavecruxTab(
        id: tabId,
        displayName: 'dump.vcd',
        filePath: '/sim/dump.vcd',
      );
      final report = await buildReport(
        tester,
        tabId: tabId,
        tab: tab,
        fileStats: _fileStats,
      );

      expect(report, contains('Tab Name: dump.vcd'));
      expect(report, contains('File: /sim/dump.vcd'));
      expect(report, contains('Path: /sim/dump.vcd'));
      expect(report, contains('Size: ${5 * 1024 * 1024} bytes'));
      expect(report, contains('Format: VCD'));
      expect(report, contains('Parse Time: 321.0 ms'));
      expect(report, contains('Signals: 320 (280 scalar, 38 vector, 2 real)'));
      expect(
        report,
        contains('Directions: 10 in, 20 out, 1 inout, 289 unknown'),
      );
      expect(report, contains('Transitions: 1400000'));
      expect(report, contains('Scope Count: 12'));
      expect(report, contains('Hierarchy Depth: 5'));
      expect(report, contains('Timescale: 1 ns'));
    });

    testWidgets('writes signal health when analysis has run', (tester) async {
      final tabId = TabId.fromString('tab-analyzed');
      final report = await buildReport(
        tester,
        tabId: tabId,
        integrity: _integrity,
      );

      expect(report, contains('Signals Analyzed: 320'));
      expect(report, contains('Constant Signals: 2'));
      expect(report, contains('X/Z-Only Signals: 1'));
      expect(report, contains('Glitch Points: 1'));
      expect(report, contains('Detected Clocks: 1'));
      expect(report, contains('Stuck at Reset: 1'));
    });

    testWidgets('writes benchmark results when a run has completed', (
      tester,
    ) async {
      final tabId = TabId.fromString('tab-benched');
      final report = await buildReport(
        tester,
        tabId: tabId,
        devTools: const DevToolsState(benchmarkResult: _benchmark),
      );

      expect(report, contains('File size: ${10 * 1024 * 1024} bytes'));
      expect(report, contains('Signals: 500'));
      expect(report, contains('Parse time: 200 ms'));
      expect(
        report,
        contains(
          'Throughput: ${_benchmark.throughputMbps.toStringAsFixed(1)} MB/s',
        ),
      );
    });
  });
}
