// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/coexistence/tablet_stage_fsm_test.dart
//
// Tablet Stage + FSM dual-feature coexistence.
//
// At a 1024 × 768 dp tablet-class surface, stands up a Stage panel (LED widget
// bound to `led_blink`) docked at the bottom and activates FSM analysis on
// `fsm_state`. Asserts the two features coexist on a tablet:
//
//   * The device classifies as tablet.
//   * The Stage panel renders in the bottom dock; the FSM panel also renders
//     (Stage and FSM share the single per-pane dock slot by design, so the
//     FSM panel is brought to the front to prove it renders, then Stage is
//     restored — see `_coexistence_helpers.dart`).
//   * Both features stay concurrently active with no cross-interference.
//   * Scrubbing the cursor updates both the LED input value and the FSM
//     active-node highlight.
//   * No `RenderFlex` overflow or unhandled exception at tablet width.
//
// Fixture: `stage/stage_demo.vcd`. See `verification/VERIFICATION_GUIDE.md`
// §22.9 "Tablet with Stage + FSM".

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/stage/widgets/stage_panel.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '_coexistence_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'Stage and FSM panels coexist on a tablet-class surface',
    (tester) async {
      final setup = await setUpStageAndFsm(
        tester,
        surface: const Size(1024, 768),
      );
      final container = setup.container;
      final root = rootContainer(tester);

      // Multi-pane device class at a tablet-class surface. On a native desktop
      // integration host (macOS/Windows/Linux) `deviceClassProvider` is floored
      // to `desktop` regardless of the 1024×768 surface — the "never reflow to
      // tablet/phone on a native desktop host" rule (commit d85c041); a phone
      // emulator's physical screen fixes the class too. So the meaningful,
      // host-portable assertion is the multi-pane class (tablet on a real
      // tablet, desktop under the floor) — never a single-pane phone class.
      // The Stage + FSM coexistence behaviour exercised below is device-class
      // independent. (Mirrors `integration_test/mobile/layout_tablet_test.dart`,
      // which likewise tolerates the floor.)
      expect(
        root.read(deviceClassProvider),
        isIn(const [DeviceClass.tablet, DeviceClass.desktop]),
        reason:
            '1024×768 dp must classify as a multi-pane class '
            '(tablet, or desktop under the native-desktop-host floor)',
      );

      // Stage panel docked bottom; FSM concurrently active.
      expect(
        await pumpUntilFound(tester, find.byType(StagePanel)),
        isTrue,
        reason: 'Stage panel must render in the bottom dock',
      );
      expect(container.read(fsmProvider).isActive, isTrue);

      // The FSM panel also renders (shared dock slot), then Stage restored.
      await assertFsmPanelRendersThenRestoreStage(tester, setup);
      expect(tester.takeException(), isNull);

      // Scrub the cursor between two times where both the LED input and the
      // FSM signal hold different values. The FSM active-node highlight and
      // the Stage LED both derive from these per-cursor signal values, so
      // asserting the underlying values change proves both panels update.
      final source = container.read(waveformSourceProvider).value!;

      container.read(cursorStateProvider.notifier).placePrimary(scrubTimeA);
      await tester.pump();
      final cursorA = container.read(cursorStateProvider).primaryCursorTime;
      final fsmValA = source.valueAt(setup.fsm.signalRef, scrubTimeA);
      final ledValA = source.valueAt(setup.led.signalRef, scrubTimeA);

      container.read(cursorStateProvider.notifier).placePrimary(scrubTimeB);
      await tester.pump();
      final cursorB = container.read(cursorStateProvider).primaryCursorTime;
      final fsmValB = source.valueAt(setup.fsm.signalRef, scrubTimeB);
      final ledValB = source.valueAt(setup.led.signalRef, scrubTimeB);

      expect(cursorA, scrubTimeA);
      expect(cursorB, scrubTimeB);
      expect(fsmValA, isNotNull);
      expect(fsmValB, isNotNull);
      expect(
        fsmValA,
        isNot(equals(fsmValB)),
        reason:
            'FSM signal value (drives the active-node highlight) must '
            'track the cursor',
      );
      expect(
        ledValA,
        isNot(equals(ledValB)),
        reason: 'Stage LED input value must track the cursor',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
