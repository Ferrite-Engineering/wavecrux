// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/rtl_source/rtl_annotation_action_test.dart
//
// Drives RTL source annotation through the REAL action-dispatch path
// (ShortcutActionIntent → _handleShortcut), in the fully booted app, against a
// real per-tab workspace.
//
// Why this exists: the unit/widget tests and even the existing coexistence
// integration test reveal the RTL panel by writing the providers DIRECTLY at
// the right scope (`container.read(panelLayoutProvider.notifier)...`). That
// sidesteps `_toggleRtlSourcePanel` / `_loadStemsFromPath` — exactly the
// per-tab widget wiring whose root-vs-tab scope bug made Cmd+Shift+R a silent
// no-op. These tests fire the action the way the menu / keyboard shortcut do,
// so the regression class is guarded end-to-end.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/features/rtl_source/providers/rtl_source_provider.dart';
import 'package:wavecrux/features/rtl_source/widgets/rtl_source_panel.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/widgets/viewer_toolbar.dart';
import 'package:wavecrux/services/rtl_source/stems_generator.dart';
import 'package:wavecrux/services/rtl_source/stems_writer.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../helpers/app_driver.dart';

/// The active tab's per-tab [ProviderContainer] (where panel visibility lives).
ProviderContainer _activeTab(WidgetTester tester) {
  final root = rootContainer(tester);
  return root
      .read(tabContainerManagerProvider)
      .containerFor(root.read(activeTabIdProvider));
}

/// Fires [action] through the real app dispatch (the same entry point the menu
/// bar and keyboard shortcuts use), from a context inside the viewer's Actions
/// scope.
void _invoke(WidgetTester tester, ShortcutAction action) {
  Actions.invoke(
    tester.element(find.byType(ViewerToolbar)),
    ShortcutActionIntent(action),
  );
}

const _vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 8 # data $end
$upscope $end
$enddefinitions $end
#0
0!
b00000000 #
#10
1!
b00000001 #
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'toggleRtlSourcePanel action reveals the RTL panel on the ACTIVE tab',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tmp = Directory.systemTemp.createTempSync('wc_rtl_action_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final vcd = File('${tmp.path}/top.vcd')..writeAsStringSync(_vcd);
      await loadFixtureVcdAbsolute(tester, vcd.path);

      final root = rootContainer(tester);
      final tab = _activeTab(tester);

      // Collapse the value column first, so we also prove the reveal force-opens
      // the right pane that hosts the RTL panel.
      tab
          .read(panelLayoutProvider.notifier)
          .setValueColumnVisible(visible: false);
      await tester.pump();
      expect(tab.read(panelLayoutProvider).rtlSourceVisible, isFalse);

      // Fire the real action.
      _invoke(tester, ShortcutAction.toggleRtlSourcePanel);

      expect(
        await pumpUntil(
          tester,
          () => find.byType(RtlSourcePanel).evaluate().isNotEmpty,
        ),
        isTrue,
        reason: "the RTL panel must appear in the active tab's right pane",
      );
      // The ACTIVE tab's state flipped (and the right pane was forced open)…
      expect(tab.read(panelLayoutProvider).rtlSourceVisible, isTrue);
      expect(tab.read(panelLayoutProvider).valueColumnVisible, isTrue);
      // …while the root scope was never written (the scope-leak marker).
      expect(root.read(panelLayoutProvider).rtlSourceVisible, isFalse);

      // Toggling again hides it.
      _invoke(tester, ShortcutAction.toggleRtlSourcePanel);
      expect(
        await pumpUntil(
          tester,
          () => find.byType(RtlSourcePanel).evaluate().isEmpty,
        ),
        isTrue,
        reason: 'toggling again must hide the RTL panel',
      );
    },
  );

  testWidgets(
    'generate (service) → load → reveal via action → annotation resolves',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tmp = Directory.systemTemp.createTempSync('wc_rtl_gen_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      // RTL source whose hierarchy matches the loaded VCD (scope `top`).
      final src = File('${tmp.path}/top.v')
        ..writeAsStringSync(
          'module top (\n'
          '    input        clk,\n'
          '    input  [7:0] data\n'
          ');\n'
          'endmodule\n',
        );
      final vcd = File('${tmp.path}/top.vcd')..writeAsStringSync(_vcd);
      await loadFixtureVcdAbsolute(tester, vcd.path);

      // Generate stems with the real service, write the .stems, load it.
      final result = await const StemsGenerator().generateFromPaths([
        src.path,
      ], topModule: 'top');
      expect(result.resolvedTop, 'top');
      final stemsPath = '${tmp.path}/top.stems';
      File(
        stemsPath,
      ).writeAsStringSync(const StemsWriter().write(result.stems));

      final root = rootContainer(tester);
      await root.read(rtlSourceProvider.notifier).loadStemsFile(stemsPath);
      expect(root.read(rtlSourceProvider).hasStems, isTrue);

      // Reveal via the real action, then navigate a signal to its source.
      _invoke(tester, ShortcutAction.toggleRtlSourcePanel);
      expect(
        await pumpUntil(
          tester,
          () => find.byType(RtlSourcePanel).evaluate().isNotEmpty,
        ),
        isTrue,
      );

      final shown = await root
          .read(rtlSourceProvider.notifier)
          .showSignal(
            signalRef: 'top.clk',
            signalPath: 'top.clk',
          );
      expect(shown, isTrue, reason: 'top.clk must resolve to a source line');

      final state = root.read(rtlSourceProvider);
      expect(state.currentSourceFile!.path, endsWith('top.v'));
      // `clk` is declared on line 2 of the generated source.
      expect(state.currentLine, 2);
      expect(
        state.currentSourceFile!.lines[state.currentLine! - 1],
        contains('clk'),
      );
    },
  );
}
