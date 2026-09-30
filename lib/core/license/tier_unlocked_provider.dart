// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderFamily;

/// Whether this seat may use something that needs [requiredTier], given the
/// beta flag and the active licence [tier].
///
/// The arithmetic behind [tierUnlockedProvider], for a caller that reads the
/// two providers itself: a notifier reacting to a licence change reads the
/// changed value directly, where a derived provider could still hold the
/// answer from before the change.
bool tierUnlocked(
  LicenseTier requiredTier, {
  required bool beta,
  required LicenseTier tier,
}) => beta || FeatureGate.satisfiesTier(requiredTier, tier);

/// Whether this seat may use something that needs the family argument's tier,
/// read live.
///
/// ### Why the consumers ask, and not only the pickers
///
/// A tier-gated item can reach the viewer without anyone choosing it. A
/// session restore puts back every decoder, Stage widget and translator
/// binding it saved, and the Pro overlay registers those items at every tier,
/// so a session saved during the public beta, or a session file edited by
/// hand, names a Pro item and the build has it. The pickers ask the tier; a
/// restore never passes through them. So the code that would *run* the item
/// asks here: the decoder run, the Stage tile, the translator registry.
///
/// It is watched rather than read once, so the stored licence resolving after
/// startup (every launch passes through Open Core before the keychain
/// answers), a licence activated mid-session, and a lapse all move the item
/// without a restart.
///
/// ### The gate
///
/// The suite-standard one: open while the public beta is on, read from
/// `betaPeriodProvider` rather than the compile-time `kBetaPeriod` so a test
/// can close it, and otherwise `FeatureGate.satisfiesTier` against
/// `licenseTierProvider`. EDU satisfies a Pro requirement, and an Open Core
/// requirement is always met.
///
/// Withholding is never silent and never destructive. A withheld item stays in
/// the session model, so the next save writes it back and an upgrade brings it
/// back, and the surface it would have drawn on says why
/// (`WaveCruxWithheldNotice`).
final ProviderFamily<bool, LicenseTier> tierUnlockedProvider =
    Provider.family<bool, LicenseTier>(
      (ref, requiredTier) => tierUnlocked(
        requiredTier,
        beta: ref.watch(betaPeriodProvider),
        tier: ref.watch(licenseTierProvider),
      ),
      name: 'tierUnlockedProvider',
    );
