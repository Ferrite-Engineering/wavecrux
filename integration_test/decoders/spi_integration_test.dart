// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/spi_integration_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('SPI decoder end-to-end', (tester) async {
    await loadFixtureVcd(tester, 'protocol/spi/generated/spi_basic.vcd');
    await activateDecoder(tester, 'SPI');
    await assertTransactionTableRows(tester, 2);
  });
}
