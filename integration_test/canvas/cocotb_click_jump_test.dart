// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_log_panel.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'tap cocotb log entry places cursor and pans viewport to that time',
    (tester) async {
      // Desktop-class surface so IdeLayout mounts a bottom pane to host the
      // cocotb log panel (phone/tablet-narrow widths force-hide it).
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // cursorStateProvider.placePrimary clamps the cursor to the loaded
      // waveform's [startTime, endTime]. The cocotb log's "FIFO full" entry is
      // at 1500 ns, but the shipped 1 ns-timescale fixtures (e.g.
      // scalar_basics.vcd) only span 100 ticks — a jump to 1500 would clamp to
      // the end and the assertion would see 100. Load a 1 ns-timescale temp VCD
      // running to #2000 so the cursor can actually reach tick 1500.
      final tmpDir = Directory.systemTemp.createTempSync('wavecrux_cocotb_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final vcdPath = '${tmpDir.path}${Platform.pathSeparator}long.vcd';
      File(vcdPath).writeAsStringSync(
        r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
#0
0!
#2000
1!
''',
      );
      await loadFixtureVcdAbsolute(tester, vcdPath);

      // The pane container is resolved per use, never hoisted: a pane can be
      // remounted under the test's feet, and a hoisted container is then a
      // disposed one. See `paneContainer` in app_driver.dart.

      // Load the cocotb log that contains "FIFO full condition reached" at 1500ns.
      final cocotbPath =
          '${Directory.current.path}${Platform.pathSeparator}verification'
          '${Platform.pathSeparator}fixtures'
          '${Platform.pathSeparator}cocotb'
          '${Platform.pathSeparator}basic_log.txt';
      await paneContainer(
        tester,
      ).read(cocotbLogProvider.notifier).loadFromFile(cocotbPath);

      // Show the bottom pane and switch it to the cocotb log view.
      //
      // Panel visibility is per-tab (`panelLayoutProvider`, overridden per-tab
      // in `wavecruxTabOverrides`); reading it through the pane container
      // resolves up to the tab scope, so toggling here drives the same provider
      // the bottom dock reads. `setTransactionViewVisible` opens the bottom
      // dock; `setCocotbLogPanelVisible` puts the cocotb tab in it.
      paneContainer(tester).read(panelLayoutProvider.notifier)
        ..setTransactionViewVisible(visible: true)
        ..setCocotbLogPanelVisible(visible: true);
      await tester.pumpAndSettle();

      // Wait for the panel's ListView to mount before scrolling — the bottom
      // pane opens via the per-tab IdeController sync bridge, which runs over a
      // few frames after the by-pane state flips.
      await pumpUntil(
        tester,
        () => find
            .descendant(
              of: find.byType(CocotbLogPanel),
              matching: find.byType(ListView),
            )
            .evaluate()
            .isNotEmpty,
      );

      // Scroll the cocotb log ListView until the target row is visible.
      // "FIFO full condition reached" is at index 8 — beyond the initial
      // viewport when the bottom pane opens at its default height.
      // _FilterBar contains a TextField (its own internal Scrollable), so we
      // must target the ListView's Scrollable specifically to avoid scrolling
      // the wrong widget.
      final listViewFinder = find.descendant(
        of: find.byType(CocotbLogPanel),
        matching: find.byType(ListView),
      );
      await tester.scrollUntilVisible(
        find.textContaining('FIFO full'),
        200,
        scrollable: find
            .descendant(
              of: listViewFinder,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // scrollUntilVisible stops as soon as the target enters the viewport, so
      // the row can sit flush against the bottom edge — tapping its center then
      // risks landing on an adjacent row. Center it and settle before tapping.
      await tester.ensureVisible(find.textContaining('FIFO full'));
      await tester.pumpAndSettle();

      // Tap the row for "FIFO full condition reached" (simTimeTicks = 1500).
      await tester.tap(find.textContaining('FIFO full'));
      await tester.pumpAndSettle();

      // Cursor must be placed at tick 1500.
      expect(
        paneContainer(tester).read(cursorStateProvider).primaryCursorTime,
        1500,
      );

      // Viewport must have scrolled to include tick 1500.
      expect(
        paneContainer(tester).read(timeMapperProvider).visibleStartTime,
        lessThanOrEqualTo(1500),
      );
    },
  );
}
