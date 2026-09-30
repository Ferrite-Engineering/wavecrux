// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/i2c_captured_integration_test.dart
//
// End-to-end activation of [I2cDecoder] against the captured fixture
// `i2c_forencich_master_slave.fst` (acquired from alexforencich/verilog-i2c).
// See `ahb_lite_captured_integration_test.dart` for the smoke-screen
// rationale.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/decoders/widgets/transaction_table_panel.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'I²C decoder activates against forencich master+slave captured fixture',
    (tester) async {
      await loadFixtureVcd(
        tester,
        'protocol/i2c/captured/i2c_forencich_master_slave.fst',
      );
      await activateDecoder(tester, 'I²C');
      _assertAtLeastOneRow(tester);
    },
  );
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
