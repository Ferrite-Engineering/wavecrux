// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/value_validity.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/services/value_format/builtin_value_translator.dart';
import 'package:wavecrux/services/value_format/value_format_service.dart';

void main() {
  const translator = BuiltinValueTranslator();
  const service = ValueFormatService();

  test('id is the stable builtin id', () {
    expect(translator.id, 'builtin.valueFormat');
    expect(BuiltinValueTranslator.translatorId, 'builtin.valueFormat');
  });

  test('text delegates verbatim to ValueFormatService', () {
    for (final format in DisplayFormat.values) {
      const raw = '10110010';
      final result = translator.translate(
        TranslationRequest(
          rawValue: raw,
          bitWidth: 8,
          format: format,
        ),
      );
      expect(result.text, service.format(raw, 8, format));
    }
  });

  test('config is forwarded (fixedPointQ)', () {
    const raw = '0010000000000000'; // Q1.15 → 0.25
    const config = {'m': 1, 'n': 15, 'signed': true};
    final result = translator.translate(
      const TranslationRequest(
        rawValue: raw,
        bitWidth: 16,
        format: DisplayFormat.fixedPointQ,
        config: config,
      ),
    );
    expect(
      result.text,
      service.format(raw, 16, DisplayFormat.fixedPointQ, config),
    );
  });

  group('validity', () {
    test('clean value → ok and no fields', () {
      final result = translator.translate(
        const TranslationRequest(
          rawValue: '1010',
          bitWidth: 4,
          format: DisplayFormat.hexadecimal,
        ),
      );
      expect(result.validity, ValueValidity.ok);
      expect(result.fields, isEmpty);
    });

    test('x present → hasX', () {
      final result = translator.translate(
        const TranslationRequest(
          rawValue: '10x0',
          bitWidth: 4,
          format: DisplayFormat.hexadecimal,
        ),
      );
      expect(result.validity, ValueValidity.hasX);
    });

    test('z present (no x) → hasZ', () {
      final result = translator.translate(
        const TranslationRequest(
          rawValue: '10z0',
          bitWidth: 4,
          format: DisplayFormat.hexadecimal,
        ),
      );
      expect(result.validity, ValueValidity.hasZ);
    });

    test('x dominates z → hasX', () {
      final result = translator.translate(
        const TranslationRequest(
          rawValue: 'x1z0',
          bitWidth: 4,
          format: DisplayFormat.hexadecimal,
        ),
      );
      expect(result.validity, ValueValidity.hasX);
    });

    test('uppercase X/Z are detected', () {
      expect(
        translator
            .translate(
              const TranslationRequest(
                rawValue: '10X0',
                bitWidth: 4,
                format: DisplayFormat.binary,
              ),
            )
            .validity,
        ValueValidity.hasX,
      );
      expect(
        translator
            .translate(
              const TranslationRequest(
                rawValue: '10Z0',
                bitWidth: 4,
                format: DisplayFormat.binary,
              ),
            )
            .validity,
        ValueValidity.hasZ,
      );
    });
  });
}
