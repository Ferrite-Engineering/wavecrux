// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/policy/wavecrux_policy_keys.dart';
import 'package:wavecrux/services/decoders/ffi/plugin_allowlist.dart';

/// The organization's approved-plugin list, from the signed policy file.
///
/// **In open core, and gated by nothing.** Every other Enterprise mechanism in
/// this product is behind a tier check; this one is not, and that is
/// deliberate. It is a *refusal*: it can only ever cause fewer plugins to load,
/// never more. Tier-gating a refusal would mean an organization that wrote an
/// allowlist got it honoured on the seats that happen to hold an Enterprise
/// licence and ignored on the rest — which is not a licensing boundary, it is
/// a hole with a licence check in front of it.
///
/// The same reasoning the telemetry `deny` binding follows: what an
/// organization forbids is honoured everywhere, because the alternative is a
/// policy that is true on some machines.
///
/// Resolves to [PluginAllowlist.absent] when no policy file is present, which
/// is every default install — see that constant for why "no list" and "empty
/// list" are different things.
final pluginAllowlistProvider = Provider<PluginAllowlist>((ref) {
  final document = ref.watch(cruxPolicyProvider).document;
  return PluginAllowlist.fromPolicyValue(
    document.products[WaveCruxPolicyKeys.productId]?[WaveCruxPolicyKeys
        .approvedPlugins],
  );
}, name: 'pluginAllowlistProvider');
