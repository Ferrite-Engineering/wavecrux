// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:wavecrux/core/app_info/application_build_info_provider.dart';
import 'package:wavecrux/core/utils/byte_format.dart';
import 'package:wavecrux/domain/models/pane_id.dart';
import 'package:wavecrux/domain/models/platform_info.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/domain/models/wavecrux_tab.dart';
import 'package:wavecrux/features/diagnostics/providers/file_stats_provider.dart';
import 'package:wavecrux/features/diagnostics/providers/memory_stats_provider.dart';
import 'package:wavecrux/features/diagnostics/providers/signal_integrity_provider.dart';
import 'package:wavecrux/features/panes/providers/active_pane_id_provider.dart';
import 'package:wavecrux/features/panes/providers/pane_render_stats_provider.dart';
import 'package:wavecrux/services/diagnostics/platform_info_service.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

/// Generates the structured plain-text "Full Diagnostics Report" exported from
/// the App Diagnostics dialog.
///
/// Distinct from the per-tab [TabDiagnosticsReportService]: this one
/// aggregates **app-level** memory and frame stats, the **active pane's**
/// render-pipeline stats, and a **per-tab** breakdown of file info, signal
/// health, and decompressed signal counts. The output is designed to drop
/// into a GitHub issue template intact.
class AppDiagnosticsReportService {
  const AppDiagnosticsReportService();

  /// Build the report string.
  ///
  /// [read] supplies a Riverpod read function whose nearest scope contains the
  /// app-level providers — a `WidgetRef.read` tear-off from a widget, or a
  /// provider `Ref.read` tear-off from a provider body (both share the
  /// `T Function<T>(ProviderListenable<T>)` shape). This lets the beta issue
  /// reporter build the same report from its `cruxIssueDiagnosticsReportProvider`
  /// override, where only a provider `Ref` is available.
  /// [tabContainerManager] is consulted to read per-tab snapshots out of each
  /// tab's own [ProviderContainer]. [rootContainer] is accepted but not
  /// required — the service prefers reading via [read] so scope rules match the
  /// caller. Pass [now] to stamp a deterministic timestamp in tests.
  String generate({
    required T Function<T>(ProviderListenable<T> provider) read,
    required List<WavecruxTab> tabs,
    required TabId activeTabId,
    required TabContainerManager tabContainerManager,
    WavecruxTab? activeTab,
    ProviderContainer? rootContainer,
    List<double>? recentFrameTimesMs,
    int frameBudgetOverruns = 0,
    DateTime? lastFrameTimestamp,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now().toUtc()).toIso8601String();
    final buf = StringBuffer()
      ..writeln('=== WaveCrux Full Diagnostics Report ===')
      ..writeln('Generated: $timestamp')
      ..writeln(
        'App Version: '
        '${read(applicationBuildInfoProvider).value?.version ?? 'unknown'}',
      )
      ..writeln('Platform: ${_platformName()}')
      ..writeln('Active Tab Id: ${activeTabId.value}')
      ..writeln(
        'Active Tab Name: ${activeTab?.displayName ?? '(unknown)'}',
      );

    _writePlatform(buf);
    _writeAppMemory(
      buf,
      tabs: tabs,
      tabContainerManager: tabContainerManager,
    );
    _writeFrameStats(
      buf,
      recentFrameTimesMs: recentFrameTimesMs,
      frameBudgetOverruns: frameBudgetOverruns,
      lastFrameTimestamp: lastFrameTimestamp,
    );
    _writeActivePaneRenderStats(buf, read);
    _writePerTabBreakdown(
      buf,
      tabs: tabs,
      tabContainerManager: tabContainerManager,
    );

    buf.write('===');
    return buf.toString();
  }

  // ── platform header ───────────────────────────────────────────────────────

