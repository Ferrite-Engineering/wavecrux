// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/apb_integration_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('APB decoder end-to-end', (tester) async {
    await loadFixtureVcd(tester, 'protocol/apb/generated/apb_basic.vcd');
    await activateDecoder(tester, 'APB');
    await assertTransactionTableRows(tester, 4);
  });

  testWidgets('APB #1 + APB #2 — two-instance picker activation', (
    tester,
  ) async {
    // Two-instance instanceNumber invariant, driven through the real
    // decoder-picker UI (mirrors the unit-level convention asserted by
    // `active_decoders_provider_test.dart`'s "increments instanceNumber per
    // decoder type" case, which adds the SAME decoder type twice with
    // identical bindings and asserts instanceNumber 1 then 2 — there is only
    // one APB bus in `apb_basic.vcd`, so both picker-driven activations
    // auto-bind to the same signals, exactly like that unit test's setup).
    await loadFixtureVcd(tester, 'protocol/apb/generated/apb_basic.vcd');

    // Activate APB #1 through the picker.
    await activateDecoder(tester, 'APB');
    // Re-open the picker and activate APB #2 — a second independent
    // instance of the same decoder type.
    await activateDecoder(tester, 'APB');

    final container = activeTabContainer(tester);
    final decoders = container.read(activeDecodersProvider);

    // Instance separation: two distinct ActiveDecoder entries, both 'apb',
    // with sequential per-type instanceNumbers — not one entry overwriting
    // the other.
    expect(decoders, hasLength(2));
    expect(decoders.every((d) => d.decoderId == 'apb'), isTrue);
    expect(
      decoders.map((d) => d.instanceNumber).toList(),
      [1, 2],
      reason:
          'APB #1 and APB #2 must each keep their own sequential '
          'instanceNumber, mirroring the SPI #1/#2 unit-test invariant',
    );
    expect(
      decoders.map((d) => d.id).toSet(),
      hasLength(2),
      reason: 'each ActiveDecoder instance must have a distinct id',
    );

    // Both instances independently decoded — instance #2 did not clobber or
    // starve instance #1's transactions.
    for (final d in decoders) {
      expect(
        d.transactions,
        hasLength(4),
        reason:
            '${d.instanceLabel('APB')} must decode the same 4 transactions '
            'as the single-instance case — both instances are bound to the '
            'same (only) APB bus in the fixture',
      );
    }

    // The transaction table (default "all decoders" filter) shows both
    // instances' rows side by side.
    await assertTransactionTableRows(tester, 8);

    expect(tester.takeException(), isNull);
  });
}
