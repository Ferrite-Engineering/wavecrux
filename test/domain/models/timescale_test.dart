// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/models/timescale.dart';

void main() {
  group('Timescale', () {
    const ns1 = Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);
    const ps10 = Timescale(factor: 10, unit: TimescaleUnit.picoSeconds);
    const unknown = Timescale(factor: 1, unit: TimescaleUnit.unknown);

    // ── construction ─────────────────────────────────────────────────────────

    test('stores factor and unit', () {
      expect(ns1.factor, 1);
      expect(ns1.unit, TimescaleUnit.nanoSeconds);
    });

    // ── displayString ────────────────────────────────────────────────────────

    test('displayString: 1ns', () => expect(ns1.displayString, '1ns'));
    test('displayString: 10ps', () => expect(ps10.displayString, '10ps'));
    test('displayString: 100µs', () {
      const t = Timescale(factor: 100, unit: TimescaleUnit.microSeconds);
      expect(t.displayString, '100µs');
    });
    test('displayString unknown unit uses ?', () {
      expect(unknown.displayString, '1?');
    });

    // ── secondsPerTick ───────────────────────────────────────────────────────

    test('1ns → 1e-9 seconds', () {
      expect(ns1.secondsPerTick, closeTo(1e-9, 1e-20));
    });
    test('10ps → 1e-11 seconds', () {
      expect(ps10.secondsPerTick, closeTo(1e-11, 1e-22));
    });
    test('1s → 1.0 seconds', () {
      const s1 = Timescale(factor: 1, unit: TimescaleUnit.seconds);
      expect(s1.secondsPerTick, closeTo(1.0, 1e-10));
    });
    test('unknown unit → null', () {
      expect(unknown.secondsPerTick, isNull);
    });

    // ── copyWith ─────────────────────────────────────────────────────────────

    test('copyWith(factor: 10) changes only factor', () {
      final t = ns1.copyWith(factor: 10);
      expect(t.factor, 10);
      expect(t.unit, TimescaleUnit.nanoSeconds);
    });
    test('copyWith(unit: ps) changes only unit', () {
      final t = ns1.copyWith(unit: TimescaleUnit.picoSeconds);
      expect(t.factor, 1);
      expect(t.unit, TimescaleUnit.picoSeconds);
    });
    test('copyWith with no args returns equal object', () {
      expect(ns1.copyWith(), equals(ns1));
    });

    // ── equality ─────────────────────────────────────────────────────────────

    test('equal when factor and unit match', () {
      const a = Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);
      const b = Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);
      expect(a, equals(b));
    });
    test('not equal when factor differs', () {
      const a = Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);
      const b = Timescale(factor: 10, unit: TimescaleUnit.nanoSeconds);
      expect(a, isNot(equals(b)));
    });
    test('not equal when unit differs', () {
      expect(ns1, isNot(equals(ps10)));
    });
    test('hashCode equal for equal objects', () {
      const a = Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);
      const b = Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);
      expect(a.hashCode, equals(b.hashCode));
    });

    // ── toString ─────────────────────────────────────────────────────────────

    test('toString includes displayString', () {
      expect(ns1.toString(), contains('1ns'));
    });
  });
}
