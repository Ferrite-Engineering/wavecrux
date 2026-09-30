// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// Floating chip rendered under the cursor while a signal is being
/// dragged onto a Stage widget. Used as the `feedback` for both the
/// signal-tree leaf drag (untriaged signal universe) and the
/// signal-list-panel row drag (signals already in the waveform
/// viewer).
///
/// Carries the full hierarchical path so the user sees what they're
/// about to drop, not just the truncated display name.
class SignalDragChip extends StatelessWidget {
  const SignalDragChip({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(4),
      color: theme.colorScheme.primaryContainer,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.drag_indicator,
                size: 14,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'JetBrainsMono',
                    fontFamilyFallback: const [
                      'FiraCode',
                      'Courier New',
                      'monospace',
                    ],
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
