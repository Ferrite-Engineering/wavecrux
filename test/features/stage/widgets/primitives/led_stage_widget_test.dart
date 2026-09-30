// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/widgets/primitives/led_stage_widget.dart';

import '_test_helpers.dart';

void main() {
  group('ledVisualStateFor', () {
    test('value 1 → on', () {
      const s = StageSignalSnapshot.value(rawValue: '1', bitWidth: 1);
      expect(ledVisualStateFor(s), LedVisualState.on);
    });

    test('value 0 → off', () {
      const s = StageSignalSnapshot.value(rawValue: '0', bitWidth: 1);
      expect(ledVisualStateFor(s), LedVisualState.off);
    });

    test('x → unknown', () {
      const s = StageSignalSnapshot.value(rawValue: 'x', bitWidth: 1);
      expect(ledVisualStateFor(s), LedVisualState.unknown);
    });

    test('z → highImpedance', () {
      const s = StageSignalSnapshot.value(rawValue: 'z', bitWidth: 1);
      expect(ledVisualStateFor(s), LedVisualState.highImpedance);
    });

    test('multi-bit bus uses LSB', () {
      const onBus = StageSignalSnapshot.value(rawValue: '0001', bitWidth: 4);
      const offBus = StageSignalSnapshot.value(rawValue: '1110', bitWidth: 4);
      expect(ledVisualStateFor(onBus), LedVisualState.on);
      expect(ledVisualStateFor(offBus), LedVisualState.off);
    });

    test('unbound snapshot → inactive', () {
      expect(
        ledVisualStateFor(const StageSignalSnapshot.unbound()),
        LedVisualState.inactive,
      );
    });

    test('loading snapshot → inactive', () {
      expect(
        ledVisualStateFor(const StageSignalSnapshot.loading()),
        LedVisualState.inactive,
      );
    });

    test('unknown snapshot → inactive', () {
      expect(
        ledVisualStateFor(const StageSignalSnapshot.unknown()),
        LedVisualState.inactive,
      );
    });

    test('strips b prefix on multi-bit', () {
      const s = StageSignalSnapshot.value(rawValue: 'b1011', bitWidth: 4);
      expect(ledVisualStateFor(s), LedVisualState.on);
    });
  });

  group('LedStageWidget definition', () {
    test('metadata fields', () {
      const w = LedStageWidget();
      expect(w.id, 'led');
      expect(w.displayName, 'LED');
      expect(w.category, StageWidgetCategory.primitive);
      expect(w.requiredSignals, hasLength(1));
      expect(w.requiredSignals.first.name, 'in');
      expect(w.requiredSignals.first.bitWidth, 1);
    });
  });

  group('LedStageRenderer', () {
    const instance = StageInstance(
      id: 'i0',
      widgetId: 'led',
      signalBindings: {'in': testBinding},
    );

    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          wrapStageWidget(
            const LedStageRenderer(instance: instance),
            snapshot: const StageSignalSnapshot.value(
              rawValue: '1',
              bitWidth: 1,
            ),
            locale: Locale(locale),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shows "1" label when bit is high', (tester) async {
      await tester.pumpWidget(
        wrapStageWidget(
          const LedStageRenderer(instance: instance),
          snapshot: const StageSignalSnapshot.value(rawValue: '1', bitWidth: 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('shows "0" label when bit is low', (tester) async {
      await tester.pumpWidget(
        wrapStageWidget(
          const LedStageRenderer(instance: instance),
          snapshot: const StageSignalSnapshot.value(rawValue: '0', bitWidth: 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('shows "X" for x-state', (tester) async {
      await tester.pumpWidget(
        wrapStageWidget(
          const LedStageRenderer(instance: instance),
          snapshot: const StageSignalSnapshot.value(rawValue: 'x', bitWidth: 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('X'), findsOneWidget);
    });

    testWidgets('shows "Z" for high-impedance', (tester) async {
      await tester.pumpWidget(
        wrapStageWidget(
          const LedStageRenderer(instance: instance),
          snapshot: const StageSignalSnapshot.value(rawValue: 'z', bitWidth: 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Z'), findsOneWidget);
    });

    testWidgets('unbound shows placeholder dash', (tester) async {
      const unboundInstance = StageInstance(id: 'i0', widgetId: 'led');
      await tester.pumpWidget(
        wrapStageWidget(
          const LedStageRenderer(instance: unboundInstance),
          snapshot: const StageSignalSnapshot.unbound(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('–'), findsOneWidget);
    });
  });
}
