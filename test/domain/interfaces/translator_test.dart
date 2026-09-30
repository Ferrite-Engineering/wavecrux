// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';

void main() {
  group('TranslationRequest equality', () {
    test('same fields (incl. config) are equal', () {
      const a = TranslationRequest(
        rawValue: '1010',
        bitWidth: 4,
        format: DisplayFormat.hexadecimal,
        config: {'m': 1, 'n': 15},
      );
      const b = TranslationRequest(
        rawValue: '1010',
        bitWidth: 4,
        format: DisplayFormat.hexadecimal,
        config: {'m': 1, 'n': 15},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing rawValue / bitWidth / format are not equal', () {
      const base = TranslationRequest(
        rawValue: '1010',
        bitWidth: 4,
        format: DisplayFormat.hexadecimal,
      );
      expect(
        base,
        isNot(
          const TranslationRequest(
            rawValue: '1011',
            bitWidth: 4,
            format: DisplayFormat.hexadecimal,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const TranslationRequest(
            rawValue: '1010',
            bitWidth: 8,
            format: DisplayFormat.hexadecimal,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const TranslationRequest(
            rawValue: '1010',
            bitWidth: 4,
            format: DisplayFormat.binary,
          ),
        ),
      );
    });

    test('differing config (value, presence, null vs empty) are not equal', () {
      const withConfig = TranslationRequest(
        rawValue: '1010',
        bitWidth: 4,
        format: DisplayFormat.namedEnum,
        config: {'k': 1},
      );
      const differentValue = TranslationRequest(
        rawValue: '1010',
        bitWidth: 4,
        format: DisplayFormat.namedEnum,
        config: {'k': 2},
      );
      const noConfig = TranslationRequest(
        rawValue: '1010',
        bitWidth: 4,
        format: DisplayFormat.namedEnum,
      );
      expect(withConfig, isNot(differentValue));
      expect(withConfig, isNot(noConfig));
    });
  });
}
