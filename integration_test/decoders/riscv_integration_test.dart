// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/riscv_integration_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('RISC-V instruction trace decoder end-to-end', (tester) async {
    await loadFixtureVcd(
      tester,
      'protocol/riscv/generated/riscv_rv32i_basic.vcd',
    );
    await activateDecoder(tester, 'RISC-V Instruction Trace');
    await assertTransactionTableRows(tester, 6);
  });
}
