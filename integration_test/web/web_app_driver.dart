// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/web/web_app_driver.dart
//
// Minimal driver helpers for the Flutter Web integration suite.
//
// Why this exists separately from `integration_test/helpers/app_driver.dart`:
// the web tests run under `flutter drive`, whose web compiler roots the
// `org-dartlang-app:` scheme at the *target file's own directory*
// (`integration_test/web/`). A relative import that escapes upward
// (`../helpers/app_driver.dart`) resolves to a path outside that root and
// fails to compile with "File not found" — which is exactly why the web
// suite never ran in CI before. So the handful of helpers the web tests need
// are mirrored here, inside `web/`, where they import cleanly with no `../`.
//
// Keep these in sync with the canonical desktop definitions in
// `app_driver.dart`; they are deliberately tiny to keep the drift surface
// minimal. The desktop suite continues to import the full `app_driver.dart`.

import 'dart:ui' as ui;

import 'package:crux_eula/crux_eula.dart';
import 'package:crux_telemetry/crux_telemetry.dart'
    show TelemetryConsentState, kTelemetryConsentKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mirror of `app_driver.dart`'s `seedFirstLaunchAnswers`. Call immediately
/// before every `bootstrap`.
///
/// The web build presents the agreement too, and a fresh headless Chrome
/// profile has never accepted it, so without this every web test drives the
/// app from underneath `CruxEulaGate`'s modal barrier: a tap on "Open File"
/// lands on the barrier and the picker is never called. The value goes through
/// the real `SharedPreferences` store (the browser's `localStorage`), which is
/// what `WavecruxEulaStorage` reads.
///
/// The telemetry disclosure is the same kind of blocker: a first launch shows
/// it over the whole app behind a modal barrier until it is answered. It is
/// answered here as declined, so a test run never counts toward usage. The
/// disclosure's own behaviour and accessibility are tested in crux_telemetry.
Future<void> seedFirstLaunchAnswers() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kCruxEulaAcceptedVersionKey, kCruxEulaVersion);
  await prefs.setString(
    kTelemetryConsentKey,
    TelemetryConsentState.disabled.name,
  );
}

/// Mirror of `app_driver.dart`'s `suppressPlatformSemanticsLeak`.
///
/// Replaces the binding's `onSemanticsEnabledChanged` callback with a no-op so
/// the framework's end-of-test `_verifySemanticsHandlesWereDisposed` verifier
/// does not trip when the embedder enables semantics mid-run. Call immediately
/// after `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`. See
/// `app_driver.dart` for the full rationale.
void suppressPlatformSemanticsLeak() {
  ui.PlatformDispatcher.instance.onSemanticsEnabledChanged = () {};
}

/// Mirror of `app_driver.dart`'s `rootContainer`.
///
/// Returns the root [ProviderContainer] supplied to `bootstrap()`'s
/// `runApp(UncontrolledProviderScope(...))` at the top of the live tree.
ProviderContainer rootContainer(WidgetTester tester) {
  final scope = tester.widget<UncontrolledProviderScope>(
    find.byType(UncontrolledProviderScope).first,
  );
  return scope.container;
}

/// Mirror of `app_driver.dart`'s `pumpUntil` — a bounded condition-poll.
///
/// Pumps frames at [interval] until [condition] holds or [timeout] elapses,
/// returning whether it became true. Use this instead of `pumpAndSettle()`
/// whenever the tree hosts an indefinite animation — see [settleEmptyCanvas]
/// for why every web test needs it: the empty-canvas `GlowingAppIcon`
/// halo/pulse controllers `repeat()` forever, so `pumpAndSettle()` never
/// settles and times out.
Future<bool> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  Duration interval = const Duration(milliseconds: 50),
}) async {
  final maxIterations = (timeout.inMilliseconds / interval.inMilliseconds)
      .ceil();
  for (var i = 0; i < maxIterations; i++) {
    if (condition()) return true;
    await tester.pump(interval);
  }
  return condition();
}

/// Settles the empty-canvas / welcome screen without waiting on its indefinite
/// animation.
///
/// The web suite boots onto the empty canvas, whose header hosts a
/// [GlowingAppIcon] whose halo/pulse `AnimationController`s `repeat()` forever.
/// A bare `pumpAndSettle()` on that screen spins until it times out (the glow
/// never settles). The animation is intentional product behavior, so — exactly
/// like the widget-test `_pumpEmptyCanvas` helper — the fix is test-side: build
/// the frame and advance a bounded number of frames so the async
/// recent-files/workspaces/settings providers and any layout reflow flush,
/// without ever waiting for the never-ending animation.
Future<void> settleEmptyCanvas(
  WidgetTester tester, {
  int frames = 20,
  Duration interval = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(interval);
  }
}
