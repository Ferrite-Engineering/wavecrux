// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// `products.wavecrux.themePacks` and `products.wavecrux.sessionTemplates` —
/// the last two of C5's registered-but-unread keys.
///
/// Both reference a file on the organization's own share, so both go through
/// [loadOrgShareResource]; what differs is only what the file is.
///
/// ### `themePacks` — a `.crux-theme.json` the whole team sees
///
/// WaveCrux already installs, activates, exports and uninstalls theme packs
/// through `crux_theme`'s browser. What was missing is the organization being
/// able to *supply* one: a house colour scheme that arrives with the app rather
/// than being emailed round as a file everybody imports by hand and half of
/// them forget.
///
/// **Locked means the pack is applied and the picker is read-only**, which is
/// what "mandatory theme lock" in the plans means. Unlocked, it is applied once
/// as the starting point and the user may pick anything else afterwards —
/// because a *default* somebody cannot depart from is a lock whose control
/// forgot to grey itself.
///
/// ### `sessionTemplates` — a `.wavecrux` session as a starting point
///
/// The format already exists: [SessionState] is what `SessionService` writes.
/// A template is one of those files, on the share, applied to a **new** session
/// so a team's standard signal arrangement, cursors and panel layout are what
/// an engineer starts from rather than what they rebuild.
///
/// **A template never touches an open session, and never overrides a session
/// the user opened from a file.** Somebody who double-clicked a `.wavecrux`
/// wants that session; applying a template over it would be the feature
/// destroying the thing the user asked for.
library;

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/core/license/enterprise_feature_gate.dart';
import 'package:wavecrux/core/policy/wavecrux_policy_keys.dart';
import 'package:wavecrux/services/policy/org_object_policy_key.dart';
import 'package:wavecrux/services/policy/org_policy_tier_gate.dart';
import 'package:wavecrux/services/policy/org_share_resource.dart';

/// An organization-supplied resource reference, with its lock state.
@immutable
final class OrgResourceRef {
  /// Creates an [OrgResourceRef].
  const OrgResourceRef({required this.resource, required this.locked});

  /// Where the file is, and whether it is pinned.
  final OrgShareResource resource;

  /// Whether the organization fixed this — the "mandatory pack" case.
  final bool locked;

  /// Reads one from a policy entry.
  ///
  /// A **list** takes the first entry: the keys are plural because an
  /// organization may want to *offer* several, and offering several is a
  /// browser feature rather than a policy one. Taking the first is the
  /// behaviour an administrator writing a one-element list expects, and it
  /// leaves the plural spelling meaning something later without meaning
  /// nothing now.
  static OrgResourceRef? fromPolicyEntry(OrgPolicyEntry? entry) {
    final raw = entry?.value;
    final candidate = raw is List ? (raw.isEmpty ? null : raw.first) : raw;
    final resource = OrgShareResource.parse(candidate);
    if (resource == null) return null;
    return OrgResourceRef(resource: resource, locked: entry!.locked);
  }
}

/// The organization's theme pack, or `null`.
///
/// `null` on a seat whose tier does not include the Enterprise administration
/// surface, exactly as if nothing were configured — the tier check comes
/// before the parse, so an administrator is never sent to fix a file a
/// licence would refuse anyway. [orgPolicyWithheldByTierProvider] carries the
/// difference between "nothing configured" and "configured and withheld".
final orgThemePackProvider = Provider<OrgResourceRef?>((ref) {
  if (!enterpriseFeatureUnlocked(
    beta: ref.watch(betaPeriodProvider),
    tier: ref.watch(licenseTierProvider),
  )) {
    return null;
  }
  return OrgResourceRef.fromPolicyEntry(
    readOrgPolicyEntry(
      ref.watch(cruxPolicyProvider).document.products,
      productId: WaveCruxPolicyKeys.productId,
      key: WaveCruxPolicyKeys.themePacks,
    ),
  );
}, name: 'orgThemePackProvider');

/// The organization's session template, or `null`.
///
/// Gated the same way as [orgThemePackProvider], for the same reason.
final orgSessionTemplateProvider = Provider<OrgResourceRef?>((ref) {
  if (!enterpriseFeatureUnlocked(
    beta: ref.watch(betaPeriodProvider),
    tier: ref.watch(licenseTierProvider),
  )) {
    return null;
  }
  return OrgResourceRef.fromPolicyEntry(
    readOrgPolicyEntry(
      ref.watch(cruxPolicyProvider).document.products,
      productId: WaveCruxPolicyKeys.productId,
      key: WaveCruxPolicyKeys.sessionTemplates,
    ),
  );
}, name: 'orgSessionTemplateProvider');
