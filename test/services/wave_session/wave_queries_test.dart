// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The shared waveform queries, on `WellenProvider`'s own query code with the
// changes injected (no native library). Expected edges and windows are
// worked by hand from the injected changes.

@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/search_mode.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/wave_session/wave_queries.dart';
import 'package:wavecrux/services/waveform/wellen_provider_io.dart';

const Variable _clk = Variable(
  name: 'clk',
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: '0',
  scopePath: 'top',
  bitWidth: 1,
);

const Variable _bus = Variable(
  name: 'bus',
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: '1',
  scopePath: 'top',
  bitWidth: 4,
);

// A row whose name is another row's signal reference, as an alias can be.
const Variable _named1 = Variable(
  name: '1',
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: '2',
  scopePath: '',
  bitWidth: 1,
);

WellenProvider _source() {
  final source = WellenProvider()
    ..injectHierarchy(const <Scope>[
      Scope(
        name: 'top',
        type: ScopeType.module,
        path: 'top',
        variables: <Variable>[_clk, _bus],
      ),
    ])
    ..injectLoadedSignal('0', const <SignalChange>[
      SignalChange(time: 0, value: '0'),
      SignalChange(time: 5, value: '1'),
      SignalChange(time: 10, value: '0'),
      SignalChange(time: 15, value: 'x'),
      SignalChange(time: 20, value: '1'),
      SignalChange(time: 30, value: 'z'),
      SignalChange(time: 35, value: '1'),
    ])
    ..injectLoadedSignal('1', const <SignalChange>[
      SignalChange(time: 0, value: 'xxxx'),
      SignalChange(time: 10, value: '0001'),
      SignalChange(time: 20, value: '0010'),
      SignalChange(time: 30, value: '0011'),
    ]);
  return source;
}

void main() {
  group('risingEdges', () {
    test('a change to 1 from 0, x or z is an edge', () {
      expect(risingEdges(_source(), _clk, from: 0, to: 40), <int>[5, 20, 35]);
    });

    test('the value before the window decides the first change', () {
      // At 5 the clock was already 1, so the next edge is at 20.
      expect(risingEdges(_source(), _clk, from: 6, to: 40), <int>[20, 35]);
      // Before 5 it was 0: the change at 5 is an edge.
      expect(risingEdges(_source(), _clk, from: 5, to: 6), <int>[5]);
    });

    test('the window is half-open', () {
      expect(risingEdges(_source(), _clk, from: 0, to: 35), <int>[5, 20]);
      expect(risingEdges(_source(), _clk, from: 0, to: 5), isEmpty);
    });

    test('the first value ever recorded is not an edge', () {
      final source = WellenProvider()
        ..injectLoadedSignal('0', const <SignalChange>[
          SignalChange(time: 0, value: '1'),
          SignalChange(time: 3, value: '0'),
          SignalChange(time: 4, value: '1'),
        ]);
      expect(risingEdges(source, _clk, from: 0, to: 10), <int>[4]);
    });
  });

  group('transitionsInWindow', () {
    test('the value at the start and every change in [start, end)', () async {
      final answer = await transitionsInWindow(
        _source(),
        _bus,
        start: 5,
        end: 30,
        limit: 10,
      );
      expect(answer.valueAtStart, 'xxxx');
      expect(answer.changes.map((c) => c.time), <int>[10, 20]);
      expect(answer.truncated, isFalse);
      expect(answer.toJson(), <String, Object?>{
        'signal': 'top.bus',
        'signalRef': '1',
        'bitWidth': 4,
        'window': <String, Object?>{'start': 5, 'end': 30},
        'valueAtStart': 'xxxx',
        'transitionCount': 2,
        'returned': 2,
        'truncated': false,
        'transitions': <Map<String, Object?>>[
          <String, Object?>{'time': 10, 'value': '0001'},
          <String, Object?>{'time': 20, 'value': '0010'},
        ],
      });
    });

    test('a limit returns the first changes and says it truncated', () async {
      final answer = await transitionsInWindow(
        _source(),
        _clk,
        start: 0,
        end: 40,
        limit: 3,
      );
      expect(answer.returned.map((c) => c.time), <int>[0, 5, 10]);
      expect(answer.changes, hasLength(7));
      expect(answer.truncated, isTrue);
    });

    test('next_from is the tick after the last change returned', () async {
      final answer = await transitionsInWindow(
        _source(),
        _clk,
        start: 0,
        end: 40,
        limit: 3,
      );
      expect(answer.nextFrom, 11);
      expect(answer.splitsLastTick, isFalse);
      expect(answer.toPagedJson()['next_from'], 11);
      final whole = await transitionsInWindow(
        _source(),
        _clk,
        start: 0,
        end: 40,
        limit: 7,
      );
      expect(whole.nextFrom, isNull);
      expect(whole.toPagedJson(), <String, Object?>{
        ...whole.toJson(),
        'next_from': null,
      });
    });

    test('with nothing returned, next_from is the start', () async {
      final answer = await transitionsInWindow(
        _source(),
        _clk,
        start: 6,
        end: 40,
        limit: 0,
      );
      expect(answer.truncated, isTrue);
      expect(answer.nextFrom, 6);
      expect(answer.splitsLastTick, isFalse);
    });

    test('a start after the end is refused', () {
      expect(
        () => transitionsInWindow(_source(), _clk, start: 9, end: 3, limit: 1),
        throwsArgumentError,
      );
    });
  });

  group('signal search', () {
    test('every match counted, the first limit returned', () {
      final answer = SignalSearchAnswer.search(
        rootScopes: _source().rootScopes,
        query: '*',
        mode: SearchMode.glob,
        limit: 1,
      );
      final json = answer.toJson();
      expect(json['matchCount'], 2);
      expect(json['returned'], 1);
      expect(json['truncated'], isTrue);
    });
  });

  group('WaveSignalIndex', () {
    test('resolves a path or a signal reference, the path first', () {
      final index = WaveSignalIndex(const <Scope>[
        Scope(
          name: 'top',
          type: ScopeType.module,
          path: 'top',
          variables: <Variable>[_clk, _bus],
        ),
        Scope(
          name: '',
          type: ScopeType.module,
          path: '',
          variables: <Variable>[_named1],
        ),
      ]);
      expect(index.resolve('top.clk'), _clk);
      expect(index.resolve('0'), _clk);
      // `1` is both the bus's reference and a row's full path: the row wins.
      expect(index.resolve('1'), _named1);
      expect(index.resolve('top.nope'), isNull);
    });
  });
}
