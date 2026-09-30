// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/fsm_transition.dart';

void main() {
  group('FsmTransition', () {
    test('preserves all fields', () {
      const t = FsmTransition(
        fromId: '0',
        toId: '1',
        count: 3,
        times: [10, 20, 30],
      );
      expect(t.fromId, '0');
      expect(t.toId, '1');
      expect(t.count, 3);
      expect(t.times, [10, 20, 30]);
    });

    test('isSelfLoop is true only when from == to', () {
      const a = FsmTransition(fromId: '0', toId: '0', count: 1, times: [10]);
      const b = FsmTransition(fromId: '0', toId: '1', count: 1, times: [10]);
      expect(a.isSelfLoop, isTrue);
      expect(b.isSelfLoop, isFalse);
    });

    test('equality compares all fields including times list', () {
      const a = FsmTransition(fromId: '0', toId: '1', count: 2, times: [5, 10]);
      const b = FsmTransition(fromId: '0', toId: '1', count: 2, times: [5, 10]);
      const c = FsmTransition(fromId: '0', toId: '1', count: 2, times: [5, 11]);
      expect(a, equals(b));
      expect(a == c, isFalse);
      expect(a.hashCode, b.hashCode);
    });

    test('inequality with different counts', () {
      const a = FsmTransition(fromId: '0', toId: '1', count: 2, times: [5, 10]);
      const b = FsmTransition(fromId: '0', toId: '1', count: 3, times: [5, 10]);
      expect(a == b, isFalse);
    });

    test('copyWith updates fields', () {
      const t = FsmTransition(fromId: '0', toId: '1', count: 1, times: [1]);
      expect(t.copyWith(count: 5).count, 5);
      expect(t.copyWith(toId: '2').toId, '2');
    });

    test('toString contains key fields', () {
      const t = FsmTransition(
        fromId: 'A',
        toId: 'B',
        count: 7,
        times: [1, 2, 3],
      );
      final str = t.toString();
      expect(str, contains('A'));
      expect(str, contains('B'));
      expect(str, contains('7'));
    });
  });
}
