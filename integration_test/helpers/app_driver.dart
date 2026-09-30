// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/helpers/app_driver.dart
//
// Open-core integration-test helper library.
//
// Each function in this file targets a complete running app (started via
// [bootstrap]) and is intended for use inside a `testWidgets` body that runs
// within the `integration_test` package.
//
// Usage pattern (one `testWidgets` per integration-test file):
//
// ```dart
// void main() {
//   IntegrationTestWidgetsFlutterBinding.ensureInitialized();
//   testWidgets('SPI decoder end-to-end', (tester) async {
//     await loadFixtureVcd(tester, 'protocol/spi/generated/spi_basic.vcd');
//     await activateDecoder(tester, 'SPI');
//     await assertTransactionTableRows(tester, 2);
//   });
// }
// ```
//
// Fixture paths are resolved relative to the repo root (the directory
// containing `pubspec.yaml`), where `flutter test` is run from.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crux_eula/crux_eula.dart';
import 'package:crux_telemetry/crux_telemetry.dart'
    show TelemetryConsentState, kTelemetryConsentKey;
import 'package:crux_workspace/crux_workspace.dart' show WorkspaceService;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/widgets/transaction_table_panel.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart'
    show workspaceProvider;
import 'package:wavecrux/services/session/restore_guard_service.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

/// Suppresses the macOS embedder's mid-test "semantics enabled" signal so
/// integration tests don't trip the framework's
/// `_verifySemanticsHandlesWereDisposed` check at teardown.
///
/// Background: in `SemanticsBinding.initInstances` the framework wires
/// `platformDispatcher.onSemanticsEnabledChanged = _handleSemanticsEnabledChanged`.
/// When the macOS embedder later sends "semantics enabled = true" (which it
/// does asynchronously, sometime during the first test that gains focus or
/// interacts with a widget that touches the accessibility tree), the binding
/// lazily acquires `_semanticsHandle` via `ensureSemantics()`. The handle is
/// only released when the platform sends "semantics enabled = false" — which
/// it never does for the duration of the test process. The framework's
/// `_recordNumberOfSemanticsHandles()` runs BEFORE the first test body, so
/// the late acquisition counts as a leak (`current > recorded`) and every
/// integration test that triggered an enable-event during its body fails at
/// teardown.
///
/// Workaround: after the binding is initialized, replace the callback with a
/// no-op. The platform may still report `semanticsEnabled` as true via the
/// getter, but the binding no longer reacts by acquiring a handle. Any
/// initial handle acquired during `initInstances` (if `semanticsEnabled` was
/// already true at startup) is already part of the recorded baseline, so no
/// leak. Accessibility-driven test code paths that depend on the binding
/// observing platform semantics changes don't apply to our integration tests
/// — they exercise the app's UI and provider plumbing, not the semantics
/// pipeline.
///
/// Call this immediately after [IntegrationTestWidgetsFlutterBinding.ensureInitialized]
/// in each integration test's `main()`.
void suppressPlatformSemanticsLeak() {
  ui.PlatformDispatcher.instance.onSemanticsEnabledChanged = () {};
}

/// Records the answers a first launch asks for, so the app under test boots to
/// its UI rather than to the agreement or the telemetry disclosure.
///
/// **Call this immediately before every `bootstrap`.** [loadFixtureVcd],
/// [loadFixtureVcdAbsolute] and the mobile `loadSyntheticVcd` already do; a
/// test that calls `bootstrap` itself must too.
///
/// `CruxEulaGate` is right for a real first launch and wrong for a test of
/// anything else: it covers the whole app with a modal barrier that swallows
/// every tap, drag, pinch and long-press. The symptom is a gesture that "would
/// not hit test" followed by an assertion about what that gesture should have
/// done, never a visible agreement. Seeding goes through the real
/// `SharedPreferences` store, which `WavecruxEulaStorage` reads, so a broken
/// adapter still fails here. After `SharedPreferences.setMockInitialValues`
/// the value lands in the mock instead, which is the store the app then reads,
/// so the call belongs after the mock, never before it.
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

