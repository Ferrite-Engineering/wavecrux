// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/widgets/primitives/toggle_switch_stage_widget.dart';

import '_test_helpers.dart';

void main() {
  group('toggleTargetPosition', () {
    test('value 1 → 1.0', () {
      expect(
        toggleTargetPosition(
          const StageSignalSnapshot.value(rawValue: '1', bitWidth: 1),
        ),
        1.0,
      );
    });

    test('value 0 → 0.0', () {
      expect(
        toggleTargetPosition(
          const StageSignalSnapshot.value(rawValue: '0', bitWidth: 1),
        ),
        0.0,
      );
    });

    test('x value → 0.5 (mid)', () {
      expect(
        toggleTargetPosition(
          const StageSignalSnapshot.value(rawValue: 'x', bitWidth: 1),
        ),
        0.5,
      );
    });

    test('z value → 0.5 (mid)', () {
      expect(
        toggleTargetPosition(
          const StageSignalSnapshot.value(rawValue: 'z', bitWidth: 1),
        ),
        0.5,
      );
    });

    test('unbound → 0.0', () {
      expect(toggleTargetPosition(const StageSignalSnapshot.unbound()), 0.0);
    });

    test('multi-bit uses LSB', () {
      expect(
        toggleTargetPosition(
          const StageSignalSnapshot.value(rawValue: '1110', bitWidth: 4),
        ),
        0.0,
      );
      expect(
        toggleTargetPosition(
          const StageSignalSnapshot.value(rawValue: '0001', bitWidth: 4),
        ),
        1.0,
      );
    });
  });

  group('ToggleSwitchStageWidget definition', () {
    test('metadata fields', () {
      const w = ToggleSwitchStageWidget();
      expect(w.id, 'toggle_switch');
      expect(w.category, StageWidgetCategory.primitive);
      expect(w.requiredSignals, hasLength(1));
      expect(w.requiredSignals.first.name, 'in');
    });
  });

  group('ToggleSwitchStageRenderer', () {
    const instance = StageInstance(
      id: 'i0',
      widgetId: 'toggle_switch',
      signalBindings: {'in': testBinding},
    );

    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          wrapStageWidget(
            const ToggleSwitchStageRenderer(instance: instance),
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

    testWidgets('renders for off, on, and x states without exception', (
      tester,
    ) async {
      for (final raw in ['0', '1', 'x', 'z']) {
        await tester.pumpWidget(
          wrapStageWidget(
            const ToggleSwitchStageRenderer(instance: instance),
            snapshot: StageSignalSnapshot.value(rawValue: raw, bitWidth: 1),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('renders an unbound instance without exception', (
      tester,
    ) async {
      const unbound = StageInstance(id: 'i0', widgetId: 'toggle_switch');
      await tester.pumpWidget(
        wrapStageWidget(
          const ToggleSwitchStageRenderer(instance: unbound),
          snapshot: const StageSignalSnapshot.unbound(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
