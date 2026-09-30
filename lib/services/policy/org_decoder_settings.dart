// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// `products.wavecrux.decoderSettings` — the organization's default protocol
/// decoder parameters.
///
/// **Registering a key is not implementing the feature it configures.** C5
/// registered this one: it resolves, honours the shared precedence and reports
/// its own diagnostics, and nothing read it. This is the feature.
///
/// ### What it does
///
/// A verification team standardises on things a decoder cannot guess — the
/// bus's clock polarity, the UART's baud, whether the I²C address is 7-bit or
/// 8-bit. Getting those wrong produces a decode that is confidently
/// meaningless, and every engineer on the team currently fixes them by hand,
/// one dialog at a time, on every design.
///
/// ### Precedence, and the one case that is not "a default"
///
/// The spec's order is `locked > user setting > policy default > built-in`, and
/// both halves matter here:
///
/// * **Unlocked**, the organization's value replaces the decoder's *built-in*
///   default — so a fresh decoder starts right — while anything the user has
///   already set for this instance wins.
/// * **Locked**, the organization's value wins outright, including over a
///   value the user set earlier. That is what "locked" means, and a lock that
///   yielded to a saved session would be a lock in name only.
///
/// The UI's job is then to say so: a locked parameter renders read-only with
/// `CruxPolicyLockNote`, because a control that invites an edit which does
/// nothing is worse than one that is plainly unavailable.
library;

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/core/license/enterprise_feature_gate.dart';
import 'package:wavecrux/core/policy/wavecrux_policy_keys.dart';
import 'package:wavecrux/services/policy/org_object_policy_key.dart';

/// The organization's decoder parameter defaults.
@immutable
final class OrgDecoderSettings {
  /// Creates an [OrgDecoderSettings].
  const OrgDecoderSettings({required this.byDecoder, required this.locked});

  /// Parses the policy value.
  ///
  /// Shape: `{ "<decoderId>": { "<parameter>": <value> } }`. A decoder id whose
  /// value is not an object is dropped rather than failing the whole key — one
  /// malformed entry must not cost an administrator the other nine.
  factory OrgDecoderSettings.fromPolicyEntry(OrgPolicyEntry? entry) {
    final raw = entry?.value;
    if (raw is! Map<String, Object?>) return none;
    final byDecoder = <String, Map<String, Object?>>{};
    for (final decoder in raw.entries) {
      final params = decoder.value;
      if (params is! Map<String, Object?>) continue;
      if (params.isEmpty) continue;
      byDecoder[decoder.key] = Map<String, Object?>.unmodifiable(params);
    }
    if (byDecoder.isEmpty) return none;
    return OrgDecoderSettings(
      byDecoder: Map<String, Map<String, Object?>>.unmodifiable(byDecoder),
      locked: entry!.locked,
    );
  }

  /// The organization set nothing.
  static const OrgDecoderSettings none = OrgDecoderSettings(
    byDecoder: <String, Map<String, Object?>>{},
    locked: false,
  );

  /// Parameter values, keyed by decoder id and then by parameter name.
  final Map<String, Map<String, Object?>> byDecoder;

  /// Whether the organization locked these. See the library doc.
  final bool locked;

  /// Whether the organization configured anything at all.
  bool get isEmpty => byDecoder.isEmpty;

  /// The organization's value for [parameter] of [decoderId], or `null`.
  Object? valueFor(String decoderId, String parameter) =>
      byDecoder[decoderId]?[parameter];

  /// Resolves one parameter under the full precedence rule.
  ///
  /// [userValue] is what the user has already set for this decoder instance —
  /// `null` when they have not. [builtIn] is the decoder's own
  /// `DecoderParameter.defaultValue`.
  Object? resolve(
    String decoderId,
    String parameter, {
    required Object? userValue,
    required Object? builtIn,
  }) {
    final org = valueFor(decoderId, parameter);
    if (org != null && locked) return org;
    if (userValue != null) return userValue;
    return org ?? builtIn;
  }

  /// Whether [parameter] of [decoderId] is fixed by the organization.
  ///
  /// The UI reads this to render the control read-only. A parameter the
  /// organization did not mention is not locked even when the key as a whole
  /// is: locking `decoderSettings` fixes the values written in it, not every
  /// parameter of every decoder.
  bool isLocked(String decoderId, String parameter) =>
      locked && valueFor(decoderId, parameter) != null;
}

/// The organization's decoder defaults, from the signed policy file.
///
/// Resolves to [OrgDecoderSettings.none] with no policy file, which is every
/// default install — so the decoder dialog's behaviour is byte-for-byte what it
/// was before this key had a reader. Also [OrgDecoderSettings.none] on a seat
/// whose tier does not include the Enterprise administration surface: this
/// key *grants* organization defaults and locks, unlike the plugin allowlist
/// beside it, which only ever refuses and so is honoured everywhere. The
/// withheld case is reported through `orgPolicyWithheldByTierProvider`.
final orgDecoderSettingsProvider = Provider<OrgDecoderSettings>((ref) {
  if (!enterpriseFeatureUnlocked(
    beta: ref.watch(betaPeriodProvider),
    tier: ref.watch(licenseTierProvider),
  )) {
    return OrgDecoderSettings.none;
  }
  return OrgDecoderSettings.fromPolicyEntry(
    readOrgPolicyEntry(
      ref.watch(cruxPolicyProvider).document.products,
      productId: WaveCruxPolicyKeys.productId,
      key: WaveCruxPolicyKeys.decoderSettings,
    ),
  );
}, name: 'orgDecoderSettingsProvider');