/// `true` when the integration test is running on a desktop host
/// (macOS/Linux/Windows) rather than a mobile target (iOS/Android).
///
/// Some `integration_test/mobile/` tests assert phone-class behavior (e.g.
/// touch-target sizing, where `MobileMetrics` must return the 48 dp touch
/// set). Under `LiveTestWidgetsFlutterBinding` the app's `MediaQuery` follows
/// the real host view — `platformDispatcher.views.first.physicalSize` — not
/// `tester.binding.setSurfaceSize`, so on a desktop CI runner (e.g. the
/// 1920×1080 xvfb screen on Linux) `deviceClassProvider` resolves to
/// `DeviceClass.desktop` no matter how small a surface the test requests, and
/// the assertion measures desktop metrics. These tests are only meaningful on
/// a genuinely phone-sized device, so they pass `skip: skipOnDesktopHost` and
/// run on the iOS/Android sim+emulator matrix, where `Platform.isIOS`/
/// `isAndroid` is true and the physical size is phone-class.
bool get skipOnDesktopHost => !(Platform.isAndroid || Platform.isIOS);

/// `true` when the integration test is running on a mobile device
/// (iOS/Android) rather than a desktop host — the mirror of
/// [skipOnDesktopHost].
///
/// Some `integration_test/mobile/` tests *simulate* a device class the running
/// machine isn't, by calling `tester.binding.setSurfaceSize` (e.g. a 1280×800
/// "desktop" or 1024×768 "tablet" surface) and then asserting class-specific
/// layout. That works under the desktop binding, where `setSurfaceSize` drives
/// `MediaQuery` and therefore `deviceClassProvider`. On a real device the
/// physical screen dominates, so the class never changes and the assertions
/// can't hold — and tests that seed state from host fixture *paths* fail
/// outright because the app sandbox isn't the repo root. These tests are fully
/// covered by the desktop/Linux integration sweep, so they pass
/// `skip: skipOnMobileDevice` to stay off the on-device (emulator/simulator)
/// matrix, which instead runs the genuinely device-only tests (FFI-from-APK,
/// platform channels, real touch-target sizing, gestures).
bool get skipOnMobileDevice => Platform.isAndroid || Platform.isIOS;

/// Polls until the [TransactionTablePanel] renders at least [min] data row(s),
/// failing after [timeout].
///
/// Use after activating a decoder. `decodeAll` populates the provider first;
/// the panel's `DataTable` (un-virtualized — it builds every `DataRow`
/// eagerly) then renders over the following frames. A *synchronous* assertion
/// races that build and intermittently finds zero `DataTable`s for large
/// transaction sets (thousands of rows, e.g. the AXI4 captured fixtures),
/// even though the decode succeeded. This bounded condition-poll returns the
/// instant the rows are observable and never uses `pumpAndSettle(Duration)`.
Future<void> expectTransactionTableRows(
  WidgetTester tester, {
  int min = 1,
  Duration timeout = const Duration(seconds: 30),
}) async {
  expect(find.byType(TransactionTablePanel), findsOneWidget);
  final ok = await pumpUntil(
    tester,
    () {
      final table = find.descendant(
        of: find.byType(TransactionTablePanel),
        matching: find.byType(DataTable),
      );
      if (table.evaluate().isEmpty) return false;
      return tester.widget<DataTable>(table.first).rows.length >= min;
    },
    timeout: timeout,
  );
  expect(
    ok,
    isTrue,
    reason:
        'transaction table did not render >= $min row(s) within '
        '${timeout.inSeconds}s',
  );
}

