// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/stage/stage_binding_test.dart
//
// Stage widget signal binding and cursor scrub integration test.
//
// Adds a Stage panel with an LED widget, binds its input pin to
// top.primitives.led_blink from stage_demo.vcd, and asserts the binding is
// recorded in the StageWorkspaceNotifier state.
//
// The test does not reference any of the retired legacy surfaces — no
// `WavecruxTab.kind`, no `isDirty`, no `last_session.json`, no Welcome
// screen / Welcome tab. The Stage workspace state assertion runs against
// the live notifier and is independent of workspace / session
// persistence semantics. Per-tab scoping of `stageWorkspaceProvider`
// is covered by `stage_session_round_trip_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('Stage LED binding persists in state', (tester) async {
    await loadFixtureVcd(tester, 'stage/stage_demo.vcd');

    final container = rootContainer(tester);

    // Add a panel and an LED instance.
    final notifier = container.read(stageWorkspaceProvider.notifier);
    final panelId = notifier.addPanel('Test Panel');
    await tester.pump();

    final instanceId = notifier.addInstance('led');
    expect(instanceId, isNotNull);
    await tester.pump();

    // Bind the LED's input pin to the led_blink signal.
    const signalRef = 'top.primitives.led_blink';
    notifier.setBinding(instanceId!, 'input', signalRef);
    await tester.pump();

    // Verify the binding is recorded in the workspace state.
    final state = container.read(stageWorkspaceProvider);
    final panel = state.panels.firstWhere((p) => p.id == panelId);
    final instance = panel.instances.firstWhere((i) => i.id == instanceId);

    expect(instance.signalBindings.containsKey('input'), isTrue);
    expect(
      instance.signalBindings['input']?.signalRef,
      equals(signalRef),
    );
  });
}
