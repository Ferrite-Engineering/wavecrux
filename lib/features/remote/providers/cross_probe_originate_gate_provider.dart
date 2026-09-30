// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/wavecrux_upgrade_dialog.dart';

/// Decides whether this seat may **originate** a cross-probe, and explains
/// itself when it may not.
///
/// Returns `true` when the send may proceed. When it returns `false` it has
/// already told the user why — the upgrade dialog, here — so the caller
/// simply returns. A user pressed a button; the one answer that is never
/// acceptable is nothing.
typedef CrossProbeOriginateGate = bool Function(BuildContext context);

/// The gate the cross-probe panel's per-peer send button consults.
///
/// ### Why the panel needs a gate of its own
///
/// Cross-probe *origination* — pointing another product at what is selected
/// here — is a Pro capability. There is no route to it in WaveCrux's open
/// core UI apart from this panel, which ships in open core and is mounted
/// from the open-core dock, with a send button per discovered peer that
/// reaches the capability directly. Without this seam that button was an
/// unguarded route to a priced capability: NetCrux, LintCrux and SimCrux
/// gate the same panel; WaveCrux's didn't.
///
/// The same rule applies to any priced capability whose code lives in open
/// core: the gate lives beside the code, in open core, reading the suite's
/// own tier providers — not in the overlay, which has no other route to
/// guard.
///
/// ### What it does
///
/// Admits every tier while the public beta is in effect
/// (`betaPeriodProvider`), and afterwards only a tier that satisfies Pro
/// (`FeatureGate.satisfiesTier`, so EDU and Enterprise pass). Like WaveCrux's
/// other two tier-badged, open-core-resident pickers (the decoder picker, the
/// translator preset picker, the Stage widget picker), the denial records
/// `tier.gate_hit` under the `cross_probe` id in
/// [kWavecruxGateFeatureIds] and raises the shared [WaveCruxUpgradeDialog] —
/// WaveCrux keeps that dialog in open core, so there is nothing for a Pro
/// overlay to rebind; the seam still exists so a test can prove the panel
/// asks it rather than the tier directly.
final Provider<CrossProbeOriginateGate> crossProbeOriginateGateProvider =
    Provider<CrossProbeOriginateGate>(
      (ref) => (context) {
        final unlocked =
            ref.read(betaPeriodProvider) ||
            FeatureGate.satisfiesTier(
              LicenseTier.pro,
              ref.read(licenseTierProvider),
            );
        if (unlocked) return true;
        if (!context.mounted) return false;
        // Unreachable for the whole beta, on purpose: it goes live with the
        // flag that ends it, like every other gate-hit site. The dialog
        // records the hit, and only when it opens.
        unawaited(
          WaveCruxUpgradeDialog.show(
            context,
            featureLabel: L10N.of(context).crossProbeSendTooltip,
            requiredTier: LicenseTier.pro,
            gateFeatureId: 'cross_probe',
          ),
        );
        return false;
      },
      name: 'crossProbeOriginateGateProvider',
    );
