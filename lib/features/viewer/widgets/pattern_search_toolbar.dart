// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Compact toolbar shown when a pattern search result is active.
///
/// Displays the current match position label, previous/next navigation buttons,
/// and a clear button.  Hidden when there is no result and no active search.
class PatternSearchToolbar extends ConsumerWidget {
  const PatternSearchToolbar({super.key});

  static const double height = 28;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(patternSearchProvider);

    // Only show the toolbar when there is something to display.
    if (!searchState.hasResult &&
        !searchState.isSearching &&
        searchState.error == null) {
      return const SizedBox.shrink();
    }

    final l10n = L10N.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final notifier = ref.read(patternSearchProvider.notifier);
    final onSurface = colorScheme.onSecondaryContainer;

    String label;
    if (searchState.isSearching) {
      label = '…';
    } else if (searchState.noWaveform) {
      label = l10n.patternSearchNoWaveform;
    } else if (searchState.error != null) {
      label = searchState.error!;
    } else if (searchState.hasMatches) {
      label = l10n.patternSearchToolbarMatchOf(
        searchState.currentMatchIndex + 1,
        searchState.matchCount,
      );
    } else {
      label = l10n.patternSearchToolbarNoMatches;
    }

    return Container(
      height: 28,
      color: colorScheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          if (searchState.isSearching)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: onSurface,
              ),
            )
          else
            Icon(Icons.search, size: 14, color: onSurface),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (searchState.hasMatches) ...[
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up, size: 16),
              tooltip: l10n.patternSearchToolbarPrev,
              onPressed: notifier.prevMatch,
              color: onSurface,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 16),
              tooltip: l10n.patternSearchToolbarNext,
              onPressed: notifier.nextMatch,
              color: onSurface,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: l10n.patternSearchToolbarClear,
            onPressed: notifier.clearSearch,
            color: onSurface,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}
