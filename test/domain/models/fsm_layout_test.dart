// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/fsm_layout.dart';

void main() {
  group('FsmStatePosition', () {
    test('preserves fields', () {
      const p = FsmStatePosition(stateId: '0', x: 0.5, y: 0.25);
      expect(p.stateId, '0');
      expect(p.x, 0.5);
      expect(p.y, 0.25);
    });

    test('equality and hashCode', () {
      const a = FsmStatePosition(stateId: '0', x: 0.5, y: 0.5);
      const b = FsmStatePosition(stateId: '0', x: 0.5, y: 0.5);
      const c = FsmStatePosition(stateId: '1', x: 0.5, y: 0.5);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('copyWith', () {
      const p = FsmStatePosition(stateId: '0', x: 0.5, y: 0.5);
      expect(p.copyWith(stateId: '7').stateId, '7');
      expect(p.copyWith(x: 0.1).x, 0.1);
    });
  });

  group('FsmLayout', () {
    test('isEmpty / isNotEmpty', () {
      const empty = FsmLayout(positions: {});
      expect(empty.isEmpty, isTrue);
      expect(empty.isNotEmpty, isFalse);

      const layout = FsmLayout(
        positions: {
          '0': FsmStatePosition(stateId: '0', x: 0.5, y: 0.5),
        },
      );
      expect(layout.isEmpty, isFalse);
      expect(layout.isNotEmpty, isTrue);
    });

    test('operator [] returns the position or null', () {
      const layout = FsmLayout(
        positions: {
          '0': FsmStatePosition(stateId: '0', x: 0.5, y: 0.5),
        },
      );
      expect(layout['0']?.x, 0.5);
      expect(layout['1'], isNull);
    });

    test('equality is structural', () {
      const a = FsmLayout(
        positions: {
          '0': FsmStatePosition(stateId: '0', x: 0.5, y: 0.5),
        },
      );
      const b = FsmLayout(
        positions: {
          '0': FsmStatePosition(stateId: '0', x: 0.5, y: 0.5),
        },
      );
      const c = FsmLayout(
        positions: {
          '0': FsmStatePosition(stateId: '0', x: 0.6, y: 0.5),
        },
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });
}
