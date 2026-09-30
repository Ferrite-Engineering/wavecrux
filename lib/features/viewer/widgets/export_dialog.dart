// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Which file format to export.
enum ExportFormat { vcd, saif, png, svg }

/// Whether to export the visible time range or the full simulation.
enum ExportTimeRange { visible, full }

/// Which signals to include in the export.
enum ExportSignals { visible, all }

/// The result returned when the user confirms the export dialog.
class ExportDialogResult {
  const ExportDialogResult({
    required this.format,
    required this.timeRange,
    required this.signals,
    required this.pixelRatio,
    this.includeAnnotations = true,
  });

  final ExportFormat format;
  final ExportTimeRange timeRange;
  final ExportSignals signals;

  /// Device-pixel ratio for PNG exports; 1.0, 2.0, or 3.0.
  final double pixelRatio;

  /// Whether annotations are drawn into the exported image. Ignored by the
  /// data formats, which carry no notion of a note.
  final bool includeAnnotations;
}

/// Modal dialog that lets the user configure a waveform export (VCD/PNG/SVG).
///
/// Returns an [ExportDialogResult] when the user presses Export, or null when
/// they cancel. Call [ExportDialog.show] as a convenience.
class ExportDialog extends StatefulWidget {
  const ExportDialog({super.key});

  /// Opens the export dialog and returns the user's configuration, or null if
  /// the user dismissed it.
  static Future<ExportDialogResult?> show(BuildContext context) =>
      showDialog<ExportDialogResult>(
        context: context,
        builder: (_) => const ExportDialog(),
      );

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  ExportFormat _format = ExportFormat.vcd;
  ExportTimeRange _timeRange = ExportTimeRange.visible;
  ExportSignals _signals = ExportSignals.visible;
  double _pixelRatio = 2;
  bool _includeAnnotations = true;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final showResolution = _format == ExportFormat.png;
    final isImage = _format == ExportFormat.png || _format == ExportFormat.svg;
    // A PNG is a capture of the on-screen viewport, so it cannot honour a time
    // range or signal set other than what is displayed. The options used to be
    // offered anyway and silently ignored — picking "full simulation" got you
    // the current window with no indication. Disabled and explained instead.
    final rangeSelectable = _format != ExportFormat.png;

    return AlertDialog(
      title: Text(l10n.exportDialogTitle),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel(l10n.exportDialogFormatSection),
              _RadioGroup<ExportFormat>(
                value: _format,
                options: [
                  (ExportFormat.vcd, l10n.exportDialogFormatVcd),
                  (ExportFormat.saif, l10n.exportDialogFormatSaif),
                  (ExportFormat.png, l10n.exportDialogFormatPng),
                  (ExportFormat.svg, l10n.exportDialogFormatSvg),
                ],
                onChanged: (v) => setState(() => _format = v),
              ),
              const SizedBox(height: 12),
              _SectionLabel(l10n.exportDialogTimeRangeSection),
              _RadioGroup<ExportTimeRange>(
                enabled: rangeSelectable,
                value: _timeRange,
                options: [
                  (ExportTimeRange.visible, l10n.exportDialogTimeRangeVisible),
                  (ExportTimeRange.full, l10n.exportDialogTimeRangeFull),
                ],
                onChanged: (v) => setState(() => _timeRange = v),
              ),
              const SizedBox(height: 12),
              _SectionLabel(l10n.exportDialogSignalsSection),
              _RadioGroup<ExportSignals>(
                enabled: rangeSelectable,
                value: _signals,
                options: [
                  (ExportSignals.visible, l10n.exportDialogSignalsVisible),
                  (ExportSignals.all, l10n.exportDialogSignalsAll),
                ],
                onChanged: (v) => setState(() => _signals = v),
              ),
              if (showResolution) ...[
                const SizedBox(height: 12),
                _SectionLabel(l10n.exportDialogResolutionSection),
                _RadioGroup<double>(
                  value: _pixelRatio,
                  options: [
                    (1.0, l10n.exportDialogResolution1x),
                    (2.0, l10n.exportDialogResolution2x),
                    (3.0, l10n.exportDialogResolution3x),
                  ],
                  onChanged: (v) => setState(() => _pixelRatio = v),
                ),
              ],
              if (!rangeSelectable)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.exportDialogImageIsWhatYouSee,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (isImage) ...[
                const SizedBox(height: 4),
                CheckboxListTile(
                  value: _includeAnnotations,
                  onChanged: (v) =>
                      setState(() => _includeAnnotations = v ?? true),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l10n.exportDialogIncludeAnnotations),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            l10n.exportDialogCancel,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            ExportDialogResult(
              includeAnnotations: _includeAnnotations,
              format: _format,
              timeRange: _timeRange,
              signals: _signals,
              pixelRatio: _pixelRatio,
            ),
          ),
          child: Text(l10n.exportDialogExport),
        ),
      ],
    );
  }
}

// ── Private helpers ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _RadioGroup<T> extends StatelessWidget {
  const _RadioGroup({
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  /// When false the options render greyed and inert — used where a format
  /// cannot honour them, rather than accepting a choice and ignoring it.
  final bool enabled;

  @override
  Widget build(BuildContext context) => RadioGroup<T>(
    groupValue: value,
    onChanged: (v) {
      if (v != null && enabled) onChanged(v);
    },
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (optValue, label) in options)
          RadioListTile<T>(
            value: optValue,
            enabled: enabled,
            title: Text(label, style: const TextStyle(fontSize: 13)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
      ],
    ),
  );
}
