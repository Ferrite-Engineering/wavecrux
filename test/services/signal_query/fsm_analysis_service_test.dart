// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/fsm_annotation.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/services/signal_query/fsm_analysis_service.dart';
import 'package:wavecrux/services/translate/translate_filter_service.dart';

class _MockSource extends Mock implements WaveformDataSource {}

const _svc = FsmAnalysisService();

/// Stubs [valueAt] and [changesInRange] for one signal.
///
/// [initValue] is the value at startTime (returned for any t before the
/// first change in [changes]). [changes] are all transitions strictly
/// after startTime — they are also returned by changesInRange in order.
void _stub(
  _MockSource ds,
  String ref,
  String? initValue,
  List<SignalChange> changes,
) {
  when(() => ds.valueAt(ref, any())).thenAnswer((inv) {
    final t = inv.positionalArguments[1] as int;
    var current = initValue;
    for (final c in changes) {
      if (c.time <= t) current = c.value;
    }
    return current;
  });
  when(() => ds.changesInRange(ref, any(), any())).thenAnswer((inv) {
    final start = inv.positionalArguments[1] as int;
    final end = inv.positionalArguments[2] as int;
    return changes.where((c) => c.time >= start && c.time < end).toList();
  });
  when(() => ds.isSignalLoaded(ref)).thenReturn(true);
}

