// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/fold_state.dart';
import 'package:wavecrux/services/platform/fold_source.dart';

/// The platform's fold events. Override in tests with a fake [FoldSource].
final foldSourceProvider = Provider<FoldSource>(
  (ref) => const PlatformFoldSource(),
  name: 'foldSourceProvider',
);

/// The device's hinge and crease, maintained by `FoldFeed` near the app root.
///
/// [FoldState.none] on every device without a hinge, and every layout that
/// reads this must then be exactly what it was before fold support existed.
final foldStateProvider = NotifierProvider<FoldStateNotifier, FoldState>(
  FoldStateNotifier.new,
  name: 'foldStateProvider',
);

/// Holds the current [FoldState]. Written only by `FoldFeed` (and tests).
class FoldStateNotifier extends Notifier<FoldState> {
  @override
  FoldState build() => FoldState.none;

  /// Replaces the state; a no-op when [next] equals it.
  void set(FoldState next) {
    if (state == next) return;
    state = next;
  }
}

/// The layout posture alone, so a layout rebuilds when the posture changes and
/// not on every hinge-angle update.
final foldPostureProvider = Provider<FoldPosture>(
  (ref) => ref.watch(foldStateProvider.select((s) => s.posture)),
  name: 'foldPostureProvider',
);

/// Whether the device has a hinge at all (iPhone Duo, Android foldables).
final hasHingeProvider = Provider<bool>(
  (ref) => ref.watch(foldStateProvider.select((s) => s.hasHinge)),
  name: 'hasHingeProvider',
);
