// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// FSM analysis perf / stress + layout-stability sweep (FSM robustness plan —
// Layer E).
//
// Backs the verification guide's "50+ states remains usable" claim — which was
// MANUAL (visual judgement) — with automated bounds, and proves the analyzer
// and the circular layout hold up under state explosion, rapid transitions,
// and very large timestamps. Pure-Dart synthetic sources (no FFI).
//
// Perf assertions are deliberately generous (soft canaries, not tight
// budgets): the hard guarantee is "completes within the test Timeout without
// hanging"; the Stopwatch ceilings only catch a catastrophic regression.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/fsm_model.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/services/signal_query/fsm_analysis_service.dart';
import 'package:wavecrux/services/signal_query/fsm_layout_service.dart';

const _svc = FsmAnalysisService();
const _layout = FsmLayoutService();
const _timeout = Timeout(Duration(seconds: 30));

/// Concrete source over a sorted change list (only valueAt/changesInRange used).
class _FakeSource implements WaveformDataSource {
  _FakeSource(this.initial, this.changes);

  final String? initial;
  final List<SignalChange> changes; // ascending time

  @override
  String? valueAt(String signalRef, int time) {
    var value = initial;
    for (final c in changes) {
      if (c.time <= time) {
        value = c.value;
      } else {
        break;
      }
    }
    return value;
  }

  @override
  List<SignalChange> changesInRange(String signalRef, int start, int end) => [
    for (final c in changes)
      if (c.time >= start && c.time < end) c,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('FSM stress — state explosion / rapid transitions / large range', () {
    for (final n in const [256, 1024, 4096]) {
      test('$n distinct states are all discovered, within budget', () {
        final changes = <SignalChange>[
          for (var i = 0; i < n; i++)
            SignalChange(time: i + 1, value: i.toRadixString(2)),
        ];
        final sw = Stopwatch()..start();
        final m = _svc.buildModel(
          signalRef: 'r',
          signalPath: 'top.fsm',
          source: _FakeSource(null, changes),
          startTime: 0,
          endTime: n + 2,
        );
        sw.stop();
        expect(m.states.length, n);
        expect(m.totalTransitionCount, n - 1);
        expect(
          sw.elapsedMilliseconds,
          lessThan(10000),
          reason: 'soft canary — $n states took ${sw.elapsedMilliseconds}ms',
        );
      }, timeout: _timeout);
    }

    test('100k rapid transitions across 2 states', () {
      const k = 100000;
      final changes = <SignalChange>[
        for (var i = 1; i <= k; i++)
          SignalChange(time: i, value: i.isOdd ? '1' : '0'),
      ];
      final sw = Stopwatch()..start();
      final m = _svc.buildModel(
        signalRef: 'r',
        signalPath: 'top.fsm',
        source: _FakeSource('0', changes),
        startTime: 0,
        endTime: k + 1,
      );
      sw.stop();
      expect(m.states.map((s) => s.id).toSet(), {'0', '1'});
      expect(m.totalTransitionCount, k);
      expect(
        sw.elapsedMilliseconds,
        lessThan(10000),
        reason: 'soft canary — ${sw.elapsedMilliseconds}ms',
      );
    }, timeout: _timeout);

    test('very large timestamps (near 2^62) do not overflow', () {
      const a = 1 << 40;
      const b = 1 << 50;
      const c = 1 << 61;
      final m = _svc.buildModel(
        signalRef: 'r',
        signalPath: 'top.fsm',
        source: _FakeSource('0', const [
          SignalChange(time: a, value: '1'),
          SignalChange(time: b, value: '0'),
          SignalChange(time: c, value: '1'),
        ]),
        startTime: 0,
        endTime: 1 << 62,
      );
      expect(m.states.map((s) => s.id).toSet(), {'0', '1'});
      expect(
        m.transitions.firstWhere((t) => t.fromId == '0').times,
        contains(a),
      );
      expect(m.transitions.firstWhere((t) => t.toId == '1').times, contains(c));
    }, timeout: _timeout);
  });

  group('FSM layout stability at large N', () {
    FsmModel build(int n) => _svc.buildModel(
      signalRef: 'r',
      signalPath: 'top.fsm',
      source: _FakeSource(null, [
        for (var i = 0; i < n; i++)
          SignalChange(time: i + 1, value: i.toRadixString(2)),
      ]),
      startTime: 0,
      endTime: n + 2,
    );

    for (final n in const [50, 256, 4096]) {
      test(
        '$n nodes: finite, in unit square, distinct, deterministic',
        () {
          final m = build(n);
          final layout = _layout.compute(m);
          expect(layout.positions.length, n);

          final coords = <String>{};
          for (final pos in layout.positions.values) {
            expect(pos.x.isFinite && pos.y.isFinite, isTrue);
            expect(pos.x, inInclusiveRange(0.0, 1.0));
            expect(pos.y, inInclusiveRange(0.0, 1.0));
            coords.add('${pos.x},${pos.y}');
          }
          expect(
            coords.length,
            n,
            reason: 'every node has a distinct position',
          );

          // Determinism: recomputing yields an identical layout.
          expect(_layout.compute(m), layout);
        },
        timeout: _timeout,
      );
    }

    test('N=50 pins the circle (radius + equal angular spacing)', () {
      const n = 50;
      const radius = 0.45; // FsmLayoutService._radiusFor(n) for n > 16
      final m = build(n);
      final layout = _layout.compute(m);

      for (var i = 0; i < n; i++) {
        final pos = layout[m.states[i].id]!;
        final theta = -math.pi / 2 + (2 * math.pi * i / n);
        final expectedX = 0.5 + radius * math.cos(theta);
        final expectedY = 0.5 + radius * math.sin(theta);
        expect(pos.x, closeTo(expectedX, 1e-9), reason: 'node $i x');
        expect(pos.y, closeTo(expectedY, 1e-9), reason: 'node $i y');
      }
    }, timeout: _timeout);
  });
}
