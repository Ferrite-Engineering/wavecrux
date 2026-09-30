// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/annotations/providers/annotation_adoption_provider.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Asks what to do with the annotations a collaborative session just produced.
///
/// **Non-modal, deliberately.** A dialog thrown up the instant a meeting ends
/// lands on somebody already reaching for the next thing, and gets dismissed
/// without being read — which would make the dismissal branch, below, the one
/// that actually decides. A strip above the canvas waits instead.
///
/// **Dismissing keeps everything, and that is the whole design of this widget.**
/// Silently discarding destroys the meeting's output; silently keeping merely
/// surprises somebody; and when the user just closes the prompt we take the
/// branch that does not lose work irreversibly. A kept layer deletes with one
/// control a week later. A discarded one is gone. The ✕ is therefore *Keep all*
/// wearing a different icon, and it is labelled as much for a screen reader.
///
/// Collapses to nothing when there is no pending decision, which is every
/// moment outside the seconds after a session ends — and always, in a build
/// with no collaboration service.
class AnnotationAdoptionPrompt extends ConsumerWidget {
  const AnnotationAdoptionPrompt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(annotationAdoptionProvider);
    if (pending == null) return const SizedBox.shrink();

    final l10n = L10N.of(context);
    final scheme = Theme.of(context).colorScheme;
    final notifier = ref.read(annotationAdoptionProvider.notifier);

    String label() => l10n.annotationLayerLabel(
      l10n.annotationsPanelTitle,
      _formatDate(pending.endedAt),
      pending.participantCount,
    );

    // "Don't ask again" resolves HERE rather than in the notifier, because the
    // layer's name is localized and the notifier has no `BuildContext`. Adopted
    // on the next frame rather than during build — mutating a provider mid-build
    // is what the framework's own assertion is for.
    if (ref.watch(appSettingsProvider).value?.alwaysKeepSessionAnnotations ??
        false) {
      final adoptLabel = label();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.read(annotationAdoptionProvider) == null) return;
        notifier.keep(onlyMine: false, label: adoptLabel);
      });
      return const SizedBox.shrink();
    }

    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        // A Wrap rather than a Row: four actions plus a sentence do not fit a
        // narrow window, and a strip that clips its own Discard button is
        // worse than one two lines tall.
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Icon(Icons.sticky_note_2_outlined, size: 16, color: scheme.primary),
            const SizedBox(width: 4),
            Text(
              l10n.annotationAdoptPrompt(
                pending.count,
                pending.participantCount,
              ),
              style: const TextStyle(fontSize: 12),
            ),
            TextButton(
              key: const ValueKey('annotation-adopt-keep-all'),
              onPressed: () => notifier.keep(onlyMine: false, label: label()),
              child: Text(l10n.annotationAdoptKeepAll),
            ),
            // Absent, not greyed, when every note in the room is already
            // yours: "keep only mine" and "keep all" would be the same button
            // pressed twice.
            if (pending.mineCount != pending.count)
              TextButton(
                key: const ValueKey('annotation-adopt-keep-mine'),
                onPressed: () => notifier.keep(onlyMine: true, label: label()),
                child: Text(l10n.annotationAdoptKeepMine),
              ),
            TextButton(
              key: const ValueKey('annotation-adopt-discard'),
              onPressed: notifier.discard,
              child: Text(l10n.annotationAdoptDiscard),
            ),
            TextButton(
              key: const ValueKey('annotation-adopt-dont-ask'),
              onPressed: () {
                unawaited(
                  ref
                      .read(appSettingsProvider.notifier)
                      .setAlwaysKeepSessionAnnotations(always: true),
                );
                notifier.keep(onlyMine: false, label: label());
              },
              child: Text(l10n.annotationAdoptDontAsk),
            ),
            Semantics(
              label: l10n.annotationAdoptKeepAll,
              button: true,
              child: IconButton(
                key: const ValueKey('annotation-adopt-dismiss'),
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close),
                // Dismiss is Keep all. See the class doc — this is the one
                // branch that must not be changed casually.
                onPressed: () => notifier.dismiss(label: label()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `YYYY-MM-DD`, deliberately not localized.
  ///
  /// The label is written into a `.wavecrux` document that travels — in a share
  /// bundle, to a colleague, into a repository — so it has to read the same to
  /// whoever opens it. A layer named in the author's locale and read in
  /// somebody else's is a group nobody can search for.
  static String _formatDate(DateTime when) =>
      '${when.year.toString().padLeft(4, '0')}-'
      '${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';
}
