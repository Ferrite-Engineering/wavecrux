// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/utils/byte_format.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/memory_stats.dart';
import 'package:wavecrux/domain/models/wavecrux_tab.dart';
import 'package:wavecrux/features/diagnostics/copy_app_diagnostics_report.dart';
import 'package:wavecrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:wavecrux/features/diagnostics/providers/memory_stats_provider.dart';
import 'package:wavecrux/features/diagnostics/widgets/logs_panel.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Process-wide App Diagnostics dialog (see `docs/ARCHITECTURE.md` §8.8).
///
/// Modal dialog that owns the app-level slice of the legacy seven-tab
/// diagnostics dialog: overall memory (RSS + total wellen DB across every
/// loaded tab + per-tab breakdown) and frame stats (FPS, frame budget
/// overruns, last-frame timestamp). The Copy Full Diagnostics Report action
/// aggregates these with the active pane's render stats and every loaded
/// tab's file info + signal health into the structured report consumed by
/// GitHub issue templates.
///
/// Open via [AppDiagnosticsDialog.open]; the entry point is also wired into
/// the Tools menu, the command palette, and the Cmd/Ctrl+Shift+M keyboard
/// shortcut. Rendered on tablet and desktop only — phone hides it via the
/// shared [diagnosticsEnabledProvider] / device-class gating used by the
/// other diagnostics surfaces.
class AppDiagnosticsDialog extends ConsumerStatefulWidget {
  const AppDiagnosticsDialog({super.key});

  /// Opens the dialog as a Material modal.
  ///
  /// No-op when [diagnosticsEnabledProvider] is false or when the active
  /// [DeviceClass] is `phone` / `phoneLandscape`. Returns when the dialog is
  /// closed.
  static Future<void> open(BuildContext context) {
    // Re-entrancy guard: a second trigger (shortcut auto-repeat, double-tap,
    // or menu while the dialog is already up) must not stack a second dialog.
    return ModalGuard.run(
      'appDiagnostics',
      () => showDialog<void>(
        context: context,
        builder: (_) => const AppDiagnosticsDialog(),
      ),
    );
  }

  @override
  ConsumerState<AppDiagnosticsDialog> createState() =>
      _AppDiagnosticsDialogState();
}

class _AppDiagnosticsDialogState extends ConsumerState<AppDiagnosticsDialog> {
  /// Sliding-window cap. Roughly matches the strip's ~60 s window at the
  /// 16 ms-per-frame cadence so the dialog's FPS estimate reflects recent
  /// behavior rather than the entire session.
  static const int _kFrameWindow = 240;
  static const double _kFrameBudgetMs = 16.7;

  final List<double> _frameDurationsMs = [];
  int _frameBudgetOverruns = 0;
  DateTime? _lastFrameAt;

  // Issue 20: explicit ScrollController + Scrollbar so the dialog has a
  // visible scroll indicator and reliably accepts two-finger trackpad pan
  // events when the per-tab memory breakdown table grows beyond the
  // dialog's fixed 620 dp height. Without the explicit controller / Scrollbar
  // pair the dialog falls back to Flutter's default behavior which clips
  // the table content silently on macOS desktop.
  final ScrollController _scrollController = ScrollController();
  Timer? _refresh;
  // Snapshot of per-tab memory; refreshed on a 2 s cadence in parallel with
  // each tab's MemoryStatsNotifier polling so this row's values converge
  // with what the strip and Tab Diagnostics drawer show.
  Map<WavecruxTab, MemoryStats?> _perTab = const {};
  // Issue 10: hold an open subscription to each tab's
  // memoryStatsProvider so the auto-dispose provider stays alive
  // while the dialog is open. Without this, the provider disposes between
  // the 2 s polls, its internal timer is cancelled, and every fresh read
  // returns the initial null state — leaving the dialog's Memory section
  // permanently empty. Map key is the tab id (TabId-stringified) so we can
  // close subscriptions for tabs that disappear between refreshes.
  final Map<String, ProviderSubscription<MemoryStats?>> _subscriptions = {};

