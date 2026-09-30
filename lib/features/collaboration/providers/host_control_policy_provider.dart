// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Open-core seam for the Presenter-Mode **host control policy**.
///
/// `true` (the default) means non-presenters may **request** the presenter role
/// — the request → approve/deny transfer path is available, surfacing an
/// approve-or-deny prompt to the current presenter/host. `false` means the host
/// keeps control assignment to explicit handoff only; the "Request Control"
/// affordance is hidden and incoming requests are ignored.
///
/// This replaces (retires) the legacy follow-me "default follow mode" setting:
/// Presenter Mode makes shared-viewport the default-on durable state, so a
/// per-user follow-mode preference no longer has meaning. The single host-side
/// knob that remains is whether participants may *ask* for control.
///
/// The state holder lives in open-core so the Settings → Collaboration section
/// (contributed by the Pro overlay via `extraSettingsCategoriesProvider`) binds
/// to a stable provider, and so the Pro `CollaborationServiceImpl` can read the
/// host's policy when arbitrating requests. Persistence and the broadcast of
/// the effective policy to participants are Pro concerns; open-core only owns
/// the in-memory seam (default `true`).
final hostControlPolicyProvider =
    NotifierProvider<HostControlPolicyNotifier, bool>(
      HostControlPolicyNotifier.new,
    );

/// Notifier backing [hostControlPolicyProvider]. See that provider for
/// semantics.
class HostControlPolicyNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  /// Set whether participants may request control.
  // ignore: avoid_positional_boolean_parameters
  void set(bool allow) {
    if (state != allow) state = allow;
  }

  /// Flip the policy.
  void toggle() => state = !state;
}
