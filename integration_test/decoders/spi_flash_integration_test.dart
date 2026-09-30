// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/spi_flash_integration_test.dart
//
// SPI Flash is a StackedDecoder that stacks on the SPI decoder. This test:
//   1. Activates SPI first (1 SPI transaction from spi_flash_rdid.vcd).
//   2. Activates SPI Flash (1 additional SPI Flash transaction).
//
// The transaction table shows all active decoder transactions combined, so the
// expected total is 2 rows (1 SPI + 1 SPI Flash).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('SPI Flash stacked decoder end-to-end', (tester) async {
    await loadFixtureVcd(
      tester,
      'protocol/spi_flash/generated/spi_flash_rdid.vcd',
    );

    // Activate the base SPI decoder first (SPI Flash stacks on it).
    await activateDecoder(tester, 'SPI');

    // Activate SPI Flash — no auto-bind required (no required signal bindings).
    await activateDecoder(tester, 'SPI Flash', runAutoBind: false);

    // Combined table: 1 SPI transaction + 1 SPI Flash transaction.
    await assertTransactionTableRows(tester, 2);
  });
}
