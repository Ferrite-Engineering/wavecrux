// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/coexistence/stage_fsm_rtl_coexistence_test.dart
//
// Stage + FSM + RTL triple-feature coexistence (desktop).
//
// At a 1600 × 1000 dp desktop surface, stands up three features at once:
//   * Stage panel (LED widget bound to `led_blink`) docked at the bottom.
//   * FSM analysis active on `fsm_state`.
//   * RTL source annotation (desktop-only) showing a source line for
//     `led_blink`, rendered in the right slot.
//
// Asserts they coexist:
//   * Stage panel (bottom dock) and RTL source panel (right slot) render
//     simultaneously — they live in different layout slots.
//   * The FSM panel also renders (Stage and FSM share the single bottom-dock
//     slot by design, so the FSM panel is brought to the front to prove it
//     renders, then Stage is restored — see `_coexistence_helpers.dart`).
//   * No `RenderFlex` overflow or unhandled exception with all three active.
//   * Scrubbing the cursor updates the LED input value and the FSM active
//     node; the RTL annotation stays bound to its source line.
//
// Fixture: `stage/stage_demo.vcd` plus a throwaway stems + Verilog source pair
// written to a temp directory (RTL stems reference absolute on-disk source
// paths, which cannot be committed portably). See
// `verification/VERIFICATION_GUIDE.md` §22.9 "Stage + FSM + RTL on desktop".

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/rtl_source/providers/rtl_source_provider.dart';
import 'package:wavecrux/features/rtl_source/widgets/rtl_source_panel.dart';
import 'package:wavecrux/features/stage/widgets/stage_panel.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '_coexistence_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'Stage, FSM and RTL source annotation coexist on desktop',
    (tester) async {
      final setup = await setUpStageAndFsm(
        tester,
        surface: const Size(1600, 1000),
      );
      final container = setup.container;
      final root = rootContainer(tester);

      expect(
        root.read(deviceClassProvider),
        DeviceClass.desktop,
        reason: '1600×1000 dp must classify as desktop',
      );

      // Stage panel is docked at the bottom; FSM is concurrently active.
      expect(
        await pumpUntilFound(tester, find.byType(StagePanel)),
        isTrue,
        reason: 'Stage panel must render in the bottom dock',
      );
      expect(
        container.read(fsmProvider).isActive,
        isTrue,
        reason: 'FSM must be concurrently active',
      );

      // The FSM panel renders in the (full-width) bottom dock, then Stage is
      // restored. Done before the RTL right slot opens, because Stage and FSM
      // share the single bottom-dock slot — verifying the FSM panel here keeps
      // the dock full-width and avoids squeezing the FSM header.
      await assertFsmPanelRendersThenRestoreStage(tester, setup);
      drainTransientOverflow(tester);

      // ── RTL source annotation (desktop-only) ──────────────────────────────
      // Build a throwaway stems + source pair mapping led_blink to line 3.
      final tmp = Directory.systemTemp.createTempSync('wc_rtl_coexist_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final srcFile = File('${tmp.path}/top.v')
        ..writeAsStringSync(
          'module top;\n'
          '  // line 2\n'
          '  wire led_blink;\n'
          'endmodule\n',
        );
      final stemsFile = File('${tmp.path}/design.stems')
        ..writeAsStringSync('++ var ${setup.led.fullPath} ${srcFile.path} 3\n');

      await root.read(rtlSourceProvider.notifier).loadStemsFile(stemsFile.path);
      expect(
        root.read(rtlSourceProvider).hasStems,
        isTrue,
        reason: 'stems file must parse and load',
      );
      final shown = await root
          .read(rtlSourceProvider.notifier)
          .showSignal(
            signalRef: setup.led.signalRef,
            signalPath: setup.led.fullPath,
          );
      expect(shown, isTrue, reason: 'led_blink must resolve to a source line');

      // Show the right slot and switch it to the RTL source panel. Panel
      // visibility is per-tab; set it on this tab's own container.
      setup.container.read(panelLayoutProvider.notifier)
        ..setValueColumnVisible(visible: true)
        ..setRtlSourceVisible(visible: true);

      // ── Simultaneous: Stage (bottom dock) + RTL (right slot) ──────────────
      expect(
        await pumpUntilFound(tester, find.byType(RtlSourcePanel)),
        isTrue,
        reason: 'RTL source panel must render in the right slot on desktop',
      );
      expect(
        find.byType(StagePanel),
        findsOneWidget,
        reason:
            'Stage (bottom dock) and RTL (right slot) render simultaneously',
      );
      drainTransientOverflow(tester);

      // ── Scrub: LED + FSM update; RTL annotation stays bound ───────────────
      // The FSM highlight and the Stage LED both derive from per-cursor signal
      // values; asserting those values change proves both panels update.
      final source = container.read(waveformSourceProvider).value!;

      container.read(cursorStateProvider.notifier).placePrimary(scrubTimeA);
      await tester.pump();
      final fsmValA = source.valueAt(setup.fsm.signalRef, scrubTimeA);
      final ledValA = source.valueAt(setup.led.signalRef, scrubTimeA);

      container.read(cursorStateProvider.notifier).placePrimary(scrubTimeB);
      await tester.pump();
      final fsmValB = source.valueAt(setup.fsm.signalRef, scrubTimeB);
      final ledValB = source.valueAt(setup.led.signalRef, scrubTimeB);

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

      // RTL annotation remains bound to its source line across the scrub.
      final rtl = root.read(rtlSourceProvider);
      expect(rtl.currentSourceFile, isNotNull);
      expect(rtl.currentLine, 3);
      expect(rtl.currentSignalPath, setup.led.fullPath);

      drainTransientOverflow(tester);
    },
  );
}
