// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/providers/browser_download_provider.dart';
import 'package:wavecrux/core/providers/system_dialog_provider.dart';
import 'package:wavecrux/domain/models/signal_activity.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/switching_activity_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';

// ── Column sort state ─────────────────────────────────────────────────────────

enum _SortColumn {
  signal,
  transitions,
  toggleRate,
  clock,
  frequency,
  dutyCycle,
}

// ── ActivityReportPanel ───────────────────────────────────────────────────────

/// Bottom-pane panel showing the switching activity analysis results.
///
/// Displays a sortable table with columns: Signal Path, Transitions,
/// Toggle Rate, Clock?, Frequency, Duty Cycle.  Clock candidates are
/// highlighted with a clock icon.  Tapping a row selects the signal in the
/// waveform view.  An Export CSV button writes the table to a file.
class ActivityReportPanel extends ConsumerStatefulWidget {
  const ActivityReportPanel({super.key});

  @override
  ConsumerState<ActivityReportPanel> createState() =>
      _ActivityReportPanelState();
}

class _ActivityReportPanelState extends ConsumerState<ActivityReportPanel> {
  _SortColumn _sortColumn = _SortColumn.toggleRate;
  bool _ascending = false;

  void _setSort(_SortColumn col) {
    setState(() {
      if (_sortColumn == col) {
        _ascending = !_ascending;
      } else {
        _sortColumn = col;
        _ascending = false;
      }
    });
  }

  List<SignalActivity> _sorted(List<SignalActivity> signals) {
    final list = [...signals]
      ..sort((a, b) {
        int cmp;
        switch (_sortColumn) {
          case _SortColumn.signal:
            cmp = a.signalPath.compareTo(b.signalPath);
          case _SortColumn.transitions:
            cmp = a.transitionCount.compareTo(b.transitionCount);
          case _SortColumn.toggleRate:
            cmp = a.toggleRate.compareTo(b.toggleRate);
          case _SortColumn.clock:
            cmp = (a.isClockCandidate ? 1 : 0).compareTo(
              b.isClockCandidate ? 1 : 0,
            );
          case _SortColumn.frequency:
            final af = a.estimatedFrequency ?? -1;
            final bf = b.estimatedFrequency ?? -1;
            cmp = af.compareTo(bf);
          case _SortColumn.dutyCycle:
            final ad = a.dutyCycle ?? -1;
            final bd = b.dutyCycle ?? -1;
            cmp = ad.compareTo(bd);
        }
        return _ascending ? cmp : -cmp;
      });
    return list;
  }

