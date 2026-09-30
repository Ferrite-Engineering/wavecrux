// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart' show ModalGuard;
import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/license/wavecrux_license_badge_strings.dart';
import 'package:wavecrux/core/license/wavecrux_upgrade_dialog_strings.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// WaveCrux binding of the cross-suite [CruxUpgradeDialog], shown when a
/// Pro/Enterprise action is activated post-beta under a license tier that
/// does not include it.
///
/// This is the suite's gate-denial convention: tier-gated items stay
/// enabled and tier-badged on every discovery surface, and an
/// insufficient-tier *activation* surfaces this dialog instead of a
/// silent no-op — the user learns why nothing happened and which tier
/// unlocks the feature. During the beta the gate short-circuits to
/// allow, so this dialog is unreachable until the beta flip.
///
/// The dialog body, badge, and layout come from the shared
/// [CruxUpgradeDialog]; this widget only supplies the WaveCrux locale
/// adapters ([WaveCruxUpgradeDialogStrings] and
/// [WaveCruxLicenseBadgeStrings]) built from the nearest [L10N], mirroring
/// how [WaveCruxFeatureTierBadge] wraps the shared [FeatureTierBadge].
/// License-key entry / purchase flows live in the Pro overlay and are not
/// referenced here.
///
/// **The one WaveCrux binding.** The Pro overlay's deny path opens this same
/// dialog rather than binding its own strings, so a user sees one dialog
/// whichever repository's gate refused them. It used to be two, with two
/// titles and two sentences in one session. What those strings say is the
/// suite copy contract, held by `upgrade_dialog_contract_test.dart`.
///
/// There is no supplemental line. The generic "visit wavecrux.app" pointer the
/// bespoke dialogs carried is gone: the See pricing action is the way out in
/// a build that can sell, and no other product carried one.
class WaveCruxUpgradeDialog extends StatelessWidget {
  /// Creates the dialog. [featureLabel] is the localized label of the
  /// activated action; [requiredTier] is the tier that unlocks it.
  const WaveCruxUpgradeDialog({
    required this.featureLabel,
    required this.requiredTier,
    super.key,
  });

  /// Localized label of the action the user activated.
  final String featureLabel;

  /// Minimum tier that unlocks the action ([LicenseTier.pro] or
  /// [LicenseTier.enterprise]).
  final LicenseTier requiredTier;

  /// Shows the dialog over [context], and counts the denial.
  ///
  /// Records the upgrade funnel's two events, in this order:
  ///
  /// * `tier.gate_hit`, when [gateFeatureId] is given — the closed id this
  ///   call site is counted under (`kWavecruxGateFeatureIds`), never the
  ///   localized [featureLabel];
  /// * `badge.click`, always. It carries only the tier, so it is recorded
  ///   here rather than per site, where it would drift the moment one call
  ///   site was added without it.
  ///
  /// Both are recorded only when a dialog actually opens. The shared
  /// [CruxUpgradeDialog.show] is re-entrancy guarded: a gated shortcut held
  /// down (key auto-repeat) re-dispatches the denial while the dialog is up,
  /// and the guard stops those repeats from stacking copies of it. A repeat
  /// that opens nothing is not another denial the user saw, so it is not
  /// counted either: one dialog, one event. That is why the gate hit is
  /// recorded here, beside the guard, and not before the call at each site.
  ///
  /// Under a VSCode extension host this reaches the network through the
  /// bridge and never from here — `telemetryServiceProvider` resolves to
  /// `HostRelayTelemetryService`, the host owns the
  /// `vscode.env.isTelemetryEnabled` gate, and the webview has no sender of
  /// its own. Nothing about this call site knows or needs to know that.
  static Future<void> show(
    BuildContext context, {
    required String featureLabel,
    required LicenseTier requiredTier,
    String? gateFeatureId,
  }) {
    // Checked and then opened in the same synchronous turn, so nothing can
    // open the dialog between the two: [ModalGuard.run] claims its key before
    // it first awaits.
    if (ModalGuard.isOpen(CruxUpgradeDialog.modalGuardKey)) {
      return Future<void>.value();
    }
    final telemetry = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(telemetryServiceProvider);
    if (gateFeatureId != null) {
      telemetry.record(
        TelemetryEvent(
          'tier.gate_hit',
          properties: <String, Object?>{
            'feature': gateFeatureId,
            'required': requiredTier.name,
          },
        ),
      );
    }
    telemetry.record(
      TelemetryEvent(
        'badge.click',
        properties: <String, Object?>{
          // `FeatureTierBadge` renders nothing for openCore/edu, so a click on
          // one is not a badge click; a gate can only ever demand pro or
          // enterprise (`action_descriptors.dart`), and the catalog's
          // closed vocabulary says the same.
          'tier': requiredTier == LicenseTier.enterprise
              ? LicenseTier.enterprise.name
              : LicenseTier.pro.name,
        },
      ),
    );
    final l10n = L10N.of(context);
    return CruxUpgradeDialog.show(
      context,
      featureName: featureLabel,
      requiredTier: requiredTier,
      strings: WaveCruxLicenseBadgeStrings(l10n),
      l10n: _strings(context),
      // After the beta: the dialog offers a way to act on what it just
      // said. Resolves to null in an open-core build, which has nothing
      // to sell, so the button is absent rather than dead — this file
      // is the deny path the open-core action dispatcher uses, and it
      // runs in both builds.
      onSeePricing: cruxSeePricingActionFor(context),
    );
  }

  /// WaveCrux's upgrade-dialog strings in [context]'s locale, with the
  /// platform's own OK as the dismiss label.
  static CruxUpgradeDialogStrings _strings(BuildContext context) =>
      WaveCruxUpgradeDialogStrings(
        L10N.of(context),
        MaterialLocalizations.of(context).okButtonLabel,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return CruxUpgradeDialog(
      featureName: featureLabel,
      requiredTier: requiredTier,
      strings: WaveCruxLicenseBadgeStrings(l10n),
      l10n: _strings(context),
      onSeePricing: cruxSeePricingActionFor(context),
    );
  }
}
