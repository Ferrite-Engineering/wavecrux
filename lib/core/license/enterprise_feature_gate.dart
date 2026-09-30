// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';

/// Whether an **Enterprise** capability is unlocked, given the beta flag and
/// the active licence [tier].
///
/// The provider-aware form of `FeatureGate.isAvailable(LicenseTier.enterprise,
/// tier)`: it takes [beta] as a *value* read from `betaPeriodProvider` rather
/// than the compile-time `kBetaPeriod` constant, because a Riverpod override
/// cannot move a `const`, and a gate that reads the constant can never
/// exercise its locked branch in a test. An Enterprise gate that has only ever
/// been tested open is a gate nobody has tested.
///
/// The organization-policy consumers are the first callers: every key in the
/// signed policy file that *grants* a capability — signal groups, decoder
/// defaults, session templates, theme packs — is honoured only on a seat whose
/// tier includes it. Keys that can only ever *withhold* something (the plugin
/// allowlist, the server switches) are honoured at every tier and never pass
/// through here; see `plugin_allowlist_provider.dart` for why a tier gate on a
/// refusal is a hole with a licence check in front of it.
///
/// EDU is feature-equivalent to Pro and therefore does **not** satisfy this
/// gate, which is the intended difference from a Pro gate.
bool enterpriseFeatureUnlocked({
  required bool beta,
  required LicenseTier tier,
}) => beta || FeatureGate.satisfiesTier(LicenseTier.enterprise, tier);
