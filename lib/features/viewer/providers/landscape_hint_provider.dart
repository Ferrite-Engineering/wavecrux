// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'landscape_hint_provider.g.dart';

/// Tracks whether the "rotate to landscape" hint has been shown or
/// dismissed in the current session.
///
/// The hint is a one-shot, non-blocking suggestion shown once per session
/// when a waveform file is opened on a phone in portrait orientation. Once
/// either [markShown] or [dismiss] is called, [shouldShow] returns `false`
/// for the remainder of the session.
///
/// State is intentionally session-scoped (not persisted) — each app launch
/// gets a fresh chance to surface the hint.
@Riverpod(keepAlive: true)
class LandscapeHintNotifier extends _$LandscapeHintNotifier {
  @override
  bool build() => true;

  /// True when the hint has not yet been shown or dismissed this session.
  bool get shouldShow => state;

  /// Records that the hint has been displayed; subsequent calls to
  /// [shouldShow] return `false`.
  void markShown() {
    if (state) state = false;
  }

  /// Records that the user explicitly dismissed the hint. Equivalent to
  /// [markShown] for the suppression check.
  void dismiss() {
    if (state) state = false;
  }
}
