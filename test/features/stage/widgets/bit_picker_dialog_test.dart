// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/widgets/bit_picker_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

Widget _harness(
  void Function(BitPickerResult? result) onResult, {
  Locale locale = const Locale('en'),
  int bitWidth = 16,
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
              final result = await BitPickerDialog.show(
                context,
                signalRef: 'top.dut.led[15:0]',
                bitWidth: bitWidth,
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
  group('BitPickerDialog — locale sweep', () {
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

  group('BitPickerDialog — choices', () {
    testWidgets('lists every bit MSB-first', (tester) async {
      await tester.pumpWidget(_harness((_) {}, bitWidth: 4));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Bit 3'), findsOneWidget);
      expect(find.text('Bit 0'), findsOneWidget);
    });

    testWidgets('selecting a bit returns BitPickerResult.bit', (tester) async {
      BitPickerResult? captured;
      await tester.pumpWidget(_harness((r) => captured = r, bitWidth: 4));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bit 2'));
      await tester.pumpAndSettle();
      expect(captured, isNotNull);
      expect(captured!.bitIndex, 2);
      expect(captured!.bindWhole, isFalse);
    });

    testWidgets('"Bind whole signal" returns BitPickerResult.whole', (
      tester,
    ) async {
      BitPickerResult? captured;
      await tester.pumpWidget(_harness((r) => captured = r, bitWidth: 8));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bind whole signal anyway'));
      await tester.pumpAndSettle();
      expect(captured, isNotNull);
      expect(captured!.bindWhole, isTrue);
      expect(captured!.bitIndex, isNull);
    });

    testWidgets('Cancel returns null', (tester) async {
      BitPickerResult? captured = const BitPickerResult.bit(0);
      var fired = false;
      await tester.pumpWidget(
        _harness((r) {
          fired = true;
          captured = r;
        }, bitWidth: 8),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fired, isTrue);
      expect(captured, isNull);
    });
  });
}
