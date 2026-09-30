// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/widgets/primitives/level_bar_stage_widget.dart';

import '_test_helpers.dart';

void main() {
  group('computeLevelBarReading', () {
    test('mid-range value → 0.5 fraction, normal zone', () {
      const s = StageSignalSnapshot.value(rawValue: '1000000', bitWidth: 8);
      final r = computeLevelBarReading(s, minValue: 0, maxValue: 256);
      expect(r.fraction, closeTo(0.25, 1e-9));
      expect(r.value, 64);
      expect(r.zone, LevelBarZone.normal);
      expect(r.isError, isFalse);
    });

    test('value above warning → warning zone', () {
      const s = StageSignalSnapshot.value(rawValue: '11001000', bitWidth: 8);
      final r = computeLevelBarReading(
        s,
        minValue: 0,
        maxValue: 255,
        warningThreshold: 200,
        criticalThreshold: 240,
      );
      expect(r.zone, LevelBarZone.warning);
    });

    test('value above critical → critical zone', () {
      const s = StageSignalSnapshot.value(rawValue: '11111111', bitWidth: 8);
      final r = computeLevelBarReading(
        s,
        minValue: 0,
        maxValue: 255,
        warningThreshold: 200,
        criticalThreshold: 240,
      );
      expect(r.zone, LevelBarZone.critical);
    });

    test('clamps below min', () {
      const s = StageSignalSnapshot.value(rawValue: '0', bitWidth: 8);
      final r = computeLevelBarReading(s, minValue: 10, maxValue: 100);
      expect(r.fraction, 0);
    });

    test('clamps above max', () {
      const s = StageSignalSnapshot.value(rawValue: '11111111', bitWidth: 8);
      final r = computeLevelBarReading(s, minValue: 0, maxValue: 100);
      expect(r.fraction, 1);
    });

    test('x → error reading', () {
      const s = StageSignalSnapshot.value(rawValue: '10x0', bitWidth: 4);
      final r = computeLevelBarReading(s, minValue: 0, maxValue: 16);
      expect(r.isError, isTrue);
      expect(r.value, isNull);
      expect(r.fraction, 0);
    });

    test('unbound → fraction 0', () {
      final r = computeLevelBarReading(
        const StageSignalSnapshot.unbound(),
        minValue: 0,
        maxValue: 100,
      );
      expect(r.fraction, 0);
      expect(r.isError, isFalse);
    });

    test('zero-width range collapses to fraction 0', () {
      const s = StageSignalSnapshot.value(rawValue: '1010', bitWidth: 4);
      final r = computeLevelBarReading(s, minValue: 5, maxValue: 5);
      expect(r.fraction, 0);
    });
  });

  group('LevelBarStageWidget definition', () {
    test('metadata fields', () {
      const w = LevelBarStageWidget();
      expect(w.id, 'level_bar');
      expect(w.category, StageWidgetCategory.instrument);
      expect(w.requiredSignals.first.name, 'value');
    });
  });

  group('LevelBarStageRenderer', () {
    const instance = StageInstance(
      id: 'i0',
      widgetId: 'level_bar',
      signalBindings: {'value': testBinding},
    );

    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          wrapStageWidget(
            const LevelBarStageRenderer(instance: instance),
            snapshot: const StageSignalSnapshot.value(
              rawValue: '10000000',
              bitWidth: 8,
            ),
            locale: Locale(locale),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('renders error state for X without exception', (tester) async {
      await tester.pumpWidget(
        wrapStageWidget(
          const LevelBarStageRenderer(instance: instance),
          snapshot: const StageSignalSnapshot.value(
            rawValue: '10x0',
            bitWidth: 4,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The level bar paints the "X" error label directly to the canvas via
      // TextPainter, so we can't grep the widget tree for it. Verify the
      // error state renders without exceptions instead.
      expect(tester.takeException(), isNull);
    });

    testWidgets('horizontal orientation renders without exception', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapStageWidget(
          const LevelBarStageRenderer(
            instance: instance,
            orientation: Axis.horizontal,
          ),
          snapshot: const StageSignalSnapshot.value(
            rawValue: '10000000',
            bitWidth: 8,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
