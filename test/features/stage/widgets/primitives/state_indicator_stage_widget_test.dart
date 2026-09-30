// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/widgets/primitives/state_indicator_stage_widget.dart';

import '_test_helpers.dart';

void main() {
  const stateMap = {
    0: StateIndicatorEntry(label: 'IDLE', color: Color(0xFF43A047)),
    1: StateIndicatorEntry(label: 'RUN', color: Color(0xFF1E88E5)),
    2: StateIndicatorEntry(label: 'ERR', color: Color(0xFFE53935)),
  };

  group('resolveStateIndicatorReading', () {
    test('value 0 → IDLE', () {
      const s = StageSignalSnapshot.value(rawValue: '00', bitWidth: 2);
      final r = resolveStateIndicatorReading(s, stateMap);
      expect(r.label, 'IDLE');
    });

    test('value 1 → RUN', () {
      const s = StageSignalSnapshot.value(rawValue: '01', bitWidth: 2);
      final r = resolveStateIndicatorReading(s, stateMap);
      expect(r.label, 'RUN');
    });

    test('value not in map → ?? unknown', () {
      const s = StageSignalSnapshot.value(rawValue: '11', bitWidth: 2);
      final r = resolveStateIndicatorReading(s, stateMap);
      expect(r.label, '??');
    });

    test('x → X error', () {
      const s = StageSignalSnapshot.value(rawValue: 'xx', bitWidth: 2);
      final r = resolveStateIndicatorReading(s, stateMap);
      expect(r.label, 'X');
    });

    test('unbound → dash', () {
      final r = resolveStateIndicatorReading(
        const StageSignalSnapshot.unbound(),
        stateMap,
      );
      expect(r.label, '–');
    });
  });

  group('StateIndicatorStageWidget definition', () {
    test('metadata fields', () {
      const w = StateIndicatorStageWidget();
      expect(w.id, 'state_indicator');
      expect(w.category, StageWidgetCategory.primitive);
      expect(w.requiredSignals.first.name, 'state');
    });
  });

  group('StateIndicatorStageRenderer', () {
    const instance = StageInstance(
      id: 'i0',
      widgetId: 'state_indicator',
      signalBindings: {'state': testBinding},
    );

    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          wrapStageWidget(
            const StateIndicatorStageRenderer(instance: instance),
            snapshot: const StageSignalSnapshot.value(
              rawValue: '00',
              bitWidth: 2,
            ),
            locale: Locale(locale),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('renders default state mapping IDLE label', (tester) async {
      await tester.pumpWidget(
        wrapStageWidget(
          const StateIndicatorStageRenderer(instance: instance),
          snapshot: const StageSignalSnapshot.value(
            rawValue: '00',
            bitWidth: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('IDLE'), findsOneWidget);
    });

    testWidgets('renders X when signal is undefined', (tester) async {
      await tester.pumpWidget(
        wrapStageWidget(
          const StateIndicatorStageRenderer(instance: instance),
          snapshot: const StageSignalSnapshot.value(
            rawValue: 'xx',
            bitWidth: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('X'), findsOneWidget);
    });

    testWidgets('renders ?? for unmapped value', (tester) async {
      await tester.pumpWidget(
        wrapStageWidget(
          const StateIndicatorStageRenderer(
            instance: instance,
            stateMap: {0: StateIndicatorEntry(label: 'A', color: Colors.red)},
          ),
          snapshot: const StageSignalSnapshot.value(
            rawValue: '11',
            bitWidth: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('??'), findsOneWidget);
    });
  });
}
