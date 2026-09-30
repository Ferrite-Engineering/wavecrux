// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/plugins/transaction_table_exporters_provider.dart';

void main() {
  group('transactionTableExportersProvider', () {
    test('open-core default is an empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(transactionTableExportersProvider), isEmpty);
    });

    test('overlay override surfaces additional exporters', () {
      var exportInvocations = 0;
      final exporter = (
        id: 'fake_pro_exporter',
        requiredTier: LicenseTier.pro,
        labelFor: (BuildContext _, ActiveDecoder _) => 'Fake Export',
        isApplicable: (ActiveDecoder d) => d.decoderId == 'fake_pro',
        export:
            ({
              required BuildContext context,
              required WidgetRef ref,
              required ActiveDecoder decoder,
            }) async {
              exportInvocations++;
            },
      );
      final container = ProviderContainer(
        overrides: [
          transactionTableExportersProvider.overrideWithValue(
            <TransactionTableExporter>[exporter],
          ),
        ],
      );
      addTearDown(container.dispose);

      final extras = container.read(transactionTableExportersProvider);
      expect(extras, hasLength(1));
      expect(extras.first.id, 'fake_pro_exporter');
      expect(extras.first.requiredTier, LicenseTier.pro);

      // Predicate behaves as configured.
      const matching = ActiveDecoder(
        id: 'd0',
        decoderId: 'fake_pro',
        config: DecoderConfig(signalBindings: {}),
        instanceNumber: 1,
      );
      const nonMatching = ActiveDecoder(
        id: 'd1',
        decoderId: 'spi',
        config: DecoderConfig(signalBindings: {}),
        instanceNumber: 1,
      );
      expect(extras.first.isApplicable(matching), isTrue);
      expect(extras.first.isApplicable(nonMatching), isFalse);
      expect(exportInvocations, 0);
    });
  });
}
