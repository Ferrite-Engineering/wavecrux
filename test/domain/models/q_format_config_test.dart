// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/q_format_config.dart';

void main() {
  group('QFormatConfig', () {
    // ── default constructor ───────────────────────────────────────────────────

    test('default is Q7.8 signed', () {
      const c = QFormatConfig();
      expect(c.m, 7);
      expect(c.n, 8);
      expect(c.signed, isTrue);
    });

    // ── totalBits ────────────────────────────────────────────────────────────

    test('totalBits signed: m + n + 1', () {
      // Q3.12 signed → 3 + 12 + 1 = 16 bits
      expect(const QFormatConfig(m: 3, n: 12).totalBits, 16);
    });

    test('totalBits unsigned: m + n (no sign bit)', () {
      // UQ4.12 → 4 + 12 = 16 bits
      expect(const QFormatConfig(m: 4, n: 12, signed: false).totalBits, 16);
    });

    test('totalBits Q0.15 signed = 16', () {
      // Q0.15 → 0 + 15 + 1 = 16 bits
      expect(const QFormatConfig(m: 0, n: 15).totalBits, 16);
    });

    test('totalBits UQ0.16 unsigned = 16', () {
      expect(const QFormatConfig(m: 0, n: 16, signed: false).totalBits, 16);
    });

    // ── notation ─────────────────────────────────────────────────────────────

    test('notation default signed: Q7.8', () {
      expect(const QFormatConfig().notation, 'Q7.8');
    });

    test('notation signed non-default: Q3.12', () {
      expect(const QFormatConfig(m: 3, n: 12).notation, 'Q3.12');
    });

    test('notation unsigned: UQ4.12', () {
      expect(
        const QFormatConfig(m: 4, n: 12, signed: false).notation,
        'UQ4.12',
      );
    });

    test('notation Q0.15', () {
      expect(const QFormatConfig(m: 0, n: 15).notation, 'Q0.15');
    });

    test('notation UQ0.16', () {
      expect(
        const QFormatConfig(m: 0, n: 16, signed: false).notation,
        'UQ0.16',
      );
    });

    // ── toString ─────────────────────────────────────────────────────────────

    test('toString contains notation for default (Q7.8)', () {
      expect(const QFormatConfig().toString(), contains('Q7.8'));
    });

    test('toString contains notation for unsigned', () {
      expect(
        const QFormatConfig(m: 4, n: 12, signed: false).toString(),
        contains('UQ4.12'),
      );
    });

    // ── fromMap / toMap ───────────────────────────────────────────────────────

    test('fromMap/toMap round-trip for signed', () {
      const c = QFormatConfig(m: 3, n: 12);
      expect(QFormatConfig.fromMap(c.toMap()), c);
    });

    test('fromMap/toMap round-trip for unsigned', () {
      const c = QFormatConfig(m: 4, n: 12, signed: false);
      expect(QFormatConfig.fromMap(c.toMap()), c);
    });

    test('fromMap uses defaults when all keys are absent', () {
      final c = QFormatConfig.fromMap(const <String, Object?>{});
      expect(c.m, 7);
      expect(c.n, 8);
      expect(c.signed, isTrue);
    });

    test('fromMap accepts num (double) for m and n', () {
      final c = QFormatConfig.fromMap(
        const <String, Object?>{'m': 4.0, 'n': 12.0, 'signed': false},
      );
      expect(c.m, 4);
      expect(c.n, 12);
      expect(c.signed, isFalse);
    });

    test('toMap contains correct keys and values', () {
      const c = QFormatConfig(m: 3, n: 5, signed: false);
      final map = c.toMap();
      expect(map['m'], 3);
      expect(map['n'], 5);
      expect(map['signed'], false);
    });

    // ── copyWith ─────────────────────────────────────────────────────────────

    test('copyWith overrides m only', () {
      const c = QFormatConfig(m: 3, n: 12);
      final copy = c.copyWith(m: 6);
      expect(copy.m, 6);
      expect(copy.n, 12);
      expect(copy.signed, isTrue);
    });

    test('copyWith overrides n only', () {
      const c = QFormatConfig(m: 3, n: 12);
      final copy = c.copyWith(n: 15);
      expect(copy.m, 3);
      expect(copy.n, 15);
      expect(copy.signed, isTrue);
    });

    test('copyWith overrides signed only', () {
      const c = QFormatConfig(m: 3, n: 12);
      final copy = c.copyWith(signed: false);
      expect(copy.m, 3);
      expect(copy.n, 12);
      expect(copy.signed, isFalse);
    });

    test('copyWith with no args returns equivalent value', () {
      const c = QFormatConfig(m: 4, n: 12, signed: false);
      expect(c.copyWith(), c);
    });

    test('copyWith overrides all fields', () {
      const c = QFormatConfig();
      final copy = c.copyWith(m: 1, n: 2, signed: false);
      expect(copy, const QFormatConfig(m: 1, n: 2, signed: false));
    });

    // ── equality / hashCode ───────────────────────────────────────────────────

    test('== true for identical values', () {
      expect(
        const QFormatConfig(m: 3, n: 12),
        const QFormatConfig(m: 3, n: 12),
      );
    });

    test('== false when m differs', () {
      expect(
        const QFormatConfig(m: 3, n: 12),
        isNot(const QFormatConfig(m: 4, n: 12)),
      );
    });

    test('== false when n differs', () {
      expect(
        const QFormatConfig(m: 3, n: 12),
        isNot(const QFormatConfig(m: 3, n: 4)),
      );
    });

    test('== false when signed differs', () {
      expect(
        const QFormatConfig(m: 3, n: 12),
        isNot(const QFormatConfig(m: 3, n: 12, signed: false)),
      );
    });

    test('hashCode matches for equal configs', () {
      expect(
        const QFormatConfig(m: 3, n: 12).hashCode,
        const QFormatConfig(m: 3, n: 12).hashCode,
      );
    });

    test('hashCode differs for unequal configs', () {
      expect(
        const QFormatConfig(m: 3, n: 12).hashCode,
        isNot(const QFormatConfig(m: 4, n: 12, signed: false).hashCode),
      );
    });
  });
}
