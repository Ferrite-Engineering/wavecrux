// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/value_validity.dart';
import 'package:wavecrux/domain/models/translated_field.dart';
import 'package:wavecrux/domain/models/translation_result.dart';

void main() {
  group('defaults', () {
    test('fields empty, validity ok, colorArgb null', () {
      const r = TranslationResult(text: 'ff');
      expect(r.fields, isEmpty);
      expect(r.validity, ValueValidity.ok);
      expect(r.colorArgb, isNull);
    });
  });

  group('equality', () {
    test('same text + metadata are equal', () {
      const a = TranslationResult(text: '42');
      const b = TranslationResult(text: '42');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing text / validity / color are not equal', () {
      const base = TranslationResult(text: '42');
      expect(base, isNot(const TranslationResult(text: '43')));
      expect(
        base,
        isNot(
          const TranslationResult(text: '42', validity: ValueValidity.hasX),
        ),
      );
      expect(
        base,
        isNot(const TranslationResult(text: '42', colorArgb: 0xFF112233)),
      );
    });

    test('differing fields are not equal; identical fields are equal', () {
      const f1 = TranslatedField(name: 'a', text: '1', hiBit: 1, loBit: 0);
      const f2 = TranslatedField(name: 'b', text: '2', hiBit: 3, loBit: 2);
      const withF1a = TranslationResult(text: 'x', fields: [f1]);
      const withF1b = TranslationResult(text: 'x', fields: [f1]);
      const withF2 = TranslationResult(text: 'x', fields: [f2]);
      expect(withF1a, equals(withF1b));
      expect(withF1a.hashCode, equals(withF1b.hashCode));
      expect(withF1a, isNot(withF2));
    });
  });

  group('copyWith', () {
    test('overrides only the provided fields', () {
      const r = TranslationResult(text: 'ff');
      final updated = r.copyWith(
        validity: ValueValidity.hasZ,
        colorArgb: 0xFF00FF00,
      );
      expect(updated.text, 'ff');
      expect(updated.validity, ValueValidity.hasZ);
      expect(updated.colorArgb, 0xFF00FF00);
    });

    test('no arguments returns an equal result', () {
      const r = TranslationResult(text: 'ff', validity: ValueValidity.hasX);
      expect(r.copyWith(), equals(r));
    });
  });
}
