// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Local-only Presenter-Mode **view-composition** follow state.
///
/// `true` means the local follower has **fully detached** from the presenter's
/// shared composition: the [CollabViewerBridge] restores the follower's own
/// workspace and stops applying the presenter's recipe overlay while this is
/// set. `false` (the default) means the follower mirrors the presenter's
/// displayed signals / decoders / translators / Stage / FSM / panel intent.
///
/// Structural composition is **follow-or-fully-detached** — distinct from the
/// navigation soft-follow ([followDetachedProvider]), which detaches the
/// *viewport / cursor / playhead* independently. A follower can be navigation-
/// detached (peeking at a different time range) while still following the
/// presenter's composition, or vice-versa. There is no idle auto-resume here:
/// re-following the composition is an explicit user action (the Pro
/// composition-scoped "Resume" affordance), because silently rebuilding the
/// whole signal/decoder/Stage view out from under the user would be jarring.
///
/// Local UI state, so this is **not** broadcast and lives at the root scope; it
/// is meaningless for the presenter (who drives rather than follows) and is
/// cleared on session end.
final compositionDetachedProvider =
    NotifierProvider<CompositionDetachedNotifier, bool>(
      CompositionDetachedNotifier.new,
    );

/// Notifier backing [compositionDetachedProvider]. See that provider for
/// semantics.
class CompositionDetachedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Fully detach from the presenter's composition (restore the follower's own
  /// workspace). Idempotent.
  void detach() {
    if (!state) state = true;
  }

  /// Re-follow the presenter's composition (re-apply the latest recipe as an
  /// overlay). Idempotent.
  void resume() {
    if (state) state = false;
  }
}
