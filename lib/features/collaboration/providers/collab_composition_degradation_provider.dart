// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/collab_view_composition.dart';

/// The set of presenter-composition references the local follower's own file
/// could **not** resolve when replaying the composition overlay — the open-core
/// **missing-reference degradation hook**.
///
/// The [CollabViewerBridge] writes here as it applies the presenter's
/// composition: a signal path absent from the follower's hierarchy, a decoder
/// id the follower's build does not have registered (a Pro decoder on an Open
/// Core viewer), or an unknown Stage widget id. Each lands here instead of
/// crashing the overlay; the matching surface renders a placeholder.
///
/// This is a **seam**: open-core exposes the data, and the closed-source Pro
/// overlay binds it to the existing waveform-mismatch banner ("the presenter's
/// view references signals/decoders your file doesn't have"). Local UI state —
/// not broadcast — cleared when the overlay detaches or the session ends.
final collabCompositionDegradationProvider =
    NotifierProvider<
      CollabCompositionDegradationNotifier,
      CollabCompositionDegradation
    >(
      CollabCompositionDegradationNotifier.new,
    );

/// Notifier backing [collabCompositionDegradationProvider].
class CollabCompositionDegradationNotifier
    extends Notifier<CollabCompositionDegradation> {
  @override
  CollabCompositionDegradation build() => CollabCompositionDegradation.none;

  /// Record the degradation observed while applying a presenter composition.
  // ignore: use_setters_to_change_properties
  void report(CollabCompositionDegradation degradation) {
    state = degradation;
  }

  /// Clear all recorded degradation (overlay detached / session ended).
  void clear() {
    if (state != CollabCompositionDegradation.none) {
      state = CollabCompositionDegradation.none;
    }
  }
}
