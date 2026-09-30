// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/editor_host/editor_host_capability_copy.dart';
import 'package:wavecrux/domain/enums/editor_host_capability.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/host_bridge/capability_nudge_provider.dart';
import 'package:wavecrux/services/host_bridge/editor_host_provider.dart';

/// Whether this build is running inside an editor extension host.
///
/// A one-line convenience over `editorHostKindProvider` so the four surfaces
/// that gate on it read the same way, and so a reviewer grepping for the
/// gate finds one name instead of four inlined comparisons.
bool isEditorHosted(WidgetRef ref) =>
    ref.watch(editorHostKindProvider) != EditorHostKind.none;

/// A capability boundary rendered *in place of* the feature the user went
/// looking for.
///
/// **Not a nudge, and deliberately not subject to the once-per-session
/// rule.** The user opened the Stage tab, or the RTL Source panel; answering
/// "here is why this is empty" is the panel doing its job. Frequency
/// discipline exists for the unsolicited case — see [CapabilityNudgeBanner]
/// — and applying it here would produce a panel that explained itself once
/// and was blank thereafter — and an absent feature teaches nothing.
///
/// Mirrors the shape of `stage_panel.dart`'s existing `_PhoneNotSupported`,
/// which is the same idea for a different constraint: centred, muted, no
/// call to action competing with the sentence.
class EditorHostBoundary extends StatelessWidget {
  /// Creates the boundary block for [capability].
  const EditorHostBoundary({required this.capability, super.key});

  /// Which boundary to explain. Never [EditorHostCapability.slowParse] —
  /// that one is raised over the waveform by [CapabilityNudgeBanner], because
  /// there is no panel a user could have opened to ask about it.
  final EditorHostCapability capability;

  @override
  Widget build(BuildContext context) {
    final copy = editorHostCapabilityCopy(L10N.of(context), capability);
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            // A dock panel inside a split VSCode editor can be very narrow.
            // The cap is a maximum, not a width: the column shrinks below it
            // and the text wraps rather than overflowing.
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  copy.title,
                  key: const Key('editorHostBoundaryTitle'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  copy.message,
                  key: const Key('editorHostBoundaryMessage'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact, inline capability note — the same words as
/// [EditorHostBoundary], laid out for a spot that already has other content
/// (the empty canvas) rather than an empty panel it can fill.
///
/// Renders nothing when there is no editor host, so a call site can mount it
/// unconditionally in the same way `WaveCruxFeatureTierBadge` can: the platform
/// check is the widget's, not every caller's.
class EditorHostCapabilityNote extends ConsumerWidget {
  /// Creates the note for [capability].
  const EditorHostCapabilityNote({required this.capability, super.key});

  /// Which boundary to state.
  final EditorHostCapability capability;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isEditorHosted(ref)) return const SizedBox.shrink();
    final copy = editorHostCapabilityCopy(L10N.of(context), capability);
    final theme = Theme.of(context);
    return Container(
      key: const Key('editorHostCapabilityNote'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            copy.message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The one unsolicited capability notice a session is allowed.
///
/// Renders `capabilityNudgeProvider`'s state and nothing else — the policy
/// that decides whether there *is* any state to render lives in
/// [CapabilityNudgeNotifier] and [mayRaiseCapabilityNudge], where it is
/// testable without a widget tree. This widget's only job is to look like a
/// notice rather than an interruption: inline, above the content, no scrim,
/// no modal barrier, and a close button that is always reachable.
///
/// **Dismissible is not optional.** A notice the user cannot get rid of is
/// an interruption wearing a banner's clothes, and the dismiss control is
/// therefore laid out first (pinned trailing, fixed size) so it survives
/// every width the panel can be dragged to.
///
/// ### It renders; it does not decide, and it does not observe
///
/// The parse-completed trigger deliberately lives in `ViewerScreen` and not
/// here. `waveformSourceProvider` is a **feature** provider overridden per
/// tab, and `lib/shared/` may not import `lib/features/` —
/// `test/static/import_layering_test.dart` enforces exactly that, and it
/// caught this widget doing it. The viewer is the sanctioned shell for
/// cross-feature composition, so the `ref.listen` belongs there and this
/// widget stays presentation-only. That is also the better split on its own
/// terms: the trigger has to run wherever a waveform can be opened, and the
/// banner has to render wherever there is room for it, and those are not
/// guaranteed to be the same widget forever.
class CapabilityNudgeBanner extends ConsumerWidget {
  /// Creates the banner.
  const CapabilityNudgeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nudge = ref.watch(capabilityNudgeProvider);
    if (nudge == null) return const SizedBox.shrink();

    final copy = editorHostCapabilityCopy(
      L10N.of(context),
      nudge.capability,
      parseDuration: nudge.parseDuration,
    );
    final theme = Theme.of(context);
    return Material(
      key: const Key('capabilityNudgeBanner'),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.info_outline,
                size: 16,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    copy.title,
                    key: const Key('capabilityNudgeTitle'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    copy.message,
                    key: const Key('capabilityNudgeMessage'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // Pinned and fixed-size: at the narrowest panel width the message
            // wraps and the dismiss control stays exactly where it was.
            IconButton(
              key: const Key('capabilityNudgeDismiss'),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Icons.close, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () =>
                  ref.read(capabilityNudgeProvider.notifier).dismiss(),
            ),
          ],
        ),
      ),
    );
  }
}
