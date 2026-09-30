// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/diff_result.dart';
import 'package:wavecrux/domain/models/signal_match.dart';
import 'package:wavecrux/domain/models/time_range.dart';

void main() {
  group('DiffSummary', () {
    test('identicalCount = matched - different', () {
      const s = DiffSummary(
        matchedCount: 5,
        differentCount: 2,
        aOnlyCount: 1,
        bOnlyCount: 3,
      );
      expect(s.identicalCount, 3);
    });

    test('equality', () {
      const a = DiffSummary(
        matchedCount: 3,
        differentCount: 1,
        aOnlyCount: 0,
        bOnlyCount: 0,
      );
      const b = DiffSummary(
        matchedCount: 3,
        differentCount: 1,
        aOnlyCount: 0,
        bOnlyCount: 0,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('toString includes counts', () {
      const s = DiffSummary(
        matchedCount: 4,
        differentCount: 2,
        aOnlyCount: 1,
        bOnlyCount: 1,
      );
      final str = s.toString();
      expect(str, contains('4'));
      expect(str, contains('2'));
    });
  });

  group('DiffResult', () {
    const identicalMatch = SignalMatch(pathA: 'top.clk', pathB: 'top.clk');
    const differentMatch = SignalMatch(
      pathA: 'top.data',
      pathB: 'top.data',
      isDifferent: true,
      divergenceRegions: [TimeRange(start: 10, end: 20)],
    );

    test('summary counts', () {
      const result = DiffResult(
        matchedSignals: [identicalMatch, differentMatch],
        unmatchedA: ['top.spi_mosi'],
        unmatchedB: ['top.uart_tx', 'top.uart_rx'],
      );
      final s = result.summary;
      expect(s.matchedCount, 2);
      expect(s.differentCount, 1);
      expect(s.identicalCount, 1);
      expect(s.aOnlyCount, 1);
      expect(s.bOnlyCount, 2);
    });

    test('empty diff result has zero counts', () {
      const r = DiffResult(
        matchedSignals: [],
        unmatchedA: [],
        unmatchedB: [],
      );
      expect(r.summary.matchedCount, 0);
      expect(r.summary.differentCount, 0);
    });

    test('equality', () {
      const a = DiffResult(
        matchedSignals: [identicalMatch],
        unmatchedA: ['top.extra'],
        unmatchedB: [],
      );
      const b = DiffResult(
        matchedSignals: [identicalMatch],
        unmatchedA: ['top.extra'],
        unmatchedB: [],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith replaces fields', () {
      const r = DiffResult(
        matchedSignals: [identicalMatch],
        unmatchedA: [],
        unmatchedB: [],
      );
      final updated = r.copyWith(unmatchedA: ['top.extra']);
      expect(updated.unmatchedA, ['top.extra']);
      expect(updated.matchedSignals, const [identicalMatch]);
    });

    test('toString contains list lengths', () {
      const r = DiffResult(
        matchedSignals: [identicalMatch, differentMatch],
        unmatchedA: ['a'],
        unmatchedB: [],
      );
      expect(r.toString(), contains('2')); // matchedSignals.length
    });
  });
}