void main() {
  group('FsmAnalysisService.buildModel', () {
    test('two-state toggle: 0→1→0→1', () {
      final ds = _MockSource();
      _stub(ds, 'r', '0', [
        const SignalChange(time: 10, value: '1'),
        const SignalChange(time: 20, value: '0'),
        const SignalChange(time: 30, value: '1'),
      ]);

      final m = _svc.buildModel(
        signalRef: 'r',
        signalPath: 'top.toggle',
        source: ds,
        startTime: 0,
        endTime: 100,
      );

      // 2 states: 0 and 1
      expect(m.states.map((s) => s.id).toList(), ['0', '1']);
      expect(m.stateById('0')!.entryCount, 2); // initial + 0→1→0
      expect(m.stateById('1')!.entryCount, 2);
      expect(m.stateById('0')!.firstEntryTime, 0);
      expect(m.stateById('1')!.firstEntryTime, 10);

      // Transitions: 0→1 (at 10, 30) and 1→0 (at 20)
      expect(m.transitions.length, 2);
      final t01 = m.transitions.firstWhere(
        (t) => t.fromId == '0' && t.toId == '1',
      );
      final t10 = m.transitions.firstWhere(
        (t) => t.fromId == '1' && t.toId == '0',
      );
      expect(t01.count, 2);
      expect(t01.times, [10, 30]);
      expect(t10.count, 1);
      expect(t10.times, [20]);
      expect(m.totalTransitionCount, 3);
    });

    test('single-state FSM (no transitions)', () {
      final ds = _MockSource();
      _stub(ds, 'r', '0', const []);

      final m = _svc.buildModel(
        signalRef: 'r',
        signalPath: 'top.const',
        source: ds,
        startTime: 0,
        endTime: 50,
      );
      expect(m.states.length, 1);
      expect(m.states.first.id, '0');
      expect(m.states.first.entryCount, 1);
      expect(m.states.first.firstEntryTime, 0);
      expect(m.transitions, isEmpty);
      expect(m.totalTransitionCount, 0);
      expect(m.isTrivial, isTrue);
    });

    test('many-state FSM (5 states) with binary-encoded values', () {
      final ds = _MockSource();
      _stub(ds, 'r', '000', [
        const SignalChange(time: 10, value: '001'), // 1
        const SignalChange(time: 20, value: '010'), // 2
        const SignalChange(time: 30, value: '011'), // 3
        const SignalChange(time: 40, value: '100'), // 4
        const SignalChange(time: 50, value: '000'), // 0
      ]);

      final m = _svc.buildModel(
        signalRef: 'r',
        signalPath: 'top.fsm',
        source: ds,
        startTime: 0,
        endTime: 100,
      );

      // States ordered numerically.
      expect(m.states.map((s) => s.id).toList(), ['0', '1', '2', '3', '4']);

      // Each transition is unique here.
      expect(m.transitions.length, 5);
      expect(m.totalTransitionCount, 5);
    });

    test('self-loops are recorded when same value re-asserts', () {
      final ds = _MockSource();
      _stub(ds, 'r', '01', [
        const SignalChange(time: 10, value: '01'), // self-loop 1→1
        const SignalChange(time: 20, value: '10'), // 1→2
        const SignalChange(time: 30, value: '10'), // self-loop 2→2
      ]);

      final m = _svc.buildModel(
        signalRef: 'r',
        signalPath: 'top.fsm',
        source: ds,
        startTime: 0,
        endTime: 100,
      );

      final selfLoops = m.transitions.where((t) => t.isSelfLoop).toList();
      expect(selfLoops.length, 2);
      expect(selfLoops.firstWhere((t) => t.fromId == '1').count, 1);
      expect(selfLoops.firstWhere((t) => t.fromId == '2').count, 1);
    });

    test('x/z values are skipped and break the transition chain', () {
      final ds = _MockSource();
      _stub(ds, 'r', '00', [
        const SignalChange(time: 10, value: '01'), // 0→1
        const SignalChange(time: 20, value: 'xx'), // chain breaks
        const SignalChange(time: 30, value: '10'), // no transition recorded
        const SignalChange(time: 40, value: '11'), // 2→3
      ]);

      final m = _svc.buildModel(
        signalRef: 'r',
        signalPath: 'top.fsm',
        source: ds,
        startTime: 0,
        endTime: 100,
      );

      // States: 0, 1, 2, 3 (xx is excluded)
      expect(m.states.map((s) => s.id).toSet(), {'0', '1', '2', '3'});
      // Transitions: 0→1 (at 10) and 2→3 (at 40); the 1→? path was broken
      // by xx, and 30 is the first defined value after the break (no
      // transition is recorded into 2 because the prior state was unknown).
      expect(m.transitions.map((t) => '${t.fromId}→${t.toId}').toSet(), {
        '0→1',
        '2→3',
      });
    });

    test('translate filter labels states by binary value', () {
      final ds = _MockSource();
      _stub(ds, 'r', '00', [
        const SignalChange(time: 10, value: '01'),
        const SignalChange(time: 20, value: '10'),
      ]);

      final filter = const TranslateFilterService().parse('''
0   IDLE
1   RUN
2   DONE
''');

      final m = _svc.buildModel(
        signalRef: 'r',
        signalPath: 'top.fsm',
        source: ds,
        startTime: 0,
        endTime: 100,
        translateFilter: filter,
      );

      expect(m.stateById('0')?.label, 'IDLE');
      expect(m.stateById('1')?.label, 'RUN');
      expect(m.stateById('2')?.label, 'DONE');
    });

    test('user annotation overrides translate filter', () {
      final ds = _MockSource();
      _stub(ds, 'r', '00', [
        const SignalChange(time: 10, value: '01'),
      ]);

      final filter = const TranslateFilterService().parse('0   FROM_FILTER\n');
      const annotation = FsmAnnotation(
        signalRef: 'r',
        stateLabels: {'0': 'FROM_USER'},
      );

      final m = _svc.buildModel(
        signalRef: 'r',
        signalPath: 'top.fsm',
        source: ds,
        startTime: 0,
        endTime: 100,
        annotation: annotation,
        translateFilter: filter,
      );

      expect(m.stateById('0')?.label, 'FROM_USER');
      // Filter still applies for the state without an annotation.
      expect(m.stateById('1')?.label, '1');
    });

    test('empty signal range produces empty model', () {
      final ds = _MockSource();
      _stub(ds, 'r', null, const []);

      final m = _svc.buildModel(
        signalRef: 'r',
        signalPath: 'top.empty',
        source: ds,
        startTime: 0,
        endTime: 100,
      );

      expect(m.states, isEmpty);
      expect(m.transitions, isEmpty);
      expect(m.totalTransitionCount, 0);
    });

    test('all-x signal produces empty model', () {
      final ds = _MockSource();
      _stub(ds, 'r', 'xx', const [
        SignalChange(time: 10, value: 'xx'),
        SignalChange(time: 20, value: 'xz'),
      ]);

      final m = _svc.buildModel(
        signalRef: 'r',
        signalPath: 'top.x',
        source: ds,
        startTime: 0,
        endTime: 100,
      );

      expect(m.states, isEmpty);
      expect(m.transitions, isEmpty);
    });

    test('real-valued signal is rejected (states stay empty)', () {
      final ds = _MockSource();
      _stub(ds, 'r', '3.14', const [
        SignalChange(time: 10, value: '2.71'),
      ]);

      final m = _svc.buildModel(
        signalRef: 'r',
        signalPath: 'top.real',
        source: ds,
        startTime: 0,
        endTime: 100,
      );

      expect(m.states, isEmpty);
    });

    test('b-prefix in raw value is handled', () {
      final ds = _MockSource();
      _stub(ds, 'r', 'b00', [
        const SignalChange(time: 10, value: 'b01'),
      ]);

      final m = _svc.buildModel(
        signalRef: 'r',
        signalPath: 'top.fsm',
        source: ds,
        startTime: 0,
        endTime: 100,
      );

      expect(m.states.map((s) => s.id).toList(), ['0', '1']);
    });

    test('transition counts sum to totalTransitionCount', () {
      final ds = _MockSource();
      _stub(ds, 'r', '00', [
        const SignalChange(time: 10, value: '01'),
        const SignalChange(time: 20, value: '00'),
        const SignalChange(time: 30, value: '01'),
        const SignalChange(time: 40, value: '00'),
        const SignalChange(time: 50, value: '01'),
      ]);

      final m = _svc.buildModel(
        signalRef: 'r',
        signalPath: 'top.fsm',
        source: ds,
        startTime: 0,
        endTime: 100,
      );
      var sum = 0;
      for (final t in m.transitions) {
        sum += t.count;
      }
      expect(sum, m.totalTransitionCount);
      expect(sum, 5);
    });
  });

  group('FsmAnalysisService.stateIdAt', () {
    test('returns canonical id', () {
      final ds = _MockSource();
      when(() => ds.valueAt('r', 50)).thenReturn('011');
      final id = _svc.stateIdAt(signalRef: 'r', source: ds, time: 50);
      expect(id, '3');
    });

    test('returns null for x/z', () {
      final ds = _MockSource();
      when(() => ds.valueAt('r', 50)).thenReturn('0x1');
      expect(
        _svc.stateIdAt(signalRef: 'r', source: ds, time: 50),
        isNull,
      );
    });

    test('returns null when valueAt returns null', () {
      final ds = _MockSource();
      when(() => ds.valueAt('r', 50)).thenReturn(null);
      expect(
        _svc.stateIdAt(signalRef: 'r', source: ds, time: 50),
        isNull,
      );
    });
  });
}
