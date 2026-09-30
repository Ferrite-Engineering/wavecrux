// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/spi_captured_integration_test.dart
//
// End-to-end activation of [SpiDecoder] against the captured fixture
// `nandland_spi_master_mode3_loopback.fst` (acquired from nandland/spi-master).
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
    'SPI decoder activates against nandland-spi-master captured fixture',
    (tester) async {
      await loadFixtureVcd(
        tester,
        'protocol/spi/captured/nandland_spi_master_mode3_loopback.fst',
      );
      await activateDecoder(tester, 'SPI');
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
