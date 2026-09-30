// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';

void main() {
  group('CursorState', () {
    // ── construction ─────────────────────────────────────────────────────────

    test('default state has both cursors null', () {
      const s = CursorState();
      expect(s.primaryCursorTime, isNull);
      expect(s.secondaryCursorTime, isNull);
    });

    test('stores explicit cursor times', () {
      const s = CursorState(primaryCursorTime: 100, secondaryCursorTime: 200);
      expect(s.primaryCursorTime, 100);
      expect(s.secondaryCursorTime, 200);
    });

    test('accepts time zero for primary cursor', () {
      const s = CursorState(primaryCursorTime: 0);
      expect(s.primaryCursorTime, 0);
    });

    // ── deltaTicks ───────────────────────────────────────────────────────────

    test('deltaTicks is null when primary cursor is absent', () {
      const s = CursorState(secondaryCursorTime: 500);
      expect(s.deltaTicks, isNull);
    });

    test('deltaTicks is null when secondary cursor is absent', () {
      const s = CursorState(primaryCursorTime: 100);
      expect(s.deltaTicks, isNull);
    });

    test('deltaTicks is null when both cursors are absent', () {
      const s = CursorState();
      expect(s.deltaTicks, isNull);
    });

    test('deltaTicks is absolute difference (primary < secondary)', () {
      const s = CursorState(primaryCursorTime: 100, secondaryCursorTime: 300);
      expect(s.deltaTicks, 200);
    });

    test('deltaTicks is absolute difference (primary > secondary)', () {
      const s = CursorState(primaryCursorTime: 300, secondaryCursorTime: 100);
      expect(s.deltaTicks, 200);
    });

    test('deltaTicks is zero when both cursors are at the same time', () {
      const s = CursorState(primaryCursorTime: 500, secondaryCursorTime: 500);
      expect(s.deltaTicks, 0);
    });

    test('deltaTicks works with large tick values', () {
      const s = CursorState(
        primaryCursorTime: 0,
        secondaryCursorTime: 1000000000,
      );
      expect(s.deltaTicks, 1000000000);
    });

    // ── copyWith ─────────────────────────────────────────────────────────────

    test('copyWith with no args returns equal object', () {
      const s = CursorState(primaryCursorTime: 100, secondaryCursorTime: 200);
      expect(s.copyWith(), equals(s));
    });

    test('copyWith(primaryCursorTime:) changes only primary', () {
      const s = CursorState(primaryCursorTime: 100, secondaryCursorTime: 200);
      final c = s.copyWith(primaryCursorTime: 999);
      expect(c.primaryCursorTime, 999);
      expect(c.secondaryCursorTime, 200);
    });

    test('copyWith(secondaryCursorTime:) changes only secondary', () {
      const s = CursorState(primaryCursorTime: 100, secondaryCursorTime: 200);
      final c = s.copyWith(secondaryCursorTime: 999);
      expect(c.primaryCursorTime, 100);
      expect(c.secondaryCursorTime, 999);
    });

    test('copyWith can clear primary cursor to null', () {
      const s = CursorState(primaryCursorTime: 100);
      final c = s.copyWith(primaryCursorTime: null);
      expect(c.primaryCursorTime, isNull);
    });

    test('copyWith can clear secondary cursor to null', () {
      const s = CursorState(primaryCursorTime: 100, secondaryCursorTime: 200);
      final c = s.copyWith(secondaryCursorTime: null);
      expect(c.secondaryCursorTime, isNull);
      expect(c.primaryCursorTime, 100);
    });

    // ── equality ─────────────────────────────────────────────────────────────

    test('equal when both fields match', () {
      const a = CursorState(primaryCursorTime: 100, secondaryCursorTime: 200);
      const b = CursorState(primaryCursorTime: 100, secondaryCursorTime: 200);
      expect(a, equals(b));
    });

    test('not equal when primary differs', () {
      const a = CursorState(primaryCursorTime: 100);
      const b = CursorState(primaryCursorTime: 200);
      expect(a, isNot(equals(b)));
    });

    test('not equal when secondary differs', () {
      const a = CursorState(primaryCursorTime: 100, secondaryCursorTime: 200);
      const b = CursorState(primaryCursorTime: 100, secondaryCursorTime: 300);
      expect(a, isNot(equals(b)));
    });

    test('not equal when one has null secondary', () {
      const a = CursorState(primaryCursorTime: 100);
      const b = CursorState(primaryCursorTime: 100, secondaryCursorTime: 200);
      expect(a, isNot(equals(b)));
    });

    test('two default states are equal', () {
      const a = CursorState();
      const b = CursorState();
      expect(a, equals(b));
    });

    test('hashCode matches for equal objects', () {
      const a = CursorState(primaryCursorTime: 100, secondaryCursorTime: 200);
      const b = CursorState(primaryCursorTime: 100, secondaryCursorTime: 200);
      expect(a.hashCode, equals(b.hashCode));
    });

    // ── toString ─────────────────────────────────────────────────────────────

    test('toString contains primary and secondary values', () {
      const s = CursorState(primaryCursorTime: 100, secondaryCursorTime: 200);
      expect(s.toString(), allOf(contains('100'), contains('200')));
    });

    test('toString contains null for absent cursors', () {
      const s = CursorState();
      expect(s.toString(), contains('null'));
    });
  });
}