  Future<void> _exportCsv(
    BuildContext context,
    List<SignalActivity> signals,
    L10N l10n,
    Timescale? timescale,
  ) async {
    const fileName = 'switching_activity.csv';
    // In the browser the CSV downloads; there is no save dialog with a path.
    final download = ref.read(browserDownloadProvider);
    String? path;
    if (download == null) {
      if (ref.read(systemDialogInFlightProvider)) return;
      // Read before the await; see [SystemDialogInFlight.end].
      final inFlight = ref.read(systemDialogInFlightProvider.notifier)..begin();
      try {
        path = await FilePicker.saveFile(
          // file_picker 12 requires bytes & writes the file; pass empty so it
          // only returns the chosen path and we write the CSV below.
          bytes: Uint8List(0),
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['csv'],
        );
      } finally {
        inFlight.end();
      }
      if (path == null) return;
    }

    final buf = StringBuffer()
      ..writeln(
        '${l10n.activityColumnSignalPath},'
        '${l10n.activityColumnTransitions},'
        '${l10n.activityColumnToggleRate},'
        '${l10n.activityColumnClock},'
        '${l10n.activityColumnFrequency},'
        '${l10n.activityColumnDutyCycle}',
      );
    for (final s in signals) {
      final freq = s.estimatedFrequency != null
          ? _formatFreq(s.estimatedFrequency!)
          : '';
      final dc = s.dutyCycle != null
          ? '${(s.dutyCycle! * 100).toStringAsFixed(1)}%'
          : '';
      buf.writeln(
        '"${s.signalPath}",'
        '${s.transitionCount},'
        '${_formatToggleRate(s.toggleRate, timescale)},'
        '${s.isClockCandidate ? l10n.activityClockLabel : ''},'
        '$freq,'
        '$dc',
      );
    }

    if (download != null) {
      await download(fileName: fileName, bytes: utf8.encode(buf.toString()));
    } else {
      await File(path!).writeAsString(buf.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final activityState = ref.watch(switchingActivityProvider);
    final timescale = ref.watch(currentTimescaleProvider);
    final formatter = TimeFormatService(timescale: timescale);

    if (activityState.isAnalyzing) {
      return _buildAnalyzing(context, l10n, colorScheme);
    }

    final report = activityState.report;
    if (report == null) {
      return _buildEmpty(context, l10n, colorScheme);
    }

    final sorted = _sorted(report.signals);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          l10n: l10n,
          colorScheme: colorScheme,
          onClear: () => ref.read(switchingActivityProvider.notifier).clear(),
          onExportCsv: () => _exportCsv(context, sorted, l10n, timescale),
          totalTransitions: report.totalTransitions,
        ),
        _ColumnHeaderRow(
          l10n: l10n,
          colorScheme: colorScheme,
          sortColumn: _sortColumn,
          ascending: _ascending,
          onSort: _setSort,
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: sorted.length,
            itemExtent: 28,
            itemBuilder: (_, i) => _SignalRow(
              activity: sorted[i],
              colorScheme: colorScheme,
              l10n: l10n,
              formatter: formatter,
              timescale: timescale,
              onTap: () => ref
                  .read(selectedVariablesProvider.notifier)
                  .selectOnly(sorted[i].signalPath),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(
    BuildContext context,
    L10N l10n,
    ColorScheme colorScheme,
  ) => ColoredBox(
    color: colorScheme.surface,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          l10n.activityEmptyState,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
      ),
    ),
  );

  Widget _buildAnalyzing(
    BuildContext context,
    L10N l10n,
    ColorScheme colorScheme,
  ) => ColoredBox(
    color: colorScheme.surface,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.activityAnalyzing,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    ),
  );
}

// ── _PanelHeader ──────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.l10n,
    required this.colorScheme,
    required this.onClear,
    required this.onExportCsv,
    required this.totalTransitions,
  });

  final L10N l10n;
  final ColorScheme colorScheme;
  final VoidCallback onClear;
  final VoidCallback onExportCsv;
  final int totalTransitions;

  @override
  Widget build(BuildContext context) => Container(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    color: colorScheme.surfaceContainerHighest,
    child: Row(
      children: [
        Icon(Icons.bolt, size: 14, color: colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            l10n.activityPanelTitle,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        Text(
          '$totalTransitions total',
          style: TextStyle(
            fontSize: 10,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onExportCsv,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontSize: 11),
          ),
          child: Text(l10n.activityExportCsv),
        ),
        TextButton(
          onPressed: onClear,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontSize: 11),
          ),
          child: Text(l10n.activityClearButton),
        ),
      ],
    ),
  );
}

// ── _ColumnHeaderRow ──────────────────────────────────────────────────────────

class _ColumnHeaderRow extends StatelessWidget {
  const _ColumnHeaderRow({
    required this.l10n,
    required this.colorScheme,
    required this.sortColumn,
    required this.ascending,
    required this.onSort,
  });

