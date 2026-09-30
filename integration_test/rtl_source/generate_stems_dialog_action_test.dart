// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/rtl_source/generate_stems_dialog_action_test.dart
//
// Verifies the Tools → "Generate RTL Stems…" action is wired into the running
// app and opens the dialog. The dialog's pick → generate → load flow drives OS
// file pickers, which cannot run in integration_test; that flow is covered by
// `test/features/rtl_source/widgets/generate_stems_dialog_test.dart` (with
// injected pickers). Here we assert the real action surfaces the dialog and
// that Cancel dismisses it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/features/rtl_source/widgets/generate_stems_dialog.dart';
import 'package:wavecrux/features/viewer/widgets/viewer_toolbar.dart';

import '../helpers/app_driver.dart';

const _vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
#0
0!
#10
1!
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'generateRtlStems action opens the Generate Stems dialog; Cancel dismisses',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tmp = Directory.systemTemp.createTempSync('wc_gen_action_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final vcd = File('${tmp.path}/top.vcd')..writeAsStringSync(_vcd);
      await loadFixtureVcdAbsolute(tester, vcd.path);

      Actions.invoke(
        tester.element(find.byType(ViewerToolbar)),
        const ShortcutActionIntent(ShortcutAction.generateRtlStems),
      );

      expect(
        await pumpUntil(
          tester,
          () => find.byType(GenerateStemsDialog).evaluate().isNotEmpty,
        ),
        isTrue,
        reason: 'the Tools → Generate RTL Stems… action must open the dialog',
      );

      await tester.tap(find.text('Cancel'));
      expect(
        await pumpUntil(
          tester,
          () => find.byType(GenerateStemsDialog).evaluate().isEmpty,
        ),
        isTrue,
        reason: 'Cancel must dismiss the dialog',
      );
    },
  );
}
