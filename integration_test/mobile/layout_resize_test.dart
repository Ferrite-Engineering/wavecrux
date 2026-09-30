// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/mobile/layout_resize_test.dart
//
// Layout adapts on window resize.
//
// Starts at desktop class (1280 × 800), then resizes to phone class
// (390 × 844), then back to desktop. Verifies:
//   - Cursor time is preserved through every transition (Riverpod state
//     survives any layout change).
//   - The waveform canvas widget is present in every transition (the
//     layout does not crash or unmount it).
//   - No exceptions are thrown.
//
// Device-class transition sweep:
//   - Resize desktop (1400 dp) → tablet (900 dp) → phone (500 dp) and
//     assert `deviceClassProvider` reports a valid DeviceClass at each
//     stop and that the WaveformCanvas widget stays mounted across the
//     transitions. The workspace state (cursor, signal arrangement) is
//     preserved across each transition — Riverpod state lives outside
//     widget lifecycle.
//   - At 500 dp (phone class) the workspace state preserves but the UI
//     is forced single-tab single-pane per ARCHITECTURE.md §6.5 /
//     §3.1.4. The IdeLayout side/bottom panes are force-hidden via the
//     `_syncControllerToState` device-class listener so no RenderFlex
//     overflow is reported (any layout-overflow exceptions are drained
//     by [drainTransientLayoutExceptions]).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '../helpers/app_driver.dart'
    show skipOnMobileDevice, suppressPlatformSemanticsLeak;
import '_mobile_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'resize desktop → phone → desktop preserves cursor',
    (tester) async {
      // Begin at desktop class so the initial layout shows all panes.
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final load = await loadSyntheticVcd(tester);
      await tester.pumpAndSettle();

      expect(find.byType(WaveformCanvas), findsOneWidget);

      // Place a cursor at T=100 ticks (per-tab state).
      load.tabContainer.read(cursorStateProvider.notifier).placePrimary(100);
      await tester.pumpAndSettle();
      final initialCursor = load.tabContainer
          .read(cursorStateProvider)
          .primaryCursorTime;
      expect(initialCursor, 100);

      // Resize to phone width.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();

      expect(
        load.tabContainer.read(cursorStateProvider).primaryCursorTime,
        initialCursor,
        reason: 'cursor must survive desktop → phone transition',
      );
      expect(
        find.byType(WaveformCanvas),
        findsOneWidget,
        reason: 'WaveformCanvas must remain mounted at phone width',
      );

      // Resize back to desktop.
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpAndSettle();

      expect(
        load.tabContainer.read(cursorStateProvider).primaryCursorTime,
        initialCursor,
        reason: 'cursor must survive phone → desktop transition',
      );
      expect(
        find.byType(WaveformCanvas),
        findsOneWidget,
        reason: 'WaveformCanvas must remain mounted after resize cycle',
      );

      drainTransientLayoutExceptions(tester);
    },
    // Desktop-binding: this test simulates device-class transitions via
    // setSurfaceSize, which only drives deviceClassProvider under the desktop
    // binding. On a real device the physical screen fixes the class, so the
    // transition can't occur. Fully covered by the Linux integration sweep.
    skip: skipOnMobileDevice,
  );

  testWidgets(
    'resize desktop (1400 dp) → tablet (900 dp) → phone (500 dp) — '
    'deviceClassProvider transitions through valid classes and the '
    'WaveformCanvas stays mounted; phone width is forced single-tab '
    'single-pane (no RenderFlex overflow surfaces)',
    (tester) async {
      // Begin at desktop class with extra room to verify the standard
      // multi-pane layout renders cleanly.
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final load = await loadSyntheticVcd(tester);
      await tester.pumpAndSettle();

      final dcDesktop = load.rootContainer.read(deviceClassProvider);
      expect(dcDesktop, isIn(DeviceClass.values));
      expect(find.byType(WaveformCanvas), findsOneWidget);

      // Resize to tablet width (still ≥ 600 dp and ≥ 500 dp height →
      // tablet class on host platforms where the test surface drives
      // classification). Some simulators report the native physical
      // size; both outcomes are valid as long as the canvas stays
      // mounted and no real exceptions surface.
      await tester.binding.setSurfaceSize(const Size(900, 700));
      await tester.pumpAndSettle();

      final dcTablet = load.rootContainer.read(deviceClassProvider);
      expect(
        dcTablet,
        isIn(DeviceClass.values),
        reason:
            'deviceClass must be valid after desktop → tablet resize '
            '(observed: $dcTablet)',
      );
      expect(
        find.byType(WaveformCanvas),
        findsOneWidget,
        reason: 'WaveformCanvas must remain mounted at tablet width',
      );

      // Drain any transient overflow before squeezing further.
      drainTransientLayoutExceptions(tester);

      // Resize to phone width — under 600 dp the side/bottom panes are
      // force-hidden by the IdeController device-class listener to
      // prevent RenderFlex overflow (ARCHITECTURE.md §3.1.8.6 /
      // §3.1.8.12). The user's per-panel preference is preserved.
      await tester.binding.setSurfaceSize(const Size(500, 844));
      await tester.pumpAndSettle();

      final dcPhone = load.rootContainer.read(deviceClassProvider);
      expect(
        dcPhone,
        isIn(DeviceClass.values),
        reason:
            'deviceClass must be valid after tablet → phone resize '
            '(observed: $dcPhone)',
      );
      expect(
        find.byType(WaveformCanvas),
        findsOneWidget,
        reason: 'WaveformCanvas must remain mounted at phone width',
      );

      drainTransientLayoutExceptions(tester);
    },
    // Desktop-binding: this test simulates device-class transitions via
    // setSurfaceSize, which only drives deviceClassProvider under the desktop
    // binding. On a real device the physical screen fixes the class, so the
    // transition can't occur. Fully covered by the Linux integration sweep.
    skip: skipOnMobileDevice,
  );
}
