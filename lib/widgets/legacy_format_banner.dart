// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/domain/enums/waveform_format.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform/legacy_conversion_controller.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Non-modal in-flow banner that announces a fresh LXT/LXT2 → FST
/// conversion.
///
/// Drives off [legacyConversionEventProvider] (set by the open path the
/// instant the converter completes successfully on a non-cache-hit open)
/// combined with the active tab's [waveformSourceProvider] state — the
/// banner stays visible while the tab continues to show the converted file
/// and disappears when the tab closes or switches to a different file
/// (handled by the consumer of this widget — typically the viewer screen).
///
/// Dismissed states:
///  * **Don't show again** — persists `suppressLegacyFormatBanner = true` so
///    subsequent legacy opens skip the banner unconditionally.
///  * **Dismiss** — local hide only (clears the active event sink so the
///    banner closes for this tab, but does not flip the persistent flag).
///
/// Render strategy: the widget itself returns [SizedBox.shrink] when the
/// suppress flag is on, when no fresh event has been emitted, or when the
/// user has dismissed the current event. Hosts can drop it into a Column /
/// SafeArea above the waveform canvas without any conditional wrapping.
class LegacyFormatBanner extends ConsumerWidget {
  const LegacyFormatBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings();
    if (settings.suppressLegacyFormatBanner) return const SizedBox.shrink();

    final event = ref.watch(legacyConversionEventProvider);
    if (event == null) return const SizedBox.shrink();

    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);

    return _LegacyFormatBannerContent(
      event: event,
      metrics: metrics,
      l10n: l10n,
    );
  }
}

class _LegacyFormatBannerContent extends ConsumerWidget {
  const _LegacyFormatBannerContent({
    required this.event,
    required this.metrics,
    required this.l10n,
  });

  final LegacyConversionEvent event;
  final MobileMetrics metrics;
  final L10N l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final originLabel = _originLabel(event.origin);
    final message = l10n.legacyFormatBannerMessage(originLabel, event.fstPath);
    final theme = Theme.of(context);

    return MaterialBanner(
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      content: Text(message),
      leading: Icon(
        Icons.info_outline,
        color: theme.colorScheme.primary,
      ),
      actions: [
        ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: metrics.touchTarget,
            minHeight: metrics.touchTarget,
          ),
          child: TextButton(
            key: const Key('legacyFormatBannerDontShowAgainButton'),
            onPressed: () async {
              await ref
                  .read(appSettingsProvider.notifier)
                  .setSuppressLegacyFormatBanner(suppressed: true);
              ref.read(legacyConversionEventProvider.notifier).clear();
            },
            child: Text(l10n.legacyFormatBannerDontShowAgain),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: metrics.touchTarget,
            minHeight: metrics.touchTarget,
          ),
          child: TextButton(
            key: const Key('legacyFormatBannerDismissButton'),
            onPressed: () {
              ref.read(legacyConversionEventProvider.notifier).clear();
            },
            child: Text(l10n.legacyFormatBannerDismiss),
          ),
        ),
      ],
    );
  }

  /// File-format acronyms are not localized.
  static String _originLabel(WaveformFormat origin) {
    if (origin == WaveformFormat.lxt) return 'LXT';
    if (origin == WaveformFormat.lxt2) return 'LXT2';
    return origin.name.toUpperCase();
  }
}
