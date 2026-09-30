// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// FSM analysis edge-case robustness sweep (FSM robustness plan — Layer C).
//
// `FsmAnalysisService.buildModel()` is structurally a decoder: it walks a
// signal's value changes over a window via `WaveformDataSource` and emits a
// structured result. The decoders have `_decoder_edge_cases_test.dart`, which
// throws ~20 pathological inputs at every decoder and asserts they don't crash;
// this file is the FSM analog. Each case constructs a synthetic
// `WaveformDataSource` (no wellen FFI), runs `buildModel` / `stateIdAt`, and
// asserts the call returns within the timeout without throwing — plus, where
// the expected shape is deterministic, the specific structural outcome.
//
// Real-world VCDs arrive with all-X registers, dumpoff gaps, simultaneous
// transitions, out-of-order changes, and timestamps that overflow 32-bit
// assumptions; the goal here is to catch the analyzer falling over on those
// shapes before users do.
//
// New edge case → add a `test(...)` with a 5-second `Timeout`.

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/fsm_model.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/services/signal_query/fsm_analysis_service.dart';

const _svc = FsmAnalysisService();
const _timeout = Timeout(Duration(seconds: 5));

/// Minimal concrete [WaveformDataSource] backed by an in-memory change list.
///
/// Only [valueAt] and [changesInRange] are exercised by
/// [FsmAnalysisService] — every other member routes through [noSuchMethod]
/// and would throw if called, which is fine because the analyzer never calls
/// them. [initial] is the value held at (and before) the analysis start; it
/// models the "value at startTime" the real source returns from a preceding
/// transition. [changes] need not be sorted — [valueAt] scans for the
/// greatest-time change ≤ the query time, and [changesInRange] preserves the
/// list order so non-monotonic inputs can be injected verbatim.
class _FakeSource implements WaveformDataSource {
  _FakeSource(this.initial, this.changes);

  final String? initial;
  final List<SignalChange> changes;

