// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/canvas/panel_toggle_scope_test.dart
//
// Lower-priority companions to the RTL toggle test: drive the cocotb-log-panel
// toggle through the REAL action dispatch and assert it hits the ACTIVE tab's
// per-tab scope (not the root). Same scope-leak class the RTL/cocotb/diff fix
// addressed.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_log_panel.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/widgets/viewer_toolbar.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../helpers/app_driver.dart';

const _vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
#0
0!
#2000
1!
''';

ProviderContainer _activeTab(WidgetTester tester) {
  final root = rootContainer(tester);
  return root
      .read(tabContainerManagerProvider)
      .containerFor(root.read(activeTabIdProvider));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'toggleCocotbLogPanel action reveals the cocotb panel on the ACTIVE tab',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tmp = Directory.systemTemp.createTempSync('wc_cocotb_action_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final vcd = File('${tmp.path}/top.vcd')..writeAsStringSync(_vcd);
      await loadFixtureVcdAbsolute(tester, vcd.path);

      final root = rootContainer(tester);
      final tab = _activeTab(tester);

      // The cocotb log is app-global; load the shipped sample.
      final logPath =
          '${Directory.current.path}${Platform.pathSeparator}'
          'verification${Platform.pathSeparator}fixtures'
          '${Platform.pathSeparator}cocotb${Platform.pathSeparator}basic_log.txt';
      await root.read(cocotbLogProvider.notifier).loadFromFile(logPath);

      expect(tab.read(panelLayoutProvider).cocotbLogPanelVisible, isFalse);

      Actions.invoke(
        tester.element(find.byType(ViewerToolbar)),
        const ShortcutActionIntent(ShortcutAction.toggleCocotbLogPanel),
      );

      expect(
        await pumpUntil(
          tester,
          () => find.byType(CocotbLogPanel).evaluate().isNotEmpty,
        ),
        isTrue,
        reason: 'the cocotb panel must appear in the active tab bottom dock',
      );
      // Active tab flipped (toggle also opens the bottom dock)…
      expect(tab.read(panelLayoutProvider).cocotbLogPanelVisible, isTrue);
      expect(tab.read(panelLayoutProvider).transactionViewVisible, isTrue);
      // …root scope untouched.
      expect(root.read(panelLayoutProvider).cocotbLogPanelVisible, isFalse);
    },
  );

  // Compare Waveforms (diff) has the same per-tab scope fix, but its action
  // opens an OS file picker (`FilePicker.platform.pickFiles`) that cannot be
  // driven under integration_test. Its per-tab routing is covered by the
  // widget-level regression in `viewer_screen_test.dart` ("compareWaveforms
  // shows snackbar when diff load fails", which overrides diffProvider as a TAB
  // override). Recorded here as a skipped marker so the gap is visible in CI.
  // Skipped: compareWaveforms opens an OS file picker not drivable in
  // integration_test; per-tab routing is covered by viewer_screen_test
  // ("compareWaveforms shows snackbar when diff load fails", tab override).
  testWidgets(
    'compareWaveforms routes the diff load to the active tab',
    (tester) async {},
    skip: true,
  );
}
