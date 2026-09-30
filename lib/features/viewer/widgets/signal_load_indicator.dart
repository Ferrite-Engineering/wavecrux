// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/features/viewer/providers/signal_load_progress_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Status-bar indicator for an in-flight bulk signal load.
///
/// Renders nothing while idle (so the slot is weightless), and a compact
/// determinate progress bar + `loaded/total` count + cancel button while the
/// canvas is decompressing a large batch of signals (e.g. "Add All in Scope"
/// on a wide scope, or scrolling a large file). Gives the user a clear "work
/// is happening" signal — and a way to abort — instead of the app appearing
/// hung while hundreds of waveforms paint in.
class SignalLoadIndicator extends ConsumerWidget {
  const SignalLoadIndicator({super.key});

  /// Width of the inline progress bar, in logical pixels.
  static const double _barWidth = 90;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(signalLoadProgressProvider);
    if (!progress.active) return const SizedBox.shrink();

    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);
    final notifier = ref.read(signalLoadProgressProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: progress.phase == SignalLoadPhase.adding
                ? l10n.signalAddIndicatorLabel
                : l10n.signalLoadIndicatorLabel,
            child: SizedBox(
              width: _barWidth,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  // During the adding-phase hold (entry list built, heavy
                  // materialization frame in flight) the count sits at
                  // total/total; a static full bar reads as a hang, so switch
                  // to indeterminate to signal live work.
                  value:
                      progress.phase == SignalLoadPhase.adding &&
                          progress.loaded >= progress.total
                      ? null
                      : progress.fraction,
                  minHeight: 4,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
          ),
          // No count until the batch has a size (see beginIndeterminate):
          // "0/0" would read as "nothing to do".
          if (progress.total > 0) ...[
            const SizedBox(width: 6),
            Text(
              l10n.signalLoadIndicatorProgress(progress.loaded, progress.total),
              style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
                fontSize: metrics.statusBarText,
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          const SizedBox(width: 2),
          Tooltip(
            message: l10n.signalLoadIndicatorCancelTooltip,
            child: IconButton(
              key: const Key('signalLoadCancelButton'),
              icon: const Icon(Icons.close, size: 14),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              onPressed: notifier.requestCancel,
            ),
          ),
        ],
      ),
    );
  }
}
