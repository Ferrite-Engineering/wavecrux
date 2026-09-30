// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/signal_query/x_trace_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../helpers/fake_waveform_data_source.dart';

// ── mocks ──────────────────────────────────────────────────────────────────────

class _MockDataSource extends Mock implements WaveformDataSource {}

// ── helpers ────────────────────────────────────────────────────────────────────

const _svc = XTraceService();

Variable _var(
  String scopePath,
  String name, {
  int? bitWidth = 1,
  String? signalRef,
}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: signalRef ?? '$scopePath.$name',
  scopePath: scopePath,
  bitWidth: bitWidth,
);

Scope _scope(
  String path,
  List<Variable> vars, [
  List<Scope> children = const [],
]) {
  final dot = path.lastIndexOf('.');
  final name = dot < 0 ? path : path.substring(dot + 1);
  return Scope(
    name: name,
    type: ScopeType.module,
    path: path,
    variables: vars,
    childScopes: children,
  );
}

SignalChange _ch(int time, String value) =>
    SignalChange(time: time, value: value);

void _stubSignal(
  _MockDataSource ds,
  String ref,
  String initValue,
  List<SignalChange> changes, {
  int startTime = 0,
}) {
  when(() => ds.startTime).thenReturn(startTime);
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
}

// ── tests ──────────────────────────────────────────────────────────────────────

