// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/help_urls.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/help_link.dart';

/// Compact toolbar rendered above the waveform canvas when diff mode is active.
///
/// Shows the comparison filename, close button, and prev/next divergence
/// navigation with a "Divergence N of M" counter.
///
/// The toolbar hides itself automatically when [DiffNotifier] is idle
/// (no comparison file loaded).
class DiffToolbar extends ConsumerWidget {
  const DiffToolbar({
    required this.onCompareWith,
    this.onClose,
    this.onPrevDivergence,
    this.onNextDivergence,
    super.key,
  });

  /// Called when the user taps "Compare with…" or the filename chip.
  final VoidCallback onCompareWith;

  /// Called when the user taps the close button. Defaults to [DiffNotifier.clearDiff].
  final VoidCallback? onClose;

  /// Called when the user taps "← Prev".  Null to use [DiffNotifier.prevDivergence].
  final VoidCallback? onPrevDivergence;

  /// Called when the user taps "Next →". Null to use [DiffNotifier.nextDivergence].
  final VoidCallback? onNextDivergence;

  static const double height = 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final diff = ref.watch(diffProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.outlineVariant;
    final notifier = ref.read(diffProvider.notifier);

    final hasDivergences = diff.totalDivergences > 0;
    final divergenceLabel = hasDivergences
        ? l10n.diffToolbarDivergenceOf(
            diff.divergenceIndex.clamp(0, diff.totalDivergences - 1) + 1,
            diff.totalDivergences,
          )
        : l10n.diffToolbarNoDivergences;

    // Filename shown in the file chip.
    final filename = diff.secondFilePath != null
        ? _basename(diff.secondFilePath!)
        : null;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: borderColor),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 6),

          // ── compare / file chip ──────────────────────────────────────────
          if (diff.isActive && filename != null) ...[
            Icon(
              Icons.compare,
              size: 13,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                l10n.diffToolbarComparingFile(filename),
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurface,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else ...[
            TextButton.icon(
              onPressed: onCompareWith,
              icon: const Icon(Icons.compare, size: 13),
              label: Text(
                l10n.diffToolbarCompareWith,
                style: const TextStyle(fontSize: 11),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],

          const SizedBox(width: 4),
          HelpLink(
            url: HelpUrls.diff,
            tooltip: l10n.helpLinkDiffInfo,
          ),

          const Spacer(),

          // ── loading indicator ────────────────────────────────────────────
          if (diff.isLoading) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 6),
          ],

          // ── divergence navigation ────────────────────────────────────────
          if (diff.isActive && !diff.isLoading) ...[
            Tooltip(
              message: l10n.diffToolbarPrevDivergenceTooltip,
              child: IconButton(
                icon: const Icon(Icons.chevron_left, size: 16),
                onPressed: hasDivergences
                    ? (onPrevDivergence ?? notifier.prevDivergence)
                    : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                splashRadius: 14,
              ),
            ),
            Text(
              divergenceLabel,
              style: TextStyle(
                fontSize: 11,
                color: hasDivergences
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            Tooltip(
              message: l10n.diffToolbarNextDivergenceTooltip,
              child: IconButton(
                icon: const Icon(Icons.chevron_right, size: 16),
                onPressed: hasDivergences
                    ? (onNextDivergence ?? notifier.nextDivergence)
                    : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                splashRadius: 14,
              ),
            ),
            const SizedBox(width: 4),
          ],

          // ── close button ─────────────────────────────────────────────────
          if (diff.isActive) ...[
            Tooltip(
              message: l10n.diffToolbarClose,
              child: IconButton(
                icon: const Icon(Icons.close, size: 14),
                onPressed: onClose ?? notifier.clearDiff,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                splashRadius: 12,
              ),
            ),
          ],

          const SizedBox(width: 4),
        ],
      ),
    );
  }

  static String _basename(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }
}
