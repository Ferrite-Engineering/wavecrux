// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/translated_field.dart';

void main() {
  const leaf = TranslatedField(name: 'len', text: '4', hiBit: 3, loBit: 0);

  group('defaults', () {
    test('fields default to empty and colorArgb to null', () {
      expect(leaf.fields, isEmpty);
      expect(leaf.colorArgb, isNull);
    });
  });

  group('equality', () {
    test('identical field definitions are equal', () {
      const a = TranslatedField(name: 'len', text: '4', hiBit: 3, loBit: 0);
      const b = TranslatedField(name: 'len', text: '4', hiBit: 3, loBit: 0);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing name / text / bits / color are not equal', () {
      expect(
        leaf,
        isNot(
          const TranslatedField(name: 'size', text: '4', hiBit: 3, loBit: 0),
        ),
      );
      expect(
        leaf,
        isNot(
          const TranslatedField(name: 'len', text: '5', hiBit: 3, loBit: 0),
        ),
      );
      expect(
        leaf,
        isNot(
          const TranslatedField(name: 'len', text: '4', hiBit: 7, loBit: 0),
        ),
      );
      expect(
        leaf,
        isNot(
          const TranslatedField(
            name: 'len',
            text: '4',
            hiBit: 3,
            loBit: 0,
            colorArgb: 0xFFFF0000,
          ),
        ),
      );
    });

    test('deep nested-field equality is respected', () {
      const parent1 = TranslatedField(
        name: 'ctrl',
        text: '0x3',
        hiBit: 7,
        loBit: 0,
        fields: [leaf],
      );
      const parent2 = TranslatedField(
        name: 'ctrl',
        text: '0x3',
        hiBit: 7,
        loBit: 0,
        fields: [leaf],
      );
      const parent3 = TranslatedField(
        name: 'ctrl',
        text: '0x3',
        hiBit: 7,
        loBit: 0,
        fields: [
          TranslatedField(name: 'len', text: '9', hiBit: 3, loBit: 0),
        ],
      );
      expect(parent1, equals(parent2));
      expect(parent1.hashCode, equals(parent2.hashCode));
      expect(parent1, isNot(parent3));
    });
  });

  group('copyWith', () {
    test('overrides only the provided fields', () {
      final updated = leaf.copyWith(text: '7', colorArgb: 0xFF00FF00);
      expect(updated.name, 'len');
      expect(updated.text, '7');
      expect(updated.hiBit, 3);
      expect(updated.loBit, 0);
      expect(updated.colorArgb, 0xFF00FF00);
    });

    test('no arguments returns an equal field', () {
      expect(leaf.copyWith(), equals(leaf));
    });
  });
}
