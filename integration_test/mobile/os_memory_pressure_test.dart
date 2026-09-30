// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/mobile/os_memory_pressure_test.dart
//
// Real OS memory-pressure callback (iOS `didReceiveMemoryWarning` / Android
// `onTrimMemory`, surfaced to Flutter as `WidgetsBindingObserver
// .didHaveMemoryPressure()`).
//
// `MobileMemoryGuardNotifier` (lib/features/viewer/providers/
// mobile_memory_guard_provider.dart) registers itself as a
// `WidgetsBindingObserver` and overrides `didHaveMemoryPressure()` to force
// an immediate pressure-relief pass at `MemoryPressureLevel.critical`,
// unloading any signal that is loaded but not present in the active tab's
// signal group. `ViewerScreen` listens to the guard's state
// (`_onMemoryGuardStateChanged`, around viewer_screen.dart:1065) purely to
// surface a snackbar — the actual drop-caches-without-crashing behavior
// lives entirely in the notifier.
//
// The guard only activates for non-desktop device classes
// (`MobileMemoryGuardNotifier.build()` early-returns on
// `DeviceClass.desktop`), and `deviceClassForSize` unconditionally floors to
// `DeviceClass.desktop` on a *native* desktop host (macOS/Windows/Linux) —
// window size alone can never demote it (see `isDesktopHostPlatform`).
// Since this integration-test binary runs as a real macOS app, exercising
// the guard requires forcing `defaultTargetPlatform` to a touch OS for the
// duration of the test via `debugDefaultTargetPlatformOverride` — the same
// technique already used by this repo's platform-conditional widget/unit
// tests (e.g. `test/shared/layouts/device_class_provider_test.dart`,
// `test/features/settings/providers/orientation_lock_provider_test.dart`).
// This only changes Flutter's *reported* target platform for
// platform-conditional Dart logic; it does not touch the real `dart:io`
// `Platform.isIOS` the OS itself reports, so it cannot accidentally invoke
// real iOS-only platform channels.
//
// `tester.view.physicalSize` (not `tester.binding.setSurfaceSize`, which
// does not drive `MediaQuery` under the live app-driving binding every
// `integration_test/` file runs under) is what actually shrinks the
// reported window down to phone width here, landing `deviceClassProvider`
// on `DeviceClass.phone` — the simplest mobile layout, and the one that
// reproduced reliably locally (see the flake note below).
//
// Known-flake note: on a local macOS 26 (Tahoe) / Flutter 3.44.2 debug
// launch, the SnackBar this test's pressure-relief pass triggers
// (`ViewerScreen._onMemoryGuardStateChanged`) intermittently crashed the
// *engine's* accessibility bridge (`flutter::AccessibilityBridge::
// CreateRemoveReparentedNodesUpdate`, `EXC_BAD_ACCESS`/`SIGSEGV`) a frame or
// two later when the surface was left at the real (tablet-class) launch
// window size — the documented Flutter debug-JIT/LLDB toolchain issue on
// macOS 26 (release/AOT and Xcode-direct launches are unaffected), not a
// defect in this test or in `MobileMemoryGuardNotifier`. Forcing the
// simpler phone-class widget tree above avoided it across every local run;
// if it ever resurfaces here, re-check `~/Library/Logs/DiagnosticReports/`
// for that exact frame before suspecting this test or the guard.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/viewer/providers/mobile_memory_guard_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/services/mobile/mobile_memory_guard_service.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '../helpers/app_driver.dart';
import '_mobile_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'real OS memory-pressure callback drops non-visible signal data and '
    'the app stays alive and responsive',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // `debugDefaultTargetPlatformOverride` must be reset *before* the test
      // body returns — flutter_test verifies foundation debug vars are unset
      // ahead of `addTearDown` callbacks running, so a plain `addTearDown`
      // here would trip `debugAssertAllFoundationVarsUnset`.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        // `loadSyntheticVcd`, not the host-side `loadFixtureVcd`: the latter
        // resolves the fixture against `Directory.current.path`, which is the
        // repo root on a desktop host but the app sandbox on a device. On the
        // Android emulator that produced
        // `//verification/fixtures/vcd/scalar_basics.vcd` — an empty base
        // joined to a repo-relative tail — and a PathNotFoundException on
        // every run *and* on the fresh-emulator retry. Every other test in
        // this directory already loads the mobile-safe way; this was the one
        // holdout. See `_mobile_fixture.dart`'s header.
        final load = await loadSyntheticVcd(tester);

        final root = load.rootContainer;
        expect(
          root.read(deviceClassProvider),
          isNot(DeviceClass.desktop),
          reason:
              'the memory guard only activates off the desktop device '
              'class; the platform override above must have taken effect',
        );

        final tab = load.tabContainer;
        final source = tab.read(waveformSourceProvider).value!;
        final vars = source.findVariables(const SignalFilter());
        final clk = vars.firstWhere((v) => v.name == 'clk');
        final data = vars.firstWhere((v) => v.name == 'data');

        // `clk` is added to the panel — this is the "visible" signal the
        // guard must spare. Give the canvas a frame to lazily load it.
        tab.read(signalGroupsProvider.notifier).addSignal(clk);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(source.isSignalLoaded(clk.signalRef), isTrue);

        // `data` is loaded directly (bypassing the panel/canvas) but never
        // added to the signal group — loaded-but-not-visible, exactly the
        // condition the guard's pressure-relief pass targets.
        await source.loadSignal(data.signalRef);
        expect(source.isSignalLoaded(data.signalRef), isTrue);

        final before = root.read(mobileMemoryGuardProvider);
        expect(before.pressureLevel, MemoryPressureLevel.ok);
        expect(before.lastUnloadedCount, 0);

        // The real OS callback path: this is the exact framework entry
        // point iOS's `didReceiveMemoryWarning` / Android's `onTrimMemory`
        // surface through, invoking every registered
        // `WidgetsBindingObserver` (including `MobileMemoryGuardNotifier`)
        // synchronously.
        WidgetsBinding.instance.handleMemoryPressure();

        final unloaded = await pumpUntil(
          tester,
          () => !source.isSignalLoaded(data.signalRef),
        );
        expect(
          unloaded,
          isTrue,
          reason:
              'the non-visible loaded signal should be dropped by the '
              'pressure-relief pass triggered off the OS callback',
        );

        // No crash, no unhandled exception from the callback or the async
        // relief pass that followed it.
        expect(tester.takeException(), isNull);

        // The visible (panel-added) signal must be spared.
        expect(source.isSignalLoaded(clk.signalRef), isTrue);

        final after = root.read(mobileMemoryGuardProvider);
        expect(after.pressureLevel, MemoryPressureLevel.critical);
        expect(after.lastUnloadedCount, greaterThan(0));

        // The app stays alive and responsive: one more frame renders
        // cleanly (no exception) and the canvas is still mounted.
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(WaveformCanvas), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
