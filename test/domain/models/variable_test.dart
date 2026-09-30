// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/variable.dart';

void main() {
  group('Variable', () {
    const clk = Variable(
      name: 'clk',
      varType: VarType.wire,
      direction: VarDirection.input,
      signalRef: '0',
      scopePath: 'top',
      bitWidth: 1,
    );

    const data = Variable(
      name: 'data',
      varType: VarType.reg,
      direction: VarDirection.unknown,
      signalRef: '1',
      scopePath: 'top.cpu',
      bitWidth: 8,
    );

    const realSig = Variable(
      name: 'voltage',
      varType: VarType.real,
      direction: VarDirection.unknown,
      signalRef: '2',
      scopePath: 'top',
    );

    const topLevel = Variable(
      name: 'rst',
      varType: VarType.wire,
      direction: VarDirection.input,
      signalRef: '3',
      scopePath: '',
      bitWidth: 1,
    );

    // ── construction ─────────────────────────────────────────────────────────

    test('stores all required fields', () {
      expect(clk.name, 'clk');
      expect(clk.varType, VarType.wire);
      expect(clk.direction, VarDirection.input);
      expect(clk.signalRef, '0');
      expect(clk.scopePath, 'top');
      expect(clk.bitWidth, 1);
    });

    test('bitWidth is null by default', () {
      expect(realSig.bitWidth, isNull);
    });

    // ── fullPath ─────────────────────────────────────────────────────────────

    test('fullPath combines scopePath and name', () {
      expect(clk.fullPath, 'top.clk');
    });
    test('fullPath for nested scope', () {
      expect(data.fullPath, 'top.cpu.data');
    });
    test('fullPath at top level (empty scopePath) is just name', () {
      expect(topLevel.fullPath, 'rst');
    });

    // ── isBitVector ───────────────────────────────────────────────────────────

    test('isBitVector true when bitWidth is set', () {
      expect(clk.isBitVector, isTrue);
    });
    test('isBitVector false when bitWidth is null', () {
      expect(realSig.isBitVector, isFalse);
    });

    // ── isReal ────────────────────────────────────────────────────────────────

    test('isReal for VarType.real', () {
      expect(realSig.isReal, isTrue);
    });
    test('isReal for VarType.realTime', () {
      const v = Variable(
        name: 'rt',
        varType: VarType.realTime,
        direction: VarDirection.unknown,
        signalRef: '99',
        scopePath: '',
      );
      expect(v.isReal, isTrue);
    });
    test('isReal for VarType.svShortReal', () {
      const v = Variable(
        name: 'sr',
        varType: VarType.svShortReal,
        direction: VarDirection.unknown,
        signalRef: '98',
        scopePath: '',
      );
      expect(v.isReal, isTrue);
    });
    test('isReal false for wire', () {
      expect(clk.isReal, isFalse);
    });

    // ── copyWith ─────────────────────────────────────────────────────────────

    test('copyWith(name:) changes only name', () {
      final v = clk.copyWith(name: 'clk2');
      expect(v.name, 'clk2');
      expect(v.varType, VarType.wire);
      expect(v.scopePath, 'top');
    });
    test('copyWith(bitWidth:) changes only bitWidth', () {
      final v = clk.copyWith(bitWidth: 4);
      expect(v.bitWidth, 4);
      expect(v.name, 'clk');
    });
    test('copyWith(clearBitWidth: true) sets bitWidth to null', () {
      final v = clk.copyWith(clearBitWidth: true);
      expect(v.bitWidth, isNull);
    });
    test('copyWith with no args returns equal object', () {
      expect(clk.copyWith(), equals(clk));
    });

    // ── equality ─────────────────────────────────────────────────────────────

    test('equal when all fields match', () {
      const a = Variable(
        name: 'clk',
        varType: VarType.wire,
        direction: VarDirection.input,
        signalRef: '0',
        scopePath: 'top',
        bitWidth: 1,
      );
      const b = Variable(
        name: 'clk',
        varType: VarType.wire,
        direction: VarDirection.input,
        signalRef: '0',
        scopePath: 'top',
        bitWidth: 1,
      );
      expect(a, equals(b));
    });
    test('not equal when name differs', () {
      expect(clk, isNot(equals(clk.copyWith(name: 'clk2'))));
    });
    test('not equal when scopePath differs', () {
      expect(clk, isNot(equals(clk.copyWith(scopePath: 'other'))));
    });
    test('not equal when bitWidth differs', () {
      expect(clk, isNot(equals(clk.copyWith(bitWidth: 8))));
    });
    test('hashCode equal for equal objects', () {
      const a = Variable(
        name: 'clk',
        varType: VarType.wire,
        direction: VarDirection.input,
        signalRef: '0',
        scopePath: 'top',
        bitWidth: 1,
      );
      const b = Variable(
        name: 'clk',
        varType: VarType.wire,
        direction: VarDirection.input,
        signalRef: '0',
        scopePath: 'top',
        bitWidth: 1,
      );
      expect(a.hashCode, equals(b.hashCode));
    });

    // ── toString ─────────────────────────────────────────────────────────────

    test('toString contains fullPath', () {
      expect(clk.toString(), contains('top.clk'));
    });
  });
}
