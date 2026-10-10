// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: pure RenderFlex-overflow regression at squeezed
// dock heights; no localized copy is asserted.
import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/widgets/transaction_table_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

void main() {
  testWidgets('squeezed inside a dock (pane open/close sweeps the size), the '
      'panel never RenderFlex-overflows', (tester) async {
    // Regression: at the bottom pane minimum (80 = 32 strip + 48 content)
    // the filter bar + 1 px Divider overflowed the content column by 1 px on
    // every open/close. Two fixes guard it: the bar's separator is a border
    // (no layout height), and crux_dock lays content out at a floor size and
    // clips when the region is squeezed below it.
    for (final height in [80.0, 48.0, 40.0]) {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 616,
                  height: height,
                  child: CruxDock(
                    entries: [
                      CruxDockEntry(
                        id: 'transactions',
                        icon: Icons.table_chart_outlined,
                        label: 'Transactions',
                        builder: (_) => const TransactionTablePanel(),
                      ),
                    ],
                    activeId: 'transactions',
                    onSelect: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow at dock height $height',
      );
    }
  });

  // The column headers are pinned above the lazily built rows, inside the
  // rows' own scroll view, so a dock height below the header row's clips
  // the table rather than overflowing a column around it.
  testWidgets('squeezed with many rows, the pinned headers do not overflow', (
    tester,
  ) async {
    for (final height in [80.0, 48.0, 40.0]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeDecodersProvider.overrideWith(_SeededDecoders.new),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 616,
                  height: height,
                  child: CruxDock(
                    entries: [
                      CruxDockEntry(
                        id: 'transactions',
                        icon: Icons.table_chart_outlined,
                        label: 'Transactions',
                        builder: (_) => const TransactionTablePanel(),
                      ),
                    ],
                    activeId: 'transactions',
                    onSelect: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow at dock height $height with many rows',
      );
    }
  });
}

class _SeededDecoders extends ActiveDecodersNotifier {
  @override
  List<ActiveDecoder> build() => [
    ActiveDecoder(
      id: 'd1',
      decoderId: 'uart',
      config: const DecoderConfig(signalBindings: {}),
      instanceNumber: 1,
      transactions: [
        for (var i = 0; i < 40; i++)
          DecodedTransaction(
            startTime: i * 10,
            endTime: i * 10 + 5,
            label: 'tx$i',
          ),
      ],
    ),
  ];
}
