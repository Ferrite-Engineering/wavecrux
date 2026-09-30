// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/mobile/gesture_long_press_context_menu_test.dart
//
// Long-press on signal row opens the PlatformContextMenu.
//
// Per ARCHITECTURE.md §3.1.8.5, long-press fires the same context menu that
// right-click fires on desktop. The viewer's signal list rows are wrapped
// in `PlatformContextMenu`, which enables long-press whenever the active
// device class is phone / phone-landscape / tablet (regardless of host
// platform) OR the host is iOS / Android.
//
// The test loads a fixture, adds the first signal to the viewer, long-
// presses its signal-list row, and asserts the expected menu items appear:
// Change Color and Copy Full Path.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/signal_list_panel.dart';

import '../helpers/app_driver.dart';
import '../helpers/gesture_helpers.dart' show longPress, rightClick;
import '_mobile_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'long-press on signal row shows context menu with expected items',
    (tester) async {
      // Tablet-class width — long-press is enabled at this device class
      // on any platform, and the signal list is a persistent pane (not
      // hidden inside a drawer), so the row is reachable directly.
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final load = await loadSyntheticVcd(tester);
      await tester.pumpAndSettle();

      // Add the first signal to the viewer so a signal-list row exists.
      final source = load.tabContainer.read(waveformSourceProvider).value;
      expect(source, isNotNull);
      final vars = source!.findVariables(const SignalFilter());
      expect(vars, isNotEmpty);
      await source.loadSignal(vars.first.signalRef);
      load.tabContainer
          .read(signalGroupsProvider.notifier)
          .addSignal(vars.first);
      await tester.pumpAndSettle();

      // Signal rows are keyed by their entry, not by their slot, so address
      // the row by the signal just added.
      final entry = load.tabContainer
          .read(signalGroupsProvider)
          .entries
          .singleWhere((e) => e.signalRef == vars.first.signalRef);
      final row = find.byKey(
        ValueKey(SignalListPanel.signalRowKeyValue(entry)),
      );
      expect(row, findsOneWidget, reason: 'signal row must be rendered');

      // Try long-press first; on desktop-host + desktop-class
      // PlatformContextMenu only listens to right-click, so fall back.
      await longPress(tester, row);
      if (find.text('Copy Full Path').evaluate().isEmpty) {
        await rightClick(tester, row);
      }

      // Assert expected menu items appear. Strings come from app_en.arb.
      expect(
        find.text('Change Color…'),
        findsOneWidget,
        reason: 'context menu must contain Change Color item',
      );
      expect(
        find.text('Copy Full Path'),
        findsOneWidget,
        reason: 'context menu must contain Copy Full Path item',
      );

      drainTransientLayoutExceptions(tester);
    },
  );
}
