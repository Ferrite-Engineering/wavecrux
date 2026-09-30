// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/fsm_model.dart';
import 'package:wavecrux/domain/models/fsm_state.dart';
import 'package:wavecrux/domain/models/fsm_transition.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/services/signal_query/fsm_layout_service.dart';

const _svc = FsmLayoutService();
const _range = TimeRange(start: 0, end: 100);

FsmModel _model(
  List<FsmState> states, [
  List<FsmTransition> transitions = const [],
]) => FsmModel(
  signalRef: 'r',
  signalPath: 'top.fsm',
  timeRange: _range,
  states: states,
  transitions: transitions,
  totalTransitionCount: transitions.fold(0, (s, t) => s + t.count),
);

FsmState _s(String id) =>
    FsmState(id: id, label: id, entryCount: 1, firstEntryTime: 0);

void main() {
  group('FsmLayoutService.compute', () {
    test('empty model produces empty layout', () {
      final layout = _svc.compute(_model(const []));
      expect(layout.isEmpty, isTrue);
    });

    test('single state placed at the centre', () {
      final layout = _svc.compute(_model([_s('0')]));
      expect(layout.positions.length, 1);
      final pos = layout['0']!;
      expect(pos.x, closeTo(0.5, 1e-6));
      expect(pos.y, closeTo(0.5, 1e-6));
    });

    test('two states placed on opposite sides of the circle', () {
      final layout = _svc.compute(_model([_s('0'), _s('1')]));
      final p0 = layout['0']!;
      final p1 = layout['1']!;
      // First state is at the top (12 o'clock).
      expect(p0.y, lessThan(0.5));
      // Second state is at the bottom.
      expect(p1.y, greaterThan(0.5));
      // Both are roughly centred horizontally for 2 states.
      expect(p0.x, closeTo(0.5, 1e-6));
      expect(p1.x, closeTo(0.5, 1e-6));
    });

    test('all positions stay within the unit square', () {
      final layout = _svc.compute(
        _model([for (var i = 0; i < 8; i++) _s('$i')]),
      );
      for (final p in layout.positions.values) {
        expect(p.x, inInclusiveRange(0, 1));
        expect(p.y, inInclusiveRange(0, 1));
      }
    });

    test('every state in the model has a position', () {
      final layout = _svc.compute(
        _model([for (var i = 0; i < 12; i++) _s('$i')]),
      );
      expect(layout.positions.length, 12);
      for (var i = 0; i < 12; i++) {
        expect(layout['$i'], isNotNull);
      }
    });

    test('many-state FSM (16 states) uses larger radius', () {
      final layout = _svc.compute(
        _model([for (var i = 0; i < 16; i++) _s('$i')]),
      );
      // Pick the first state — it should be displaced from the centre by a
      // larger amount than for the 4-state case.
      final pSmall = _svc.compute(
        _model([for (var i = 0; i < 4; i++) _s('$i')]),
      )['0']!;
      final pBig = layout['0']!;
      final smallDist = (pSmall.y - 0.5).abs();
      final bigDist = (pBig.y - 0.5).abs();
      // Larger FSM uses the larger radius.
      expect(bigDist, greaterThan(smallDist));
    });

    test('layout is deterministic across runs', () {
      final m = _model([_s('0'), _s('1'), _s('2')]);
      final a = _svc.compute(m);
      final b = _svc.compute(m);
      expect(a, equals(b));
    });
  });
}
