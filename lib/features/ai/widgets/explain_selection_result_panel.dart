// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/ai/providers/explain_selection_provider.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/ai/explain_selection.dart';
import 'package:wavecrux/shared/widgets/experimental_chip.dart';

/// Bottom-pane result panel for the open-core **Explain Selection** feature.
///
/// Renders the model's explanation as flowing text with inline, clickable
/// citation chips. A citation that grounds to a real coordinate jumps the
/// cursor (and selects the signal) on tap; a citation that does not resolve
/// renders as a non-clickable "could not locate" chip — never a wrong jump.
/// The header carries the [ExperimentalChip] (not a tier badge).
class ExplainSelectionResultPanel extends ConsumerWidget {
  /// Creates the Explain Selection result panel.
  const ExplainSelectionResultPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final state = ref.watch(explainSelectionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(),
        const Divider(height: 1),
        Expanded(child: _body(context, l10n, state)),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    L10N l10n,
    ExplainSelectionState state,
  ) {
    switch (state.phase) {
      case ExplainSelectionPhase.loading:
        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(l10n.explainSelectionInProgress),
            ],
          ),
        );
      case ExplainSelectionPhase.emptySelection:
        return _message(context, l10n.explainSelectionEmptySelection);
      case ExplainSelectionPhase.notConfigured:
        return _message(context, l10n.explainSelectionNoModelConfigured);
      case ExplainSelectionPhase.error:
        return _message(context, l10n.explainSelectionModelUnavailable);
      case ExplainSelectionPhase.idle:
        return const SizedBox.shrink();
      case ExplainSelectionPhase.ready:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text.rich(
            TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: [
                for (final segment in state.segments)
                  if (segment is ExplainText)
                    TextSpan(text: segment.text)
                  else
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: _CitationChip(
                        citation: segment as ExplainCitation,
                      ),
                    ),
              ],
            ),
          ),
        );
    }
  }

  Widget _message(BuildContext context, String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

class _Header extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Flexible(
            child: Text(
              l10n.explainSelectionPanelTitle,
              style: Theme.of(context).textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          const ExperimentalChip(),
          // No header ×: the panel is a bottom-dock tab and the tab's ×
          // calls the same notifier.close() this button used to.
        ],
      ),
    );
  }
}

/// An inline citation affordance. Resolves the cited coordinate against the
/// loaded trace; clickable + cursor-jumping when it grounds, a muted
/// "could not locate" marker when it does not.
class _CitationChip extends ConsumerWidget {
  const _CitationChip({required this.citation});

  final ExplainCitation citation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final scheme = Theme.of(context).colorScheme;
    final resolution = resolveExplainCitation(
      citation,
      source: ref.watch(waveformSourceProvider).value,
      variablesByRef: ref.watch(signalVariablesMapProvider),
      decoders: ref.watch(activeDecodersProvider),
    );

    if (!resolution.resolved) {
      return Tooltip(
        message: citation.raw,
        child: _chip(
          context,
          key: const Key('explainCitationUnresolved'),
          label: l10n.explainSelectionCouldNotLocate,
          icon: Icons.error_outline,
          background: scheme.errorContainer,
          foreground: scheme.onErrorContainer,
        ),
      );
    }

    return _chip(
      context,
      key: const Key('explainCitationResolved'),
      label: _label(resolution),
      icon: Icons.my_location,
      background: scheme.secondaryContainer,
      foreground: scheme.onSecondaryContainer,
      onTap: () {
        final time = resolution.time;
        if (time != null) {
          ref.read(cursorStateProvider.notifier).placePrimary(time);
        }
        // Selection is keyed by fullPath (row identity), so highlight the
        // resolved row via its path rather than its (possibly aliased) ref.
        final signalPath = resolution.signalPath;
        if (signalPath != null) {
          ref.read(selectedVariablesProvider.notifier).selectOnly(signalPath);
        }
      },
    );
  }

  String _label(ExplainCitationResolution r) {
    if (r.signalPath != null && r.time != null) {
      return '${r.signalPath} @ ${r.time}';
    }
    if (r.signalPath != null) return r.signalPath!;
    return '${r.time}';
  }

  Widget _chip(
    BuildContext context, {
    required Key key,
    required String label,
    required IconData icon,
    required Color background,
    required Color foreground,
    VoidCallback? onTap,
  }) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: foreground,
              fontFeatures: const [],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return KeyedSubtree(key: key, child: content);
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: content,
    );
  }
}
