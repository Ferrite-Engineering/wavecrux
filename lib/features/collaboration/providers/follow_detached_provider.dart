// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_async/crux_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Default idle window after which a soft-follow detach auto-resumes following
/// the presenter. The follower "peeked away" and then stopped touching
/// the view; once they have been idle this long, snap back automatically so the
/// room re-converges without a manual action.
///
/// Overridable via [followDetachIdleTimeoutProvider] (tests inject a short
/// duration; a host could expose it as a preference later). A `null` timeout
/// disables auto-resume entirely — detach then persists until the explicit
/// "Resume following" action.
const Duration kFollowDetachIdleTimeout = Duration(seconds: 12);

/// The idle auto-resume window consulted by [FollowDetachedNotifier]. Open-core
/// default is [kFollowDetachIdleTimeout]; override to tune or disable (`null`).
final followDetachIdleTimeoutProvider = Provider<Duration?>(
  (_) => kFollowDetachIdleTimeout,
);

/// Local-only Presenter-Mode soft-follow state.
///
/// `true` means the local follower has navigated away from the presenter's
/// shared viewport (pan / zoom / cursor) and is **detached** — the
/// [CollabViewerBridge] stops driving the local viewport and playhead from the
/// presenter's broadcast while this is set. Detaching is purely local: it does
/// **not** end the session and does **not** change the presenter. A
/// "Resume following `<presenter>`" affordance ([resume]) snaps back, and an idle
/// timeout ([followDetachIdleTimeoutProvider]) auto-resumes.
///
/// This is the "peek without leaving" need that the legacy follow-me model
/// served only by accident (any gesture silently dropped the follower) — here
/// it is first-class and reversible.
///
/// Local UI state, so this is **not** broadcast and lives at the root scope
/// (the bridge reads/writes it via the root [Ref]); it is meaningless for the
/// presenter (who drives rather than follows) and is cleared on session end and
/// when the local participant becomes the presenter.
final followDetachedProvider = NotifierProvider<FollowDetachedNotifier, bool>(
  FollowDetachedNotifier.new,
);

/// Notifier backing [followDetachedProvider]. See that provider for semantics.
class FollowDetachedNotifier extends Notifier<bool> {
  /// The idle auto-resume, on the timeout configured when it was last
  /// restarted: a timeout that changed since gets a fresh debouncer.
  Debouncer? _idle;

  @override
  bool build() {
    ref.onDispose(_cancelIdle);
    return false;
  }

  /// Mark the local follower detached (a local navigation gesture happened).
  ///
  /// Idempotent for the boolean state, but every call **restarts** the idle
  /// auto-resume timer — continuous navigation keeps the follower detached, and
  /// the snap-back fires only once they have been idle for the configured
  /// window. A `null` configured timeout disables auto-resume.
  void detach() {
    final timeout = ref.read(followDetachIdleTimeoutProvider);
    if (timeout == null) {
      _cancelIdle();
    } else {
      var idle = _idle;
      if (idle == null || idle.duration != timeout) {
        idle?.cancel();
        idle = _idle = Debouncer(duration: timeout);
      }
      idle.run(resume);
    }
    if (!state) state = true;
  }

  /// Snap back to following the presenter (the explicit "Resume following"
  /// action, or the idle auto-resume). Cancels any pending idle timer.
  void resume() {
    _cancelIdle();
    if (state) state = false;
  }

  /// Cancels, never disposes: Riverpod keeps this notifier instance when the
  /// provider rebuilds, and [build] registers this as its dispose hook.
  void _cancelIdle() => _idle?.cancel();
}
