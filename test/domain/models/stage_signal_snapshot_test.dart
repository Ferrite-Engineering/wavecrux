// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';

void main() {
  group('StageSignalSnapshot — lifecycle states', () {
    test('unbound', () {
      const s = StageSignalSnapshot.unbound();
      expect(s.kind, StageSignalSnapshotKind.unbound);
      expect(s.isBound, isFalse);
      expect(s.hasValue, isFalse);
    });

    test('noFile', () {
      const s = StageSignalSnapshot.noFile();
      expect(s.kind, StageSignalSnapshotKind.noFile);
      expect(s.isBound, isTrue);
      expect(s.hasValue, isFalse);
    });

    test('loading', () {
      const s = StageSignalSnapshot.loading();
      expect(s.kind, StageSignalSnapshotKind.loading);
      expect(s.hasValue, isFalse);
    });

    test('unknown', () {
      const s = StageSignalSnapshot.unknown();
      expect(s.kind, StageSignalSnapshotKind.unknown);
      expect(s.hasValue, isFalse);
    });

    test('error', () {
      const s = StageSignalSnapshot.error('Invalid signalRef: "top.x"');
      expect(s.kind, StageSignalSnapshotKind.error);
      expect(s.isError, isTrue);
      expect(s.isBound, isTrue);
      expect(s.hasValue, isFalse);
      expect(s.errorMessage, 'Invalid signalRef: "top.x"');
    });

    test('error defaults to an empty message and is distinct from unknown', () {
      const e = StageSignalSnapshot.error();
      const u = StageSignalSnapshot.unknown();
      expect(e.errorMessage, isEmpty);
      expect(e.isError, isTrue);
      expect(u.isError, isFalse);
      expect(e == u, isFalse);
    });

    test('error snapshots with different messages are unequal', () {
      const a = StageSignalSnapshot.error('a');
      const b = StageSignalSnapshot.error('b');
      expect(a == b, isFalse);
      expect(a == const StageSignalSnapshot.error('a'), isTrue);
    });
  });

  group('StageSignalSnapshot — value parsing', () {
    test('cleanBits strips b prefix and lowercases', () {
      const s = StageSignalSnapshot.value(rawValue: 'B1010', bitWidth: 4);
      expect(s.cleanBits, '1010');
    });

    test('cleanBits strips r prefix for real signals', () {
      const s = StageSignalSnapshot.value(
        rawValue: 'r3.14',
        bitWidth: 0,
        isReal: true,
      );
      expect(s.cleanBits, '3.14');
    });

    test('hasX detects unknown bits', () {
      const s = StageSignalSnapshot.value(rawValue: '10x1', bitWidth: 4);
      expect(s.hasX, isTrue);
      expect(s.hasZ, isFalse);
    });

    test('hasZ detects high-impedance bits', () {
      const s = StageSignalSnapshot.value(rawValue: '10z1', bitWidth: 4);
      expect(s.hasZ, isTrue);
      expect(s.hasX, isFalse);
    });

    test('hasZ false when both x and z present', () {
      const s = StageSignalSnapshot.value(rawValue: '10xz', bitWidth: 4);
      expect(s.hasX, isTrue);
      expect(s.hasZ, isFalse);
    });

    test('intValue parses pure binary', () {
      const s = StageSignalSnapshot.value(rawValue: '1010', bitWidth: 4);
      expect(s.intValue, BigInt.from(10));
    });

    test('intValue null on x', () {
      const s = StageSignalSnapshot.value(rawValue: '10x0', bitWidth: 4);
      expect(s.intValue, isNull);
    });

    test('intValue null on z', () {
      const s = StageSignalSnapshot.value(rawValue: '10z0', bitWidth: 4);
      expect(s.intValue, isNull);
    });

    test('intValue null on real', () {
      const s = StageSignalSnapshot.value(
        rawValue: '3.14',
        bitWidth: 0,
        isReal: true,
      );
      expect(s.intValue, isNull);
    });

    test('intValue handles wide buses', () {
      const s = StageSignalSnapshot.value(
        rawValue:
            '11111111111111111111111111111111111111111111111111111111111111111',
        bitWidth: 65,
      );
      expect(s.intValue, BigInt.parse('36893488147419103231'));
    });

    test('realValue parses real signals', () {
      const s = StageSignalSnapshot.value(
        rawValue: 'r3.14',
        bitWidth: 0,
        isReal: true,
      );
      expect(s.realValue, closeTo(3.14, 1e-9));
    });

    test('realValue returns int as double', () {
      const s = StageSignalSnapshot.value(rawValue: '1010', bitWidth: 4);
      expect(s.realValue, 10.0);
    });

    test('realValue null on x/z', () {
      const s = StageSignalSnapshot.value(rawValue: '10x0', bitWidth: 4);
      expect(s.realValue, isNull);
    });

    test('intValue null on empty bits', () {
      const s = StageSignalSnapshot.value(rawValue: 'b', bitWidth: 0);
      expect(s.intValue, isNull);
    });
  });

  group('StageSignalSnapshot — equality', () {
    test('equal values produce equal hashCodes', () {
      const a = StageSignalSnapshot.value(rawValue: '1010', bitWidth: 4);
      const b = StageSignalSnapshot.value(rawValue: '1010', bitWidth: 4);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different lifecycle states are not equal', () {
      expect(
        const StageSignalSnapshot.unbound(),
        isNot(equals(const StageSignalSnapshot.loading())),
      );
    });

    test('toString includes lifecycle and width', () {
      const s = StageSignalSnapshot.value(rawValue: '11', bitWidth: 2);
      expect(s.toString(), contains('value'));
      expect(s.toString(), contains('w: 2'));
    });
  });
}
