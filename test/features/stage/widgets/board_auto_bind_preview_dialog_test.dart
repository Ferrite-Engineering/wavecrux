// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/board_auto_bind_candidate.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/features/stage/widgets/board_auto_bind_preview_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

BoardAutoBindResult _exampleResult() {
  return BoardAutoBindResult(
    candidates: {
      // Vector fan-out family: 4 LEDs all bound to top.leds[3:0].
      for (var i = 0; i < 4; i++)
        'led$i': BoardAutoBindCandidate(
          confidence: BoardAutoBindConfidence.vectorFanOut,
          matchReason: 'vector match: top.leds is 4 bits wide',
          binding: StageSignalBinding(
            signalRef: 'top.leds',
            bitIndex: i,
          ),
          familyPrefix: 'led',
        ),
      // Single-slot exact match.
      'btnC': const BoardAutoBindCandidate(
        confidence: BoardAutoBindConfidence.exactMatch,
        matchReason: "leaf 'btnC' matches",
        binding: StageSignalBinding(signalRef: 'top.btnC'),
      ),
      // Fuzzy match — should be skipped by "Apply confirmed only".
      'btnL': const BoardAutoBindCandidate(
        confidence: BoardAutoBindConfidence.fuzzyMatch,
        matchReason: 'fuzzy: btnLeft is 4 edits',
        binding: StageSignalBinding(signalRef: 'top.btnLeft'),
      ),
      // No match.
      'unmapped': const BoardAutoBindCandidate(
        confidence: BoardAutoBindConfidence.noMatch,
        matchReason: 'no plausible signal',
      ),
    },
  );
}

Widget _harness(
  void Function(BoardAutoBindApplyResult? result) onResult, {
  required BoardAutoBindResult result,
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
              final apply = await BoardAutoBindPreviewDialog.show(
                context,
                result: result,
              );
              onResult(apply);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('BoardAutoBindPreviewDialog — locale sweep', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          _harness(
            (_) {},
            locale: Locale(locale),
            result: _exampleResult(),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('BoardAutoBindPreviewDialog — apply', () {
    testWidgets('Apply all returns every binding including fuzzy', (
      tester,
    ) async {
      BoardAutoBindApplyResult? captured;
      await tester.pumpWidget(
        _harness(
          (r) => captured = r,
          result: _exampleResult(),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply all'));
      await tester.pumpAndSettle();
      expect(captured, isNotNull);
      // 4 LEDs (vector) + 1 button (exact) + 1 fuzzy = 6 bindings.
      expect(captured!.bindings, hasLength(6));
      expect(captured!.bindings['btnL']?.signalRef, 'top.btnLeft');
    });

    testWidgets('Apply confirmed only skips fuzzy matches', (tester) async {
      BoardAutoBindApplyResult? captured;
      await tester.pumpWidget(
        _harness(
          (r) => captured = r,
          result: _exampleResult(),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply confirmed only'));
      await tester.pumpAndSettle();
      expect(captured, isNotNull);
      // 4 LEDs + 1 exact = 5 (fuzzy and noMatch are dropped).
      expect(captured!.bindings, hasLength(5));
      expect(captured!.bindings.containsKey('btnL'), isFalse);
    });

    testWidgets('Cancel returns null', (tester) async {
      BoardAutoBindApplyResult? captured = const BoardAutoBindApplyResult({});
      var fired = false;
      await tester.pumpWidget(
        _harness(
          (r) {
            fired = true;
            captured = r;
          },
          result: _exampleResult(),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fired, isTrue);
      expect(captured, isNull);
    });
  });

  group('BoardAutoBindPreviewDialog — display', () {
    testWidgets('groups vector-fan-out family into a single header row', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness((_) {}, result: _exampleResult()),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // The 4 led slots collapse to one header row 'led0…led3'.
      expect(find.text('led0…led3'), findsOneWidget);
      // The single-slot rows still appear individually.
      expect(find.text('btnC'), findsOneWidget);
      expect(find.text('btnL'), findsOneWidget);
      expect(find.text('unmapped'), findsOneWidget);
    });
  });
}
