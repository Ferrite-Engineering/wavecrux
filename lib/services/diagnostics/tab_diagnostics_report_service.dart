// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/file_stats.dart';
import 'package:wavecrux/domain/models/signal_integrity_report.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/domain/models/wavecrux_tab.dart';
import 'package:wavecrux/features/diagnostics/providers/dev_tools_provider.dart';
import 'package:wavecrux/features/diagnostics/providers/file_stats_provider.dart';
import 'package:wavecrux/features/diagnostics/providers/signal_integrity_provider.dart';

/// Generates the structured plain-text "Tab Diagnostics Report" exported from
/// the Tab Diagnostics drawer.
///
/// The report identifies the source tab, summarizes file stats, signal
/// integrity, and (when run) the "Benchmark This File" results for that tab.
/// Distinct from the App Diagnostics "Copy Full Diagnostics Report" — this
/// one is scoped to a single tab.
class TabDiagnosticsReportService {
  const TabDiagnosticsReportService();

  /// Build the report string.
  ///
  /// Pulls all data from the supplied [ref], using the per-tab providers that
  /// the drawer itself watches. [tab] is supplied separately so the report
  /// always carries the tab's display metadata (file name, file path) even
  /// when the underlying providers transiently report null. Pass [now] to
  /// stamp a deterministic timestamp in tests.
  String generate({
    required WidgetRef ref,
    required TabId tabId,
    WavecruxTab? tab,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now().toUtc()).toIso8601String();
    final fileStats = ref.read(fileStatsProvider);
    final integrityReport = ref.read(signalIntegrityProvider).value;
    final benchmark = ref.read(devToolsProvider).benchmarkResult;

    final buf = StringBuffer()
      ..writeln('=== WaveCrux Tab Diagnostics Report ===')
      ..writeln('Generated: $timestamp')
      ..writeln('Tab Id: ${tabId.value}')
      ..writeln('Tab Name: ${tab?.displayName ?? '(unknown)'}')
      ..writeln('File: ${tab?.filePath ?? '(no file loaded)'}');

    _writeFileInfo(buf, fileStats);
    _writeSignalHealth(buf, integrityReport);
    _writeBenchmark(buf, benchmark);

    buf.write('===');
    return buf.toString();
  }

  void _writeFileInfo(StringBuffer buf, FileStats? stats) {
    buf
      ..writeln()
      ..writeln('--- File Info ---');
    if (stats == null) {
      buf.writeln('(no file loaded in this tab)');
      return;
    }
    buf
      ..writeln('Path: ${stats.filePath}')
      ..writeln('Size: ${stats.fileSizeBytes} bytes')
      ..writeln('Format: ${stats.formatName}')
      ..writeln('Parse Time: ${stats.parseTimeMs.toStringAsFixed(1)} ms')
      ..writeln(
        'Signals: ${stats.totalSignals} '
        '(${stats.scalarCount} scalar, '
        '${stats.vectorCount} vector, '
        '${stats.realCount} real)',
      )
      ..writeln(
        'Directions: ${stats.inputCount} in, '
        '${stats.outputCount} out, '
        '${stats.inoutCount} inout, '
        '${stats.unknownDirectionCount} unknown',
      )
      ..writeln('Transitions: ${stats.totalTransitions}')
      ..writeln('Scope Count: ${stats.scopeCount}')
      ..writeln('Hierarchy Depth: ${stats.hierarchyDepth}');
    if (stats.timescaleDisplay != null) {
      buf.writeln('Timescale: ${stats.timescaleDisplay}');
    }
  }

  void _writeSignalHealth(StringBuffer buf, SignalIntegrityReport? report) {
    buf
      ..writeln()
      ..writeln('--- Signal Health ---');
    if (report == null) {
      buf.writeln('(analysis not run for this tab)');
      return;
    }
    buf
      ..writeln('Signals Analyzed: ${report.signalsAnalyzed}')
      ..writeln('Constant Signals: ${report.constantSignalPaths.length}')
      ..writeln('X/Z-Only Signals: ${report.xzOnlySignalPaths.length}')
      ..writeln('Glitch Points: ${report.glitchSignals.length}')
      ..writeln('Detected Clocks: ${report.detectedClocks.length}')
      ..writeln('Stuck at Reset: ${report.stuckAtResetPaths.length}');
  }

  void _writeBenchmark(StringBuffer buf, BenchmarkResult? result) {
    buf
      ..writeln()
      ..writeln('--- Benchmark This File ---');
    if (result == null) {
      buf.writeln('(benchmark not run for this tab)');
      return;
    }
    buf
      ..writeln('File size: ${result.fileSizeBytes} bytes')
      ..writeln('Signals: ${result.signalCount}')
      ..writeln('Parse time: ${result.parseMs} ms')
      ..writeln(
        'Throughput: ${result.throughputMbps.toStringAsFixed(1)} MB/s',
      );
  }
}
