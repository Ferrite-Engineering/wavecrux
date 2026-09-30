// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/signal_integrity_report.dart';
import 'package:wavecrux/features/diagnostics/providers/signal_integrity_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Diagnostics tab that runs signal integrity checks over the loaded waveform.
///
/// Shows a "Run Analysis" button in the initial state, a progress indicator
/// while the analysis is running, and grouped [ExpansionTile] results once
/// complete.  Each group is colour-coded: problem groups (constant, X/Z-only,
/// glitch, stuck-at-reset) show an amber badge when issues are found and green
/// when none are found; the detected-clocks group uses blue as it is
/// informational rather than a warning.
class SignalHealthPanel extends ConsumerWidget {
  const SignalHealthPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final analysisState = ref.watch(signalIntegrityProvider);
    final hasFile = ref.watch(waveformSourceProvider).value != null;

    return analysisState.when(
      // Hosted inside the Tab Diagnostics drawer's outer scroll, which gives
      // the empty state unbounded vertical space — CruxPanelEmptyState's
      // Center shrink-wraps to its child under unbounded constraints, so
      // layout stays bounded vertically.
      data: (report) => report == null
          ? CruxPanelEmptyState(
              message: l10n.diagnosticsHealthEmpty,
              action: Tooltip(
                message: hasFile ? '' : l10n.diagnosticsHealthDisabledNoFile,
                child: ElevatedButton(
                  onPressed: hasFile
                      ? () => ref
                            .read(signalIntegrityProvider.notifier)
                            .runAnalysis()
                      : null,
                  child: Text(l10n.diagnosticsHealthRunButton),
                ),
              ),
            )
          : _ResultsView(report: report, hasFile: hasFile),
      loading: () => _LoadingState(l10n: l10n),
      error: (e, _) => _ErrorState(error: e.toString()),
    );
  }
}

// ── Loading state ─────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.l10n});

  final L10N l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(l10n.diagnosticsHealthRunning),
        ],
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        error,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Results view ──────────────────────────────────────────────────────────────

class _ResultsView extends ConsumerWidget {
  const _ResultsView({required this.report, required this.hasFile});

  final SignalIntegrityReport report;
  final bool hasFile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final timeStr = report.analysisTimeMs.toStringAsFixed(1);

    // Hosted inside the Tab Diagnostics drawer's outer SingleChildScrollView,
    // so this panel renders its full content vertically without an inner
    // scroll wrapper — nesting two vertical viewports would give this
    // panel's scroll an unbounded height.
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Summary card ───────────────────────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.diagnosticsHealthSummary(
                        report.signalsAnalyzed.toString(),
                        timeStr,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Tooltip(
                    message: hasFile
                        ? ''
                        : l10n.diagnosticsHealthDisabledNoFile,
                    child: TextButton(
                      onPressed: hasFile
                          ? () => ref
                                .read(signalIntegrityProvider.notifier)
                                .runAnalysis()
                          : null,
                      child: Text(l10n.diagnosticsHealthRunButton),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Constant signals ───────────────────────────────────────────────
          _SignalGroup(
            title: l10n.diagnosticsHealthConstant,
            count: report.constantSignalPaths.length,
            paths: report.constantSignalPaths,
            badgeIsWarning: true,
          ),
          const SizedBox(height: 8),

          // ── X/Z-only signals ───────────────────────────────────────────────
          _SignalGroup(
            title: l10n.diagnosticsHealthXzOnly,
            count: report.xzOnlySignalPaths.length,
            paths: report.xzOnlySignalPaths,
            badgeIsWarning: true,
          ),
          const SizedBox(height: 8),

          // ── Glitch signals ─────────────────────────────────────────────────
          _GlitchGroup(
            title: l10n.diagnosticsHealthGlitches,
            glitchSignals: report.glitchSignals,
          ),
          const SizedBox(height: 8),

          // ── Detected clocks ────────────────────────────────────────────────
          _ClocksGroup(
            title: l10n.diagnosticsHealthClocks,
            clocks: report.detectedClocks,
            l10n: l10n,
          ),
          const SizedBox(height: 8),

          // ── Stuck-at-reset ─────────────────────────────────────────────────
          _SignalGroup(
            title: l10n.diagnosticsHealthStuckReset,
            count: report.stuckAtResetPaths.length,
            paths: report.stuckAtResetPaths,
            badgeIsWarning: true,
          ),
        ],
      ),
    );
  }
}

// ── Reusable group tiles ──────────────────────────────────────────────────────

/// [ExpansionTile] showing a flat list of signal paths.
class _SignalGroup extends StatelessWidget {
  const _SignalGroup({
    required this.title,
    required this.count,
    required this.paths,
    required this.badgeIsWarning,
  });

  final String title;
  final int count;
  final List<String> paths;
  final bool badgeIsWarning;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final hasIssues = count > 0;
    final badgeColor = badgeIsWarning
        ? (hasIssues ? Colors.amber.shade700 : Colors.green.shade600)
        : Colors.blue.shade400;

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: _CountBadge(count: count, color: badgeColor),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        children: [
          if (paths.isEmpty)
            _NoneFoundTile(l10n: l10n)
          else
            ...paths.map((p) => _PathTile(path: p)),
        ],
      ),
    );
  }
}

/// [ExpansionTile] for glitch signals, which include per-signal counts.
class _GlitchGroup extends StatelessWidget {
  const _GlitchGroup({
    required this.title,
    required this.glitchSignals,
  });

  final String title;
  final Map<String, int> glitchSignals;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final count = glitchSignals.length;
    final hasIssues = count > 0;
    final badgeColor = hasIssues
        ? Colors.amber.shade700
        : Colors.green.shade600;

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: _CountBadge(count: count, color: badgeColor),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        children: [
          if (glitchSignals.isEmpty)
            _NoneFoundTile(l10n: l10n)
          else
            ...glitchSignals.entries.map(
              (e) => _PathTile(
                path: e.key,
                trailing: '×${e.value}',
              ),
            ),
        ],
      ),
    );
  }
}

/// [ExpansionTile] for detected clocks with frequency and duty-cycle details.
class _ClocksGroup extends StatelessWidget {
  const _ClocksGroup({
    required this.title,
    required this.clocks,
    required this.l10n,
  });

  final String title;
  final List<ClockInfo> clocks;
  final L10N l10n;

  @override
  Widget build(BuildContext context) {
    const badgeColor = Colors.blue;

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: _CountBadge(count: clocks.length, color: badgeColor),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        children: [
          if (clocks.isEmpty)
            _NoneFoundTile(l10n: l10n)
          else
            ...clocks.map(
              (c) => ListTile(
                dense: true,
                title: SelectableText(
                  c.signalPath,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.diagnosticsHealthClockFreq(c.estimatedFrequency),
                      style: const TextStyle(fontSize: 11),
                    ),
                    Text(
                      l10n.diagnosticsHealthClockDuty(
                        c.dutyCyclePercent.toStringAsFixed(1),
                      ),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Small shared helpers ──────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PathTile extends StatelessWidget {
  const _PathTile({required this.path, this.trailing});

  final String path;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: SelectableText(
        path,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
      trailing: trailing != null
          ? Text(
              trailing!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
  }
}

class _NoneFoundTile extends StatelessWidget {
  const _NoneFoundTile({required this.l10n});

  final L10N l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        l10n.diagnosticsHealthNoneFound,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
