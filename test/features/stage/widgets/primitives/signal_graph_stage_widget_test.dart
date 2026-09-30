// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/widgets/primitives/signal_graph_stage_widget.dart';

import '_test_helpers.dart';

void main() {
  group('computeSignalGraphYRange', () {
    test('empty samples → fallback range', () {
      final r = computeSignalGraphYRange(const []);
      expect(r.min, 0);
      expect(r.max, 1);
    });

    test('all-null samples → fallback range', () {
      final r = computeSignalGraphYRange(const [
        SignalGraphSample(time: 0, value: null),
        SignalGraphSample(time: 1, value: null),
      ]);
      expect(r.min, 0);
      expect(r.max, 1);
    });

    test('single value pads above and below', () {
      final r = computeSignalGraphYRange(const [
        SignalGraphSample(time: 0, value: 5),
      ]);
      expect(r.min, lessThan(5));
      expect(r.max, greaterThan(5));
    });

    test('value range has 5% margin', () {
      final r = computeSignalGraphYRange(const [
        SignalGraphSample(time: 0, value: 0),
        SignalGraphSample(time: 1, value: 100),
      ]);
      expect(r.min, lessThan(0));
      expect(r.max, greaterThan(100));
    });

    test('handles negatives', () {
      final r = computeSignalGraphYRange(const [
        SignalGraphSample(time: 0, value: -10),
        SignalGraphSample(time: 1, value: 10),
      ]);
      expect(r.min, lessThan(-10));
      expect(r.max, greaterThan(10));
    });
  });

  group('SignalGraphSample equality', () {
    test('equal samples produce equal hashCodes', () {
      const a = SignalGraphSample(time: 1, value: 2);
      const b = SignalGraphSample(time: 1, value: 2);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('SignalGraphStageWidget definition', () {
    test('metadata fields', () {
      const w = SignalGraphStageWidget();
      expect(w.id, 'signal_graph');
      expect(w.category, StageWidgetCategory.instrument);
      expect(w.requiredSignals.first.name, 'value');
    });
  });

  group('SignalGraphStageRenderer', () {
    const instance = StageInstance(
      id: 'i0',
      widgetId: 'signal_graph',
      signalBindings: {'value': testBinding},
    );

    testWidgets('unbound shows placeholder', (tester) async {
      const unbound = StageInstance(id: 'i0', widgetId: 'signal_graph');
      await tester.pumpWidget(
        wrapStageWidget(
          const SignalGraphStageRenderer(instance: unbound),
          snapshot: const StageSignalSnapshot.unbound(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Bind'), findsOneWidget);
    });

    testWidgets('no-file state shows file placeholder', (tester) async {
      await tester.pumpWidget(
        wrapStageWidget(
          const SignalGraphStageRenderer(instance: instance),
          snapshot: const StageSignalSnapshot.noFile(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('waveform'), findsOneWidget);
    });

    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders unbound without exception in $locale', (
        tester,
      ) async {
        const unbound = StageInstance(id: 'i0', widgetId: 'signal_graph');
        await tester.pumpWidget(
          wrapStageWidget(
            const SignalGraphStageRenderer(instance: unbound),
            snapshot: const StageSignalSnapshot.unbound(),
            locale: Locale(locale),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
