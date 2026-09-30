// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart'
    show kTranslatorIdConfigKey;
import 'package:wavecrux/domain/models/translation_result.dart';
import 'package:wavecrux/plugins/translator_registry.dart';
import 'package:wavecrux/services/value_format/analog_value_extractor.dart';

/// A stand-in for a curated Pro translator (bf16, FP8, the pixel formats).
///
/// The point of the tests below is that open core never learns what any of
/// those *are* — a Pro translator reaches the analog renderer only by
/// returning a decimal number in [TranslationResult.text].
class _FakeProTranslator implements Translator {
  _FakeProTranslator(this.id, this._respond);

  @override
  final String id;
  final String Function(String raw) _respond;

  @override
  TranslationResult translate(TranslationRequest request) =>
      TranslationResult(text: _respond(request.rawValue));
}

class _ThrowingTranslator implements Translator {
  @override
  String get id => 'test.throws';

  @override
  TranslationResult translate(TranslationRequest request) =>
      throw StateError('translator blew up');
}

void main() {
  group('AnalogValueExtractors.real — the historical path is untouched', () {
    test('parses real literals', () {
      expect(AnalogValueExtractors.real('3.14'), closeTo(3.14, 1e-9));
      expect(AnalogValueExtractors.real('-1.5e-3'), closeTo(-0.0015, 1e-12));
      expect(AnalogValueExtractors.real('0.0'), 0.0);
    });

    test('x, z, empty and unparseable are gaps', () {
      expect(AnalogValueExtractors.real('x'), isNaN);
      expect(AnalogValueExtractors.real('z'), isNaN);
      expect(AnalogValueExtractors.real(''), isNaN);
      expect(AnalogValueExtractors.real('nan'), isNaN);
      expect(AnalogValueExtractors.real('garbage'), isNaN);
    });
  });

  group('forDigitalLane — built-in formats', () {
    test('reads the bus through the lane format, not the rendered text', () {
      final hex = AnalogValueExtractors.forDigitalLane(
        bitWidth: 12,
        format: DisplayFormat.hexadecimal,
      );
      expect(hex('000111100101'), 485); // renders "1e5"; is not 100000
    });

    test('Q4.12 and hex disagree on the same bits, as they should', () {
      const bits = '0001100000000000';
      final asHex = AnalogValueExtractors.forDigitalLane(
        bitWidth: 16,
        format: DisplayFormat.hexadecimal,
      );
      final asQ = AnalogValueExtractors.forDigitalLane(
        bitWidth: 16,
        format: DisplayFormat.fixedPointQ,
        config: const {'m': 4, 'n': 12, 'signed': true},
      );
      expect(asHex(bits), 6144);
      expect(asQ(bits), 1.5);
    });

    test('unknown bits are gaps', () {
      final f = AnalogValueExtractors.forDigitalLane(
        bitWidth: 8,
        format: DisplayFormat.unsignedDecimal,
      );
      expect(f('0000x000'), isNaN);
      expect(f('zzzzzzzz'), isNaN);
    });
  });

  group('forDigitalLane — the Pro translator seam', () {
    late TranslatorRegistry registry;

    setUp(() => registry = TranslatorRegistry());

    Map<String, Object?> bind(String id) => {kTranslatorIdConfigKey: id};

    test('a translator returning a decimal number is plotted verbatim', () {
      // This is the bf16 / FP8 case: open core has no idea how those bits
      // decode, and does not need to.
      registry.register(_FakeProTranslator('pro.mlFloat', (_) => '1.5'));
      final f = AnalogValueExtractors.forDigitalLane(
        bitWidth: 16,
        format: DisplayFormat.hexadecimal,
        config: bind('pro.mlFloat'),
        registry: registry,
      );
      expect(f('0011111111000000'), 1.5);
    });

    test('negative and exponent forms parse', () {
      registry.register(_FakeProTranslator('pro.ml', (_) => '-2.5e-3'));
      final f = AnalogValueExtractors.forDigitalLane(
        bitWidth: 16,
        format: DisplayFormat.hexadecimal,
        config: bind('pro.ml'),
        registry: registry,
      );
      expect(f('0000000000000000'), closeTo(-0.0025, 1e-12));
    });

    test('a label falls back to the bus magnitude rather than a gap', () {
      // A pixel-format or named-enum translator returns text with no
      // magnitude. The bus still has one, so plot that — a gap would lose the
      // trace entirely for a signal that is perfectly well defined.
      registry.register(_FakeProTranslator('pro.pixel', (_) => 'RGB565'));
      final f = AnalogValueExtractors.forDigitalLane(
        bitWidth: 8,
        format: DisplayFormat.unsignedDecimal,
        config: bind('pro.pixel'),
        registry: registry,
      );
      expect(f('00001010'), 10);
    });

    test('an X / Z answer from a translator is a gap', () {
      registry.register(_FakeProTranslator('pro.x', (_) => 'X'));
      final f = AnalogValueExtractors.forDigitalLane(
        bitWidth: 8,
        format: DisplayFormat.unsignedDecimal,
        config: bind('pro.x'),
        registry: registry,
      );
      expect(f('00001010'), isNaN);
    });

    test('a translator that throws does not take the canvas down', () {
      registry.register(_ThrowingTranslator());
      final f = AnalogValueExtractors.forDigitalLane(
        bitWidth: 8,
        format: DisplayFormat.unsignedDecimal,
        config: bind('test.throws'),
        registry: registry,
      );
      expect(f('00001010'), 10); // fell back to the built-in reading
    });

    test(
      'an unresolvable translator id falls back to the built-in reading',
      () {
        final f = AnalogValueExtractors.forDigitalLane(
          bitWidth: 8,
          format: DisplayFormat.unsignedDecimal,
          config: bind('pro.doesNotExist'),
          registry: registry,
        );
        expect(f('00001010'), 10);
      },
    );

    test('the built-in id short-circuits the registry entirely', () {
      final f = AnalogValueExtractors.forDigitalLane(
        bitWidth: 8,
        format: DisplayFormat.unsignedDecimal,
        config: bind(TranslatorRegistry.builtinId),
        registry: registry,
      );
      expect(f('00001010'), 10);
    });
  });

  group('parseTranslatedText', () {
    test('accepts ordinary decimals', () {
      expect(AnalogValueExtractors.parseTranslatedText('42'), 42);
      expect(AnalogValueExtractors.parseTranslatedText('-3.5'), -3.5);
      expect(AnalogValueExtractors.parseTranslatedText('  1.25  '), 1.25);
    });

    test('accepts the Unicode minus the sign-magnitude formatter emits', () {
      // U+2212, not ASCII hyphen. double.tryParse rejects it outright.
      expect(AnalogValueExtractors.parseTranslatedText('−7'), -7);
    });

    test('maps the unknown-value sentinels to NaN', () {
      expect(AnalogValueExtractors.parseTranslatedText('X'), isNaN);
      expect(AnalogValueExtractors.parseTranslatedText('z'), isNaN);
      expect(AnalogValueExtractors.parseTranslatedText('NaN'), isNaN);
    });

    test('rejects text that is not a number', () {
      expect(AnalogValueExtractors.parseTranslatedText('ff'), isNull);
      expect(AnalogValueExtractors.parseTranslatedText('IDLE'), isNull);
      expect(AnalogValueExtractors.parseTranslatedText(''), isNull);
    });

    test('rejects the word Infinity, which double.tryParse would accept', () {
      // A translator naming infinity is describing a value, not giving an axis
      // a bound to scale to.
      expect(AnalogValueExtractors.parseTranslatedText('Infinity'), isNull);
      expect(AnalogValueExtractors.parseTranslatedText('-Infinity'), isNull);
    });
  });
}
