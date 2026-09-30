// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/axi4_lite_integration_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('AXI4-Lite decoder end-to-end', (tester) async {
    await loadFixtureVcd(
      tester,
      'protocol/axi4lite/generated/axi4lite_basic.vcd',
    );
    await activateDecoder(tester, 'AXI4-Lite');
    await assertTransactionTableRows(tester, 4);
  });
}