/// Pumps the live tree in [interval] steps until [condition] returns true or
/// [timeout] elapses, then returns whether [condition] held.
///
/// IMPORTANT — use this, NOT `pumpAndSettle(const Duration(seconds: N))`, to
/// wait for work in an integration test.
///
/// Under [LiveTestWidgetsFlutterBinding] (the binding every test in this tree
/// runs under) the `duration` argument to `pump` / `pumpAndSettle` is the
/// *per-pump real-time interval*, NOT a timeout. `pumpAndSettle(Duration(
/// seconds: 10))` therefore schedules a real 10-second `Timer` and blocks the
/// FULL ten seconds even when the UI settled instantly — multiplied across the
/// suite that is minutes of wasted CI wall-clock. Stripping the duration to a
/// bare `pumpAndSettle()` is also wrong: the background-isolate FFI parse and
/// the decode pass schedule NO Flutter frames until they complete, so a bare
/// `pumpAndSettle()` returns before the data is ready and the test races the
/// load. A bounded condition-poll is the only correct shape: it returns the
/// instant the real ready-state is observable (e.g. `waveformSourceProvider`
/// non-loading, a decoder's transactions populated, a tab count reached) and
/// caps the wait at [timeout].
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

/// True once the active tab's [waveformSourceProvider] has resolved — i.e. the
/// background-isolate FFI parse produced a source (`value != null`) or failed
/// (`hasError`). The provider sits at `AsyncData(null)` before the load starts
/// and `AsyncLoading` while parsing, so this is the earliest point at which a
/// loaded waveform is observable.
bool _activeWaveformReady(WidgetTester tester) {
  final async = activeTabContainer(tester).read(waveformSourceProvider);
  return async.hasError || async.value != null;
}

/// Pumps until the active tab's waveform source has resolved (loaded or
/// errored), or [timeout] elapses; returns whether it resolved.
///
/// The canonical "wait for the background-isolate FFI parse to finish"
/// primitive. [loadFixtureVcd] uses it internally; call it directly after a
/// bare `bootstrap(args: [path])` in tests that boot the app themselves
/// (e.g. multi-file CLI boots) instead of going through [loadFixtureVcd].
Future<bool> pumpUntilWaveformReady(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 10),
}) => pumpUntil(tester, () => _activeWaveformReady(tester), timeout: timeout);

/// Returns the root [ProviderContainer] the live app is rendering against.
///
/// Pulled directly off the outermost [UncontrolledProviderScope] widget's
/// public `container` field rather than via
/// `ProviderScope.containerOf(tester.element(find.byType(UncontrolledProviderScope).first))`.
/// Under flutter_riverpod 3 the public `UncontrolledProviderScope` is a
/// `StatefulWidget` that wraps a private `_UncontrolledProviderScope`
/// `InheritedWidget` as its *child*; calling
/// `dependOnInheritedWidgetOfExactType<_UncontrolledProviderScope>()` from
/// the outer wrapper's own element walks UP and finds nothing →
/// `StateError: No ProviderScope found`. Reading the container off the
/// widget instance avoids the inherited-widget walk entirely.
///
/// Returns the **root** container — the one supplied to `bootstrap()`'s
/// `runApp(UncontrolledProviderScope(...))` at the top of the live tree.
/// Per-pane and per-tab scopes (see `PaneHost` and `ViewerScreen`) are
/// nested inside the root scope; to access their containers, look them
/// up via [tabContainerManagerProvider] / [paneContainerManagerProvider]
/// on the root container rather than walking the widget tree.
ProviderContainer rootContainer(WidgetTester tester) {
  final scope = tester.widget<UncontrolledProviderScope>(
    find.byType(UncontrolledProviderScope).first,
  );
  return scope.container;
}

/// Returns the per-tab [ProviderContainer] for the workspace's currently
/// active tab.
///
/// Waveform-specific state (`waveformSourceProvider`, `hierarchyProvider`,
/// `signalGroupsProvider`, `cursorStateProvider`, `fileWatcherProvider`,
/// `fsmProvider`, …) is overridden per-tab in `wavecruxTabOverrides`, so reads
/// of those providers must go through this container rather than the root one.
/// Resolves the active tab via `activeTabIdProvider` and looks its container up
/// in the `tabContainerManagerProvider`.
ProviderContainer activeTabContainer(WidgetTester tester) {
  final root = rootContainer(tester);
  final tcm = root.read(tabContainerManagerProvider);
  final activeTabId = root.read(activeTabIdProvider);
  return tcm.containerFor(activeTabId);
}

