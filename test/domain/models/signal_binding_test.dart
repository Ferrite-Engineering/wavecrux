// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';

void main() {
  group('SignalBinding', () {
    const binding = SignalBinding(
      name: 'mosi',
      description: 'Master Out Slave In',
      bitWidth: 1,
    );

    const bindingNoWidth = SignalBinding(
      name: 'cs',
      description: 'Chip Select',
    );

    // ── equality ──────────────────────────────────────────────────────────────

    test('equal when all fields match', () {
      const other = SignalBinding(
        name: 'mosi',
        description: 'Master Out Slave In',
        bitWidth: 1,
      );
      expect(binding, equals(other));
    });

    test('identical instances are equal', () {
      expect(binding, equals(binding));
    });

    test('not equal when name differs', () {
      const other = SignalBinding(
        name: 'miso',
        description: 'Master Out Slave In',
        bitWidth: 1,
      );
      expect(binding, isNot(equals(other)));
    });

    test('not equal when description differs', () {
      const other = SignalBinding(
        name: 'mosi',
        description: 'Other',
        bitWidth: 1,
      );
      expect(binding, isNot(equals(other)));
    });

    test('not equal when bitWidth differs', () {
      const other = SignalBinding(
        name: 'mosi',
        description: 'Master Out Slave In',
        bitWidth: 8,
      );
      expect(binding, isNot(equals(other)));
    });

    test('not equal when one bitWidth is null', () {
      const other = SignalBinding(
        name: 'mosi',
        description: 'Master Out Slave In',
      );
      expect(binding, isNot(equals(other)));
    });

    test('null bitWidth equals null bitWidth', () {
      const other = SignalBinding(name: 'cs', description: 'Chip Select');
      expect(bindingNoWidth, equals(other));
    });

    test('hashCode consistent with equality', () {
      const other = SignalBinding(
        name: 'mosi',
        description: 'Master Out Slave In',
        bitWidth: 1,
      );
      expect(binding.hashCode, equals(other.hashCode));
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    test('copyWith returns identical when no args', () {
      expect(binding.copyWith(), equals(binding));
    });

    test('copyWith updates name', () {
      expect(binding.copyWith(name: 'miso').name, 'miso');
    });

    test('copyWith updates description', () {
      expect(binding.copyWith(description: 'New desc').description, 'New desc');
    });

    test('copyWith updates bitWidth', () {
      expect(binding.copyWith(bitWidth: 8).bitWidth, 8);
    });

    test('clearBitWidth sets bitWidth to null', () {
      expect(binding.copyWith(clearBitWidth: true).bitWidth, isNull);
    });

    test('clearBitWidth takes precedence over new bitWidth', () {
      expect(
        binding.copyWith(bitWidth: 4, clearBitWidth: true).bitWidth,
        isNull,
      );
    });

    // ── toString ──────────────────────────────────────────────────────────────

    test('toString contains name and bitWidth', () {
      expect(binding.toString(), contains('mosi'));
      expect(binding.toString(), contains('1'));
    });

    test('toString handles null bitWidth', () {
      expect(bindingNoWidth.toString(), contains('cs'));
    });

    // ── conditional visibility ────────────────────────────────────────────────

    group('isVisibleIn', () {
      test('a binding with no predicate is always visible', () {
        // The additive-change guarantee: every pin declared before this
        // seam existed must enumerate exactly as it did.
        expect(binding.isVisibleIn(const {}), isTrue);
        expect(binding.isVisibleIn(const {'stageCount': 4}), isTrue);
        expect(
          bindingNoWidth.isVisibleIn(const {'anything': 'at all'}),
          isTrue,
        );
      });

      test('single-value equality', () {
        const conditional = SignalBinding(
          name: 'stage3_valid',
          description: 'Stage 3 valid',
          visibleWhenKey: 'mode',
          visibleWhenValue: 'advanced',
        );
        expect(conditional.isVisibleIn(const {'mode': 'advanced'}), isTrue);
        expect(conditional.isVisibleIn(const {'mode': 'basic'}), isFalse);
        expect(conditional.isVisibleIn(const {}), isFalse);
      });

      test('OR-of-discrete-values membership', () {
        // The 2–8 configurable-stage case: stage 5's pins are visible for
        // any stage count from 5 up.
        const conditional = SignalBinding(
          name: 'stage5_valid',
          description: 'Stage 5 valid',
          visibleWhenKey: 'stageCount',
          visibleWhenValues: {5, 6, 7, 8},
        );
        expect(conditional.isVisibleIn(const {'stageCount': 5}), isTrue);
        expect(conditional.isVisibleIn(const {'stageCount': 8}), isTrue);
        expect(conditional.isVisibleIn(const {'stageCount': 4}), isFalse);
        expect(conditional.isVisibleIn(const {}), isFalse);
      });

      test('equality accounts for the visibility predicate', () {
        const a = SignalBinding(
          name: 'p',
          description: 'd',
          visibleWhenKey: 'k',
          visibleWhenValues: {1, 2},
        );
        const b = SignalBinding(
          name: 'p',
          description: 'd',
          visibleWhenKey: 'k',
          visibleWhenValues: {2, 1},
        );
        const c = SignalBinding(
          name: 'p',
          description: 'd',
          visibleWhenKey: 'k',
          visibleWhenValues: {1, 3},
        );
        const plain = SignalBinding(name: 'p', description: 'd');
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
        expect(a, isNot(equals(c)));
        expect(a, isNot(equals(plain)));
      });

      test('copyWith carries and clears the predicate', () {
        const conditional = SignalBinding(
          name: 'p',
          description: 'd',
          visibleWhenKey: 'k',
          visibleWhenValue: 3,
        );
        expect(conditional.copyWith(name: 'q').visibleWhenKey, 'k');
        expect(
          conditional.copyWith(clearVisibleWhen: true).visibleWhenKey,
          isNull,
        );
        expect(
          conditional.copyWith(clearVisibleWhen: true).visibleWhenValue,
          isNull,
        );
      });
    });
  });
}
