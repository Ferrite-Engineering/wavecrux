// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:wavecrux/domain/enums/log_verbosity.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/logging/log_verbosity_level.dart';

/// Live view of the in-memory log ring buffer ([CruxIssueReporterLogBuffer]),
/// embedded as a section in the App Diagnostics dialog (process-wide,
/// tablet/desktop only).
///
/// Auto-updates as records arrive (the buffer is a [Listenable]). A level
/// filter (defaulting to the user's "Log verbosity" setting) governs which
/// entries show; the ring buffer itself always holds every level. Copy and
/// clear actions mirror the existing diagnostics-report patterns.
class LogsPanel extends ConsumerStatefulWidget {
  /// Creates the panel. [height] bounds the internal scroll area so the panel
  /// fits inside the (already scrollable) App Diagnostics dialog.
  const LogsPanel({this.height = 220, super.key});

  /// Height of the scrollable log list.
  final double height;

  @override
  ConsumerState<LogsPanel> createState() => _LogsPanelState();
}

class _LogsPanelState extends ConsumerState<LogsPanel> {
  /// Panel-local filter; initialized lazily from the persisted setting.
  LogVerbosity? _filter;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final buffer = ref.watch(cruxIssueReporterLogBufferProvider);
    final settingVerbosity = ref.watch(
      appSettingsProvider.select(
        (s) => s.value?.logVerbosity ?? LogVerbosity.normal,
      ),
    );
    final filter = _filter ?? settingVerbosity;
    final threshold = filter.threshold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            DropdownButton<LogVerbosity>(
              key: const Key('logsPanelLevelFilter'),
              value: filter,
              isDense: true,
              items: [
                for (final v in LogVerbosity.values)
                  DropdownMenuItem(
                    value: v,
                    child: Text(_verbosityLabel(v, l10n)),
                  ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _filter = v);
              },
            ),
            const Spacer(),
            IconButton(
              key: const Key('logsPanelCopy'),
              icon: const Icon(Icons.copy_all_outlined),
              tooltip: l10n.logsPanelCopy,
              onPressed: () => _copy(context, buffer, threshold, l10n),
            ),
            IconButton(
              key: const Key('logsPanelClear'),
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: l10n.logsPanelClear,
              onPressed: buffer.clear,
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: widget.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: ListenableBuilder(
              listenable: buffer,
              builder: (context, _) {
                final visible = buffer.entries
                    .where((e) => e.level >= threshold)
                    .toList()
                    .reversed
                    .toList(growable: false);
                if (visible.isEmpty) {
                  return Center(
                    child: Text(
                      l10n.logsPanelEmpty,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return Scrollbar(
                  child: ListView.builder(
                    key: const Key('logsPanelList'),
                    padding: const EdgeInsets.all(8),
                    itemCount: visible.length,
                    itemBuilder: (context, i) =>
                        _LogLine(entry: visible[i], theme: theme),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copy(
    BuildContext context,
    CruxIssueReporterLogBuffer buffer,
    Level threshold,
    L10N l10n,
  ) async {
    final lines = buffer.entries
        .where((e) => e.level >= threshold)
        .map(
          (e) =>
              '[${e.timestamp.toIso8601String()}] ${e.level.name} '
              '${e.loggerName.isEmpty ? 'root' : e.loggerName}: ${e.message}',
        )
        .join('\n');
    await Clipboard.setData(ClipboardData(text: lines));
    if (!context.mounted) return;
    showCruxInfoSnack(context, l10n.logsPanelCopied);
  }

  String _verbosityLabel(LogVerbosity v, L10N l10n) => switch (v) {
    LogVerbosity.quiet => l10n.logVerbosityQuiet,
    LogVerbosity.normal => l10n.logVerbosityNormal,
    LogVerbosity.detailed => l10n.logVerbosityDetailed,
    LogVerbosity.verbose => l10n.logVerbosityVerbose,
  };
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry, required this.theme});

  final CruxIssueLogEntry entry;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      final l when l >= Level.SEVERE => theme.colorScheme.error,
      final l when l >= Level.WARNING => Colors.amber.shade800,
      final l when l >= Level.INFO => theme.colorScheme.onSurface,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    final t = entry.timestamp;
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    final logger = entry.loggerName.isEmpty ? 'root' : entry.loggerName;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText(
        '$stamp ${entry.level.name} $logger: ${entry.message}',
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.35,
          color: color,
        ),
      ),
    );
  }
}
