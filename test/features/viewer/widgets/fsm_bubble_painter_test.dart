// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/fsm_model.dart';
import 'package:wavecrux/domain/models/fsm_state.dart';
import 'package:wavecrux/domain/models/fsm_transition.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/features/viewer/widgets/fsm_bubble_painter.dart';
import 'package:wavecrux/services/signal_query/fsm_layout_service.dart';

const _range = TimeRange(start: 0, end: 100);
const _layoutSvc = FsmLayoutService();

FsmModel _model(
  List<FsmState> states, [
  List<FsmTransition> transitions = const [],
]) => FsmModel(
  signalRef: 'r',
  signalPath: 'top',
  timeRange: _range,
  states: states,
  transitions: transitions,
  totalTransitionCount: transitions.fold(0, (s, t) => s + t.count),
);

// Helper to render via a CustomPaint widget.
Widget _wrap(FsmBubblePainter painter, Size size) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: CustomPaint(painter: painter, size: size),
      ),
    ),
  ),
);

void main() {
  group('FsmBubblePainter — paint', () {
    testWidgets('paints empty model without throwing', (tester) async {
      final model = _model(const []);
      final layout = _layoutSvc.compute(model);
      const colorScheme = ColorScheme.dark();
      final painter = FsmBubblePainter(
        model: model,
        layout: layout,
        colorScheme: colorScheme,
      );
      await tester.pumpWidget(_wrap(painter, const Size(400, 300)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('paints two-state model without throwing', (tester) async {
      final model = _model(
        const [
          FsmState(id: '0', label: 'IDLE', entryCount: 1, firstEntryTime: 0),
          FsmState(id: '1', label: 'RUN', entryCount: 1, firstEntryTime: 10),
        ],
        const [
          FsmTransition(fromId: '0', toId: '1', count: 1, times: [10]),
        ],
      );
      final layout = _layoutSvc.compute(model);
      const colorScheme = ColorScheme.dark();
      final painter = FsmBubblePainter(
        model: model,
        layout: layout,
        colorScheme: colorScheme,
      );
      await tester.pumpWidget(_wrap(painter, const Size(400, 300)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('paints with self-loops without throwing', (tester) async {
      final model = _model(
        const [
          FsmState(id: '0', label: 'A', entryCount: 1, firstEntryTime: 0),
          FsmState(id: '1', label: 'B', entryCount: 1, firstEntryTime: 5),
        ],
        const [
          FsmTransition(fromId: '0', toId: '0', count: 1, times: [10]),
          FsmTransition(fromId: '1', toId: '1', count: 1, times: [15]),
        ],
      );
      final layout = _layoutSvc.compute(model);
      const colorScheme = ColorScheme.dark();
      final painter = FsmBubblePainter(
        model: model,
        layout: layout,
        colorScheme: colorScheme,
      );
      await tester.pumpWidget(_wrap(painter, const Size(400, 300)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('paints with active state highlighted', (tester) async {
      final model = _model(const [
        FsmState(id: '0', label: 'IDLE', entryCount: 1, firstEntryTime: 0),
        FsmState(id: '1', label: 'RUN', entryCount: 1, firstEntryTime: 10),
      ]);
      final layout = _layoutSvc.compute(model);
      const colorScheme = ColorScheme.dark();
      final painter = FsmBubblePainter(
        model: model,
        layout: layout,
        colorScheme: colorScheme,
        activeStateId: '0',
      );
      await tester.pumpWidget(_wrap(painter, const Size(400, 300)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('paints with active transition highlighted', (tester) async {
      final model = _model(
        const [
          FsmState(id: '0', label: 'A', entryCount: 1, firstEntryTime: 0),
          FsmState(id: '1', label: 'B', entryCount: 1, firstEntryTime: 5),
        ],
        const [
          FsmTransition(fromId: '0', toId: '1', count: 1, times: [10]),
        ],
      );
      final layout = _layoutSvc.compute(model);
      const colorScheme = ColorScheme.dark();
      final painter = FsmBubblePainter(
        model: model,
        layout: layout,
        colorScheme: colorScheme,
        activeTransition: (fromId: '0', toId: '1'),
      );
      await tester.pumpWidget(_wrap(painter, const Size(400, 300)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('paints many-state FSM without throwing', (tester) async {
      final states = [
        for (var i = 0; i < 10; i++)
          FsmState(id: '$i', label: 'S$i', entryCount: 1, firstEntryTime: i),
      ];
      final transitions = [
        for (var i = 0; i < 9; i++)
          FsmTransition(fromId: '$i', toId: '${i + 1}', count: 1, times: [i]),
      ];
      final model = _model(states, transitions);
      final layout = _layoutSvc.compute(model);
      const colorScheme = ColorScheme.dark();
      final painter = FsmBubblePainter(
        model: model,
        layout: layout,
        colorScheme: colorScheme,
      );
      await tester.pumpWidget(_wrap(painter, const Size(800, 600)));
      expect(tester.takeException(), isNull);
    });
  });

  group('FsmBubblePainter.hitTestState', () {
    test('returns the state id under the pointer', () {
      final model = _model(const [
        FsmState(id: '0', label: 'A', entryCount: 1, firstEntryTime: 0),
        FsmState(id: '1', label: 'B', entryCount: 1, firstEntryTime: 5),
      ]);
      final layout = _layoutSvc.compute(model);
      const colorScheme = ColorScheme.dark();
      final painter = FsmBubblePainter(
        model: model,
        layout: layout,
        colorScheme: colorScheme,
      );

      const size = Size(400, 300);
      // State '0' should be roughly centred horizontally and above the
      // vertical centre.
      final pos0 = layout['0']!;
      final centre0 = Offset(pos0.x * size.width, pos0.y * size.height);
      expect(painter.hitTestState(centre0, size), '0');

      // A point far away from any state returns null.
      expect(painter.hitTestState(Offset.zero, size), isNull);
    });

    test('returns null for empty layouts', () {
      final model = _model(const []);
      final layout = _layoutSvc.compute(model);
      const colorScheme = ColorScheme.dark();
      final painter = FsmBubblePainter(
        model: model,
        layout: layout,
        colorScheme: colorScheme,
      );
      expect(
        painter.hitTestState(const Offset(100, 100), const Size(400, 300)),
        isNull,
      );
    });
  });

  group('FsmBubblePainter.shouldRepaint', () {
    test('repaints when active state id changes', () {
      final model = _model(const [
        FsmState(id: '0', label: 'A', entryCount: 1, firstEntryTime: 0),
      ]);
      final layout = _layoutSvc.compute(model);
      const cs = ColorScheme.dark();
      final a = FsmBubblePainter(model: model, layout: layout, colorScheme: cs);
      final b = FsmBubblePainter(
        model: model,
        layout: layout,
        colorScheme: cs,
        activeStateId: '0',
      );
      expect(b.shouldRepaint(a), isTrue);
    });

    test('does not repaint when nothing changes', () {
      final model = _model(const [
        FsmState(id: '0', label: 'A', entryCount: 1, firstEntryTime: 0),
      ]);
      final layout = _layoutSvc.compute(model);
      const cs = ColorScheme.dark();
      final a = FsmBubblePainter(model: model, layout: layout, colorScheme: cs);
      final b = FsmBubblePainter(model: model, layout: layout, colorScheme: cs);
      expect(b.shouldRepaint(a), isFalse);
    });
  });
}