  void _writePlatform(StringBuffer buf) {
    final screens = ui.PlatformDispatcher.instance.views
        .map(
          (v) => ScreenInfo(
            physicalWidth: v.physicalSize.width.round(),
            physicalHeight: v.physicalSize.height.round(),
            devicePixelRatio: v.devicePixelRatio,
          ),
        )
        .toList();
    final info = const PlatformInfoService().collect(screens: screens);
    buf
      ..writeln()
      ..writeln('--- Platform ---')
      ..writeln('OS: ${info.operatingSystem}');
    if (info.osVersion.isNotEmpty) {
      buf.writeln('OS Version: ${info.osVersion}');
    }
    buf
      ..writeln('Architecture: ${info.cpuArchitecture}')
      ..writeln('CPU Cores: ${info.cpuCores}');
    if (info.totalRamBytes != null) {
      buf.writeln('Total RAM: ${formatBytes(info.totalRamBytes!)}');
    }
    if (info.locale.isNotEmpty) {
      buf.writeln('Locale: ${info.locale}');
    }
    if (info.dartVersion.isNotEmpty) {
      buf.writeln('Dart Version: ${info.dartVersion}');
    }
    for (var i = 0; i < info.screens.length; i++) {
      final s = info.screens[i];
      final label = info.screens.length == 1 ? 'Display' : 'Display ${i + 1}';
      buf.writeln(
        '$label: ${s.physicalWidth}×${s.physicalHeight} px'
        ' (${s.logicalWidth}×${s.logicalHeight} logical)'
        ' @ ${s.devicePixelRatio}x',
      );
    }
  }

  // ── app-level memory totals ──────────────────────────────────────────────

  void _writeAppMemory(
    StringBuffer buf, {
    required List<WavecruxTab> tabs,
    required TabContainerManager tabContainerManager,
  }) {
    buf
      ..writeln()
      ..writeln('--- App Memory ---');
    var totalWellen = 0;
    var loadedSignals = 0;
    var totalSignals = 0;
    int? rss;
    for (final tab in tabs) {
      final container = tabContainerManager.containerFor(tab.id);
      final stats = container.read(memoryStatsProvider);
      if (stats == null) continue;
      totalWellen += stats.wellenEstimateBytes;
      loadedSignals += stats.loadedSignalCount;
      totalSignals += stats.totalSignalCount;
      if (rss == null && stats.dartProcessRssBytes > 0) {
        rss = stats.dartProcessRssBytes;
      }
    }
    buf
      ..writeln('Process RSS: ${rss == null ? '—' : formatBytes(rss)}')
      ..writeln(
        'Wellen Signal DB (total): ${formatBytes(totalWellen)}',
      )
      ..writeln(
        'Decompressed Signals: $loadedSignals / $totalSignals',
      );
  }

  // ── frame stats ──────────────────────────────────────────────────────────

  void _writeFrameStats(
    StringBuffer buf, {
    List<double>? recentFrameTimesMs,
    int frameBudgetOverruns = 0,
    DateTime? lastFrameTimestamp,
  }) {
    buf
      ..writeln()
      ..writeln('--- Frame Stats ---');
    if (recentFrameTimesMs == null || recentFrameTimesMs.isEmpty) {
      buf
        ..writeln('(no frames recorded yet)')
        ..writeln('Frame budget overruns: $frameBudgetOverruns');
      return;
    }
    final avg =
        recentFrameTimesMs.reduce((a, b) => a + b) / recentFrameTimesMs.length;
    final worst = recentFrameTimesMs.reduce((a, b) => a > b ? a : b);
    final fps = avg > 0 ? 1000.0 / avg : 0.0;
    buf
      ..writeln('FPS: ${fps.toStringAsFixed(1)}')
      ..writeln(
        'Frame Time: ${avg.toStringAsFixed(1)} ms avg, '
        '${worst.toStringAsFixed(1)} ms worst',
      )
      ..writeln('Frame budget overruns: $frameBudgetOverruns');
    if (lastFrameTimestamp != null) {
      buf.writeln('Last frame: ${lastFrameTimestamp.toIso8601String()}');
    }
  }

  // ── active pane render stats ─────────────────────────────────────────────

