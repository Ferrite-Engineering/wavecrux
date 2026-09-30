// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/pattern_expression.dart';
import 'package:wavecrux/domain/models/pattern_match.dart';
import 'package:wavecrux/domain/models/pattern_search_result.dart';
import 'package:wavecrux/domain/models/time_range.dart';

void main() {
  const expr = SignalCondition(
    signalPath: 'top.en',
    operator: ConditionOperator.eq,
    value: '1',
  );
  const range = TimeRange(start: 0, end: 1000);

  const match1 = PatternMatch(
    time: 100,
    endTime: 200,
    signalValues: {'top.en': '1'},
  );
  const match2 = PatternMatch(
    time: 500,
    endTime: 600,
    signalValues: {'top.en': '1'},
  );

  group('PatternSearchResult', () {
    test('stores fields', () {
      const result = PatternSearchResult(
        matches: [match1],
        expression: expr,
        searchRange: range,
      );
      expect(result.matches, [match1]);
      expect(result.expression, expr);
      expect(result.searchRange, range);
    });

    test('hasMatches is false for empty list', () {
      const result = PatternSearchResult(
        matches: [],
        expression: expr,
        searchRange: range,
      );
      expect(result.hasMatches, isFalse);
    });

    test('hasMatches is true when matches is non-empty', () {
      const result = PatternSearchResult(
        matches: [match1],
        expression: expr,
        searchRange: range,
      );
      expect(result.hasMatches, isTrue);
    });

    test('matchCount reflects list length', () {
      const result = PatternSearchResult(
        matches: [match1, match2],
        expression: expr,
        searchRange: range,
      );
      expect(result.matchCount, 2);
    });

    // ── equality ──────────────────────────────────────────────────────────────

    test('equality and hashCode — same fields', () {
      const a = PatternSearchResult(
        matches: [match1],
        expression: expr,
        searchRange: range,
      );
      const b = PatternSearchResult(
        matches: [match1],
        expression: expr,
        searchRange: range,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when matches differ', () {
      const a = PatternSearchResult(
        matches: [match1],
        expression: expr,
        searchRange: range,
      );
      const b = PatternSearchResult(
        matches: [match2],
        expression: expr,
        searchRange: range,
      );
      expect(a, isNot(b));
    });

    test('inequality when expression differs', () {
      const otherExpr = SignalCondition(
        signalPath: 'top.other',
        operator: ConditionOperator.eq,
        value: '1',
      );
      const a = PatternSearchResult(
        matches: [],
        expression: expr,
        searchRange: range,
      );
      const b = PatternSearchResult(
        matches: [],
        expression: otherExpr,
        searchRange: range,
      );
      expect(a, isNot(b));
    });

    test('inequality when searchRange differs', () {
      const a = PatternSearchResult(
        matches: [],
        expression: expr,
        searchRange: TimeRange(start: 0, end: 100),
      );
      const b = PatternSearchResult(
        matches: [],
        expression: expr,
        searchRange: TimeRange(start: 0, end: 200),
      );
      expect(a, isNot(b));
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    test('copyWith changes matches', () {
      const original = PatternSearchResult(
        matches: [match1],
        expression: expr,
        searchRange: range,
      );
      final copy = original.copyWith(matches: [match1, match2]);
      expect(copy.matches, [match1, match2]);
      expect(copy.expression, expr);
      expect(copy.searchRange, range);
    });

    test('copyWith changes expression', () {
      const newExpr = SignalCondition(
        signalPath: 'top.data',
        operator: ConditionOperator.gt,
        value: '5',
      );
      const original = PatternSearchResult(
        matches: [],
        expression: expr,
        searchRange: range,
      );
      final copy = original.copyWith(expression: newExpr);
      expect(copy.expression, newExpr);
    });

    test('copyWith changes searchRange', () {
      const newRange = TimeRange(start: 50, end: 500);
      const original = PatternSearchResult(
        matches: [],
        expression: expr,
        searchRange: range,
      );
      final copy = original.copyWith(searchRange: newRange);
      expect(copy.searchRange, newRange);
    });

    test('copyWith with no args returns equivalent object', () {
      const original = PatternSearchResult(
        matches: [match1],
        expression: expr,
        searchRange: range,
      );
      expect(original.copyWith(), original);
    });

    // ── toString ──────────────────────────────────────────────────────────────

    test('toString contains match count', () {
      const result = PatternSearchResult(
        matches: [match1, match2],
        expression: expr,
        searchRange: range,
      );
      expect(result.toString(), contains('2'));
    });
  });
}