/// The per-**pane** [ProviderContainer] behind the waveform canvas, resolved
/// fresh on every call.
///
/// **Never cache the result across an interaction that can reflow the layout.**
/// Revealing a dock used to rebuild the whole IDE layout (the restore-bar
/// wrapper changed its widget type), which disposed the pane's container and
/// built a new one, so a handle captured beforehand threw
///
///   Bad state: Tried to read a provider from a ProviderContainer that was
///   already disposed
///
/// on its next read. That rebuild is gone — the wrapper keeps one tree shape,
/// and a regression test holds it there — but a pane can still be remounted
/// by a split, a cross-pane tab move or a device-class change, so resolving
/// at each use site instead of hoisting into a `final` stays the rule.
ProviderContainer paneContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(WaveformCanvas)));

/// Flushes any pending debounced workspace auto-save held by an app instance
/// still mounted from an earlier `testWidgets` body in this file, so it can
/// no longer rewrite `workspace.json` behind a subsequent clear. No-op when
/// no app tree is mounted (first boot in the file).
Future<void> _flushMountedAppWorkspaceSave() async {
  final scopes = find.byType(UncontrolledProviderScope).evaluate();
  if (scopes.isEmpty) return;
  // Depth-first order puts the root scope (the one bootstrap installs) first;
  // workspaceProvider is a root-scope provider, so that is the container
  // holding the debounce timer. Same resolution rationale as [rootContainer].
  final container =
      (scopes.first.widget as UncontrolledProviderScope).container;
  await container.read(workspaceProvider.notifier).flushPendingSave();
}

/// Deletes the auto-managed `{appSupportDir}/workspace.json` (and the per-tab
/// session sidecars) so a fresh launch starts from an empty workspace.
///
/// Integration tests run sequentially against a shared application-support
/// directory; a test that persists a workspace (the `workspace/*` round-trip
/// suite, or any run whose debounced auto-save lands) leaves a `workspace.json`
/// behind. On the next launch `bootstrap` hydrates `workspaceProvider` from that
/// file (app.dart) before the CLI file opens, so a stale *deferred* (unloaded)
/// tab lands at `tabListProvider.first` while the opened fixture becomes the
/// *active* tab — and any test that reads `tabListProvider.first` then reads the
/// wrong, source-less container. [loadFixtureVcd]/[loadFixtureVcdAbsolute] call
/// this first so every fixture launch is the hermetic single-tab scenario those
/// tests assume (mirrors the explicit `clear()` the `workspace/*` tests do).
///
/// Clearing `workspace.json` alone only *orphans* the per-tab session sidecars
/// under `{appSupportDir}/sessions/` — they linger on disk. A subsequent boot
/// that hydrated a stale workspace (clear skipped, or a tab-id collision) would
/// re-attach the orphaned sidecar's persisted decoders on top of the ones the
/// test adds, producing the "N× transaction-table rows" over-decode flake on
/// the Linux integration sweep. So we also wipe the sidecar directory, leaving
/// on-disk persistence in a truly empty state for the fresh launch.
///
/// Clearing alone is not enough when an app instance from an earlier
/// `testWidgets` body in the same file is still mounted: its workspace
/// notifier holds a 2 s-debounced auto-save (and a dispose-time
/// `flushPendingSave`, triggered when the next `bootstrap()`'s `runApp`
/// replaces the tree). Either one can rewrite `workspace.json` with the
/// previous test's tabs *after* this clear but *before* the new instance's
/// restore read — on the slow Windows Debug runner the new boot then restores
/// a stale tab and "boot with no workspace → EmptyCanvasState" tests time
/// out (windows-latest 2026-07-02 tablet, 2026-07-16 phone). Flushing the
/// mounted instance's pending save FIRST cancels the debounce timer and makes
/// the dispose-time flush a no-op, so nothing can dirty the document after
/// the clear.
Future<void> clearPersistedWorkspace() async {
  await _flushMountedAppWorkspaceSave();
  final service = WorkspaceService(codec: const WaveCruxWorkspaceCodec());
  await service.clear();
  await service.clearAllSidecars();
  // Tests share one application-support dir and run sequentially. A test whose
  // restore guard armed but didn't disarm before teardown (or any crash/force
  // -quit) leaves `{appSupportDir}/restore_in_progress` behind, so the NEXT
  // launch reports StartupRecoveryReason.interrupted and renders the recovery
  // banner — polluting layout assertions (e.g. a transient RenderFlex overflow
  // in mobile/layout_tablet). Disarm it so every hermetic launch starts clean.
  await const RestoreGuardService().disarm();
}