  void _writeActivePaneRenderStats(
    StringBuffer buf,
    T Function<T>(ProviderListenable<T> provider) read,
  ) {
    buf
      ..writeln()
      ..writeln('--- Active Pane Render Stats ---');
    PaneId? activePane;
    try {
      activePane = read(activePaneIdProvider);
    } on Object catch (_) {
      // The provider can be unimplemented in test scopes; gracefully skip.
    }
    if (activePane == null) {
      buf.writeln('(no active pane)');
      return;
    }
    buf.writeln('Pane Id: ${activePane.value}');
    final pcm = _safeReadPaneContainerManager(read);
    if (pcm == null) {
      buf.writeln('(pane container manager unavailable)');
      return;
    }
    final paneContainer = pcm.containerFor(activePane);
    final stats = paneContainer.read(paneRenderStatsProvider);
    final latest = stats.latest;
    if (latest == null) {
      buf.writeln('(no frames painted in this pane yet)');
      return;
    }
    buf
      ..writeln(
        'Canvas: ${latest.canvasWidth.round()}×${latest.canvasHeight.round()} px',
      )
      ..writeln('Visible signals: ${latest.visibleSignalRows}')
      ..writeln('Visible transitions: ${latest.visibleTransitions}')
      ..writeln('Line segments: ${latest.lineSegmentsDrawn}')
      ..writeln(
        'Total paint: '
        '${(latest.totalPaintTimeUs / 1000).toStringAsFixed(1)} ms',
      )
      ..writeln(
        'Paint breakdown:'
        ' layout ${_usToMs(latest.layoutTimeUs)} ms,'
        ' scalar ${_usToMs(latest.scalarPaintTimeUs)} ms,'
        ' vector ${_usToMs(latest.vectorPaintTimeUs)} ms,'
        ' analog ${_usToMs(latest.analogPaintTimeUs)} ms,'
        ' cursor ${_usToMs(latest.cursorPaintTimeUs)} ms,'
        ' tx ${_usToMs(latest.transactionPaintTimeUs)} ms',
      );
  }

  PaneContainerManager? _safeReadPaneContainerManager(
    T Function<T>(ProviderListenable<T> provider) read,
  ) {
    try {
      return read(paneContainerManagerProvider);
    } on Object catch (_) {
      return null;
    }
  }

  // ── per-tab breakdown ────────────────────────────────────────────────────

  void _writePerTabBreakdown(
    StringBuffer buf, {
    required List<WavecruxTab> tabs,
    required TabContainerManager tabContainerManager,
  }) {
    buf
      ..writeln()
      ..writeln('--- Per-Tab Breakdown ---');
    if (tabs.isEmpty) {
      buf.writeln('(no tabs are loaded)');
      return;
    }
    for (final tab in tabs) {
      buf
        ..writeln()
        ..writeln('* Tab: ${tab.displayName}')
        ..writeln('  Tab Id: ${tab.id.value}');
      if (tab.filePath != null) buf.writeln('  File: ${tab.filePath}');
      final container = tabContainerManager.containerFor(tab.id);

      final fileStats = container.read(fileStatsProvider);
      if (fileStats != null) {
        buf
          ..writeln('  Size: ${formatBytes(fileStats.fileSizeBytes)}')
          ..writeln('  Format: ${fileStats.formatName}')
          ..writeln(
            '  Parse Time: ${fileStats.parseTimeMs.toStringAsFixed(1)} ms',
          )
          ..writeln(
            '  Signals: ${fileStats.totalSignals} '
            '(${fileStats.scalarCount} scalar, '
            '${fileStats.vectorCount} vector, '
            '${fileStats.realCount} real)',
          )
          ..writeln('  Transitions: ${fileStats.totalTransitions}');
        if (fileStats.timescaleDisplay != null) {
          buf.writeln('  Timescale: ${fileStats.timescaleDisplay}');
        }
      } else {
        buf.writeln('  (no file loaded)');
      }

      final mem = container.read(memoryStatsProvider);
      if (mem != null) {
        buf
          ..writeln(
            '  Wellen DB: ${formatBytes(mem.wellenEstimateBytes)}',
          )
          ..writeln(
            '  Decompressed Signals: '
            '${mem.loadedSignalCount} / ${mem.totalSignalCount}',
          );
      }

      final integrity = container.read(signalIntegrityProvider).value;
      if (integrity != null) {
        buf
          ..writeln(
            '  Signals Analyzed: ${integrity.signalsAnalyzed}',
          )
          ..writeln(
            '  Constant: ${integrity.constantSignalPaths.length}',
          )
          ..writeln(
            '  X/Z-Only: ${integrity.xzOnlySignalPaths.length}',
          )
          ..writeln(
            '  Glitches: ${integrity.glitchSignals.length}',
          )
          ..writeln(
            '  Detected Clocks: ${integrity.detectedClocks.length}',
          );
      }
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  static String _platformName() {
    if (kIsWeb) return 'web';
    try {
      return '${Platform.operatingSystem} '
          '(${PlatformInfoService.parseCpuArch(Platform.version)})';
    } on Object catch (_) {
      return 'unknown';
    }
  }

  static String _usToMs(int us) => (us / 1000).toStringAsFixed(1);
}
