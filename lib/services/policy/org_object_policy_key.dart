// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Reading a policy key whose value is an **object** or a **list**.
///
/// ### The ambiguity this exists for
///
/// `crux_policy`'s resolver accepts two shapes for any key: the bare value, and
/// the object form `{"value": …, "locked": true}` that carries the lock flag.
/// It tells them apart by asking *is this a Map?* — exactly right for every
/// scalar key in the suite, and ambiguous for a key whose value is itself an
/// object.
///
/// WaveCrux has four such keys — `signalGroups`, `decoderSettings`,
/// `themePacks` and `sessionTemplates` — and under the resolver's rule an
/// administrator writing the natural thing gets *object form is missing its
/// "value" member* and a key that silently does nothing.
///
/// **Both spellings are accepted here.** The disambiguation is the one rule
/// that cannot be wrong: a map carrying a `value` member is the wrapper, and
/// anything else is the payload. No object-valued key in this product has a
/// field called `value`, and this comment is where that constraint is written
/// down for whoever adds the fifth.
///
/// SimCrux hit the same thing first and solved it the same way in its Pro
/// overlay. Two copies rather than an extraction because this one is fourteen
/// lines and lives in open core while the first is in a Pro overlay — a shared home
/// would have to be `crux_policy` itself, and changing the shared resolver's
/// contract to fix two products' keys is a bigger decision than either of them
/// needs. If a third product hits it, that is the moment.
library;

import 'package:meta/meta.dart';

/// A policy value that survived the wrapper ambiguity, with its lock state.
@immutable
final class OrgPolicyEntry {
  /// Creates an [OrgPolicyEntry].
  const OrgPolicyEntry({required this.value, required this.locked});

  /// The payload, already unwrapped. A `Map` or a `List`.
  final Object value;

  /// Whether the organization locked it.
  ///
  /// **Locked outranks the user's own setting** (the policy precedence rule:
  /// `locked > user setting > policy default > built-in`). Every consumer of
  /// this has to honour that, and a consumer that treats a locked value as a
  /// mere default is the incoherence the spec's own correction was about.
  final bool locked;
}

/// Reads [key] out of [products] for [productId], accepting both spellings.
///
/// Returns `null` when the key is absent, or when its value is neither a map
/// nor a list — a scalar under an object-valued key is a mistake the caller
/// reports rather than coerces.
OrgPolicyEntry? readOrgPolicyEntry(
  Map<String, Map<String, Object?>> products, {
  required String productId,
  required String key,
}) {
  final raw = products[productId]?[key];
  if (raw is List) return OrgPolicyEntry(value: raw, locked: false);
  if (raw is! Map<String, Object?>) return null;

  if (!raw.containsKey('value')) {
    return OrgPolicyEntry(value: raw, locked: false);
  }
  final inner = raw['value'];
  if (inner is! Map<String, Object?> && inner is! List) return null;
  final locked = raw['locked'];
  // A non-boolean `locked` degrades to unlocked rather than throwing, mirroring
  // the resolver's own diagnostic behaviour for scalar keys: a typo in the lock
  // flag must not take the value with it.
  return OrgPolicyEntry(value: inner!, locked: locked is bool && locked);
}
