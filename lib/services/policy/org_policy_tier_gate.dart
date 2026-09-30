// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/license/enterprise_feature_gate.dart';
import 'package:wavecrux/core/policy/wavecrux_policy_keys.dart';
import 'package:wavecrux/services/policy/org_object_policy_key.dart';

/// The organization keys that *grant* a capability, and are therefore honoured
/// only on a seat whose tier includes the Enterprise administration surface.
///
/// Every key here has a consumer that checks the tier before it parses:
/// `orgSignalGroupsProvider`, `orgDecoderSettingsProvider`,
/// `orgSessionTemplateProvider`, `orgThemePackProvider`. The keys that are
/// **not** here are honoured at every tier, deliberately — `approvedPlugins`
/// is a refusal, and `wcpServer` / `cxpServer` decide whether a socket the
/// engineer could open anyway is allowed to — because a tier gate on a
/// restriction is a hole with a licence check in front of it.
const List<String> kWaveCruxTierGatedPolicyKeys = <String>[
  WaveCruxPolicyKeys.signalGroups,
  WaveCruxPolicyKeys.decoderSettings,
  WaveCruxPolicyKeys.sessionTemplates,
  WaveCruxPolicyKeys.themePacks,
];

/// The gated keys the policy file sets that this seat is **not** honouring
/// because of its tier — empty whenever nothing is withheld.
///
/// A consumer that resolves to "nothing configured" cannot tell an
/// administrator *why*, and "your organization configured this and this
/// licence does not include it" is a different sentence from "nobody
/// configured it" — the only one that does not read as a bug. This is where
/// the difference survives, for a diagnostic or a settings surface to say.
///
/// Empty during the public beta and on an Enterprise seat, exactly as the
/// consumers are open then; it names a key only when a consumer is actually
/// returning its "none" value for want of a tier.
final orgPolicyWithheldByTierProvider = Provider<Set<String>>((ref) {
  if (enterpriseFeatureUnlocked(
    beta: ref.watch(betaPeriodProvider),
    tier: ref.watch(licenseTierProvider),
  )) {
    return const <String>{};
  }
  final products = ref.watch(cruxPolicyProvider).document.products;
  return <String>{
    for (final key in kWaveCruxTierGatedPolicyKeys)
      if (readOrgPolicyEntry(
            products,
            productId: WaveCruxPolicyKeys.productId,
            key: key,
          ) !=
          null)
        key,
  };
}, name: 'orgPolicyWithheldByTierProvider');
