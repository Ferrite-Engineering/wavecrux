// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/features/viewer/providers/unresolved_bindings_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/session/binding_paths.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Non-modal in-flow banner naming the decoder and Stage bindings a session
/// restore or reload could not find in the waveform.
///
/// A binding is saved with its signal's hierarchical path; when a regenerated
/// dump no longer has that path, the binding is left empty (and keeps its path,
/// so it binds again when the signal returns). Without this notice a decoder
/// would simply go quiet. Driven by the per-tab [unresolvedBindingsProvider];
/// renders [SizedBox.shrink] when there is nothing to report, so the viewer
/// drops it into its banner column unconditionally, as it does
/// `LegacyFormatBanner`.
class UnresolvedBindingsBanner extends ConsumerWidget {
  const UnresolvedBindingsBanner({super.key});

  /// How many missing paths are spelled out before the rest are counted.
  @visibleForTesting
  static const int maxListedPaths = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unresolved = ref.watch(unresolvedBindingsProvider);
    if (unresolved.isEmpty) return const SizedBox.shrink();

    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final metrics = MobileMetrics.of(context, ref.watch(deviceClassProvider));

    return MaterialBanner(
      key: const Key('unresolvedBindingsBanner'),
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      leading: Icon(
        Icons.link_off,
        color: theme.colorScheme.error,
      ),
      content: Text(
        l10n.unresolvedBindingsBannerMessage(
          unresolved.length,
          listedPaths(l10n, unresolved),
        ),
      ),
      actions: [
        ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: metrics.touchTarget,
            minHeight: metrics.touchTarget,
          ),
          child: TextButton(
            key: const Key('unresolvedBindingsBannerDismissButton'),
            onPressed: () =>
                ref.read(unresolvedBindingsProvider.notifier).clear(),
            child: Text(l10n.unresolvedBindingsBannerDismiss),
          ),
        ),
      ],
    );
  }

  /// The distinct missing paths, comma-separated, with any beyond
  /// [maxListedPaths] counted rather than listed.
  @visibleForTesting
  static String listedPaths(L10N l10n, List<UnresolvedBinding> unresolved) {
    final paths = {for (final u in unresolved) u.path}.toList();
    if (paths.length <= maxListedPaths) return paths.join(', ');
    final rest = paths.length - maxListedPaths;
    return [
      ...paths.take(maxListedPaths),
      l10n.unresolvedBindingsBannerMore(rest),
    ].join(', ');
  }
}
