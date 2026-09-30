// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/uart_captured_integration_test.dart
//
// End-to-end activation of [UartDecoder] against a real captured trace.
// Loads `ben_marshall_tx_9600bps.fst` (a 9600 bps standalone TX run from the
// ben-marshall/uart MIT-licensed project), activates the decoder with the
// validated bindings + parameters (baud_rate) from the sibling fixture.json,
// and asserts the snapshot's single grouped 20-byte transaction lands in the
// transaction table.
//
// Binds explicitly from fixture.json rather than via the auto-bind UI: captured
// traces frequently expose the same bus under multiple scopes, which auto-bind
// cannot disambiguate without human input (see activateDecoderFromCapturedSpec).
// The unit-test sweep in [test/services/decoders/uart_captured_fixtures_test.dart]
// covers every captured fixture against its snapshot.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('UART decoder activates against ben-marshall captured fixture', (
    tester,
  ) async {
    await activateDecoderFromCapturedSpec(
      tester,
      'protocol/uart/captured/ben_marshall_tx_9600bps.fst',
    );
    // The snapshot contains exactly one grouped 20-byte TX transaction.
    await assertTransactionTableRows(tester, 1);
  });
}
