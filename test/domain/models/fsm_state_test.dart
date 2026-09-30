// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/fsm_state.dart';

void main() {
  group('FsmState', () {
    test('default constructor preserves all fields', () {
      const s = FsmState(
        id: '3',
        label: 'IDLE',
        entryCount: 7,
        firstEntryTime: 42,
      );
      expect(s.id, '3');
      expect(s.label, 'IDLE');
      expect(s.entryCount, 7);
      expect(s.firstEntryTime, 42);
    });

    test('firstEntryTime can be null', () {
      const s = FsmState(
        id: '0',
        label: '0',
        entryCount: 0,
        firstEntryTime: null,
      );
      expect(s.firstEntryTime, isNull);
    });

    test('equality compares all fields', () {
      const a = FsmState(id: '1', label: 'A', entryCount: 1, firstEntryTime: 0);
      const b = FsmState(id: '1', label: 'A', entryCount: 1, firstEntryTime: 0);
      const c = FsmState(id: '1', label: 'B', entryCount: 1, firstEntryTime: 0);
      expect(a, equals(b));
      expect(a == c, isFalse);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith updates individual fields', () {
      const s = FsmState(
        id: '0',
        label: 'IDLE',
        entryCount: 1,
        firstEntryTime: 100,
      );
      expect(s.copyWith(label: 'RUN').label, 'RUN');
      expect(s.copyWith(entryCount: 99).entryCount, 99);
      expect(s.copyWith(id: '5').id, '5');
    });

    test('copyWith can clear firstEntryTime to null', () {
      const s = FsmState(
        id: '0',
        label: 'IDLE',
        entryCount: 1,
        firstEntryTime: 100,
      );
      expect(s.copyWith(firstEntryTime: null).firstEntryTime, isNull);
    });

    test('toString includes the canonical fields', () {
      const s = FsmState(
        id: '2',
        label: 'BUSY',
        entryCount: 3,
        firstEntryTime: 500,
      );
      final str = s.toString();
      expect(str, contains('2'));
      expect(str, contains('BUSY'));
      expect(str, contains('3'));
    });
  });
}
