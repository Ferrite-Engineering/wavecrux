// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/fsm/fsm_cursor_tracking_test.dart
//
// FSM state visualization cursor tracking integration test.
//
// Loads stage_demo.vcd (which contains a 3-bit fsm_state signal), invokes
// FSM analysis on it, and asserts that the FsmViewState is active.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('FSM analysis activates on fsm_state signal', (tester) async {
    await loadFixtureVcd(tester, 'stage/stage_demo.vcd');

    // fsmProvider and waveformSourceProvider are per-tab scoped — drive them
    // through the active tab's container, not the root (the root instances are
    // never populated, so analyzeSignal would see a null source and bail).
    final tab = activeTabContainer(tester);
    final source = tab.read(waveformSourceProvider).value;
    expect(source, isNotNull);

    // stage_demo.vcd declares a 3-bit fsm_state wire with numeric state
    // transitions — sufficient for FSM auto-detection. Resolve its real
    // signalRef (the FFI ref, not a hardcoded path string) and load it before
    // analysis, mirroring the passing fsm_context_menu_dispatch test.
    final fsmVar = source!
        .findVariables(const SignalFilter())
        .firstWhere((v) => v.name == 'fsm_state');
    await source.loadSignal(fsmVar.signalRef);

    expect(
      tab.read(fsmProvider).isActive,
      isFalse,
      reason: 'FSM should start inactive',
    );

    await tab.read(fsmProvider.notifier).analyzeSignal(fsmVar.signalRef);
    await pumpUntil(tester, () => tab.read(fsmProvider).isActive);
    await tester.pumpAndSettle();

    expect(
      tab.read(fsmProvider).isActive,
      isTrue,
      reason: 'FSM should be active after analysis',
    );
    expect(
      tab.read(fsmProvider).signalRef,
      equals(fsmVar.signalRef),
    );
  });
}