  @override
  void initState() {
    super.initState();
    // SchedulerBinding may be unavailable in pure ProviderContainer tests —
    // guard so the dialog still mounts (it just won't get frame timings).
    try {
      SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    } on Object catch (_) {
      // Best-effort: tests skip the binding; the metric row renders the
      // "no frames" placeholder.
    }
    // Refresh per-tab memory every 2 s — same cadence as
    // MemoryStatsNotifier's internal polling.
    _refresh = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(_refreshPerTab);
    });
    // Kick off an initial read in the first post-frame slot so each tab's
    // MemoryStatsNotifier begins polling before the user looks at the row.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(_refreshPerTab);
    });
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!mounted) return;
    setState(() {
      for (final t in timings) {
        final ms = (t.buildDuration + t.rasterDuration).inMicroseconds / 1000.0;
        if (ms <= 0) continue;
        _frameDurationsMs.add(ms);
        if (_frameDurationsMs.length > _kFrameWindow) {
          _frameDurationsMs.removeAt(0);
        }
        if (ms > _kFrameBudgetMs) _frameBudgetOverruns++;
        _lastFrameAt = DateTime.now();
      }
    });
  }

  void _refreshPerTab() {
    final tabs = ref.read(tabListProvider);
    final tcm = ref.read(tabContainerManagerProvider);
    final next = <WavecruxTab, MemoryStats?>{};
    final liveIds = <String>{};
    for (final tab in tabs) {
      final container = tcm.containerFor(tab.id);
      final key = tab.id.toString();
      liveIds.add(key);
      // Issue 10: open a long-lived subscription so the auto-dispose
      // memoryStatsProvider stays alive across the dialog's polling
      // cycle. Without an active listener the provider disposes immediately
      // after each read(), its internal Timer.periodic is cancelled in
      // onDispose, and the Memory section stays permanently empty.
      _subscriptions.putIfAbsent(
        key,
        () => container.listen<MemoryStats?>(
          memoryStatsProvider,
          (_, _) {
            if (mounted) setState(_refreshPerTab);
          },
        ),
      );
      next[tab] = container.read(memoryStatsProvider);
    }
    // Close subscriptions for tabs that disappeared between refreshes.
    final stale = _subscriptions.keys.toSet().difference(liveIds);
    for (final key in stale) {
      _subscriptions.remove(key)?.close();
    }
    _perTab = next;
  }

  @override
  void dispose() {
    for (final sub in _subscriptions.values) {
      sub.close();
    }
    _subscriptions.clear();
    _refresh?.cancel();
    _scrollController.dispose();
    try {
      SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    } on Object catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final diagnosticsEnabled = ref.watch(diagnosticsEnabledProvider);
    final deviceClass = ref.watch(deviceClassProvider);

    // Mirror the Tab Diagnostics drawer's gating: hide on phone /
    // phone-landscape and when the user has disabled diagnostics. Close
    // post-frame so the dialog does not linger if the user resizes after
    // opening.
    if (!diagnosticsEnabled ||
        deviceClass == DeviceClass.phone ||
        deviceClass == DeviceClass.phoneLandscape) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }

    final tabs = ref.watch(tabListProvider);
    final perTab = _perTab;
    final totalWellenBytes = perTab.values.fold<int>(
      0,
      (acc, stats) => acc + (stats?.wellenEstimateBytes ?? 0),
    );
    // RSS is process-wide; take it from any tab's poll snapshot, or
    // fall back to "—" when no tabs have polled yet.
    final rss = _firstNonNullRss(perTab.values);

    final fps = _computeFps(_frameDurationsMs);
    final fpsLabel = fps == null ? '—' : '${fps.toStringAsFixed(1)} fps';
    final lastFrameLabel = _lastFrameAt == null
        ? '—'
        : _lastFrameAt!.toIso8601String();
    final lastFrameMs = _frameDurationsMs.isEmpty
        ? null
        : _frameDurationsMs.last;

    return Dialog(
      child: SizedBox(
        width: 720,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              title: l10n.appDiagnosticsTitle,
              subtitle: l10n.appDiagnosticsSubtitle,
              onCopy: () => _copyReport(context, l10n),
              onClose: () => Navigator.of(context).maybePop(),
              theme: theme,
              l10n: l10n,
            ),
            const Divider(height: 1),
            Expanded(
              // Issue 20: Scrollbar + ScrollConfiguration wrapping so the
              // per-tab memory table is reachable when it overflows the
              // dialog's fixed 620 dp height. The custom ScrollBehavior
              // enables mouse-drag *and* trackpad pan in addition to the
              // default touch+wheel set so two-finger trackpad scroll
              // works on macOS desktop without the user having to find
              // the scroll thumb.
              child: ScrollConfiguration(
                behavior: const _AppDiagnosticsScrollBehavior(),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionHeader(
                          key: const Key('appDiagnosticsSectionMemory'),
                          title: l10n.appDiagnosticsSectionMemory,
                        ),
                        const SizedBox(height: 8),
                        _MetricsCard(
                          rows: [
                            _MetricRow(
                              label: l10n.appDiagnosticsMetricRss,
                              value: rss == null ? '—' : formatBytes(rss),
                            ),
                            _MetricRow(
                              label: l10n.appDiagnosticsMetricWellenTotal,
                              value: formatBytes(totalWellenBytes),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _SectionHeader(
                          key: const Key(
                            'appDiagnosticsSectionPerTabBreakdown',
                          ),
                          title: l10n.appDiagnosticsSectionPerTabBreakdown,
                        ),
                        const SizedBox(height: 8),
                        _PerTabTable(
                          tabs: tabs,
                          perTab: perTab,
                          l10n: l10n,
                        ),
                        const SizedBox(height: 20),
                        _SectionHeader(
                          key: const Key('appDiagnosticsSectionFrameStats'),
                          title: l10n.appDiagnosticsSectionFrameStats,
                        ),
                        const SizedBox(height: 8),
                        _MetricsCard(
                          rows: [
                            _MetricRow(
                              label: l10n.appDiagnosticsMetricFps,
                              value: fpsLabel,
                            ),
                            _MetricRow(
                              label: l10n.appDiagnosticsMetricFrameBudget,
                              value: '$_frameBudgetOverruns',
                            ),
                            _MetricRow(
                              label: l10n.appDiagnosticsMetricLastFrame,
                              value: lastFrameMs == null
                                  ? '—'
                                  : '${lastFrameMs.toStringAsFixed(1)} ms — '
                                        '$lastFrameLabel',
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _SectionHeader(
                          key: const Key('appDiagnosticsSectionLogs'),
                          title: l10n.logsPanelTitle,
                        ),
                        const SizedBox(height: 8),
                        const LogsPanel(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyReport(BuildContext context, L10N l10n) =>
      copyAppDiagnosticsReport(
        context,
        ref,
        recentFrameTimesMs: List<double>.unmodifiable(_frameDurationsMs),
        frameBudgetOverruns: _frameBudgetOverruns,
        lastFrameTimestamp: _lastFrameAt,
      );

  static double? _computeFps(List<double> samples) {
    if (samples.isEmpty) return null;
    final avgMs = samples.reduce((a, b) => a + b) / samples.length;
    if (avgMs <= 0) return null;
    return 1000.0 / avgMs;
  }

  static int? _firstNonNullRss(Iterable<MemoryStats?> stats) {
    for (final s in stats) {
      if (s != null && s.dartProcessRssBytes > 0) return s.dartProcessRssBytes;
    }
    return null;
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.onCopy,
    required this.onClose,
    required this.theme,
    required this.l10n,
  });

  final String title;
  final String subtitle;
  final VoidCallback onCopy;
  final VoidCallback onClose;
  final ThemeData theme;
  final L10N l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            key: const Key('appDiagnosticsCopyReportButton'),
            onPressed: onCopy,
            icon: const Icon(Icons.copy, size: 16),
            label: Text(l10n.appDiagnosticsCopyReportLabel),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const Key('appDiagnosticsCloseButton'),
            icon: const Icon(Icons.close),
            tooltip: l10n.appDiagnosticsCloseTooltip,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.labelMedium?.copyWith(
        letterSpacing: 0.8,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

// ── Metrics card (reused layout) ──────────────────────────────────────────────

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({required this.rows});

  final List<_MetricRow> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: rows
              .map(
                (row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          row.label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          row.value,
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _MetricRow {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;
}

// ── Per-tab memory breakdown table ────────────────────────────────────────────

class _PerTabTable extends StatelessWidget {
  const _PerTabTable({
    required this.tabs,
    required this.perTab,
    required this.l10n,
  });

  final List<WavecruxTab> tabs;
  final Map<WavecruxTab, MemoryStats?> perTab;
  final L10N l10n;

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          l10n.appDiagnosticsNoTabs,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: DataTable(
          key: const Key('appDiagnosticsPerTabTable'),
          columnSpacing: 24,
          headingRowHeight: 36,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 44,
          columns: [
            DataColumn(label: Text(l10n.appDiagnosticsColumnTab)),
            DataColumn(
              label: Text(l10n.appDiagnosticsColumnWellenBytes),
              numeric: true,
            ),
            DataColumn(
              label: Text(l10n.appDiagnosticsColumnDecompressedSignals),
              numeric: true,
            ),
          ],
          rows: [
            for (final tab in tabs)
              DataRow(
                // Namespaced so the row key never collides with the tab chip's
                // `ValueKey(tab.id)` (see tab_drag_reorder regression).
                key: ValueKey('diagTabRow:${tab.id.value}'),
                cells: [
                  DataCell(
                    Text(
                      tab.displayName,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  DataCell(
                    Text(
                      perTab[tab] == null
                          ? '—'
                          : formatBytes(perTab[tab]!.wellenEstimateBytes),
                    ),
                  ),
                  DataCell(
                    Text(
                      perTab[tab] == null
                          ? '—'
                          : '${perTab[tab]!.loadedSignalCount} / '
                                '${perTab[tab]!.totalSignalCount}',
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ── Scroll behavior ───────────────────────────────────────────────────────────

/// [ScrollBehavior] that explicitly accepts trackpad and mouse input in
/// addition to the default touch + stylus + invertedStylus set, so the App
/// Diagnostics dialog scrolls reliably under two-finger trackpad gestures on
/// macOS desktop where the per-tab memory breakdown may overflow the dialog's
/// fixed 620 dp height. Without this, the default `MaterialScrollBehavior`
/// drops mouse-drag and trackpad pan events that the user expects to scroll
/// the contents.
class _AppDiagnosticsScrollBehavior extends MaterialScrollBehavior {
  const _AppDiagnosticsScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };
}
