// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// FSM analysis fuzz / property sweep (FSM robustness plan — Layer D).
//
// Over hundreds of seed-deterministic random value-change streams, the
// analyzer's structural invariants must always hold. This complements the
// example-based `fsm_analysis_service_test.dart` (which checks fixed cases)
// and the `fsm_edge_cases_test.dart` adversarial sweep: here we cross-check the
// full model against an INDEPENDENT oracle that re-derives states and
// transitions from the contract (x/z breaks the chain; a transition is only
// recorded between consecutive defined values), then assert the layout is
// finite and bounded for arbitrary state counts.
//
// The seed is fixed so failures reproduce exactly; the failing iteration index
// is included in every `reason:` so a red run points straight at the stream.
//
// Streams are generated with strictly-increasing change times that all start
// after the analysis start tick, so the start-boundary skip rule (a change
// exactly at startTime) never applies here — that rule is covered
// deterministically in `fsm_edge_cases_test.dart`. This keeps the oracle a
// faithful, simple statement of the contract.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/services/signal_query/fsm_analysis_service.dart';
import 'package:wavecrux/services/signal_query/fsm_layout_service.dart';

const _svc = FsmAnalysisService();
const _layout = FsmLayoutService();

/// Concrete [WaveformDataSource] backed by a sorted change list + a value held
/// at/before the start tick. Only [valueAt] / [changesInRange] are used.
class _FakeSource implements WaveformDataSource {
  _FakeSource(this.initial, this.changes);

