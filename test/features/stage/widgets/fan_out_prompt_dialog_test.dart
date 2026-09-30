// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/widgets/fan_out_prompt_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

Widget _harness(
  void Function(FanOutPromptChoice result) onResult, {
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final result = await FanOutPromptDialog.show(
                context,
                signalRef: 'top.dut.led[15:0]',
                signalWidth: 16,
                familyPrefix: 'led',
                familySize: 16,
                familyMinIndex: 0,
              );
              onResult(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('FanOutPromptDialog — locale sweep', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(_harness((_) {}, locale: Locale(locale)));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('FanOutPromptDialog — choices', () {
    testWidgets('Bind all returns FanOutPromptChoice.bindAll', (tester) async {
      late FanOutPromptChoice captured;
      await tester.pumpWidget(_harness((r) => captured = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bind all'));
      await tester.pumpAndSettle();
      expect(captured, FanOutPromptChoice.bindAll);
    });

    testWidgets('Just this slot returns FanOutPromptChoice.bindOne', (
      tester,
    ) async {
      late FanOutPromptChoice captured;
      await tester.pumpWidget(_harness((r) => captured = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Just this slot'));
      await tester.pumpAndSettle();
      expect(captured, FanOutPromptChoice.bindOne);
    });

    testWidgets('Cancel returns FanOutPromptChoice.cancel', (tester) async {
      late FanOutPromptChoice captured;
      await tester.pumpWidget(_harness((r) => captured = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(captured, FanOutPromptChoice.cancel);
    });

    testWidgets('barrier dismiss returns cancel', (tester) async {
      late FanOutPromptChoice captured;
      await tester.pumpWidget(_harness((r) => captured = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(captured, FanOutPromptChoice.cancel);
    });
  });

  group('FanOutPromptDialog — multi-bit slice body variant', () {
    // When `sliceWidth` is non-null and > 1 the dialog uses
    // `stageFanOutPromptBodySlice` instead of `stageFanOutPromptBody`,
    // mentioning the slice width inline. Mirrors the DE10-Nano scenario:
    // 96-bit `adc_ch` bus across 8 ADC slots → 12 bits per slot.
    testWidgets(
      'shows the N-bit slice body when sliceWidth > 1',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      await FanOutPromptDialog.show(
                        context,
                        signalRef: 'top.adc_ch',
                        signalWidth: 96,
                        familyPrefix: 'adc_ch',
                        familySize: 8,
                        familyMinIndex: 0,
                        sliceWidth: 12,
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('12-bit slice', findRichText: true),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'falls back to single-bit body when sliceWidth is null',
      (tester) async {
        await tester.pumpWidget(_harness((_) {}));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        // The single-bit body says "matching bit" — never "matching X-bit slice".
        expect(
          find.textContaining('matching bit', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.textContaining('-bit slice', findRichText: true),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'falls back to single-bit body when sliceWidth == 1',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      await FanOutPromptDialog.show(
                        context,
                        signalRef: 'top.dut.led[15:0]',
                        signalWidth: 16,
                        familyPrefix: 'led',
                        familySize: 16,
                        familyMinIndex: 0,
                        sliceWidth: 1,
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('-bit slice', findRichText: true),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
