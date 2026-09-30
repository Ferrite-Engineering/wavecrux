// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/uart_integration_test.dart
//
// The uart_basic.vcd fixture uses 1 Mbaud timing (1000-tick bit periods at 1ns
// timescale). The decoder defaults to 9600 baud, which produces a bit period of
// ~104 166 ticks — too coarse to detect any frames in this fixture. This test
// therefore uses a custom activation flow that sets baud_rate = 1 000 000 in
// the config dialog before triggering auto-bind and adding the decoder.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('UART decoder end-to-end', (tester) async {
    await loadFixtureVcd(tester, 'protocol/uart/generated/uart_basic.vcd');

    // ── Step 1: open the decoder picker ──────────────────────────────────────
    await tester.tap(find.byIcon(Icons.developer_board).first);
    await tester.pumpAndSettle();

    // ── Step 2: expand all category sections ─────────────────────────────────
    final dialogFinder = find.byType(AlertDialog);
    final tileCount = tester
        .widgetList(
          find.descendant(
            of: dialogFinder,
            matching: find.byType(ExpansionTile),
          ),
        )
        .length;
    for (var i = 0; i < tileCount; i++) {
      final tileFinder = find
          .descendant(
            of: dialogFinder,
            matching: find.byType(ExpansionTile),
          )
          .at(i);
      await tester.ensureVisible(tileFinder);
      await tester.pumpAndSettle();
      await tester.tap(tileFinder);
      await tester.pumpAndSettle();
    }

    // ── Step 3: tap the UART tile ─────────────────────────────────────────────
    final decoderFinder = find.descendant(
      of: dialogFinder,
      matching: find.text('UART'),
    );
    await tester.ensureVisible(decoderFinder);
    await tester.pumpAndSettle();
    await tester.tap(decoderFinder);
    await tester.pumpAndSettle();

    // ── Step 4: set baud_rate = 1 000 000 ────────────────────────────────────
    // The first TextFormField in the config dialog is baud_rate (the first
    // integer parameter in UartDecoder.decoderDefinition). Signal binding rows
    // use DropdownButton, not TextFormField, so .first is unambiguous.
    await tester.enterText(find.byType(TextFormField).first, '1000000');
    await tester.pumpAndSettle();

    // ── Step 5: auto-bind signals and apply ──────────────────────────────────
    await tester.tap(find.text('Auto-bind signals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply all'));
    await tester.pumpAndSettle();

    // ── Step 6: add decoder and wait for decode pass ──────────────────────────
    // decodeAll() runs unawaited off the tap and awaits FFI signal loads;
    // poll the active tab's decoder list until the transactions populate
    // rather than burning a fixed real-time budget (see app_driver helpers).
    await tester.tap(find.text('Add Decoder'));
    final container = activeTabContainer(tester);
    await pumpUntil(tester, () {
      final decoders = container.read(activeDecodersProvider);
      return decoders.isNotEmpty && decoders.last.transactions.isNotEmpty;
    });
    await tester.pumpAndSettle();

    await assertTransactionTableRows(tester, 3);
  });
}