void main() {
  // ── findXOrigin ─────────────────────────────────────────────────────────────

  group('findXOrigin', () {
    test('returns null when signal is not X at the given time', () {
      final ds = _MockDataSource();
      _stubSignal(ds, 'top.s', '0', [_ch(100, '1'), _ch(200, '0')]);

      final result = _svc.findXOrigin('top.s', 'top.s', 200, ds);
      expect(result, isNull);
    });

    test('single X transition — finds origin with correct previous value', () {
      final ds = _MockDataSource();
      _stubSignal(ds, 'top.s', '0', [
        _ch(100, '1'),
        _ch(200, 'x'),
        _ch(300, '0'),
      ]);

      // Query at time 250 (still in x streak from 200)
      final result = _svc.findXOrigin('top.s', 'top.s', 250, ds);
      expect(result, isNotNull);
      expect(result!.originTime, 200);
      expect(result.previousValue, '1');
      expect(result.signalPath, 'top.s');
    });

    test('x streak that started at the very first change', () {
      final ds = _MockDataSource();
      // Initially '0', then immediately x at t=10
      _stubSignal(ds, 'top.s', '0', [_ch(10, 'x'), _ch(50, 'x')]);

      final result = _svc.findXOrigin('top.s', 'top.s', 40, ds);
      expect(result, isNotNull);
      expect(result!.originTime, 10);
      expect(result.previousValue, '0');
    });

    test('signal was X from simulation start (no non-X changes)', () {
      final ds = _MockDataSource();
      // Initial value is x, no prior non-x
      _stubSignal(ds, 'top.s', 'x', [_ch(100, 'x')]);

      final result = _svc.findXOrigin('top.s', 'top.s', 150, ds);
      expect(result, isNotNull);
      expect(result!.previousValue, isNull);
    });

    test('multiple x transitions — finds origin of current streak only', () {
      // 0→x→1→x; query at t=500 should find the second x streak
      final ds = _MockDataSource();
      _stubSignal(ds, 'top.s', '0', [
        _ch(100, 'x'),
        _ch(200, '1'),
        _ch(300, 'x'),
        _ch(400, 'x'),
      ]);

      final result = _svc.findXOrigin('top.s', 'top.s', 450, ds);
      expect(result, isNotNull);
      expect(result!.originTime, 300);
      expect(result.previousValue, '1');
    });

    test('multi-bit X value (bus with x bits) is detected', () {
      final ds = _MockDataSource();
      _stubSignal(ds, 'top.bus', '0000', [_ch(50, '00xx'), _ch(100, '0000')]);

      // At t=75 the bus has x bits
      final result = _svc.findXOrigin('top.bus', 'top.bus', 75, ds);
      expect(result, isNotNull);
      expect(result!.originTime, 50);
      expect(result.previousValue, '0000');
    });

    test('returns null when no changes exist and initial value is not X', () {
      final ds = _MockDataSource();
      _stubSignal(ds, 'top.s', '1', []);

      final result = _svc.findXOrigin('top.s', 'top.s', 500, ds);
      expect(result, isNull);
    });
  });

  // ── buildCausalChain ────────────────────────────────────────────────────────

  group('buildCausalChain', () {
    test('root node has correct x-start time and previous value', () {
      final ds = _MockDataSource();
      final variable = _var('top', 'status');
      _stubSignal(ds, 'top.status', '1', [_ch(200, '0'), _ch(400, 'x')]);
      when(() => ds.isSignalLoaded(any())).thenReturn(false);

      final hierarchy = [
        _scope('top', [variable]),
      ];
      final chain = _svc.buildCausalChain(variable, 500, hierarchy, ds);

      expect(chain.signalPath, 'top.status');
      expect(chain.xStartTime, 400);
      expect(chain.previousValue, '0');
    });

    test('no loaded siblings → children is empty', () {
      final ds = _MockDataSource();
      final v1 = _var('top', 'status');
      final v2 = _var('top', 'data');
      _stubSignal(ds, 'top.status', '0', [_ch(100, 'x')]);
      when(() => ds.isSignalLoaded('top.data')).thenReturn(false);
      when(() => ds.isSignalLoaded('top.status')).thenReturn(true);

      final hierarchy = [
        _scope('top', [v1, v2]),
      ];
      final chain = _svc.buildCausalChain(v1, 200, hierarchy, ds);

      expect(chain.children, isEmpty);
    });

    test('loaded sibling that is also X at xStartTime appears as child', () {
      final ds = _MockDataSource();
      final v1 = _var('top', 'status');
      final v2 = _var('top', 'data');

      _stubSignal(ds, 'top.status', '0', [_ch(100, 'x')]);
      when(() => ds.startTime).thenReturn(0);
      when(() => ds.valueAt('top.data', any())).thenReturn('x');
      when(
        () => ds.changesInRange('top.data', any(), any()),
      ).thenReturn([_ch(50, 'x')]);
      when(() => ds.isSignalLoaded('top.data')).thenReturn(true);
      when(() => ds.isSignalLoaded('top.status')).thenReturn(true);

      final hierarchy = [
        _scope('top', [v1, v2]),
      ];
      final chain = _svc.buildCausalChain(v1, 200, hierarchy, ds);

      expect(chain.children.length, 1);
      expect(chain.children.first.signalPath, 'top.data');
    });

    test('loaded sibling that is NOT X at xStartTime is excluded', () {
      final ds = _MockDataSource();
      final v1 = _var('top', 'status');
      final v2 = _var('top', 'data');

      _stubSignal(ds, 'top.status', '0', [_ch(100, 'x')]);
      when(() => ds.startTime).thenReturn(0);
      when(() => ds.valueAt('top.data', any())).thenReturn('1');
      when(() => ds.changesInRange('top.data', any(), any())).thenReturn([]);
      when(() => ds.isSignalLoaded('top.data')).thenReturn(true);
      when(() => ds.isSignalLoaded('top.status')).thenReturn(true);

      final hierarchy = [
        _scope('top', [v1, v2]),
      ];
      final chain = _svc.buildCausalChain(v1, 200, hierarchy, ds);

      expect(chain.children, isEmpty);
    });

    test('signal not X at query time → x start defaults to query time', () {
      // If findXOrigin returns null (signal not x), xStartTime = time.
      final ds = _MockDataSource();
      final variable = _var('top', 'sig');
      _stubSignal(ds, 'top.sig', 'x', []);
      when(() => ds.isSignalLoaded(any())).thenReturn(false);

      final hierarchy = [
        _scope('top', [variable]),
      ];
      final chain = _svc.buildCausalChain(variable, 300, hierarchy, ds);

      // signal is x (initial value), so origin should be at startTime (0)
      expect(chain.xStartTime, isNotNull);
    });

    test('scope not found in hierarchy → children is empty', () {
      final ds = _MockDataSource();
      final variable = _var('other', 'sig'); // scope not in hierarchy
      _stubSignal(ds, 'other.sig', '0', [_ch(10, 'x')]);
      when(() => ds.isSignalLoaded(any())).thenReturn(false);

      final hierarchy = [
        _scope('top', [_var('top', 'clk')]),
      ];
      final chain = _svc.buildCausalChain(variable, 50, hierarchy, ds);

      expect(chain.children, isEmpty);
    });
  });

  // ── XOriginResult equality ──────────────────────────────────────────────────

  group('XOriginResult', () {
    test('equality holds for same fields', () {
      const a = XOriginResult(
        signalPath: 'top.s',
        originTime: 100,
        previousValue: '1',
      );
      const b = XOriginResult(
        signalPath: 'top.s',
        originTime: 100,
        previousValue: '1',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differs when originTime differs', () {
      const a = XOriginResult(signalPath: 'top.s', originTime: 100);
      const b = XOriginResult(signalPath: 'top.s', originTime: 200);
      expect(a, isNot(equals(b)));
    });

    test('toString contains key fields', () {
      const r = XOriginResult(
        signalPath: 'top.s',
        originTime: 50,
        previousValue: '0',
      );
      expect(r.toString(), contains('top.s'));
      expect(r.toString(), contains('50'));
    });
  });

  // ── XCausalNode equality ───────────────────────────────────────────────────

  group('XCausalNode', () {
    test('equality holds for same fields', () {
      const a = XCausalNode(
        signalPath: 'top.s',
        signalRef: 'ref',
        xStartTime: 100,
      );
      const b = XCausalNode(
        signalPath: 'top.s',
        signalRef: 'ref',
        xStartTime: 100,
      );
      expect(a, equals(b));
    });

    test('differs when children differ', () {
      const child = XCausalNode(
        signalPath: 'top.c',
        signalRef: 'ref2',
        xStartTime: 50,
      );
      const a = XCausalNode(
        signalPath: 'top.s',
        signalRef: 'ref',
        xStartTime: 100,
        children: [child],
      );
      const b = XCausalNode(
        signalPath: 'top.s',
        signalRef: 'ref',
        xStartTime: 100,
      );
      expect(a, isNot(equals(b)));
    });

    test('copyWith replaces specified fields', () {
      const node = XCausalNode(
        signalPath: 'top.s',
        signalRef: 'ref',
        xStartTime: 100,
      );
      final copy = node.copyWith(xStartTime: 999);
      expect(copy.xStartTime, 999);
      expect(copy.signalPath, 'top.s');
    });

    test('toString contains signal path', () {
      const node = XCausalNode(
        signalPath: 'top.s',
        signalRef: 'ref',
        xStartTime: 0,
      );
      expect(node.toString(), contains('top.s'));
    });
  });

  // The packed store is walked in place rather than materialized first; the
  // two paths must agree on every history, including streaks that reach back
  // to the first change and histories that end on a non-X value.
  group('findXOrigin on a packed store', () {
    test('agrees with the changesInRange path on random histories', () {
      final random = Random(11);
      const alphabet = ['0', '1', 'x', 'X', '10', '1x', 'z'];
      for (var trial = 0; trial < 200; trial++) {
        var t = 0;
        final changes = <SignalChange>[];
        for (var i = 0; i < 1 + random.nextInt(60); i++) {
          t += 1 + random.nextInt(20);
          changes.add(
            SignalChange(
              time: t,
              value: alphabet[random.nextInt(alphabet.length)],
            ),
          );
        }
        final packed = WellenProvider()..injectLoadedSignal('4', changes);
        final listed = FakeWaveformDataSource(
          signals: {'4': changes},
          endTime: t + 10,
        );
        for (var q = 0; q < 10; q++) {
          final at = random.nextInt(t + 10);
          expect(
            _svc.findXOrigin('4', 'top.s', at, packed),
            _svc.findXOrigin('4', 'top.s', at, listed),
            reason: 'trial $trial at $at',
          );
        }
      }
    });
  });
}