/// Starts the open-core app with [relativePath] resolved under
/// `verification/fixtures/` and pumps until the viewer is idle.
///
/// [relativePath] is a POSIX-style path relative to `verification/fixtures/`,
/// e.g. `'protocol/spi/generated/spi_basic.vcd'`.
///
/// Allows up to 60 seconds for the Rust FFI parse and initial paint to
/// settle — large VCDs may need the full budget, but the [pumpUntil]
/// condition-poll returns the instant the parse resolves, so the typical wait
/// is a few hundred milliseconds. Call this exactly once per `testWidgets`
/// body; the Flutter framework throws if `runApp` is invoked more than once in
/// a single test process. Calls [clearPersistedWorkspace] first so every
/// fixture launch is the hermetic single-tab scenario these tests assume.
Future<void> loadFixtureVcd(WidgetTester tester, String relativePath) async {
  await clearPersistedWorkspace();
  final fixturePath = path_join(
    Directory.current.path,
    'verification',
    'fixtures',
    relativePath,
  );
  await seedFirstLaunchAnswers();
  await bootstrap(args: [fixturePath]);
  await tester.pump();
  await pumpUntil(
    tester,
    () => _activeWaveformReady(tester),
    // Heavier captured fixtures (e.g. multi-MB .fst) can exceed the 10s
    // default on slow headless CI; pumpUntil returns the instant it's ready,
    // so a larger cap only extends the slow path.
    timeout: const Duration(seconds: 60),
  );
  await tester.pumpAndSettle();
}

/// Starts the open-core app with [absolutePath] as the file to open and pumps
/// until the viewer is idle.
///
/// Use this variant when the file path is already absolute (e.g. a temp file
/// created during the test). For fixture-relative paths prefer [loadFixtureVcd].
Future<void> loadFixtureVcdAbsolute(
  WidgetTester tester,
  String absolutePath,
) async {
  await clearPersistedWorkspace();
  await seedFirstLaunchAnswers();
  await bootstrap(args: [absolutePath]);
  await tester.pump();
  await pumpUntil(
    tester,
    () => _activeWaveformReady(tester),
    // Heavier captured fixtures (e.g. multi-MB .fst) can exceed the 10s
    // default on slow headless CI; pumpUntil returns the instant it's ready,
    // so a larger cap only extends the slow path.
    timeout: const Duration(seconds: 60),
  );
  await tester.pumpAndSettle();
}

