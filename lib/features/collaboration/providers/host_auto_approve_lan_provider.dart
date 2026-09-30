// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Open-core seam for the host's **LAN auto-admit** policy.
///
/// `false` (the default) means every joiner — LAN or WAN — waits for the host's
/// explicit approve-or-deny. `true` means joiners arriving over the LAN are
/// admitted without a prompt, for the case the policy exists to serve: a lab
/// bench where the host is driving a projector and does not want a dialog
/// between them and their colleagues.
///
/// **Default off, and deliberately not persisted.** The state holder is
/// in-memory only, so it resets to `false` on every app start. That is the
/// fail-safe direction for an admission control: a host who wanted the relaxed
/// policy re-enables it in one click, whereas a host who forgot they enabled it
/// three weeks ago would otherwise be silently admitting strangers on a hotel
/// network. Persistence is the kind of convenience that has to be asked for.
///
/// It governs LAN only, and that is honest rather than arbitrary: over WAN the
/// room code is the only thing standing between a forwarded invite and a
/// listener, so auto-admitting there would defeat the whole control. Over LAN
/// zero-config discovery already hands the session to anyone on the segment,
/// which is exactly why host approval is the meaningful LAN control.
///
/// Mirrors [hostControlPolicyProvider]: open core owns the in-memory seam so
/// the Settings → Collaboration section (contributed by the Pro overlay via
/// `extraSettingsCategoriesProvider`) binds to a stable provider, and the Pro
/// `CollaborationServiceImpl` reads it fresh on each inbound join request.
final hostAutoApproveLanProvider =
    NotifierProvider<HostAutoApproveLanNotifier, bool>(
      HostAutoApproveLanNotifier.new,
    );

/// Notifier backing [hostAutoApproveLanProvider]. See that provider for
/// semantics.
class HostAutoApproveLanNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Set whether LAN joiners are admitted without a prompt.
  // ignore: avoid_positional_boolean_parameters
  void set(bool autoApprove) {
    if (state != autoApprove) state = autoApprove;
  }

  /// Flip the policy.
  void toggle() => state = !state;
}
