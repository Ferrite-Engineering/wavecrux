// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/i2c_integration_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('I²C decoder end-to-end', (tester) async {
    await loadFixtureVcd(tester, 'protocol/i2c/generated/i2c_basic.vcd');
    await activateDecoder(tester, 'I²C');
    await assertTransactionTableRows(tester, 2);
  });
}
