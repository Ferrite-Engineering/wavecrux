// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/wavecrux_feature_tier_badge.dart';
import 'package:wavecrux/shared/widgets/wavecrux_upgrade_dialog.dart';

/// How much room a [WaveCruxWithheldNotice] has, and so how it says its
/// sentence.
enum WithheldNoticeLayout {
  /// A body with room to spare, such as a Stage tile: the sentence, the tier
  /// badge, and a See pricing action when the build can sell.
  panel,

  /// One line, such as a decoder row: a lock, the sentence and the tier badge.
  /// A tap opens the upgrade dialog.
  row,

  /// A few dozen pixels beside a value that is still shown: a lock and the
  /// tier badge, with the sentence as the tooltip and the spoken label. A tap
  /// opens the upgrade dialog.
  chip,
}

/// The locked state of an item this seat's tier does not include, drawn where
/// the item would have been.
///
/// A session restore puts back what it saved, and some of that can be sold at
/// a tier this seat does not have: a session saved during the public beta, or
/// one edited by hand. The consumer that would run the item withholds it
/// (see `tierUnlockedProvider`), and this is what it draws instead, because a
/// withheld item that simply vanished, or that fell back to something plainer
/// without saying so, would read as a broken session.
///
/// It says the upgrade dialog's own sentence, `“<feature>” requires <tier>.`,
/// so a product that has already localized the dialog has nothing new to
/// translate, and the locked item, the dialog and the locked Settings panel
/// all say one thing. [WithheldNoticeLayout.panel] offers the same See pricing
/// action as the locked Settings panel, and only in a build that can sell;
/// the other layouts open the shared [WaveCruxUpgradeDialog], which records
/// the gate hit under [gateFeatureId] when it opens.
///
/// It is only ever drawn in place of the item, never as a replacement for it:
/// the item stays in the session, so the next save writes it back and an
/// upgrade brings it back.
class WaveCruxWithheldNotice extends StatelessWidget {
  /// Creates the notice for the item labelled [featureLabel], which needs
  /// [requiredTier].
  const WaveCruxWithheldNotice({
    required this.featureLabel,
    required this.requiredTier,
    required this.gateFeatureId,
    this.layout = WithheldNoticeLayout.panel,
    super.key,
  });

  /// Localized label of the withheld item, as the surface it sits on names
  /// it.
  final String featureLabel;

  /// The tier that unlocks the item ([LicenseTier.pro] or
  /// [LicenseTier.enterprise]).
  final LicenseTier requiredTier;

  /// The closed id the upgrade dialog counts a tap under
  /// (`kWavecruxGateFeatureIds`): the same id as the picker that sells the
  /// item, because the item is the same whichever door the user reached it
  /// through.
  final String gateFeatureId;

  /// How much room the notice has.
  final WithheldNoticeLayout layout;

  /// The sentence this notice says for [featureLabel] and [requiredTier] in
  /// [context]'s locale.
  static String sentence(
    BuildContext context, {
    required String featureLabel,
    required LicenseTier requiredTier,
  }) {
    final l10n = L10N.of(context);
    final tierName = requiredTier == LicenseTier.enterprise
        ? l10n.upgradeDialogTierNameEnterprise
        : l10n.upgradeDialogTierNamePro;
    return l10n.upgradeDialogMessage(featureLabel, tierName);
  }

  @override
  Widget build(BuildContext context) {
    final message = sentence(
      context,
      featureLabel: featureLabel,
      requiredTier: requiredTier,
    );
    return switch (layout) {
      WithheldNoticeLayout.panel => _Panel(
        message: message,
        requiredTier: requiredTier,
      ),
      WithheldNoticeLayout.row || WithheldNoticeLayout.chip => _Tappable(
        message: message,
        showMessage: layout == WithheldNoticeLayout.row,
        requiredTier: requiredTier,
        onTap: () => unawaited(
          WaveCruxUpgradeDialog.show(
            context,
            featureLabel: featureLabel,
            requiredTier: requiredTier,
            gateFeatureId: gateFeatureId,
          ),
        ),
      ),
    };
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.message, required this.requiredTier});

  final String message;
  final LicenseTier requiredTier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seePricing = cruxSeePricingActionFor(context);
    // Stage tiles resize down to a few dozen pixels. The column lays out at
    // its natural height inside a viewport that clips instead of overflowing,
    // and takes no scroll gestures, so the tile's own drag still moves it. The
    // sentence comes first, so it is what a tile too small for the rest keeps.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: constraints.maxWidth,
            minHeight: constraints.maxHeight,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      WaveCruxFeatureTierBadge(requiredTier: requiredTier),
                      if (seePricing != null)
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: seePricing,
                          child: Text(L10N.of(context).upgradeDialogSeePricing),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Below this width a [WithheldNoticeLayout.row] drops its badge rather than
/// squeeze the sentence to nothing.
const double _rowBadgeMinWidth = 120;

class _Tappable extends StatelessWidget {
  const _Tappable({
    required this.message,
    required this.showMessage,
    required this.requiredTier,
    required this.onTap,
  });

  final String message;
  final bool showMessage;
  final LicenseTier requiredTier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: message,
      excludeSemantics: true,
      child: Tooltip(
        message: message,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: showMessage
                ? LayoutBuilder(
                    // A narrow row keeps the lock and the sentence and drops
                    // the badge, which the sentence already says in words.
                    builder: (context, constraints) => Row(
                      children: [
                        Icon(Icons.lock_outline, size: 14, color: muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          ),
                        ),
                        if (constraints.maxWidth >= _rowBadgeMinWidth) ...[
                          const SizedBox(width: 6),
                          WaveCruxFeatureTierBadge(requiredTier: requiredTier),
                        ],
                      ],
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 14, color: muted),
                      const SizedBox(width: 4),
                      WaveCruxFeatureTierBadge(requiredTier: requiredTier),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
