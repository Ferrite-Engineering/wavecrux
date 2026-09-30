// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/ahb_lite_integration_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('AHB-Lite decoder end-to-end', (tester) async {
    await loadFixtureVcd(
      tester,
      'protocol/ahb_lite/generated/ahb_lite_single_basic.vcd',
    );
    await activateDecoder(tester, 'AHB-Lite');
    await assertTransactionTableRows(tester, 2);
  });
}