  @override
  String? valueAt(String signalRef, int time) {
    var value = initial;
    int? best;
    for (final c in changes) {
      if (c.time <= time && (best == null || c.time >= best)) {
        best = c.time;
        value = c.value;
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

FsmModel _build(
  _FakeSource src, {
  int start = 0,
  int end = 1000,
}) => _svc.buildModel(
  signalRef: 'r',
  signalPath: 'top.fsm',
  source: src,
  startTime: start,
  endTime: end,
);

void main() {
  group('FsmAnalysisService edge-case sweep — must not crash or hang', () {
    test('empty change stream produces an empty model', () {
      final m = _build(_FakeSource(null, const []));
      expect(m.states, isEmpty);
      expect(m.transitions, isEmpty);
      expect(m.totalTransitionCount, 0);
      expect(m.isTrivial, isTrue);
    }, timeout: _timeout);

    test('held-constant 0 → single trivial state, no transitions', () {
      final m = _build(_FakeSource('0', const []));
      expect(m.states.single.id, '0');
      expect(m.states.single.entryCount, 1);
      expect(m.transitions, isEmpty);
      expect(m.isTrivial, isTrue);
    }, timeout: _timeout);

    test('held-constant 1 → single trivial state', () {
      final m = _build(_FakeSource('1', const []));
      expect(m.states.single.id, '1');
      expect(m.isTrivial, isTrue);
    }, timeout: _timeout);

    test('all-X stream → empty model (no reachable states)', () {
      final m = _build(
        _FakeSource('x', const [
          SignalChange(time: 10, value: 'x'),
          SignalChange(time: 20, value: 'xx'),
        ]),
      );
      expect(m.states, isEmpty);
      expect(m.transitions, isEmpty);
    }, timeout: _timeout);

    test('all-Z stream → empty model', () {
      final m = _build(
        _FakeSource('z', const [
          SignalChange(time: 10, value: 'z'),
        ]),
      );
      expect(m.states, isEmpty);
    }, timeout: _timeout);

    test(
      'x/z mid-stream breaks the transition chain (marquee invariant)',
      () {
        // 0 → x → 1 → x → 0 : every defined value is preceded by an x, so NO
        // transition may be recorded even though states 0 and 1 are reached.
        final m = _build(
          _FakeSource('0', const [
            SignalChange(time: 10, value: 'x'),
            SignalChange(time: 20, value: '1'),
            SignalChange(time: 30, value: 'x'),
            SignalChange(time: 40, value: '0'),
          ]),
        );
        expect(m.states.map((s) => s.id).toSet(), {'0', '1'});
        expect(m.stateById('0')!.entryCount, 2); // initial + re-entry at 40
        expect(
          m.transitions,
          isEmpty,
          reason: 'no transition may cross an x/z gap',
        );
        expect(m.totalTransitionCount, 0);
      },
      timeout: _timeout,
    );

    test('self-loop recorded when the same value re-asserts', () {
      final m = _build(
        _FakeSource('1', const [
          SignalChange(time: 10, value: '1'),
          SignalChange(time: 20, value: '1'),
        ]),
      );
      expect(m.transitions.length, 1);
      final t = m.transitions.single;
      expect(t.isSelfLoop, isTrue);
      expect(t.fromId, '1');
      expect(t.toId, '1');
      expect(t.count, 2);
      expect(t.times, [10, 20]);
      expect(m.totalTransitionCount, 2);
    }, timeout: _timeout);

    test('empty-string value → undefined, no state', () {
      final m = _build(
        _FakeSource('', const [
          SignalChange(time: 10, value: ''),
        ]),
      );
      expect(m.states, isEmpty);
    }, timeout: _timeout);

    test('whitespace-only value → undefined, no state', () {
      final m = _build(
        _FakeSource('   ', const [
          SignalChange(time: 10, value: '  '),
        ]),
      );
      expect(m.states, isEmpty);
    }, timeout: _timeout);

    test('invalid value characters are all rejected', () {
      final m = _build(
        _FakeSource(null, const [
          SignalChange(time: 10, value: '@@@@'),
          SignalChange(time: 20, value: '5'), // decimal digit in a bit-string
          SignalChange(time: 30, value: '0x1f'), // hex literal — contains x
          SignalChange(time: 40, value: 'b'), // bare prefix, empty body
        ]),
      );
      expect(m.states, isEmpty);
    }, timeout: _timeout);

    test('real-valued signal is rejected', () {
      final m = _build(
        _FakeSource('3.14', const [
          SignalChange(time: 10, value: '2.71'),
        ]),
      );
      expect(m.states, isEmpty);
    }, timeout: _timeout);

    test('b-prefixed binary value is normalized to its decimal id', () {
      final m = _build(_FakeSource('b1010', const []));
      expect(m.states.single.id, '10');
      expect(m.isTrivial, isTrue);
    }, timeout: _timeout);

    test('simultaneous changes at the same tick do not throw', () {
      // A "race": three changes at t=50. Output may be busy, but it must be
      // deterministic and self-consistent.
      final src = _FakeSource(null, const [
        SignalChange(time: 50, value: '0'),
        SignalChange(time: 50, value: '1'),
        SignalChange(time: 50, value: '0'),
        SignalChange(time: 100, value: '1'),
      ]);
      final m = _build(src, end: 200);
      var sum = 0;
      for (final t in m.transitions) {
        sum += t.count;
      }
      expect(sum, m.totalTransitionCount);
      // Determinism: a second pass yields an identical model.
      expect(_build(_FakeSource(null, src.changes), end: 200), m);
    }, timeout: _timeout);

    test('sub-cycle flicker (toggle every tick) terminates', () {
      final flicker = <SignalChange>[
        for (var i = 1; i <= 500; i++)
          SignalChange(time: i, value: i.isOdd ? '1' : '0'),
      ];
      final m = _build(_FakeSource('0', flicker), end: 501);
      expect(m.states.map((s) => s.id).toSet(), {'0', '1'});
      expect(m.totalTransitionCount, 500);
    }, timeout: _timeout);

    test('change exactly at startTime is not double-counted', () {
      // Two changes land on the start boundary (t=0). The analyzer represents
      // the start value via valueAt() and must skip the coincident changes —
      // no spurious self-transition from the boundary.
      final m = _build(
        _FakeSource(null, const [
          SignalChange(time: 0, value: '0'),
          SignalChange(time: 0, value: '1'),
          SignalChange(time: 10, value: '0'),
        ]),
      );
      expect(m.transitions.length, 1);
      expect(m.transitions.single.fromId, '1'); // last value at t=0 wins
      expect(m.transitions.single.toId, '0');
    }, timeout: _timeout);

    test('huge tick range does not overflow or hang', () {
      final m = _build(
        _FakeSource('0', const [
          SignalChange(time: 1000000000, value: '1'),
          SignalChange(time: 4000000000, value: '0'),
        ]),
        end: 5000000000, // > 2^32
      );
      expect(m.states.map((s) => s.id).toSet(), {'0', '1'});
      final t = m.transitions.firstWhere((t) => t.fromId == '0');
      expect(t.times, contains(1000000000));
    }, timeout: _timeout);

    test('non-monotonic change list does not throw', () {
      // A buggy upstream hands us out-of-order changes. The model may be
      // garbage, but the call must terminate and stay self-consistent.
      final src = _FakeSource(null, const [
        SignalChange(time: 300, value: '1'),
        SignalChange(time: 100, value: '0'),
        SignalChange(time: 200, value: '1'),
        SignalChange(time: 50, value: '0'),
      ]);
      final m = _build(src, end: 400);
      var sum = 0;
      for (final t in m.transitions) {
        sum += t.count;
      }
      expect(sum, m.totalTransitionCount);
      expect(
        _build(_FakeSource(null, src.changes), end: 400),
        m,
      ); // deterministic
    }, timeout: _timeout);

    test('very wide (256-bit) one-hot vector is not truncated', () {
      final wide = '1${'0' * 255}'; // 2^255
      final m = _build(_FakeSource(wide, const []));
      expect(m.states.single.id, BigInt.two.pow(255).toString());
    }, timeout: _timeout);

    test('1024 distinct states are all discovered', () {
      final changes = <SignalChange>[
        for (var i = 0; i < 1024; i++)
          SignalChange(time: i + 1, value: i.toRadixString(2)),
      ];
      final m = _build(_FakeSource(null, changes), end: 2000);
      expect(m.states.length, 1024);
      expect(m.totalTransitionCount, 1023); // each consecutive pair, no x/z
    }, timeout: _timeout);

    test(
      'zero-duration range (start == end) → at most the seeded state',
      () {
        // valueAt(start) still seeds the held value; the empty window carries no
        // changes, so no transitions. (Inverted ranges, start > end, are out of
        // contract — TimeRange asserts end >= start — so the caller, not the
        // analyzer, owns that invariant.)
        final m = _build(
          _FakeSource('0', const [
            SignalChange(time: 10, value: '1'),
          ]),
          end: 0,
        );
        expect(m.states.single.id, '0');
        expect(m.transitions, isEmpty);
        expect(m.totalTransitionCount, 0);
      },
      timeout: _timeout,
    );

    group('stateIdAt', () {
      test('returns the canonical decimal id at a defined time', () {
        final src = _FakeSource(null, const [
          SignalChange(time: 50, value: '011'),
        ]);
        expect(_svc.stateIdAt(signalRef: 'r', source: src, time: 50), '3');
      });

      test('returns null at an x/z time', () {
        final src = _FakeSource(null, const [
          SignalChange(time: 50, value: '0x1'),
        ]);
        expect(_svc.stateIdAt(signalRef: 'r', source: src, time: 50), isNull);
      });

      test('returns null before the first change', () {
        final src = _FakeSource(null, const [
          SignalChange(time: 50, value: '1'),
        ]);
        expect(_svc.stateIdAt(signalRef: 'r', source: src, time: 10), isNull);
      });
    });
  });
}