  final L10N l10n;
  final ColorScheme colorScheme;
  final _SortColumn sortColumn;
  final bool ascending;
  final void Function(_SortColumn) onSort;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      color: colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          _HeaderCell(
            label: l10n.activityColumnSignalPath,
            col: _SortColumn.signal,
            flex: 3,
            sortColumn: sortColumn,
            ascending: ascending,
            onSort: onSort,
            colorScheme: colorScheme,
          ),
          _HeaderCell(
            label: l10n.activityColumnTransitions,
            col: _SortColumn.transitions,
            flex: 2,
            sortColumn: sortColumn,
            ascending: ascending,
            onSort: onSort,
            colorScheme: colorScheme,
          ),
          _HeaderCell(
            label: l10n.activityColumnToggleRate,
            col: _SortColumn.toggleRate,
            flex: 2,
            sortColumn: sortColumn,
            ascending: ascending,
            onSort: onSort,
            colorScheme: colorScheme,
          ),
          _HeaderCell(
            label: l10n.activityColumnClock,
            col: _SortColumn.clock,
            flex: 1,
            sortColumn: sortColumn,
            ascending: ascending,
            onSort: onSort,
            colorScheme: colorScheme,
          ),
          _HeaderCell(
            label: l10n.activityColumnFrequency,
            col: _SortColumn.frequency,
            flex: 2,
            sortColumn: sortColumn,
            ascending: ascending,
            onSort: onSort,
            colorScheme: colorScheme,
          ),
          _HeaderCell(
            label: l10n.activityColumnDutyCycle,
            col: _SortColumn.dutyCycle,
            flex: 2,
            sortColumn: sortColumn,
            ascending: ascending,
            onSort: onSort,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.col,
    required this.flex,
    required this.sortColumn,
    required this.ascending,
    required this.onSort,
    required this.colorScheme,
  });

  final String label;
  final _SortColumn col;
  final int flex;
  final _SortColumn sortColumn;
  final bool ascending;
  final void Function(_SortColumn) onSort;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final isActive = sortColumn == col;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => onSort(col),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: isActive
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive)
                Icon(
                  ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 10,
                  color: colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _SignalRow ─────────────────────────────────────────────────────────────────

class _SignalRow extends StatelessWidget {
  const _SignalRow({
    required this.activity,
    required this.colorScheme,
    required this.l10n,
    required this.formatter,
    required this.timescale,
    required this.onTap,
  });

  final SignalActivity activity;
  final ColorScheme colorScheme;
  final L10N l10n;
  final TimeFormatService formatter;
  final Timescale? timescale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final freq = activity.estimatedFrequency != null
        ? _formatFreq(activity.estimatedFrequency!)
        : '—';
    final dc = activity.dutyCycle != null
        ? '${(activity.dutyCycle! * 100).toStringAsFixed(1)}%'
        : '—';

    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          // Signal Path (flex 3) — leaf name shown, full path in tooltip
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Tooltip(
                message: activity.signalPath,
                child: Text(
                  activity.signalPath.contains('.')
                      ? activity.signalPath.split('.').last
                      : activity.signalPath,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'JetBrainsMono',
                    fontFamilyFallback: const [
                      'FiraCode',
                      'Courier New',
                      'monospace',
                    ],
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          // Transitions (flex 2)
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '${activity.transitionCount}',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurface),
              ),
            ),
          ),
          // Toggle Rate (flex 2)
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                _formatToggleRate(activity.toggleRate, timescale),
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),
          // Clock? (flex 1)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: activity.isClockCandidate
                  ? Tooltip(
                      message: l10n.activityClockLabel,
                      child: Icon(
                        Icons.access_time,
                        size: 14,
                        color: colorScheme.tertiary,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          // Frequency (flex 2)
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                freq,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: activity.isClockCandidate
                      ? colorScheme.tertiary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          // Duty Cycle (flex 2)
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                dc,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── helpers ───────────────────────────────────────────────────────────────────

String _formatFreq(double hz) {
  if (hz >= 1e9) return '${(hz / 1e9).toStringAsFixed(2)} GHz';
  if (hz >= 1e6) return '${(hz / 1e6).toStringAsFixed(2)} MHz';
  if (hz >= 1e3) return '${(hz / 1e3).toStringAsFixed(2)} kHz';
  return '${hz.toStringAsFixed(2)} Hz';
}

/// Formats [toggleRate] (transitions per simulation tick) as a human-readable
/// transitions-per-second value scaled to the most appropriate SI prefix.
///
/// Falls back to "X.XXX/tick" when [timescale] is unavailable.
String _formatToggleRate(double toggleRate, Timescale? timescale) {
  final secondsPerTick = timescale?.secondsPerTick;
  if (secondsPerTick == null || secondsPerTick <= 0) {
    return '${toggleRate.toStringAsPrecision(3)}/tick';
  }
  final transitionsPerSecond = toggleRate / secondsPerTick;
  if (transitionsPerSecond >= 1e9) {
    return '${(transitionsPerSecond / 1e9).toStringAsFixed(2)} GT/s';
  }
  if (transitionsPerSecond >= 1e6) {
    return '${(transitionsPerSecond / 1e6).toStringAsFixed(2)} MT/s';
  }
  if (transitionsPerSecond >= 1e3) {
    return '${(transitionsPerSecond / 1e3).toStringAsFixed(2)} kT/s';
  }
  return '${transitionsPerSecond.toStringAsFixed(2)} T/s';
}
