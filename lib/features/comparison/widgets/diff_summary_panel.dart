// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/signal_match.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Panel showing the summary of a waveform diff comparison.
///
/// Displays matched-signal counts (identical / different / unmatched) and a
/// scrollable signal list where tapping a differing signal jumps the cursor to
/// its first divergence time.
///
/// Shown in the left sidebar when diff mode is active.
class DiffSummaryPanel extends ConsumerWidget {
  const DiffSummaryPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final diff = ref.watch(diffProvider);

    if (diff.isLoading) {
      return _buildCentered(
        context,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              l10n.diffSummaryLoading,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (diff.error != null) {
      return _buildCentered(
        context,
        Text(
          l10n.diffLoadError(diff.error!),
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }

    final result = diff.diffResult;
    if (result == null) {
      return _buildCentered(
        context,
        Text(
          l10n.diffSummaryNoFile,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final summary = result.summary;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── summary chips ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: colorScheme.surfaceContainerHighest,
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _SummaryChip(
                label: l10n.diffSummaryIdentical(summary.identicalCount),
                color: Colors.green,
              ),
              _SummaryChip(
                label: l10n.diffSummaryDifferent(summary.differentCount),
                color: colorScheme.error,
              ),
              if (summary.aOnlyCount > 0)
                _SummaryChip(
                  label: l10n.diffSummaryOnlyInA(summary.aOnlyCount),
                  color: colorScheme.onSurfaceVariant,
                ),
              if (summary.bOnlyCount > 0)
                _SummaryChip(
                  label: l10n.diffSummaryOnlyInB(summary.bOnlyCount),
                  color: colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
        // ── matched signal list ────────────────────────────────────────────
        Expanded(
          child: ListView(
            children: [
              if (result.matchedSignals.isNotEmpty) ...[
                _SectionHeader(label: l10n.diffSummaryMatchedSignals),
                ...result.matchedSignals.map(
                  (match) => _SignalMatchTile(match: match),
                ),
              ],
              if (result.unmatchedA.isNotEmpty ||
                  result.unmatchedB.isNotEmpty) ...[
                _SectionHeader(label: l10n.diffSummaryUnmatched),
                ...result.unmatchedA.map(
                  (path) => _UnmatchedTile(path: path, fromFileA: true),
                ),
                ...result.unmatchedB.map(
                  (path) => _UnmatchedTile(path: path, fromFileA: false),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCentered(BuildContext context, Widget child) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
}

// ── _SummaryChip ──────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
    ),
  );
}

// ── _SectionHeader ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.8,
      ),
    ),
  );
}

// ── _SignalMatchTile ──────────────────────────────────────────────────────────

/// A single row in the matched-signal list.
///
/// Tapping a row that is [SignalMatch.isDifferent] jumps the primary cursor to
/// [SignalMatch.firstDivergenceTime] via [DiffNotifier].
class _SignalMatchTile extends ConsumerWidget {
  const _SignalMatchTile({required this.match});

  final SignalMatch match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDifferent = match.isDifferent;
    final iconColor = isDifferent ? colorScheme.error : Colors.green;
    final icon = isDifferent ? Icons.close : Icons.check;

    return InkWell(
      onTap: isDifferent ? () => _jumpToFirstDivergence(ref, match) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          children: [
            Icon(icon, size: 12, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                match.pathA,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: isDifferent
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isDifferent && match.divergenceRegions.isNotEmpty)
              Text(
                '${match.divergenceRegions.length}',
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.error.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _jumpToFirstDivergence(WidgetRef ref, SignalMatch match) {
    final t = match.firstDivergenceTime;
    if (t == null) return;
    ref.read(cursorStateProvider.notifier).placePrimary(t);
    ref.read(navigationProvider.notifier).jumpToTime(t);
  }
}

// ── _UnmatchedTile ────────────────────────────────────────────────────────────

class _UnmatchedTile extends StatelessWidget {
  const _UnmatchedTile({required this.path, required this.fromFileA});

  final String path;
  final bool fromFileA;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: [
          Icon(
            Icons.remove,
            size: 12,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              path,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            fromFileA ? 'A' : 'B',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
