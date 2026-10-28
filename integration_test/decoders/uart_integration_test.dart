// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/uart_integration_test.dart
//
// The uart_basic.vcd fixture uses 1 Mbaud timing (1000-tick bit periods at 1ns
// timescale). The decoder defaults to 9600 baud, which produces a bit period of
// ~104 166 ticks — too coarse to detect any frames in this fixture. This test
// therefore uses a custom activation flow that sets baud_rate = 1 000 000 in
// the Inspector's decoder draft before triggering auto-bind and adding the
// decoder.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('UART decoder end-to-end', (tester) async {
    await loadFixtureVcd(tester, 'protocol/uart/generated/uart_basic.vcd');

    // Pick UART, set baud_rate = 1 000 000 in the Inspector draft, then
    // auto-bind and add it (see activateDecoder).
    await activateDecoder(
      tester,
      'UART',
      configure: (tester) async {
        // The first TextFormField in the Inspector's decoder draft is
        // baud_rate (the first integer parameter in
        // UartDecoder.decoderDefinition). Signal binding rows use pop-up
        // buttons, not TextFormField, so .first is unambiguous.
        final baud = find.byType(TextFormField).first;
        await tester.ensureVisible(baud);
        await tester.pumpAndSettle();
        await tester.enterText(baud, '1000000');
        await tester.pumpAndSettle();
      },
    );

    await assertTransactionTableRows(tester, 3);
  });
}
