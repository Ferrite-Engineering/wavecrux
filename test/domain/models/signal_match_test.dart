// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_match.dart';
import 'package:wavecrux/domain/models/time_range.dart';

void main() {
  group('SignalMatch', () {
    test('default values', () {
      const m = SignalMatch(pathA: 'top.clk', pathB: 'top.clk');
      expect(m.isDifferent, isFalse);
      expect(m.divergenceRegions, isEmpty);
      expect(m.firstDivergenceTime, isNull);
    });

    test('firstDivergenceTime is first region start', () {
      const m = SignalMatch(
        pathA: 'a.sig',
        pathB: 'b.sig',
        isDifferent: true,
        divergenceRegions: [
          TimeRange(start: 20, end: 30),
          TimeRange(start: 50, end: 60),
        ],
      );
      expect(m.firstDivergenceTime, 20);
    });

    test('equality', () {
      const a = SignalMatch(
        pathA: 'top.clk',
        pathB: 'top.clk',
        isDifferent: true,
        divergenceRegions: [TimeRange(start: 0, end: 10)],
      );
      const b = SignalMatch(
        pathA: 'top.clk',
        pathB: 'top.clk',
        isDifferent: true,
        divergenceRegions: [TimeRange(start: 0, end: 10)],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('inequality on pathA', () {
      const a = SignalMatch(pathA: 'a.sig', pathB: 'b.sig');
      const b = SignalMatch(pathA: 'c.sig', pathB: 'b.sig');
      expect(a, isNot(b));
    });

    test('inequality on divergenceRegions', () {
      const a = SignalMatch(
        pathA: 'a.sig',
        pathB: 'b.sig',
        divergenceRegions: [TimeRange(start: 0, end: 10)],
      );
      const b = SignalMatch(
        pathA: 'a.sig',
        pathB: 'b.sig',
        divergenceRegions: [TimeRange(start: 0, end: 20)],
      );
      expect(a, isNot(b));
    });

    test('copyWith updates isDifferent and regions', () {
      const original = SignalMatch(pathA: 'a', pathB: 'b');
      final updated = original.copyWith(
        isDifferent: true,
        divergenceRegions: [const TimeRange(start: 5, end: 15)],
      );
      expect(updated.isDifferent, isTrue);
      expect(updated.divergenceRegions.length, 1);
      expect(updated.pathA, 'a');
    });

    test('toString contains pathA', () {
      const m = SignalMatch(pathA: 'top.data', pathB: 'top.data');
      expect(m.toString(), contains('top.data'));
    });

    test('signalRefA defaults to pathA when not provided', () {
      const m = SignalMatch(pathA: 'top.clk', pathB: 'dut.clk');
      expect(m.signalRefA, 'top.clk');
    });

    test('signalRefB defaults to pathB when not provided', () {
      const m = SignalMatch(pathA: 'top.clk', pathB: 'dut.clk');
      expect(m.signalRefB, 'dut.clk');
    });

    test('explicit signalRefA and signalRefB can differ from paths', () {
      const m = SignalMatch(
        pathA: 'top.clk',
        pathB: 'dut.clk',
        signalRefA: 'ref_001',
        signalRefB: 'ref_002',
      );
      expect(m.signalRefA, 'ref_001');
      expect(m.signalRefB, 'ref_002');
      expect(m.pathA, 'top.clk');
      expect(m.pathB, 'dut.clk');
    });

    test('equality considers signalRefA and signalRefB', () {
      const a = SignalMatch(
        pathA: 'top.clk',
        pathB: 'top.clk',
        signalRefA: 'ref_001',
        signalRefB: 'ref_001',
      );
      const b = SignalMatch(
        pathA: 'top.clk',
        pathB: 'top.clk',
        signalRefA: 'ref_999',
        signalRefB: 'ref_001',
      );
      expect(a, isNot(b));
    });

    test('copyWith updates signalRefA independently of pathA', () {
      const original = SignalMatch(
        pathA: 'a',
        pathB: 'b',
        signalRefA: 'old_A',
        signalRefB: 'old_B',
      );
      final updated = original.copyWith(signalRefA: 'new_A');
      expect(updated.signalRefA, 'new_A');
      expect(updated.signalRefB, 'old_B');
      expect(updated.pathA, 'a');
    });

    test('toString contains signalRefA when it differs from pathA', () {
      const m = SignalMatch(
        pathA: 'top.data',
        pathB: 'top.data',
        signalRefA: 'id_42',
      );
      expect(m.toString(), contains('id_42'));
    });
  });
}
