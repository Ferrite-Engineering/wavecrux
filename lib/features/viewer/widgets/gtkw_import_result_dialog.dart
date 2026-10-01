// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/session/gtkw_import_service.dart';

/// Dialog shown after a GTKWave `.gtkw` session import completes.
///
/// Displays a summary of imported signals, groups, and markers, and lists any
/// signal paths from the `.gtkw` file that could not be matched to a variable
/// in the currently loaded waveform, then any filters it names that were not
/// applied (a filter file that was not found, or a filter process).
class GtkwImportResultDialog extends StatelessWidget {
  const GtkwImportResultDialog({required this.result, super.key});

  final GtkwImportResult result;

  /// Shows this dialog as a modal and returns when the user dismisses it.
  static Future<void> show(
    BuildContext context, {
    required GtkwImportResult result,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => GtkwImportResultDialog(result: result),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);

    return AlertDialog(
      title: Text(l10n.gtkwImportDialogTitle),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SummaryRow(
              icon: Icons.signal_cellular_alt,
              label: l10n.gtkwImportSignalsMatched(result.matchedSignalCount),
            ),
            const SizedBox(height: 4),
            _SummaryRow(
              icon: Icons.folder_outlined,
              label: l10n.gtkwImportGroupCount(result.groupCount),
            ),
            const SizedBox(height: 4),
            _SummaryRow(
              icon: Icons.flag_outlined,
              label: l10n.gtkwImportMarkerCount(result.markerCount),
            ),
            if (result.hasUnmatchedSignals) ...[
              const SizedBox(height: 16),
              _IssueList(
                header: l10n.gtkwImportUnmatchedHeader(
                  result.unmatchedSignalPaths.length,
                ),
                rows: result.unmatchedSignalPaths,
              ),
            ],
            if (result.hasFilterIssues) ...[
              const SizedBox(height: 16),
              _IssueList(
                header: l10n.gtkwImportFilterIssuesHeader(
                  result.filterIssues.length,
                ),
                rows: [
                  for (final issue in result.filterIssues)
                    _filterIssueText(l10n, issue),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.gtkwImportClose),
        ),
      ],
    );
  }
}

String _filterIssueText(L10N l10n, GtkwFilterIssue issue) =>
    switch (issue.kind) {
      GtkwFilterIssueKind.missingFile => l10n.gtkwImportFilterMissing(
        issue.signalPath,
        issue.filterPath,
      ),
      GtkwFilterIssueKind.process => l10n.gtkwImportFilterProcess(
        issue.signalPath,
        issue.filterPath,
      ),
      GtkwFilterIssueKind.transaction => l10n.gtkwImportFilterTransaction(
        issue.signalPath,
        issue.filterPath,
      ),
    };

/// A header in the error color over a scrolling list of monospace rows: the
/// parts of a `.gtkw` the import could not bring across.
class _IssueList extends StatelessWidget {
  const _IssueList({required this.header, required this.rows});

  final String header;
  final List<String> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          header,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: Scrollbar(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: rows.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  rows[i],
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A single summary row with an icon and a text label.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}
