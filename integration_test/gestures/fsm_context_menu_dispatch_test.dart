// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/gestures/fsm_context_menu_dispatch_test.dart
//
// FSM "Visualize as FSM" context-menu dispatch.
//
// Loads a VCD with a known multi-bit enum/state signal (stage_demo.vcd's
// top.primitives.fsm_state — the same fixture fsm_cursor_tracking_test uses), adds it to the
// viewer, opens the signal-row context menu (right-click on desktop, with a
// long-press fallback), and asserts:
//   - the menu includes the "Visualize as FSM" item, and
//   - activating it opens the FSM panel with a bubble diagram of >= 1 node.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/core/router.dart' show rootScaffoldMessengerKey;
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/fsm_panel.dart';
import 'package:wavecrux/features/viewer/widgets/signal_list_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

import '../helpers/app_driver.dart';
import '../helpers/gesture_helpers.dart' show longPress, rightClick;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('Visualize FSM context-menu item opens the FSM bubble diagram', (
    tester,
  ) async {
    // Desktop-class surface so the signal-list row is a persistent pane and
    // the FSM panel renders in the bottom pane (not the phone modal).
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await loadFixtureVcd(tester, 'stage/stage_demo.vcd');

    final tab = activeTabContainer(tester);
    final source = tab.read(waveformSourceProvider).value;
    expect(source, isNotNull);

    // Add the 3-bit FSM state register to the viewer (an FSM candidate:
    // bitWidth >= 2, not real).
    final vars = source!.findVariables(const SignalFilter());
    final fsm = vars.firstWhere((v) => v.name == 'fsm_state');
    await source.loadSignal(fsm.signalRef);
    tab.read(signalGroupsProvider.notifier).addSignal(fsm);
    await tester.pumpAndSettle();

    // Rows are keyed by their entry's id, not their position, so the key is
    // derived from the entry that was just added.
    final entry = tab
        .read(signalGroupsProvider)
        .entries
        .singleWhere((e) => e.signalRef == fsm.signalRef);
    final row = find.byKey(ValueKey(SignalListPanel.signalRowKeyValue(entry)));
    expect(row, findsOneWidget, reason: 'the FSM signal row must be rendered');

    final l10n = L10N.of(rootScaffoldMessengerKey.currentContext!);

    // Right-click (desktop) opens the PlatformContextMenu; fall back to
    // long-press if the host/device class routes the menu through long-press.
    await rightClick(tester, row);
    if (find.text(l10n.fsmMenuVisualize).evaluate().isEmpty) {
      await longPress(tester, row);
    }
    expect(
      find.text(l10n.fsmMenuVisualize),
      findsOneWidget,
      reason: 'context menu must include the Visualize FSM item',
    );

    await tester.tap(find.text(l10n.fsmMenuVisualize));
    await tester.pump();

    // Poll for FSM activation (analysis runs over the full time range).
    var active = false;
    for (var i = 0; i < 40; i++) {
      if (tab.read(fsmProvider).isActive) {
        active = true;
        break;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(active, isTrue, reason: 'Visualize FSM must activate the FSM view');

    // The bubble diagram renders at least one node.
    final model = tab.read(fsmProvider).model;
    expect(model, isNotNull);
    expect(
      model!.states.length,
      greaterThanOrEqualTo(1),
      reason: 'the FSM bubble diagram must render at least one state node',
    );

    // The FSM panel surface is present in the tree.
    expect(
      find.byType(FsmPanel),
      findsAtLeastNWidgets(1),
      reason: 'the FSM panel must open',
    );

    expect(tester.takeException(), isNull);
  });
}
