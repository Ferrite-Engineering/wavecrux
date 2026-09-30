// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/gestures/gesture_conflict_drawer_canvas_test.dart
//
// Gesture conflict resolution: drawer vs canvas.
//
// At phone layout the viewer's Scaffold exposes the signal/activity panel as a
// left [Drawer] while the waveform canvas owns horizontal drags over its body.
// The drawer-vs-canvas conflict only exists at phone class — at tablet/desktop
// the side panels are docked panes, not a drawer, so there is no conflict.
//
// What this test asserts, and where it runs:
//   - EVERYWHERE (incl. macOS/Linux/Windows desktop CI): a horizontal touch
//     drag on the canvas body is treated as a viewport pan, NOT a cursor
//     scrub — the cursor tick must not change — and it must not spuriously
//     open a drawer.
//   - PHONE CLASS ONLY (iOS/Android mobile track): the left signal/activity
//     Drawer exists, opens via its production path, and opening it does not
//     disturb the canvas cursor.
//
// Harness notes (follow-up context):
//   - The macOS/desktop integration runner classifies even a 390 x 844 surface
//     as `DeviceClass.tablet` (the native physical screen dominates the
//     `deviceClassProvider` classification — the same reason the phone
//     layout tests are mobile-track). The phone-only Drawer is therefore absent
//     on desktop CI, so the drawer half is gated on the Drawer actually being
//     present and runs on the iOS/Android simulator matrix.
//   - The left-EDGE drawer-open *gesture* (Scaffold `drawerEdgeDragWidth`
//     drag-recognizer vs the canvas raw-pointer `Listener`) is a gesture-arena
//     interaction faithful only on a real device (the verification guide
//     already flags the drawer-vs-canvas conflict as real-device-only); it is
//     verified manually. This test uses the drawer's production open path.
//   - Canvas viewport-pan magnitude is covered by the two-finger pan
//     test (`integration_test/mobile/gesture_two_finger_pan_test.dart`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '../helpers/app_driver.dart' show suppressPlatformSemanticsLeak;
import '../mobile/_mobile_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('canvas swipe stays a pan (no cursor scrub); phone drawer opens '
      'cleanly', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final load = await loadSyntheticVcd(tester);
    await tester.pumpAndSettle();

    // Add a signal so the canvas paints lanes (a real gesture surface).
    final source = load.tabContainer.read(waveformSourceProvider).value;
    expect(source, isNotNull);
    final vars = source!.findVariables(const SignalFilter());
    expect(vars, isNotEmpty);
    await source.loadSignal(vars.first.signalRef);
    load.tabContainer.read(signalGroupsProvider.notifier).addSignal(vars.first);
    await tester.pumpAndSettle();
    drainTransientLayoutExceptions(tester);

    final dc = load.rootContainer.read(deviceClassProvider);

    final canvas = find.byType(WaveformCanvas);
    expect(canvas, findsOneWidget);
    final canvasRect = tester.getRect(canvas);

    // A Scaffold [Drawer] is only present in the tree while it is open or
    // animating, so its presence is the drawer-open signal. (The drawer's
    // contents, e.g. ActivityHeatmapOverlay, render elsewhere in the viewer
    // too, so the content type is not a reliable open/closed test.)
    expect(
      find.byType(Drawer),
      findsNothing,
      reason: 'no drawer is open before any interaction',
    );

    // Place a cursor at a known tick — neither interaction may move it.
    load.tabContainer.read(cursorStateProvider.notifier).placePrimary(30);
    await tester.pump();

    // ── Canvas swipe → a pan, not a cursor scrub; no drawer (everywhere) ───
    await tester.dragFrom(canvasRect.center, const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(
      find.byType(Drawer),
      findsNothing,
      reason: 'a center canvas swipe must not open a drawer',
    );
    expect(
      load.tabContainer.read(cursorStateProvider).primaryCursorTime,
      30,
      reason: 'a canvas touch-swipe is a pan and must not scrub the cursor',
    );
    drainTransientLayoutExceptions(tester);

    // ── Phone-class only: the left drawer exists and opens cleanly ─────────
    final scaffoldWithDrawer = find.byWidgetPredicate(
      (w) => w is Scaffold && w.drawer != null,
    );
    if (scaffoldWithDrawer.evaluate().isNotEmpty) {
      tester.state<ScaffoldState>(scaffoldWithDrawer.first).openDrawer();
      await tester.pumpAndSettle();
      expect(
        find.byType(Drawer),
        findsOneWidget,
        reason: 'the phone signal/activity drawer must open',
      );
      expect(
        load.tabContainer.read(cursorStateProvider).primaryCursorTime,
        30,
        reason: 'opening the drawer must not scrub the cursor',
      );
    } else {
      // No phone Drawer on this runner → it must be a non-phone class (the
      // desktop runner forces tablet/desktop). The drawer half runs on the
      // iOS/Android mobile track.
      expect(
        dc.isPhoneClass,
        isFalse,
        reason: 'phone class must expose a left drawer (device class: $dc)',
      );
    }
    drainTransientLayoutExceptions(tester);
  });
}
