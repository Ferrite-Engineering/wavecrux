// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_panel.dart';
import 'package:wavecrux/features/viewer/providers/switching_activity_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Wraps [SignalTreePanel] with a visual indicator when heatmap mode is active.
///
/// When switching activity analysis is active, a thin colored bar appears at
/// the top of the panel indicating heat mode.  The per-row background coloring
/// is applied directly inside [VariableTreeLeaf] by reading
/// [switchingActivityProvider].
class ActivityHeatmapOverlay extends ConsumerWidget {
  const ActivityHeatmapOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = ref.watch(
      switchingActivityProvider.select((s) => s.isActive),
    );

    if (!isActive) return const SignalTreePanel();

    return Column(
      children: [
        _HeatBanner(
          onClear: () => ref.read(switchingActivityProvider.notifier).clear(),
        ),
        const Expanded(child: SignalTreePanel()),
      ],
    );
  }
}

// ── _HeatBanner ───────────────────────────────────────────────────────────────

class _HeatBanner extends StatelessWidget {
  const _HeatBanner({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = L10N.of(context);
    return Container(
      height: 20,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.withValues(alpha: 0.55),
            Colors.red.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 6),
          Icon(Icons.bolt, size: 11, color: colorScheme.onSurface),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              l10n.activityPanelTitle,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          InkWell(
            onTap: onClear,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.close, size: 11, color: colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
