// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_change.dart';

void main() {
  group('SignalChange', () {
    const change = SignalChange(time: 100, value: '1');

    // ── construction ─────────────────────────────────────────────────────────

    test('stores time and value', () {
      expect(change.time, 100);
      expect(change.value, '1');
    });

    test('accepts multi-bit value string', () {
      const c = SignalChange(time: 42, value: '10xz');
      expect(c.value, '10xz');
    });

    test('accepts real value string', () {
      const c = SignalChange(time: 0, value: '3.14');
      expect(c.value, '3.14');
    });

    // ── copyWith ─────────────────────────────────────────────────────────────

    test('copyWith(time:) changes only time', () {
      final c = change.copyWith(time: 200);
      expect(c.time, 200);
      expect(c.value, '1');
    });
    test('copyWith(value:) changes only value', () {
      final c = change.copyWith(value: '0');
      expect(c.time, 100);
      expect(c.value, '0');
    });
    test('copyWith with no args returns equal object', () {
      expect(change.copyWith(), equals(change));
    });

    // ── equality ─────────────────────────────────────────────────────────────

    test('equal when both fields match', () {
      const a = SignalChange(time: 100, value: '1');
      const b = SignalChange(time: 100, value: '1');
      expect(a, equals(b));
    });
    test('not equal when time differs', () {
      const a = SignalChange(time: 100, value: '1');
      const b = SignalChange(time: 200, value: '1');
      expect(a, isNot(equals(b)));
    });
    test('not equal when value differs', () {
      const a = SignalChange(time: 100, value: '0');
      const b = SignalChange(time: 100, value: '1');
      expect(a, isNot(equals(b)));
    });
    test('hashCode equal for equal objects', () {
      const a = SignalChange(time: 100, value: '1');
      const b = SignalChange(time: 100, value: '1');
      expect(a.hashCode, equals(b.hashCode));
    });

    // ── toString ─────────────────────────────────────────────────────────────

    test('toString contains time and value', () {
      expect(change.toString(), allOf(contains('100'), contains('1')));
    });
  });
}
