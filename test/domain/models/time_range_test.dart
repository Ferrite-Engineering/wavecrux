// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/time_range.dart';

void main() {
  group('TimeRange', () {
    test('stores start and end', () {
      const r = TimeRange(start: 10, end: 50);
      expect(r.start, 10);
      expect(r.end, 50);
    });

    test('duration equals end minus start', () {
      expect(const TimeRange(start: 10, end: 50).duration, 40);
      expect(const TimeRange(start: 0, end: 0).duration, 0);
    });

    test('equality and hashCode', () {
      const a = TimeRange(start: 5, end: 15);
      const b = TimeRange(start: 5, end: 15);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when fields differ', () {
      const base = TimeRange(start: 5, end: 15);
      expect(base, isNot(const TimeRange(start: 6, end: 15)));
      expect(base, isNot(const TimeRange(start: 5, end: 16)));
    });

    test('copyWith changes selected fields', () {
      const r = TimeRange(start: 10, end: 20);
      expect(r.copyWith(end: 30), const TimeRange(start: 10, end: 30));
      expect(r.copyWith(start: 5), const TimeRange(start: 5, end: 20));
    });

    test('toString contains start and end', () {
      expect(const TimeRange(start: 1, end: 9).toString(), contains('1'));
      expect(const TimeRange(start: 1, end: 9).toString(), contains('9'));
    });
  });
}