  final String? initial;
  final List<SignalChange> changes; // strictly increasing time

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

/// Independent re-implementation of the value→state-id rule, valid for the
/// restricted `{0,1,x,z}` alphabet this fuzzer emits: any x/z taint → null,
/// otherwise the binary string parsed to a decimal id.
String? _oracleNormalize(String? raw) {
  if (raw == null) return null;
  final lower = raw.toLowerCase();
  if (lower.isEmpty) return null;
  if (lower.contains('x') || lower.contains('z')) return null;
  return BigInt.parse(lower, radix: 2).toString();
}

/// What the model should contain, derived independently from the stream.
class _Expected {
  final entryCounts = <String, int>{};
  final firstEntries = <String, int>{};
  // key: "from\x00to" → list of times (in chronological order).
  final transitions = <String, List<int>>{};
  int totalTransitions = 0;
}

_Expected _oracle(String? initial, List<SignalChange> changes, int startTime) {
  final exp = _Expected();
  var prev = _oracleNormalize(initial);
  if (prev != null) {
    exp.entryCounts[prev] = 1;
    exp.firstEntries[prev] = startTime;
  }
  for (final c in changes) {
    final id = _oracleNormalize(c.value);
    if (id == null) {
      prev = null; // x/z breaks the chain
      continue;
    }
    exp.entryCounts[id] = (exp.entryCounts[id] ?? 0) + 1;
    exp.firstEntries.putIfAbsent(id, () => c.time);
    if (prev != null) {
      (exp.transitions['$prev\x00$id'] ??= <int>[]).add(c.time);
      exp.totalTransitions++;
    }
    prev = id;
  }
  return exp;
}

/// A random bit-string of [width] bits where each bit is ~10% likely to be
/// x/z taint, otherwise 0/1 — yielding a realistic mix of defined values and
/// chain-breaking undefined values.
String _randValue(math.Random rng, int width) {
  final sb = StringBuffer();
  for (var i = 0; i < width; i++) {
    if (rng.nextInt(10) == 0) {
      sb.write(rng.nextBool() ? 'x' : 'z');
    } else {
      sb.write(rng.nextBool() ? '1' : '0');
    }
  }
  return sb.toString();
}

void main() {
  group('FsmAnalysisService fuzz — structural invariants hold', () {
    test('500 random streams match an independent oracle', () {
      final rng = math.Random(0xF50FF5E); // fixed seed for reproducibility
      const start = 0;

      for (var iter = 0; iter < 500; iter++) {
        final width = 1 + rng.nextInt(8); // 1..8 bits
        final nChanges = rng.nextInt(60); // 0..59 changes
        final initial = rng.nextInt(5) == 0 ? null : _randValue(rng, width);

        var t = 0;
        final changes = <SignalChange>[];
        for (var i = 0; i < nChanges; i++) {
          t += 1 + rng.nextInt(5); // strictly increasing, all > start
          changes.add(SignalChange(time: t, value: _randValue(rng, width)));
        }
        final end = t + 5;
        final reason = 'iter=$iter (seed 0xF50FF5E)';

        final m = _svc.buildModel(
          signalRef: 'r',
          signalPath: 'top.fsm',
          source: _FakeSource(initial, changes),
          startTime: start,
          endTime: end,
        );
        final exp = _oracle(initial, changes, start);

        // ── totalTransitionCount is the sum of per-transition counts ──────────
        var sum = 0;
        for (final tr in m.transitions) {
          sum += tr.count;
        }
        expect(m.totalTransitionCount, sum, reason: 'sum mismatch: $reason');
        expect(
          m.totalTransitionCount,
          exp.totalTransitions,
          reason: 'total vs oracle: $reason',
        );

        // ── states match the oracle, and are sorted by numeric id ────────────
        expect(
          m.states.map((s) => s.id).toList(),
          _sortedNumeric(exp.entryCounts.keys),
          reason: 'state set / ordering: $reason',
        );
        for (final s in m.states) {
          expect(
            s.entryCount,
            exp.entryCounts[s.id],
            reason: 'entryCount[${s.id}]: $reason',
          );
          expect(
            s.firstEntryTime,
            exp.firstEntries[s.id],
            reason: 'firstEntry[${s.id}]: $reason',
          );
          expect(s.entryCount, greaterThanOrEqualTo(1), reason: reason);
          expect(s.firstEntryTime, isNotNull, reason: reason);
          expect(
            s.firstEntryTime,
            inInclusiveRange(start, end - 1),
            reason: 'firstEntry in range: $reason',
          );
        }

        // ── transitions match the oracle; every endpoint is a real state ─────
        final stateIds = m.states.map((s) => s.id).toSet();
        final seenKeys = <String>{};
        for (final tr in m.transitions) {
          final key = '${tr.fromId}\x00${tr.toId}';
          expect(
            seenKeys.add(key),
            isTrue,
            reason: 'duplicate transition $key: $reason',
          );
          expect(
            stateIds,
            contains(tr.fromId),
            reason: 'from is a state: $reason',
          );
          expect(stateIds, contains(tr.toId), reason: 'to is a state: $reason');
          final expectedTimes = exp.transitions[key];
          expect(
            expectedTimes,
            isNotNull,
            reason: 'unexpected transition $key: $reason',
          );
          expect(tr.count, tr.times.length, reason: 'count==len: $reason');
          expect(
            tr.times,
            _ascending(expectedTimes!),
            reason: 'times[$key]: $reason',
          );
          for (final time in tr.times) {
            expect(
              time,
              inInclusiveRange(start, end - 1),
              reason: 'transition time in range: $reason',
            );
          }
        }
        expect(
          m.transitions.length,
          exp.transitions.length,
          reason: 'transition count: $reason',
        );

        // ── determinism: a second identical run yields an equal model ────────
        final m2 = _svc.buildModel(
          signalRef: 'r',
          signalPath: 'top.fsm',
          source: _FakeSource(initial, changes),
          startTime: start,
          endTime: end,
        );
        expect(m2, m, reason: 'determinism: $reason');

        // ── layout: every state positioned, finite, inside the unit square ───
        final layout = _layout.compute(m);
        expect(
          layout.positions.length,
          m.states.length,
          reason: 'every state positioned: $reason',
        );
        final coords = <String>{};
        for (final pos in layout.positions.values) {
          expect(
            pos.x.isFinite && pos.y.isFinite,
            isTrue,
            reason: 'finite position: $reason',
          );
          expect(pos.x, inInclusiveRange(0.0, 1.0), reason: 'x bound: $reason');
          expect(pos.y, inInclusiveRange(0.0, 1.0), reason: 'y bound: $reason');
          coords.add('${pos.x},${pos.y}');
        }
        // Distinct nodes never share a coordinate (circular layout separation).
        if (m.states.length > 1) {
          expect(
            coords.length,
            m.states.length,
            reason: 'distinct positions: $reason',
          );
        }
      }
    });

    test('zero-duration ranges never throw and stay consistent', () {
      // A zero-width window (start == end) is the boundary case the analyzer
      // must tolerate (the file's [start, end] is always valid; an inverted
      // range is a caller bug TimeRange asserts on). It carries no changes, so
      // it can only seed the held start value: ≤1 state, no transitions.
      final rng = math.Random(0x12345);
      for (var iter = 0; iter < 100; iter++) {
        final width = 1 + rng.nextInt(6);
        final changes = <SignalChange>[
          for (var i = 0; i < rng.nextInt(20); i++)
            SignalChange(time: i * 3, value: _randValue(rng, width)),
        ];
        final point = rng.nextInt(60);
        final m = _svc.buildModel(
          signalRef: 'r',
          signalPath: 'top.fsm',
          source: _FakeSource(null, changes),
          startTime: point,
          endTime: point,
        );
        expect(m.transitions, isEmpty, reason: 'iter=$iter');
        expect(m.totalTransitionCount, 0, reason: 'iter=$iter');
        expect(m.states.length, lessThanOrEqualTo(1), reason: 'iter=$iter');
        final layout = _layout.compute(m);
        for (final pos in layout.positions.values) {
          expect(
            pos.x.isFinite && pos.y.isFinite,
            isTrue,
            reason: 'iter=$iter',
          );
        }
      }
    });
  });
}

/// Sorts decimal-string ids numerically (BigInt), matching the analyzer.
List<String> _sortedNumeric(Iterable<String> ids) {
  final list = ids.toList()
    ..sort((a, b) => BigInt.parse(a).compareTo(BigInt.parse(b)));
  return list;
}

List<int> _ascending(List<int> times) => [...times]..sort();
