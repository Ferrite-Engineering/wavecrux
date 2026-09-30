// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/widgets/primitives/seven_segment_stage_widget.dart';

import '_test_helpers.dart';

void main() {
  group('sevenSegmentDigits — hexadecimal', () {
    test('value 0 → all zeros', () {
      const s = StageSignalSnapshot.value(rawValue: '0000', bitWidth: 4);
      expect(
        sevenSegmentDigits(
          s,
          digitCount: 4,
          radix: SevenSegmentRadix.hexadecimal,
        ),
        ['0', '0', '0', '0'],
      );
    });

    test('value 0xCAFE in 4 hex digits', () {
      const s = StageSignalSnapshot.value(
        rawValue: '1100101011111110',
        bitWidth: 16,
      );
      expect(
        sevenSegmentDigits(
          s,
          digitCount: 4,
          radix: SevenSegmentRadix.hexadecimal,
        ),
        ['c', 'a', 'f', 'e'],
      );
    });

    test('overflow → all x', () {
      const s = StageSignalSnapshot.value(
        rawValue: '11111111',
        bitWidth: 8,
      );
      expect(
        sevenSegmentDigits(
          s,
          digitCount: 1,
          radix: SevenSegmentRadix.hexadecimal,
        ),
        ['x'],
      );
    });

    test('x bit → all x', () {
      const s = StageSignalSnapshot.value(rawValue: '10x0', bitWidth: 4);
      expect(
        sevenSegmentDigits(
          s,
          digitCount: 4,
          radix: SevenSegmentRadix.hexadecimal,
        ),
        ['x', 'x', 'x', 'x'],
      );
    });

    test('z bit → all x', () {
      const s = StageSignalSnapshot.value(rawValue: '10z0', bitWidth: 4);
      expect(
        sevenSegmentDigits(
          s,
          digitCount: 4,
          radix: SevenSegmentRadix.hexadecimal,
        ),
        ['x', 'x', 'x', 'x'],
      );
    });

    test('unbound → all dashes', () {
      expect(
        sevenSegmentDigits(
          const StageSignalSnapshot.unbound(),
          digitCount: 4,
          radix: SevenSegmentRadix.hexadecimal,
        ),
        ['-', '-', '-', '-'],
      );
    });
  });

  group('sevenSegmentDigits — decimal', () {
    test('value 42 in 2 digits', () {
      const s = StageSignalSnapshot.value(rawValue: '101010', bitWidth: 6);
      expect(
        sevenSegmentDigits(
          s,
          digitCount: 2,
          radix: SevenSegmentRadix.decimal,
        ),
        ['4', '2'],
      );
    });

    test('value 7 left-pads', () {
      const s = StageSignalSnapshot.value(rawValue: '111', bitWidth: 3);
      expect(
        sevenSegmentDigits(
          s,
          digitCount: 4,
          radix: SevenSegmentRadix.decimal,
        ),
        ['0', '0', '0', '7'],
      );
    });

    test('value 100 overflows 2-digit decimal', () {
      const s = StageSignalSnapshot.value(rawValue: '1100100', bitWidth: 7);
      expect(
        sevenSegmentDigits(
          s,
          digitCount: 2,
          radix: SevenSegmentRadix.decimal,
        ),
        ['x', 'x'],
      );
    });
  });

  group('SegmentGlyph.fromCathodes', () {
    test('bit assignments map to a..g (active high)', () {
      // Cathode value 0x3F = 0b0111111: a, b, c, d, e, f on; g off.
      // That's the canonical "0" digit pattern.
      final g = SegmentGlyph.fromCathodes(0x3F);
      expect(g.a, isTrue);
      expect(g.b, isTrue);
      expect(g.c, isTrue);
      expect(g.d, isTrue);
      expect(g.e, isTrue);
      expect(g.f, isTrue);
      expect(g.g, isFalse);
    });

    test('active-low inverts each segment bit', () {
      // 0x3F under active-low means segments where the bus bit is 0
      // are on. Inverted: g is the only segment on.
      final g = SegmentGlyph.fromCathodes(0x3F, activeHigh: false);
      expect(g.a, isFalse);
      expect(g.g, isTrue);
    });

    test('dpFromBus drives dp', () {
      final g = SegmentGlyph.fromCathodes(0, dpFromBus: true, dpVisible: true);
      expect(g.dp, isTrue);
      expect(g.dpVisible, isTrue);
    });

    test('dpOverride wins over dpFromBus', () {
      final g = SegmentGlyph.fromCathodes(
        0,
        dpFromBus: true,
        dpOverride: false,
        dpVisible: true,
      );
      expect(g.dp, isFalse);
    });

    test('"1" cathode pattern lights only b and c', () {
      // 0x06 = 0b0000110: b + c only.
      final g = SegmentGlyph.fromCathodes(0x06);
      expect(g.a, isFalse);
      expect(g.b, isTrue);
      expect(g.c, isTrue);
      expect(g.d, isFalse);
      expect(g.e, isFalse);
      expect(g.f, isFalse);
      expect(g.g, isFalse);
    });
  });

  group('SegmentGlyph.fromChar', () {
    test('"0" lights all outer segments', () {
      final g = SegmentGlyph.fromChar('0');
      expect(g.a, isTrue);
      expect(g.b, isTrue);
      expect(g.c, isTrue);
      expect(g.d, isTrue);
      expect(g.e, isTrue);
      expect(g.f, isTrue);
      expect(g.g, isFalse);
    });

    test('"-" returns blank', () {
      expect(SegmentGlyph.fromChar('-').isBlank, isTrue);
    });

    test('"x" returns error', () {
      expect(SegmentGlyph.fromChar('x').isError, isTrue);
    });
  });

  group('SevenSegmentStageWidget definition', () {
    test('metadata fields', () {
      const w = SevenSegmentStageWidget();
      expect(w.id, 'seven_segment');
      expect(w.category, StageWidgetCategory.primitive);
      // Both binding modes are optional — the user picks which to wire.
      expect(w.requiredSignals, isEmpty);
      final optionalNames = w.optionalSignals.map((b) => b.name).toSet();
      expect(optionalNames, contains('cathodes'));
      expect(optionalNames, contains('value'));
      expect(optionalNames, contains('dp'));
    });
  });

  group('SevenSegmentStageRenderer', () {
    const instance = StageInstance(
      id: 'i0',
      widgetId: 'seven_segment',
      signalBindings: {'value': testBinding},
    );

    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          wrapStageWidget(
            const SevenSegmentStageRenderer(instance: instance),
            snapshot: const StageSignalSnapshot.value(
              rawValue: '1010',
              bitWidth: 4,
            ),
            locale: Locale(locale),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('renders for x and z states without exception', (tester) async {
      for (final raw in ['10x0', '10z0']) {
        await tester.pumpWidget(
          wrapStageWidget(
            const SevenSegmentStageRenderer(instance: instance),
            snapshot: StageSignalSnapshot.value(rawValue: raw, bitWidth: 4),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('renders unbound without exception', (tester) async {
      const unbound = StageInstance(id: 'i0', widgetId: 'seven_segment');
      await tester.pumpWidget(
        wrapStageWidget(
          const SevenSegmentStageRenderer(instance: unbound),
          snapshot: const StageSignalSnapshot.unbound(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