/// Opens the decoder picker and activates the decoder named [decoderDisplayName].
///
/// The flow handled by this helper:
/// 1. Tap the "Add Protocol Decoder" toolbar button to open [DecoderPickerDialog].
/// 2. Expand all collapsed [ExpansionTile] category sections so every decoder
///    name is visible.
/// 3. Tap the decoder's list tile.
/// 4. (When [runAutoBind] is true, which is the default) In the config dialog,
///    tap "Auto-bind signals" to open the auto-bind preview, then tap
///    "Apply all" to apply the best-guess signal bindings.
/// 5. Tap "Add Decoder" to commit the decoder and trigger the decode pass.
/// 6. Poll (up to 10 s, returning early) until the newly-added decoder's
///    transactions have populated — `decodeAll()` runs unawaited off the
///    "Add Decoder" tap and awaits FFI signal loads, so the transactions
///    appear only after the background isolate returns. Keying the wait on the
///    *last* decoder's transactions (rather than on a `DataTable` being
///    present) is correct for stacked / multi-decoder activations, where the
///    table is already on screen from a previous decoder.
///
/// Pass [runAutoBind] as `false` for stacked decoders that have no required
/// signal bindings (e.g. SPI Flash) — these can be added directly without
/// going through the auto-bind flow.
///
/// Example:
/// ```dart
/// await activateDecoder(tester, 'SPI');
/// await activateDecoder(tester, 'SPI Flash', runAutoBind: false);
/// ```
Future<void> activateDecoder(
  WidgetTester tester,
  String decoderDisplayName, {
  bool runAutoBind = true,
}) async {
  // Tap the "Add Protocol Decoder" toolbar button. It is always present once
  // a file is loaded, regardless of whether signals have been added to the
  // viewer — this avoids any dependency on WaveformCanvas.waveformCanvasKey
  // which only appears when signal lanes are populated.
  await tester.tap(find.byIcon(Icons.developer_board).first);
  await tester.pumpAndSettle();

  // Expand all collapsed category sections so the decoder tile is visible.
  // Scope to the AlertDialog so that ExpansionTiles in the signal tree (which
  // is alive in the widget tree behind the dialog overlay) are not counted or
  // tapped. ensureVisible handles the case where expanded content scrolls a
  // later tile just below the 520 dp SizedBox clip boundary.
  final dialogFinder = find.byType(AlertDialog);
  final tileCount = tester
      .widgetList(
        find.descendant(of: dialogFinder, matching: find.byType(ExpansionTile)),
      )
      .length;
  for (var i = 0; i < tileCount; i++) {
    final tileFinder = find
        .descendant(
          of: dialogFinder,
          matching: find.byType(ExpansionTile),
        )
        .at(i);
    await tester.ensureVisible(tileFinder);
    await tester.pumpAndSettle();
    await tester.tap(tileFinder);
    await tester.pumpAndSettle();
  }

  // Tap the decoder's list tile in the picker — scoped to the dialog so that
  // a signal whose name matches the decoder name (e.g. 'SPI') in the tree
  // panel behind the overlay is not accidentally matched first.
  // ensureVisible scrolls the dialog's SingleChildScrollView to bring the
  // tile back into view after category expansion may have scrolled it above
  // the visible area.
  final decoderFinder = find.descendant(
    of: dialogFinder,
    matching: find.text(decoderDisplayName),
  );
  await tester.ensureVisible(decoderFinder);
  await tester.pumpAndSettle();
  await tester.tap(decoderFinder);
  await tester.pumpAndSettle();

  if (runAutoBind) {
    // DecoderConfigDialog is now open. Trigger auto-bind.
    await tester.tap(find.text('Auto-bind signals'));
    await tester.pumpAndSettle();

    // DecoderAutoBindPreviewDialog is now open. Apply all suggested bindings.
    await tester.tap(find.text('Apply all'));
    await tester.pumpAndSettle();
  }

  // Confirm — add the decoder and trigger the decode pass.
  await tester.tap(find.text('Add Decoder'));
  final container = activeTabContainer(tester);
  await pumpUntil(
    tester,
    () {
      final decoders = container.read(activeDecodersProvider);
      return decoders.isNotEmpty && decoders.last.transactions.isNotEmpty;
    },
    // decodeAll() awaits FFI signal loads off the "Add Decoder" tap; the
    // heavier captured fixtures can exceed the 10s default on slow CI.
    timeout: const Duration(seconds: 60),
  );
  await tester.pumpAndSettle();
}

