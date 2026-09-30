// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/pattern_match.dart';

void main() {
  group('PatternMatch', () {
    const values = {'top.a': '1', 'top.b': '0'};
    const match = PatternMatch(time: 100, endTime: 200, signalValues: values);

    test('stores fields', () {
      expect(match.time, 100);
      expect(match.endTime, 200);
      expect(match.signalValues, values);
    });

    test('duration equals endTime minus time', () {
      expect(match.duration, 100);
    });

    test('zero-duration match has duration 0', () {
      const m = PatternMatch(time: 50, endTime: 50, signalValues: {});
      expect(m.duration, 0);
    });

    // ── equality ──────────────────────────────────────────────────────────────

    test('equality and hashCode — same fields', () {
      const same = PatternMatch(
        time: 100,
        endTime: 200,
        signalValues: {'top.a': '1', 'top.b': '0'},
      );
      expect(match, same);
      expect(match.hashCode, same.hashCode);
    });

    test('inequality when time differs', () {
      const other = PatternMatch(
        time: 99,
        endTime: 200,
        signalValues: values,
      );
      expect(match, isNot(other));
    });

    test('inequality when endTime differs', () {
      const other = PatternMatch(
        time: 100,
        endTime: 201,
        signalValues: values,
      );
      expect(match, isNot(other));
    });

    test('inequality when signalValues differ', () {
      const other = PatternMatch(
        time: 100,
        endTime: 200,
        signalValues: {'top.a': '0', 'top.b': '0'},
      );
      expect(match, isNot(other));
    });

    test('inequality when signalValues have extra entry', () {
      const other = PatternMatch(
        time: 100,
        endTime: 200,
        signalValues: {'top.a': '1', 'top.b': '0', 'top.c': '1'},
      );
      expect(match, isNot(other));
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    test('copyWith changes time', () {
      final copy = match.copyWith(time: 50);
      expect(copy.time, 50);
      expect(copy.endTime, match.endTime);
      expect(copy.signalValues, match.signalValues);
    });

    test('copyWith changes endTime', () {
      final copy = match.copyWith(endTime: 300);
      expect(copy.time, match.time);
      expect(copy.endTime, 300);
    });

    test('copyWith changes signalValues', () {
      final copy = match.copyWith(signalValues: {'top.a': 'x'});
      expect(copy.signalValues, {'top.a': 'x'});
    });

    test('copyWith with no args returns equivalent object', () {
      final copy = match.copyWith();
      expect(copy, match);
    });

    // ── toString ──────────────────────────────────────────────────────────────

    test('toString contains time and endTime', () {
      expect(match.toString(), contains('100'));
      expect(match.toString(), contains('200'));
    });

    // ── assert ────────────────────────────────────────────────────────────────

    test('assert fires when endTime < time', () {
      expect(
        () => PatternMatch(
          time: 200,
          endTime: 100, // invalid
          signalValues: const {},
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
