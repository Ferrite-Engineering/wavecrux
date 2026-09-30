// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/time_selection.dart';

void main() {
  group('TimeSelection', () {
    // ── construction ─────────────────────────────────────────────────────────

    test('stores start and end times', () {
      const sel = TimeSelection(startTime: 100, endTime: 500);
      expect(sel.startTime, 100);
      expect(sel.endTime, 500);
    });

    test('accepts inverted range (startTime > endTime)', () {
      const sel = TimeSelection(startTime: 800, endTime: 200);
      expect(sel.startTime, 800);
      expect(sel.endTime, 200);
    });

    test('accepts zero-value times', () {
      const sel = TimeSelection(startTime: 0, endTime: 0);
      expect(sel.startTime, 0);
      expect(sel.endTime, 0);
    });

    // ── duration ─────────────────────────────────────────────────────────────

    test('duration is absolute difference for forward range', () {
      const sel = TimeSelection(startTime: 100, endTime: 600);
      expect(sel.duration, 500);
    });

    test('duration is absolute difference for inverted range', () {
      const sel = TimeSelection(startTime: 700, endTime: 200);
      expect(sel.duration, 500);
    });

    test('duration is zero for empty selection', () {
      const sel = TimeSelection(startTime: 300, endTime: 300);
      expect(sel.duration, 0);
    });

    // ── isEmpty ───────────────────────────────────────────────────────────────

    test('isEmpty is true when start equals end', () {
      const sel = TimeSelection(startTime: 400, endTime: 400);
      expect(sel.isEmpty, isTrue);
    });

    test('isEmpty is false for non-zero duration forward range', () {
      const sel = TimeSelection(startTime: 0, endTime: 1);
      expect(sel.isEmpty, isFalse);
    });

    test('isEmpty is false for non-zero duration inverted range', () {
      const sel = TimeSelection(startTime: 500, endTime: 100);
      expect(sel.isEmpty, isFalse);
    });

    // ── normalized ────────────────────────────────────────────────────────────

    test('normalized preserves already-ordered range', () {
      const sel = TimeSelection(startTime: 100, endTime: 500);
      final norm = sel.normalized();
      expect(norm.startTime, 100);
      expect(norm.endTime, 500);
    });

    test('normalized swaps inverted range so start <= end', () {
      const sel = TimeSelection(startTime: 800, endTime: 200);
      final norm = sel.normalized();
      expect(norm.startTime, 200);
      expect(norm.endTime, 800);
    });

    test('normalized is a no-op for empty selection', () {
      const sel = TimeSelection(startTime: 300, endTime: 300);
      final norm = sel.normalized();
      expect(norm.startTime, 300);
      expect(norm.endTime, 300);
    });

    test('normalized returns same object for already-ordered range', () {
      const sel = TimeSelection(startTime: 10, endTime: 20);
      expect(identical(sel.normalized(), sel), isTrue);
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    test('copyWith replaces startTime', () {
      const sel = TimeSelection(startTime: 100, endTime: 500);
      final copy = sel.copyWith(startTime: 200);
      expect(copy.startTime, 200);
      expect(copy.endTime, 500);
    });

    test('copyWith replaces endTime', () {
      const sel = TimeSelection(startTime: 100, endTime: 500);
      final copy = sel.copyWith(endTime: 800);
      expect(copy.startTime, 100);
      expect(copy.endTime, 800);
    });

    test('copyWith with no args returns equal selection', () {
      const sel = TimeSelection(startTime: 100, endTime: 500);
      final copy = sel.copyWith();
      expect(copy, equals(sel));
    });

    // ── equality ──────────────────────────────────────────────────────────────

    test('equal when both times match', () {
      const a = TimeSelection(startTime: 100, endTime: 500);
      const b = TimeSelection(startTime: 100, endTime: 500);
      expect(a, equals(b));
    });

    test('not equal when startTime differs', () {
      const a = TimeSelection(startTime: 100, endTime: 500);
      const b = TimeSelection(startTime: 200, endTime: 500);
      expect(a, isNot(equals(b)));
    });

    test('not equal when endTime differs', () {
      const a = TimeSelection(startTime: 100, endTime: 500);
      const b = TimeSelection(startTime: 100, endTime: 600);
      expect(a, isNot(equals(b)));
    });

    test('identical objects are equal', () {
      const a = TimeSelection(startTime: 0, endTime: 1000);
      expect(a, equals(a));
    });

    // ── hashCode ──────────────────────────────────────────────────────────────

    test('equal selections have same hashCode', () {
      const a = TimeSelection(startTime: 100, endTime: 500);
      const b = TimeSelection(startTime: 100, endTime: 500);
      expect(a.hashCode, equals(b.hashCode));
    });

    // ── toString ──────────────────────────────────────────────────────────────

    test('toString contains start and end times', () {
      const sel = TimeSelection(startTime: 100, endTime: 500);
      expect(sel.toString(), contains('100'));
      expect(sel.toString(), contains('500'));
    });
  });
}
