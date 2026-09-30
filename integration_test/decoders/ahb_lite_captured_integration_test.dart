// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/ahb_lite_captured_integration_test.dart
//
// End-to-end activation of [AhbLiteDecoder] against the captured fixture
// `ahb_lite_shalan_dmac.fst` (acquired from shalan/AHB-Lite). Smoke-screens
// that opening the file, picking the decoder, auto-binding signals, and
// triggering the decode pass produces ≥1 transaction — exact-count matching
// is the unit-sweep's job (see
// test/services/decoders/ahb_lite_captured_fixtures_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/decoders/widgets/transaction_table_panel.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'AHB-Lite decoder activates against shalan-DMAC captured fixture',
    (tester) async {
      await activateDecoderFromCapturedSpec(
        tester,
        'protocol/ahb_lite/captured/ahb_lite_shalan_dmac.fst',
      );
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
