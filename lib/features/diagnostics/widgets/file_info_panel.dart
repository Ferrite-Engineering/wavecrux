// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart' show showCruxInfoSnack;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/waveform_format.dart';
import 'package:wavecrux/domain/models/file_stats.dart';
import 'package:wavecrux/features/diagnostics/providers/file_stats_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/platform_context_menu.dart';

/// Diagnostics tab showing file and parser statistics for the loaded waveform.
///
/// Displays file size, format, parse time, signal counts by type and direction,
/// hierarchy metrics, time range, and optional simulation metadata. Shows a
/// placeholder when no file is loaded.
class FileInfoPanel extends ConsumerWidget {
  const FileInfoPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final stats = ref.watch(fileStatsProvider);

    if (stats == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          l10n.diagnosticsDiagNoWaveform,
          textAlign: TextAlign.center,
        ),
      );
    }

    final hasMetadata =
        stats.simulationDate != null || stats.simulatorVersion != null;

    // Hosted inside the Tab Diagnostics drawer's outer SingleChildScrollView,
    // so this panel renders its full content vertically without an inner
    // scroll wrapper — nesting two vertical viewports would give this
    // panel's scroll an unbounded height.
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── File ──────────────────────────────────────────────────────────
          _SectionHeader(title: l10n.diagnosticsFileInfoSectionFile),
          const SizedBox(height: 8),
          _MetricsCard(
            rows: [
              // Issue 23: the file path row truncates with an ellipsis on
              // narrow drawers and previously had no way to read the full
              // path. Wrap the value in a manual-trigger Tooltip for desktop
              // hover and attach a PlatformContextMenu whose first item is
              // the non-interactive monospace full path (per ARCHITECTURE
              // §3.1.8.14) plus a "Copy File Path" action.
              _MetricRow(
                label: l10n.diagnosticsFileInfoPath,
                value: stats.filePath.isEmpty
                    ? l10n.diagnosticsFileInfoNotAvailable
                    : stats.filePath,
                overflow: TextOverflow.ellipsis,
                tooltipText: stats.filePath.isEmpty ? null : stats.filePath,
                copyText: stats.filePath.isEmpty ? null : stats.filePath,
                copyMenuLabel: l10n.diagnosticsFileInfoCopyPath,
                copiedSnackbar: l10n.diagnosticsFileInfoCopiedPath,
              ),
              _MetricRow(
                label: l10n.diagnosticsFileInfoSize,
                value: stats.fileSizeBytes == 0
                    ? l10n.diagnosticsFileInfoNotAvailable
                    : _formatBytes(stats.fileSizeBytes),
              ),
              _MetricRow(
                label: l10n.diagnosticsFileInfoFormat,
                value: stats.formatName,
              ),
              if (stats.originalFormat != null)
                _MetricRow(
                  label: l10n.diagnosticsFileInfoOriginalFormat,
                  value: _formatOriginalFormatValue(l10n, stats),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Parse ─────────────────────────────────────────────────────────
          _SectionHeader(title: l10n.diagnosticsFileInfoSectionParse),
          const SizedBox(height: 8),
          _MetricsCard(
            rows: [
              _MetricRow(
                label: l10n.diagnosticsFileInfoParseTime,
                value: _formatParseTime(stats.parseTimeMs),
              ),
              _MetricRow(
                label: l10n.diagnosticsFileInfoTotalSignals,
                value: _formatCount(stats.totalSignals),
              ),
              _MetricRow(
                label: l10n.diagnosticsFileInfoTransitions,
                value: stats.totalTransitions == 0
                    ? l10n.diagnosticsFileInfoNotAvailable
                    : _formatCount(stats.totalTransitions),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Signals by Type ───────────────────────────────────────────────
          _SectionHeader(title: l10n.diagnosticsFileInfoSectionByType),
          const SizedBox(height: 8),
          _MetricsCard(
            rows: [
              _MetricRow(
                label: l10n.diagnosticsFileInfoScalar,
                value: _formatCount(stats.scalarCount),
              ),
              _MetricRow(
                label: l10n.diagnosticsFileInfoVector,
                value: _formatCount(stats.vectorCount),
              ),
              _MetricRow(
                label: l10n.diagnosticsFileInfoReal,
                value: _formatCount(stats.realCount),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Signals by Direction ──────────────────────────────────────────
          _SectionHeader(title: l10n.diagnosticsFileInfoSectionByDirection),
          const SizedBox(height: 8),
          _MetricsCard(
            rows: [
              _MetricRow(
                label: l10n.diagnosticsFileInfoInput,
                value: _formatCount(stats.inputCount),
              ),
              _MetricRow(
                label: l10n.diagnosticsFileInfoOutput,
                value: _formatCount(stats.outputCount),
              ),
              _MetricRow(
                label: l10n.diagnosticsFileInfoInout,
                value: _formatCount(stats.inoutCount),
              ),
              _MetricRow(
                label: l10n.diagnosticsFileInfoUnknown,
                value: _formatCount(stats.unknownDirectionCount),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Hierarchy ─────────────────────────────────────────────────────
          _SectionHeader(title: l10n.diagnosticsFileInfoSectionHierarchy),
          const SizedBox(height: 8),
          _MetricsCard(
            rows: [
              _MetricRow(
                label: l10n.diagnosticsFileInfoDepth,
                value: stats.hierarchyDepth.toString(),
              ),
              _MetricRow(
                label: l10n.diagnosticsFileInfoScopes,
                value: _formatCount(stats.scopeCount),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Time ──────────────────────────────────────────────────────────
          _SectionHeader(title: l10n.diagnosticsFileInfoSectionTime),
          const SizedBox(height: 8),
          _MetricsCard(
            rows: [
              _MetricRow(
                label: l10n.diagnosticsFileInfoTimeRange,
                value:
                    '${_formatCount(stats.startTime)} – ${_formatCount(stats.endTime)}',
              ),
              _MetricRow(
                label: l10n.diagnosticsFileInfoTimescale,
                value:
                    stats.timescaleDisplay ??
                    l10n.diagnosticsFileInfoNotAvailable,
              ),
            ],
          ),

          // ── Metadata (only when present) ──────────────────────────────────
          if (hasMetadata) ...[
            const SizedBox(height: 16),
            _SectionHeader(title: l10n.diagnosticsFileInfoSectionMetadata),
            const SizedBox(height: 8),
            _MetricsCard(
              rows: [
                if (stats.simulationDate != null)
                  _MetricRow(
                    label: l10n.diagnosticsFileInfoDate,
                    value: stats.simulationDate!,
                  ),
                if (stats.simulatorVersion != null)
                  _MetricRow(
                    label: l10n.diagnosticsFileInfoVersion,
                    value: stats.simulatorVersion!,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Formatting helpers ─────────────────────────────────────────────────────

  /// Format the Original Format row's value. Renders
  /// `"<acronym> (converted to FST on <date>)"` when both the origin format
  /// and a conversion timestamp are known; falls back to the no-date variant
  /// otherwise. The acronyms `LXT` / `LXT2` are file-format identifiers and
  /// are not localized.
  static String _formatOriginalFormatValue(L10N l10n, FileStats stats) {
    final origin = stats.originalFormat;
    if (origin == null) return '';
    final acronym = switch (origin) {
      WaveformFormat.lxt => 'LXT',
      WaveformFormat.lxt2 => 'LXT2',
      _ => origin.name.toUpperCase(),
    };
    final converted = stats.convertedAt;
    if (converted == null) {
      return l10n.diagnosticsFileInfoOriginalFormatValueUnknownDate(acronym);
    }
    return l10n.diagnosticsFileInfoOriginalFormatValue(
      acronym,
      _formatDate(converted),
    );
  }

  /// Locale-independent ISO date — keeps the value monospaced-friendly and
  /// stable across the locale sweep.
  static String _formatDate(DateTime d) {
    final yyyy = d.year.toString().padLeft(4, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  static String _formatParseTime(double ms) {
    if (ms < 1000) return '${ms.toStringAsFixed(1)} ms';
    return '${(ms / 1000).toStringAsFixed(2)} s';
  }

  static String _formatCount(int n) {
    final s = n.toString();
    if (s.length <= 3) return s;
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ── Private shared helpers ────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

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
          children: rows.map((row) => _MetricsCardRow(row: row)).toList(),
        ),
      ),
    );
  }
}

/// One row of [_MetricsCard]. Renders the label / value pair and, when the
/// row carries [`_MetricRow.tooltipText`] or [`_MetricRow.copyText`],
/// wraps the value in a manual-trigger [Tooltip] and the entire row in a
/// [PlatformContextMenu] whose first entry is the non-interactive
/// monospace full content header (per ARCHITECTURE.md §3.1.8.14, the
/// "truncated text always has a reveal" rule).
class _MetricsCardRow extends StatelessWidget {
  const _MetricsCardRow({required this.row});

  final _MetricRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget valueText = Text(
      row.value,
      overflow: row.overflow,
      textAlign: TextAlign.end,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        fontFamily: 'monospace',
      ),
    );
    final tooltipText = row.tooltipText;
    if (tooltipText != null) {
      // Manual trigger so a long-press on touch doesn't beat the outer
      // PlatformContextMenu to the gesture arena (per the
      // "Tooltips inside a row use TooltipTriggerMode.manual" rule).
      valueText = Tooltip(
        message: tooltipText,
        triggerMode: TooltipTriggerMode.manual,
        child: valueText,
      );
    }

    final rowContent = Padding(
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
          Flexible(child: valueText),
        ],
      ),
    );

    final copyText = row.copyText;
    if (copyText == null) return rowContent;

    return PlatformContextMenu(
      onContextMenu: (globalPosition) => _showContextMenu(
        context: context,
        globalPosition: globalPosition,
        colorScheme: colorScheme,
        fullText: copyText,
        copyLabel: row.copyMenuLabel,
        copiedSnackbar: row.copiedSnackbar,
      ),
      child: rowContent,
    );
  }

  Future<void> _showContextMenu({
    required BuildContext context,
    required Offset globalPosition,
    required ColorScheme colorScheme,
    required String fullText,
    required String? copyLabel,
    required String? copiedSnackbar,
  }) async {
    if (!context.mounted) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final menuPosition = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlay.size,
    );
    final result = await showMenu<_RowMenuAction>(
      context: context,
      position: menuPosition,
      items: <PopupMenuEntry<_RowMenuAction>>[
        // Full-content header — non-interactive monospace per
        // ARCHITECTURE.md §3.1.8.14.
        PopupMenuItem<_RowMenuAction>(
          enabled: false,
          height: 36,
          child: Text(
            fullText,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const PopupMenuDivider(),
        if (copyLabel != null)
          PopupMenuItem<_RowMenuAction>(
            value: _RowMenuAction.copy,
            child: Text(copyLabel),
          ),
      ],
    );
    if (result == _RowMenuAction.copy) {
      await Clipboard.setData(ClipboardData(text: fullText));
      if (copiedSnackbar != null && context.mounted) {
        showCruxInfoSnack(context, copiedSnackbar);
      }
    }
  }
}

enum _RowMenuAction { copy }

class _MetricRow {
  const _MetricRow({
    required this.label,
    required this.value,
    this.overflow,
    this.tooltipText,
    this.copyText,
    this.copyMenuLabel,
    this.copiedSnackbar,
  });

  final String label;
  final String value;
  final TextOverflow? overflow;

  /// When non-null, the value text is wrapped in a manual-trigger Tooltip
  /// showing this string on hover (desktop reveal for truncated content).
  final String? tooltipText;

  /// When non-null, the entire row gains a [PlatformContextMenu] whose
  /// first item is the non-interactive monospace full-content header
  /// (per ARCHITECTURE.md §3.1.8.14) and, when [copyMenuLabel] is also
  /// supplied, a "copy to clipboard" action.
  final String? copyText;

  /// Localized label for the "Copy …" menu item. Required when [copyText]
  /// is set; ignored otherwise.
  final String? copyMenuLabel;

  /// Localized snackbar shown after a successful copy. Optional even when
  /// [copyText] is set.
  final String? copiedSnackbar;
}
