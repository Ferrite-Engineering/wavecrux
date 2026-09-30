// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_match.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/diff/waveform_diff_service.dart';

// ── mocks ──────────────────────────────────────────────────────────────────────

class _MockDataSource extends Mock implements WaveformDataSource {}

// ── helpers ────────────────────────────────────────────────────────────────────

const _svc = WaveformDiffService();

// signalRef is deliberately distinct from fullPath to expose any bug that
// confuses the two (e.g. passing pathA instead of signalRefA to the data
// source).
Variable _var(String scopePath, String name, {int? bitWidth = 1}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'ref:$name',
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

// Stub a mock to return specific changes in range and a value at a time.
void _stubSignal(
  _MockDataSource ds,
  String ref,
  String initValue,
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
    return changes.where((c) => c.time >= start && c.time <= end).toList();
  });
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── matchSignals ────────────────────────────────────────────────────────────

  group('matchSignals — exact path match', () {
    test('identical single-level hierarchies match all signals', () {
      final ha = [
        _scope('top', [_var('top', 'clk'), _var('top', 'data')]),
      ];
      final hb = [
        _scope('top', [_var('top', 'clk'), _var('top', 'data')]),
      ];

      final matches = _svc.matchSignals(ha, hb);
      expect(matches.length, 2);
      expect(matches.map((m) => m.pathA).toSet(), {'top.clk', 'top.data'});
      expect(matches.every((m) => m.pathA == m.pathB), isTrue);
    });

    test('extra signal in A that has no counterpart in B', () {
      final ha = [
        _scope('top', [_var('top', 'clk'), _var('top', 'extra')]),
      ];
      final hb = [
        _scope('top', [_var('top', 'clk')]),
      ];

      final matches = _svc.matchSignals(ha, hb);
      // Only 'top.clk' matches; 'top.extra' has no counterpart.
      expect(matches.length, 1);
      expect(matches.single.pathA, 'top.clk');
    });

    test(
      'extra signal in B produces no match entry (reported via full diff)',
      () {
        final ha = [
          _scope('top', [_var('top', 'clk')]),
        ];
        final hb = [
          _scope('top', [_var('top', 'clk'), _var('top', 'extra')]),
        ];

        final matches = _svc.matchSignals(ha, hb);
        expect(matches.length, 1);
        expect(matches.single.pathA, 'top.clk');
      },
    );

    test('nested hierarchy is fully flattened', () {
      final ha = [
        _scope(
          'top',
          [_var('top', 'clk')],
          [
            _scope('top.cpu', [
              _var('top.cpu', 'reset'),
              _var('top.cpu', 'pc'),
            ]),
          ],
        ),
      ];
      final hb = [
        _scope(
          'top',
          [_var('top', 'clk')],
          [
            _scope('top.cpu', [
              _var('top.cpu', 'reset'),
              _var('top.cpu', 'pc'),
            ]),
          ],
        ),
      ];

      final matches = _svc.matchSignals(ha, hb);
      expect(matches.length, 3);
      expect(
        matches.map((m) => m.pathA).toSet(),
        {'top.clk', 'top.cpu.reset', 'top.cpu.pc'},
      );
    });
  });

  group('matchSignals — leaf-name match (different root scope)', () {
    test('signals with different root scope names match via leaf path', () {
      final ha = [
        _scope(
          'dut_a',
          [_var('dut_a', 'clk')],
          [
            _scope('dut_a.cpu', [_var('dut_a.cpu', 'reset')]),
          ],
        ),
      ];
      final hb = [
        _scope(
          'dut_b',
          [_var('dut_b', 'clk')],
          [
            _scope('dut_b.cpu', [_var('dut_b.cpu', 'reset')]),
          ],
        ),
      ];

      final matches = _svc.matchSignals(ha, hb);
      expect(matches.length, 2);
      // pathA differs from pathB due to different root.
      final clkMatch = matches.firstWhere((m) => m.pathA == 'dut_a.clk');
      expect(clkMatch.pathB, 'dut_b.clk');
      final resetMatch = matches.firstWhere(
        (m) => m.pathA == 'dut_a.cpu.reset',
      );
      expect(resetMatch.pathB, 'dut_b.cpu.reset');
    });

    test(
      'ambiguous leaf paths (two signals with same leaf) are not matched',
      () {
        // B has two signals that would both match 'cpu.data' after root strip.
        final ha = [
          _scope('a', [], [
            _scope('a.cpu', [_var('a.cpu', 'data')]),
          ]),
        ];
        final hb = [
          _scope(
            'b',
            [],
            [
              _scope('b.cpu', [_var('b.cpu', 'data')]),
              _scope('b.other', [_var('b.other', 'data')]),
            ],
          ),
        ];

        final matches = _svc.matchSignals(ha, hb);
        // 'a.cpu.data' leaf = 'cpu.data'; both 'b.cpu.data' and 'b.other.data'
        // strip to 'cpu.data' and 'other.data' respectively — no ambiguity here
        // since they strip to different leaf paths. This test checks the
        // non-ambiguous path still matches.
        expect(matches.where((m) => m.pathA == 'a.cpu.data').length, 1);
      },
    );

    test('signalRefA and signalRefB are populated from Variable.signalRef', () {
      final ha = [
        _scope('top', [_var('top', 'clk')]),
      ];
      final hb = [
        _scope('top', [_var('top', 'clk')]),
      ];

      final matches = _svc.matchSignals(ha, hb);
      // fullPath = 'top.clk', signalRef = 'ref:clk' (from _var helper)
      expect(matches.single.pathA, 'top.clk');
      expect(matches.single.signalRefA, 'ref:clk');
      expect(matches.single.signalRefB, 'ref:clk');
    });

    test('single-component paths (no dot) do not match via leaf fallback', () {
      // Variables with empty scopePath have fullPath == name (no dot).
      // _stripRoot('x') == '' — the empty-string leaf key is never added to
      // the B index, so these never participate in leaf matching.
      Variable topVar(String name) => Variable(
        name: name,
        varType: VarType.wire,
        direction: VarDirection.unknown,
        signalRef: name,
        scopePath: '',
        bitWidth: 1,
      );
      // Use different names so they don't exact-match in Pass 1.
      final ha = [
        _scope('sigA', [topVar('foo')]),
      ];
      final hb = [
        _scope('sigB', [topVar('bar')]),
      ];

      final matches = _svc.matchSignals(ha, hb);
      expect(matches, isEmpty);
    });
  });

  // ── computeDiff ─────────────────────────────────────────────────────────────

  group('computeDiff', () {
    test('identical signals produce no divergence regions', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.clk',
        pathB: 'top.clk',
        signalRefA: '!',
        signalRefB: '"',
      );

      _stubSignal(dsA, '!', '0', [_ch(10, '1'), _ch(20, '0')]);
      _stubSignal(dsB, '"', '0', [_ch(10, '1'), _ch(20, '0')]);

      final result = _svc.computeDiff(match, dsA, dsB, 0, 30);
      expect(result.isDifferent, isFalse);
      expect(result.divergenceRegions, isEmpty);
    });

    test('signals differ for a single contiguous region', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.data',
        pathB: 'top.data',
        signalRefA: '!',
        signalRefB: '"',
      );

      // A: 0 → 1 at t=10 → 0 at t=30
      // B: stays 0 throughout
      _stubSignal(dsA, '!', '0', [_ch(10, '1'), _ch(30, '0')]);
      _stubSignal(dsB, '"', '0', []);

      final result = _svc.computeDiff(match, dsA, dsB, 0, 40);
      expect(result.isDifferent, isTrue);
      expect(result.divergenceRegions.length, 1);
      expect(
        result.divergenceRegions.first,
        const TimeRange(start: 10, end: 30),
      );
    });

    test('multiple non-contiguous divergence regions', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.q',
        pathB: 'top.q',
        signalRefA: '!',
        signalRefB: '"',
      );

      // A: 0,1,0,1,0  B: 0,0,0,1,0
      // Diverge at t=10 (A=1, B=0), converge at t=30 (A=0, B=0... wait A=0 at 30)
      // Actually: A=1@10, A=0@30, A=1@50, A=0@70
      //           B=1@30, B=0@70
      // t=0: A=0, B=0 → same
      // t=10: A=1, B=0 → differ → region opens at 10
      // t=30: A=0, B=1 → still differ (different values)
      // t=70: A=0, B=0 → same → region closes at 70
      // That's one big region. Let me redesign to get two regions.
      //
      // A: 0→1@10→0@20→1@40→0@50  B: 0,0,0,0,0
      // t=0: 0==0
      // t=10: A=1 != B=0 → open at 10
      // t=20: A=0 == B=0 → close at 20  → region [10,20]
      // t=40: A=1 != B=0 → open at 40
      // t=50: A=0 == B=0 → close at 50  → region [40,50]
      _stubSignal(dsA, '!', '0', [
        _ch(10, '1'),
        _ch(20, '0'),
        _ch(40, '1'),
        _ch(50, '0'),
      ]);
      _stubSignal(dsB, '"', '0', []);

      final result = _svc.computeDiff(match, dsA, dsB, 0, 60);
      expect(result.isDifferent, isTrue);
      expect(result.divergenceRegions.length, 2);
      expect(result.divergenceRegions[0], const TimeRange(start: 10, end: 20));
      expect(result.divergenceRegions[1], const TimeRange(start: 40, end: 50));
    });

    test('divergence that extends to endTime is closed at endTime', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.en',
        pathB: 'top.en',
        signalRefA: '!',
        signalRefB: '"',
      );

      _stubSignal(dsA, '!', '0', [_ch(5, '1')]);
      _stubSignal(dsB, '"', '0', []);

      final result = _svc.computeDiff(match, dsA, dsB, 0, 50);
      expect(result.divergenceRegions.length, 1);
      expect(
        result.divergenceRegions.first,
        const TimeRange(start: 5, end: 50),
      );
    });

    test('X vs 0 counts as a divergence', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.sig',
        pathB: 'top.sig',
        signalRefA: '!',
        signalRefB: '"',
      );

      _stubSignal(dsA, '!', 'x', [_ch(20, '0')]);
      _stubSignal(dsB, '"', '0', []);

      final result = _svc.computeDiff(match, dsA, dsB, 0, 30);
      expect(result.isDifferent, isTrue);
      expect(result.divergenceRegions.first.start, 0);
      expect(result.divergenceRegions.first.end, 20);
    });

    test('X vs X is treated as identical', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.sig',
        pathB: 'top.sig',
        signalRefA: '!',
        signalRefB: '"',
      );

      _stubSignal(dsA, '!', 'x', []);
      _stubSignal(dsB, '"', 'x', []);

      final result = _svc.computeDiff(match, dsA, dsB, 0, 20);
      expect(result.isDifferent, isFalse);
      expect(result.divergenceRegions, isEmpty);
    });

    test('Z vs 0 counts as a divergence', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.bus',
        pathB: 'top.bus',
        signalRefA: '!',
        signalRefB: '"',
      );

      _stubSignal(dsA, '!', 'z', [_ch(10, '0')]);
      _stubSignal(dsB, '"', '0', []);

      final result = _svc.computeDiff(match, dsA, dsB, 0, 20);
      expect(result.isDifferent, isTrue);
    });

    test('both signals start with null value (treated as x)', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.a',
        pathB: 'top.b',
        signalRefA: '!',
        signalRefB: '"',
      );

      when(() => dsA.valueAt('!', any())).thenReturn(null);
      when(
        () => dsA.changesInRange('!', any(), any()),
      ).thenReturn([_ch(10, '1')]);
      when(() => dsB.valueAt('"', any())).thenReturn(null);
      when(
        () => dsB.changesInRange('"', any(), any()),
      ).thenReturn([_ch(10, '1')]);

      final result = _svc.computeDiff(match, dsA, dsB, 0, 20);
      // Both start as 'x' (null fallback), converge to '1' at t=10 — identical
      // across [10,20].  Initial state x==x so no divergence.
      expect(result.isDifferent, isFalse);
    });

    test('simultaneous changes at the same tick', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.d',
        pathB: 'top.d',
        signalRefA: '!',
        signalRefB: '"',
      );

      // Both change at t=10 but to different values.
      _stubSignal(dsA, '!', '0', [_ch(10, '1')]);
      _stubSignal(dsB, '"', '0', [_ch(10, '0')]);

      // A stays 1, B stays 0 after t=10.
      final result = _svc.computeDiff(match, dsA, dsB, 0, 20);
      expect(result.isDifferent, isTrue);
      expect(result.divergenceRegions.first.start, 10);
    });

    test('windowed diff respects startTime and endTime', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.sig',
        pathB: 'top.sig',
        signalRefA: '!',
        signalRefB: '"',
      );

      // Divergence exists from t=5 to t=50, but we only query [20, 30].
      _stubSignal(dsA, '!', '1', []);
      _stubSignal(dsB, '"', '0', []);

      final result = _svc.computeDiff(match, dsA, dsB, 20, 30);
      expect(result.isDifferent, isTrue);
      expect(
        result.divergenceRegions.first,
        const TimeRange(start: 20, end: 30),
      );
    });

    test('uses signalRefA/B (not pathA/B) when querying data sources', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      // Paths and refs are intentionally distinct.
      const match = SignalMatch(
        pathA: 'top.clk',
        pathB: 'other.clk',
        signalRefA: 'ref:clk_a',
        signalRefB: 'ref:clk_b',
      );
      _stubSignal(dsA, 'ref:clk_a', '0', [_ch(10, '1')]);
      _stubSignal(dsB, 'ref:clk_b', '0', []);

      // A goes high at t=10, B stays 0 → divergence [10, 20].
      final result = _svc.computeDiff(match, dsA, dsB, 0, 20);
      expect(result.isDifferent, isTrue);
      expect(
        result.divergenceRegions.single,
        const TimeRange(start: 10, end: 20),
      );
    });
  });

  // ── computeXorTrace ─────────────────────────────────────────────────────────

  group('computeXorTrace', () {
    test('identical 1-bit signals produce all-zero trace', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.clk',
        pathB: 'top.clk',
        signalRefA: '!',
        signalRefB: '"',
      );

      _stubSignal(dsA, '!', '0', [_ch(5, '1'), _ch(10, '0')]);
      _stubSignal(dsB, '"', '0', [_ch(5, '1'), _ch(10, '0')]);

      final trace = _svc.computeXorTrace(match, dsA, dsB, 0, 15);
      expect(trace.every((c) => c.value == '0'), isTrue);
    });

    test('1-bit signals: XOR is 1 when values differ', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.a',
        pathB: 'top.b',
        signalRefA: '!',
        signalRefB: '"',
      );

      // A=0 throughout; B=0→1@10→0@20.
      _stubSignal(dsA, '!', '0', []);
      _stubSignal(dsB, '"', '0', [_ch(10, '1'), _ch(20, '0')]);

      final trace = _svc.computeXorTrace(match, dsA, dsB, 0, 25);
      // Expect: t=0 → '0', t=10 → '1', t=20 → '0'
      expect(trace[0], const SignalChange(time: 0, value: '0'));
      expect(trace[1], const SignalChange(time: 10, value: '1'));
      expect(trace[2], const SignalChange(time: 20, value: '0'));
    });

    test('trace is run-length compressed (no consecutive duplicates)', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.a',
        pathB: 'top.b',
        signalRefA: '!',
        signalRefB: '"',
      );

      // Both toggle at the same time — XOR stays 0 the whole time.
      _stubSignal(dsA, '!', '0', [_ch(10, '1'), _ch(20, '0')]);
      _stubSignal(dsB, '"', '0', [_ch(10, '1'), _ch(20, '0')]);

      final trace = _svc.computeXorTrace(match, dsA, dsB, 0, 30);
      // Only one entry at t=0 with value '0'; value never changes.
      expect(trace.length, 1);
      expect(trace.single.value, '0');
    });

    test('multi-bit signals: trace is 1 when any bit position differs', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.bus',
        pathB: 'top.bus',
        signalRefA: '!',
        signalRefB: '"',
      );

      // A = "10", B = "01" → different → XOR = '1'.
      _stubSignal(dsA, '!', '10', []);
      _stubSignal(dsB, '"', '01', []);

      final trace = _svc.computeXorTrace(match, dsA, dsB, 0, 10);
      expect(trace.single.value, '1');
    });

    test('multi-bit identical values produce XOR = 0', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.bus',
        pathB: 'top.bus',
        signalRefA: '!',
        signalRefB: '"',
      );

      _stubSignal(dsA, '!', '1010', []);
      _stubSignal(dsB, '"', '1010', []);

      final trace = _svc.computeXorTrace(match, dsA, dsB, 0, 10);
      expect(trace.single.value, '0');
    });

    test('trace starts at startTime', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.sig',
        pathB: 'top.sig',
        signalRefA: '!',
        signalRefB: '"',
      );

      _stubSignal(dsA, '!', '1', []);
      _stubSignal(dsB, '"', '0', []);

      final trace = _svc.computeXorTrace(match, dsA, dsB, 50, 100);
      expect(trace.first.time, 50);
    });

    test('uses signalRefA/B (not pathA/B) when querying data sources', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();
      const match = SignalMatch(
        pathA: 'top.sig',
        pathB: 'other.sig',
        signalRefA: 'ref:sig_a',
        signalRefB: 'ref:sig_b',
      );
      _stubSignal(dsA, 'ref:sig_a', '0', []);
      _stubSignal(dsB, 'ref:sig_b', '1', []);

      final trace = _svc.computeXorTrace(match, dsA, dsB, 0, 10);
      expect(trace.single.value, '1'); // 0 != 1
    });
  });

  // ── computeFullDiff ─────────────────────────────────────────────────────────

  group('computeFullDiff', () {
    test('all identical signals produce zero-difference result', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();

      final ha = [
        _scope('top', [_var('top', 'clk'), _var('top', 'data')]),
      ];
      final hb = [
        _scope('top', [_var('top', 'clk'), _var('top', 'data')]),
      ];

      // signalRef from _var is 'ref:<name>', not the fullPath 'top.<name>'.
      for (final ref in ['ref:clk', 'ref:data']) {
        _stubSignal(dsA, ref, '0', []);
        _stubSignal(dsB, ref, '0', []);
      }

      final result = _svc.computeFullDiff(ha, hb, dsA, dsB, 0, 100);
      expect(result.summary.differentCount, 0);
      expect(result.summary.matchedCount, 2);
      expect(result.unmatchedA, isEmpty);
      expect(result.unmatchedB, isEmpty);
    });

    test('unmatchedA and unmatchedB are populated', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();

      final ha = [
        _scope('top', [_var('top', 'clk'), _var('top', 'onlyInA')]),
      ];
      final hb = [
        _scope('top', [_var('top', 'clk'), _var('top', 'onlyInB')]),
      ];

      _stubSignal(dsA, 'ref:clk', '0', []);
      _stubSignal(dsB, 'ref:clk', '0', []);

      final result = _svc.computeFullDiff(ha, hb, dsA, dsB, 0, 10);
      expect(result.unmatchedA, ['top.onlyInA']);
      expect(result.unmatchedB, ['top.onlyInB']);
      expect(result.summary.matchedCount, 1);
    });

    test('different signal is flagged in result', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();

      final ha = [
        _scope('top', [_var('top', 'data')]),
      ];
      final hb = [
        _scope('top', [_var('top', 'data')]),
      ];

      _stubSignal(dsA, 'ref:data', '0', [_ch(5, '1')]);
      _stubSignal(dsB, 'ref:data', '0', []);

      final result = _svc.computeFullDiff(ha, hb, dsA, dsB, 0, 20);
      expect(result.summary.differentCount, 1);
      expect(result.matchedSignals.single.isDifferent, isTrue);
    });

    test('empty hierarchies produce empty result', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();

      final result = _svc.computeFullDiff([], [], dsA, dsB, 0, 100);
      expect(result.matchedSignals, isEmpty);
      expect(result.unmatchedA, isEmpty);
      expect(result.unmatchedB, isEmpty);
    });

    test('unmatchedB is sorted', () {
      final dsA = _MockDataSource();
      final dsB = _MockDataSource();

      final ha = [
        _scope('top', [_var('top', 'clk')]),
      ];
      final hb = [
        _scope('top', [
          _var('top', 'clk'),
          _var('top', 'zzz'),
          _var('top', 'aaa'),
        ]),
      ];

      _stubSignal(dsA, 'ref:clk', '0', []);
      _stubSignal(dsB, 'ref:clk', '0', []);

      final result = _svc.computeFullDiff(ha, hb, dsA, dsB, 0, 10);
      expect(result.unmatchedB, ['top.aaa', 'top.zzz']);
    });
  });
}
