// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'system_dialog_provider.g.dart';

/// Tracks whether a native OS dialog (file picker, save dialog) is currently
/// open anywhere in the app.
///
/// On macOS the native [NSOpenPanel] runs its own event loop, which suspends
/// Flutter's main run loop and makes modality automatic. On Windows the Win32
/// dialog runs on a background thread while Flutter's UI thread keeps pumping
/// events, so buttons remain live. This provider lets top-level screens engage
/// an [AbsorbPointer] that blocks all pointer input to the Flutter UI for the
/// duration of the native dialog, matching macOS behaviour.
///
/// Usage — any code that has a [Ref]:
/// ```dart
/// final notifier = ref.read(systemDialogInFlightProvider.notifier);
/// if (ref.read(systemDialogInFlightProvider)) return; // already showing one
/// notifier.begin();
/// try {
///   final result = await FilePicker.pickFiles(...);
///   ...
/// } finally {
///   notifier.end();
/// }
/// ```
@Riverpod(keepAlive: true)
class SystemDialogInFlight extends _$SystemDialogInFlight {
  @override
  bool build() => false;

  /// Marks a native OS dialog as open. Call before [FilePicker] or any native
  /// save/open dialog is shown.
  void begin() => state = true;

  /// Marks the native OS dialog as closed. Always call in a `finally` block,
  /// on the notifier read before the dialog's `await`.
  ///
  /// Never `ref.read(systemDialogInFlightProvider.notifier).end()` inside the
  /// `finally`. Whatever opened the dialog can be disposed while it is up — on
  /// Windows and Linux the app stays live behind an OS picker — and its `ref`
  /// then throws, so the flag stays set and the viewer ignores every pointer
  /// event for the rest of the session. The static guard
  /// `test/static/finally_after_await_guard_test.dart` enforces this.
  void end() => state = false;
}
