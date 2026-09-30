// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/axi4lite_captured_integration_test.dart
//
// End-to-end activation of [Axi4LiteDecoder] against the captured fixture
// `forencich_axil_ram.fst` (acquired from alexforencich/verilog-axi). See
// `ahb_lite_captured_integration_test.dart` for the smoke-screen rationale.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'AXI4-Lite decoder activates against forencich_axil_ram captured fixture',
    (tester) async {
      await activateDecoderFromCapturedSpec(
        tester,
        'protocol/axi4lite/captured/forencich_axil_ram.fst',
      );
      await expectTransactionTableRows(tester);
    },
  );
}
