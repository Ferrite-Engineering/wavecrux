// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/wishbone_integration_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('Wishbone decoder end-to-end', (tester) async {
    await loadFixtureVcd(
      tester,
      'protocol/wishbone/generated/wishbone_b3_classic_basic.vcd',
    );
    await activateDecoder(tester, 'Wishbone');
    await assertTransactionTableRows(tester, 4);
  });
}
