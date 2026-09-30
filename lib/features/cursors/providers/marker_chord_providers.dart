// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart'
    show kCruxInfoSnackDuration;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/router.dart' show rootScaffoldMessengerKey;
import 'package:wavecrux/features/cursors/marker_chord_controller.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

/// Root-scope singleton [MarkerChordController]. Lifting the controller out of
/// `ViewerScreen` (where it used to be a `State` field) lets the focus-
/// independent arming path — the app-level global handlers in `WaveCruxApp` —
/// share the *same* chord state as the focus-dependent path (the viewer's
/// `Actions` handler and the global `HardwareKeyboard` completion handler).
final markerChordControllerProvider = Provider<MarkerChordController>((ref) {
  final controller = MarkerChordController();
  ref.onDispose(controller.dispose);
  return controller;
});

/// Coordinates the two-key marker chords (`M`+a–z = set, `⇧M`+a–z = jump) from
/// a root-scope, focus-independent vantage point.
///
/// ## Why this exists (the focus bug it fixes)
///
/// The bare `M` / `⇧M` shortcuts and the command-palette entries dispatch a
/// `ShortcutActionIntent` that is only caught by the viewer's `Actions` widget
/// when focus sits inside the viewer. After the user touches toolbar / menu
/// chrome (or opens the palette via the global `⌘⇧P` handler), focus leaves
/// that scope and the arming intent is silently dropped — so `M` and the
/// palette "do nothing". Marker chords have no native-menu key-equivalent
/// (a chord cannot be one), so there is no responder-chain fallback either.
///
/// Registering `setMarker` / `jumpToMarker` as app-level global handlers
/// (`WaveCruxApp` → `ShortcutManagerWidget.handlers`) routes both the keypress
/// and the palette dispatch *above* the focus chain to [arm] here. The viewer's
/// `_handleShortcut` cases (used by the menu, which calls the handler directly,
/// and by the in-viewer-focus keyboard path) delegate to the *same* coordinator
/// — exactly one path fires per keystroke because the global `Actions` consumes
/// an intent only for actions it actually handles.
///
/// Snackbars are shown through [rootScaffoldMessengerKey] and localization is
/// resolved from the messenger's (in-`MaterialApp`) context, mirroring the
/// idiom in `WaveCruxApp`.
class MarkerChordCoordinator {
  MarkerChordCoordinator(this._ref);

  final Ref _ref;
  Timer? _timeout;

  /// How long an armed chord waits for its completing a–z keystroke before it
  /// auto-cancels. Mirrors the historical viewer-screen window.
  static const Duration window = Duration(seconds: 3);

  /// Arms the [mode] chord and shows a transient "press a–z" hint. Setting a
  /// marker requires a primary cursor to anchor it; with none, shows a hint and
  /// does not arm.
  void arm(MarkerChordMode mode) {
    final container = _activeContainer();
    if (container == null) return;

    if (mode == MarkerChordMode.set &&
        container.read(cursorStateProvider).primaryCursorTime == null) {
      _showSnackBar((l10n) => l10n.markerSetNoCursor);
      return;
    }

    final controller = _ref.read(markerChordControllerProvider)..arm(mode);
    _showSnackBar(
      (l10n) => mode == MarkerChordMode.set
          ? l10n.markerChordSetHint
          : l10n.markerChordJumpHint,
      duration: window,
    );

    _timeout?.cancel();
    _timeout = Timer(window, () {
      controller.cancel();
      rootScaffoldMessengerKey.currentState?.hideCurrentSnackBar();
    });
  }

  /// Feeds [key] into an armed chord. Returns true when a chord was armed (and
  /// thus the key is consumed — completing or cancelling the chord), false when
  /// nothing was armed so the caller should let the key propagate. Called from
  /// the viewer's global `HardwareKeyboard` handler so completion works
  /// regardless of focus and is swallowed before WASD/QE navigation can claim
  /// it.
  bool handleCompletionKey(LogicalKeyboardKey key) {
    final controller = _ref.read(markerChordControllerProvider);
    if (!controller.isArmed) return false;
    _timeout?.cancel();
    rootScaffoldMessengerKey.currentState?.hideCurrentSnackBar();
    final completion = controller.handleKey(key);
    if (completion != null) _apply(completion);
    return true;
  }

  void _apply(MarkerChordCompletion completion) {
    final container = _activeContainer();
    if (container == null) return;
    final letter = completion.letter;
    switch (completion.mode) {
      case MarkerChordMode.set:
        final cursor = container.read(cursorStateProvider).primaryCursorTime;
        if (cursor == null) return;
        container.read(markerStateProvider.notifier).setMarker(letter, cursor);
      case MarkerChordMode.jump:
        final time = container
            .read(markerStateProvider.notifier)
            .jumpToMarker(letter);
        if (time == null) {
          _showSnackBar((l10n) => l10n.markerNotSet(letter));
          return;
        }
        container.read(cursorStateProvider.notifier).placePrimary(time);
        container.read(navigationProvider.notifier).jumpToTime(time);
    }
  }

  ProviderContainer? _activeContainer() {
    try {
      final tcm = _ref.read(tabContainerManagerProvider);
      return tcm.containerFor(_ref.read(activeTabIdProvider));
    } on Object {
      return null;
    }
  }

  void _showSnackBar(String Function(L10N) message, {Duration? duration}) {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null || !messenger.mounted) return;
    final l10n = Localizations.of<L10N>(messenger.context, L10N);
    if (l10n == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message(l10n)),
          behavior: SnackBarBehavior.floating,
          duration: duration ?? kCruxInfoSnackDuration,
        ),
      );
  }

  void dispose() => _timeout?.cancel();
}

/// Root-scope singleton coordinator. See [MarkerChordCoordinator].
final markerChordCoordinatorProvider = Provider<MarkerChordCoordinator>((ref) {
  final coordinator = MarkerChordCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
