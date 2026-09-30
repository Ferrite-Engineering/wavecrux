// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/riscv_captured_integration_test.dart
//
// End-to-end activation of the RISC-V Instruction Trace decoder against the
// captured fixture `riscv_picorv32_wb_ez.fst` (acquired from
// YosysHQ/picorv32). See `ahb_lite_captured_integration_test.dart` for the
// smoke-screen rationale.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/decoders/widgets/transaction_table_panel.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('RISC-V decoder activates against picorv32 captured fixture', (
    tester,
  ) async {
    await activateDecoderFromCapturedSpec(
      tester,
      'protocol/riscv/captured/riscv_picorv32_wb_ez.fst',
    );
    _assertAtLeastOneRow(tester);
  });
}

void _assertAtLeastOneRow(WidgetTester tester) {
  expect(find.byType(TransactionTablePanel), findsOneWidget);
  final dataTable = tester.widget<DataTable>(
    find.descendant(
      of: find.byType(TransactionTablePanel),
      matching: find.byType(DataTable),
    ),
  );
  expect(dataTable.rows.length, greaterThanOrEqualTo(1));
}
