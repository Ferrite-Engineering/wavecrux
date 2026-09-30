// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/widgets/primitives/bus_readout_stage_widget.dart';

import '_test_helpers.dart';

void main() {
  group('formatBusReadout', () {
    test('hex format', () {
      const s = StageSignalSnapshot.value(rawValue: '11111110', bitWidth: 8);
      expect(
        formatBusReadout(s, format: DisplayFormat.hexadecimal).text,
        'fe',
      );
    });

    test('decimal format', () {
      const s = StageSignalSnapshot.value(rawValue: '11111110', bitWidth: 8);
      expect(
        formatBusReadout(s, format: DisplayFormat.unsignedDecimal).text,
        '254',
      );
    });

    test('binary format pads to width', () {
      const s = StageSignalSnapshot.value(rawValue: '101', bitWidth: 8);
      expect(
        formatBusReadout(s, format: DisplayFormat.binary).text,
        '00000101',
      );
    });

    test('x → error', () {
      const s = StageSignalSnapshot.value(rawValue: '10x0', bitWidth: 4);
      final r = formatBusReadout(s, format: DisplayFormat.hexadecimal);
      expect(r.text, 'X');
      expect(r.isError, isTrue);
    });

    test('z → error', () {
      const s = StageSignalSnapshot.value(rawValue: '10z0', bitWidth: 4);
      final r = formatBusReadout(s, format: DisplayFormat.hexadecimal);
      expect(r.text, 'Z');
      expect(r.isError, isTrue);
    });

    test('unbound → dash', () {
      final r = formatBusReadout(
        const StageSignalSnapshot.unbound(),
        format: DisplayFormat.hexadecimal,
      );
      expect(r.text, '–');
      expect(r.isError, isFalse);
    });
  });

  group('BusReadoutStageWidget definition', () {
    test('metadata fields', () {
      const w = BusReadoutStageWidget();
      expect(w.id, 'bus_readout');
      expect(w.category, StageWidgetCategory.primitive);
      expect(w.requiredSignals.first.name, 'value');
    });
  });

  group('BusReadoutStageRenderer', () {
    const instance = StageInstance(
      id: 'i0',
      widgetId: 'bus_readout',
      signalBindings: {'value': testBinding},
    );

    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          wrapStageWidget(
            const BusReadoutStageRenderer(instance: instance),
            snapshot: const StageSignalSnapshot.value(
              rawValue: '11111110',
              bitWidth: 8,
            ),
            locale: Locale(locale),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('hex shows 0x prefix', (tester) async {
      await tester.pumpWidget(
        wrapStageWidget(
          const BusReadoutStageRenderer(instance: instance),
          snapshot: const StageSignalSnapshot.value(
            rawValue: '11111110',
            bitWidth: 8,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0xfe'), findsOneWidget);
    });

    testWidgets('decimal shows raw number', (tester) async {
      await tester.pumpWidget(
        wrapStageWidget(
          const BusReadoutStageRenderer(
            instance: instance,
            format: DisplayFormat.unsignedDecimal,
          ),
          snapshot: const StageSignalSnapshot.value(
            rawValue: '11111110',
            bitWidth: 8,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('254'), findsOneWidget);
    });

    testWidgets('X-state shows error label', (tester) async {
      await tester.pumpWidget(
        wrapStageWidget(
          const BusReadoutStageRenderer(instance: instance),
          snapshot: const StageSignalSnapshot.value(
            rawValue: '10x0',
            bitWidth: 4,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('X'), findsOneWidget);
    });
  });
}
