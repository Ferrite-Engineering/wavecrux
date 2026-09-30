// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/policy/wavecrux_policy_keys.dart';

/// Records `license.tier.changed` when this installation's entitlement moves.
///
/// ### Why this is a provider that listens rather than an emitter at a call site
///
/// There is no single place a tier "changes". It is derived — from a stored
/// credential, an activation, a deactivation, an expiry crossing, a policy file
/// supplying a licence at startup — and an emitter at any one of those would
/// miss the others. What an administrator wants in the log is the *transition*,
/// wherever it came from, so the only correct producer observes the resolved
/// value.
///
/// ### The initial resolution is not a change, and this is what makes that true
///
/// Every launch resolves the tier once. Recording that would put a line in the
/// audit file on every start saying nothing happened, and the file's whole value
/// is that a line in it means something. `ref.listen` does not fire for the
/// initial value — only for subsequent ones — so the startup resolution is
/// silently skipped by construction rather than by a flag somebody has to
/// remember to check. The `previous == next` guard below covers the remaining
/// case: a rebuild that re-emits an equal value.
///
/// ### It must be realized eagerly, and a `read` is not enough
///
/// Riverpod is lazy, so nothing constructs this provider on its own; and an
/// un-listened provider is paused, which propagates into the `ref.listen`
/// installed here and drops every event. The Pro overlay therefore
/// registers it in `eagerStartupProvidersProvider`, whose host holds a real
/// root-container subscription for the session. Registering it as a hook is the
/// difference between an audit trail and an audit trail that stops the moment
/// no licence screen is mounted.
///
/// ### Open core is a no-op, honestly
///
/// `licenseTierProvider`'s open-core binding is a constant `openCore`, so this
/// listener can never fire there. It lives in open core anyway, next to the
/// kind it records and alongside WaveCrux's other emitters — the Pro overlay
/// supplies the tier that can actually move, exactly as it supplies the run
/// stream LintCrux's ingestion listener consumes.
final Provider<void> licenseTierChangeAuditListenerProvider = Provider<void>((
  ref,
) {
  ref.listen<LicenseTier>(licenseTierProvider, (previous, next) {
    // `previous` is null only if Riverpod ever delivers an initial value here;
    // it does not, and if that changed this would still refuse to log it.
    if (previous == null || previous == next) return;

    // Both ends of the transition, because "became Pro" and "stopped being
    // Pro" are different events to the person reading the log, and a single
    // `tier` field makes the second one unrecoverable from the first.
    ref
        .read(cruxAuditRecorderProvider)
        .record(
          WaveCruxAuditKinds.licenseTierChanged,
          payload: <String, Object?>{
            'from': previous.name,
            'to': next.name,
          },
        );
  });
}, name: 'licenseTierChangeAuditListenerProvider');
