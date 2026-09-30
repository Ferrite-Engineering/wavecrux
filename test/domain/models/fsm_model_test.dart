// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/fsm_model.dart';
import 'package:wavecrux/domain/models/fsm_state.dart';
import 'package:wavecrux/domain/models/fsm_transition.dart';
import 'package:wavecrux/domain/models/time_range.dart';

const _range = TimeRange(start: 0, end: 100);

FsmModel _model({
  List<FsmState> states = const [],
  List<FsmTransition> transitions = const [],
  int total = 0,
}) => FsmModel(
  signalRef: 'ref',
  signalPath: 'top.fsm',
  timeRange: _range,
  states: states,
  transitions: transitions,
  totalTransitionCount: total,
);

void main() {
  group('FsmModel', () {
    test('preserves all fields', () {
      final m = _model(
        states: [
          const FsmState(
            id: '0',
            label: 'IDLE',
            entryCount: 1,
            firstEntryTime: 0,
          ),
        ],
        transitions: [
          const FsmTransition(fromId: '0', toId: '1', count: 1, times: [10]),
        ],
        total: 1,
      );
      expect(m.signalRef, 'ref');
      expect(m.signalPath, 'top.fsm');
      expect(m.timeRange, _range);
      expect(m.states, hasLength(1));
      expect(m.transitions, hasLength(1));
      expect(m.totalTransitionCount, 1);
    });

    test('isTrivial when 0 or 1 states', () {
      expect(_model().isTrivial, isTrue);
      expect(
        _model(
          states: const [
            FsmState(id: '0', label: '0', entryCount: 1, firstEntryTime: 0),
          ],
        ).isTrivial,
        isTrue,
      );
      expect(
        _model(
          states: const [
            FsmState(id: '0', label: '0', entryCount: 1, firstEntryTime: 0),
            FsmState(id: '1', label: '1', entryCount: 1, firstEntryTime: 5),
          ],
        ).isTrivial,
        isFalse,
      );
    });

    test('stateById returns matching state or null', () {
      final m = _model(
        states: const [
          FsmState(id: '0', label: 'IDLE', entryCount: 1, firstEntryTime: 0),
          FsmState(id: '1', label: 'RUN', entryCount: 2, firstEntryTime: 10),
        ],
      );
      expect(m.stateById('0')?.label, 'IDLE');
      expect(m.stateById('1')?.label, 'RUN');
      expect(m.stateById('99'), isNull);
    });

    test('equality is structural', () {
      final a = _model(
        states: const [
          FsmState(id: '0', label: 'A', entryCount: 1, firstEntryTime: 0),
        ],
        transitions: const [
          FsmTransition(fromId: '0', toId: '1', count: 1, times: [5]),
        ],
        total: 1,
      );
      final b = _model(
        states: const [
          FsmState(id: '0', label: 'A', entryCount: 1, firstEntryTime: 0),
        ],
        transitions: const [
          FsmTransition(fromId: '0', toId: '1', count: 1, times: [5]),
        ],
        total: 1,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality with different transitions', () {
      final a = _model(
        transitions: const [
          FsmTransition(fromId: '0', toId: '1', count: 1, times: [5]),
        ],
      );
      final b = _model(
        transitions: const [
          FsmTransition(fromId: '0', toId: '2', count: 1, times: [5]),
        ],
      );
      expect(a == b, isFalse);
    });

    test('copyWith updates the requested fields', () {
      final m = _model();
      final updated = m.copyWith(
        signalPath: 'new.path',
        totalTransitionCount: 5,
      );
      expect(updated.signalPath, 'new.path');
      expect(updated.totalTransitionCount, 5);
      expect(updated.signalRef, m.signalRef);
    });
  });
}
