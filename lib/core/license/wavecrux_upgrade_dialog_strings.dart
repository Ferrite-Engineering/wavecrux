// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Adapter that satisfies the cross-suite [CruxUpgradeDialogStrings]
/// interface from `package:crux_license` using WaveCrux's ARB-generated
/// [L10N] strings.
///
/// The shared [CruxUpgradeDialog] accepts a [CruxUpgradeDialogStrings] so it
/// renders the same layout across every Crux product while pulling its text
/// from the product's active locale. WaveCrux binds each member to its
/// `upgradeDialog*` ARB keys; the dismiss label is supplied by the caller
/// (WaveCrux's bespoke dialogs used `MaterialLocalizations.okButtonLabel`,
/// and this adapter preserves that source verbatim).
class WaveCruxUpgradeDialogStrings extends CruxUpgradeDialogStrings {
  /// Wraps the supplied [L10N] so the shared dialog renders in the active
  /// locale. [dismissLabel] is the already-localized dismiss-button label
  /// (typically `MaterialLocalizations.of(context).okButtonLabel`).
  const WaveCruxUpgradeDialogStrings(this._l10n, this.dismissLabel);

  final L10N _l10n;

  @override
  String get title => _l10n.upgradeDialogTitle;

  @override
  String body(String featureName, String tierName) =>
      _l10n.upgradeDialogMessage(featureName, tierName);

  @override
  String get tierNamePro => _l10n.upgradeDialogTierNamePro;

  @override
  String get tierNameEnterprise => _l10n.upgradeDialogTierNameEnterprise;

  @override
  final String dismissLabel;

  @override
  String get seePricingLabel => _l10n.upgradeDialogSeePricing;
}