/// Loads [fstRelativePath] and activates its decoder using the EXPLICIT signal
/// bindings from the sibling `<name>.fixture.json`, then runs the decode pass.
///
/// Captured-fixture integration tests use this instead of [activateDecoder]'s
/// auto-bind: real captured traces frequently expose the same bus under
/// multiple scopes (e.g. the master interface `tb.M_*` and the DUT internals
/// `tb.DUV.*`), which auto-bind cannot disambiguate without human input — so
/// relying on it makes the test non-deterministic. Binding the validated
/// `fixture.json` paths (the same source of truth the unit sweep uses) is
/// deterministic and still exercises the full app pipeline: file open →
/// `decodeAll` on the FFI isolate → transaction-table render.
Future<void> activateDecoderFromCapturedSpec(
  WidgetTester tester,
  String fstRelativePath,
) async {
  await loadFixtureVcd(tester, fstRelativePath);

  final specPath = path_join(
    Directory.current.path,
    'verification',
    'fixtures',
    fstRelativePath.replaceFirst(
      RegExp(r'\.(fst|vcd)(\.zst)?$'),
      '.fixture.json',
    ),
  );
  final spec =
      jsonDecode(File(specPath).readAsStringSync()) as Map<String, dynamic>;
  final decoderId = spec['decoder'] as String;
  final pathBindings = (spec['signal_bindings'] as Map).cast<String, String>();
  final parameters = Map<String, Object?>.from(
    spec['parameters'] as Map? ?? const {},
  );

  final container = activeTabContainer(tester);
  final source = container.read(waveformSourceProvider).value!;
  final refByPath = <String, String>{
    for (final v in source.findVariables(const SignalFilter()))
      v.fullPath: v.signalRef,
  };
  final refBindings = <String, String>{
    for (final entry in pathBindings.entries)
      entry.key:
          refByPath[entry.value] ??
          (throw StateError(
            'fixture $decoderId: signal not in trace: ${entry.value}',
          )),
  };

  // Stacked decoders (e.g. SPI Flash on top of SPI) declare their base in a
  // `parent` block. The base must be active first so `decodeAll`'s Pass 1
  // produces the parent transactions that Pass 2 consumes; without it the
  // stacked decoder decodes against nothing. The parent reads the same raw
  // signals (the child's `requiredSignals` is empty) but its own parameters.
  final parentSpec = spec['parent'] as Map?;
  if (parentSpec != null) {
    final parentId = parentSpec['decoder'] as String;
    final parentParams = Map<String, Object?>.from(
      parentSpec['parameters'] as Map? ?? const {},
    );
    container
        .read(activeDecodersProvider.notifier)
        .addDecoder(
          parentId,
          DecoderConfig(signalBindings: refBindings, parameters: parentParams),
        );
  }

  container
      .read(activeDecodersProvider.notifier)
      .addDecoder(
        decoderId,
        DecoderConfig(signalBindings: refBindings, parameters: parameters),
      );
  await container.read(activeDecodersProvider.notifier).decodeAll();
  await tester.pump();
  await pumpUntil(tester, () {
    final ds = container.read(activeDecodersProvider);
    return ds.isNotEmpty && ds.last.transactions.isNotEmpty;
  }, timeout: const Duration(seconds: 60));
  await tester.pumpAndSettle();
}

/// Asserts that the [TransactionTablePanel] is visible and contains exactly
/// [expectedCount] decoded transaction rows.
///
/// When [expectedCount] is 0, asserts the panel is showing its empty state
/// (no [DataTable] rendered). Otherwise reads the [DataTable.rows] list
/// length directly, which avoids coupling to internal widget-tree structures.
Future<void> assertTransactionTableRows(
  WidgetTester tester,
  int expectedCount,
) async {
  expect(find.byType(TransactionTablePanel), findsOneWidget);
  if (expectedCount == 0) {
    expect(
      find.descendant(
        of: find.byType(TransactionTablePanel),
        matching: find.byType(DataTable),
      ),
      findsNothing,
    );
    return;
  }
  final dataTableFinder = find.descendant(
    of: find.byType(TransactionTablePanel),
    matching: find.byType(DataTable),
  );
  expect(dataTableFinder, findsOneWidget);
  final dataTable = tester.widget<DataTable>(dataTableFinder);
  expect(dataTable.rows.length, expectedCount);
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Joins path segments with the platform separator. Avoids a `path` package
/// dependency in the integration_test/ tree.
//
// `path_join` is intentionally snake_case — it stands in for dart:path's
// `join`; suppress the identifier-style lint on the declaration itself.
// ignore: non_constant_identifier_names
String path_join(String base, String a, String b, String c) =>
    '$base${Platform.pathSeparator}$a${Platform.pathSeparator}$b${Platform.pathSeparator}$c';
