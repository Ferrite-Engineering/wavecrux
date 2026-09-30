// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/providers/x_trace_provider.dart';
import 'package:wavecrux/features/viewer/widgets/signal_list_panel.dart';

import '../helpers/app_driver.dart';
import '../helpers/gesture_helpers.dart' show rightClick;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'long-press on x-state signal row shows Trace X Origin and activates x-trace',
    (tester) async {
      // xtrace.vcd: data_out transitions to x at T=200.
      await loadFixtureVcd(tester, 'vcd/xtrace.vcd');

      // Resolved per use, never hoisted: a pane can be remounted under the
      // test's feet, and a hoisted container is then a disposed one. See
      // `paneContainer` in app_driver.dart.

      // Add data_out (the signal with x at T=200) to the viewer.
      final source = paneContainer(tester).read(waveformSourceProvider).value!;
      final vars = source.findVariables(const SignalFilter());
      final dataOut = vars.firstWhere((v) => v.name == 'data_out');

      // Load signal data before adding so signalValueAtCursorProvider can
      // return a non-null value immediately (canvas load is async and may not
      // complete before pumpAndSettle returns).
      await source.loadSignal(dataOut.signalRef);

      paneContainer(
        tester,
      ).read(signalGroupsProvider.notifier).addSignal(dataOut);
      await tester.pumpAndSettle();

      // Place the primary cursor at T=200 so the signal reports hasX=true.
      paneContainer(
        tester,
      ).read(cursorStateProvider.notifier).placePrimary(200);
      await tester.pumpAndSettle();

      // Right-click data_out's row. Rows are keyed by their entry's id, not
      // their position, so the key is derived from the entry that was added.
      // PlatformContextMenu only enables long-press on touch device classes;
      // on macOS desktop (the integration-test environment) it responds to
      // secondary-button tap-up.
      final entry = paneContainer(tester)
          .read(signalGroupsProvider)
          .entries
          .singleWhere((e) => e.signalRef == dataOut.signalRef);
      await rightClick(
        tester,
        find.byKey(ValueKey(SignalListPanel.signalRowKeyValue(entry))),
      );

      expect(find.text('Trace X Origin'), findsOneWidget);

      await tester.tap(find.text('Trace X Origin'));
      await tester.pumpAndSettle();

      // Re-resolved rather than hoisted; see above.
      expect(paneContainer(tester).read(xTraceProvider).isActive, isTrue);
    },
  );
}
