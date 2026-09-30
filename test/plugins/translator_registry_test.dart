// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/models/translation_result.dart';
import 'package:wavecrux/plugins/translator_registry.dart';
import 'package:wavecrux/services/value_format/value_format_service.dart';

/// A stub translator used to prove registration / override behavior.
class _UpperEchoTranslator implements Translator {
  const _UpperEchoTranslator();

  @override
  String get id => 'test.upperEcho';

  @override
  TranslationResult translate(TranslationRequest request) =>
      TranslationResult(text: request.rawValue.toUpperCase());
}

/// A translator that masquerades as the built-in id to prove last-write-wins.
class _ShadowBuiltinTranslator implements Translator {
  const _ShadowBuiltinTranslator();

  @override
  String get id => TranslatorRegistry.builtinId;

  @override
  TranslationResult translate(TranslationRequest request) =>
      const TranslationResult(text: 'SHADOWED');
}

void main() {
  group('TranslatorRegistry (plain)', () {
    test('default constructor seeds the built-in translator', () {
      final registry = TranslatorRegistry();
      expect(registry.isRegistered(TranslatorRegistry.builtinId), isTrue);
      expect(registry.get(TranslatorRegistry.builtinId), isNotNull);
    });

    test(
      'default constructor also seeds the declarative bitfield translator',
      () {
        final registry = TranslatorRegistry();
        expect(registry.isRegistered('builtin.bitfield'), isTrue);
      },
    );

    test('empty() has no built-in seeded', () {
      final registry = TranslatorRegistry.empty();
      expect(registry.isRegistered(TranslatorRegistry.builtinId), isFalse);
    });

    test('resolve falls back to built-in for null / unknown id', () {
      final registry = TranslatorRegistry();
      expect(registry.resolve().id, TranslatorRegistry.builtinId);
      expect(
        registry.resolve('does.not.exist').id,
        TranslatorRegistry.builtinId,
      );
    });

    test('resolve returns the registered translator for a known id', () {
      final registry = TranslatorRegistry()
        ..register(const _UpperEchoTranslator());
      expect(registry.resolve('test.upperEcho').id, 'test.upperEcho');
    });

    test('translate convenience resolves + delegates', () {
      final registry = TranslatorRegistry()
        ..register(const _UpperEchoTranslator());
      final result = registry.translate(
        const TranslationRequest(
          rawValue: 'abc',
          bitWidth: 0,
          format: DisplayFormat.ascii,
        ),
        translatorId: 'test.upperEcho',
      );
      expect(result.text, 'ABC');
    });

    test('register replaces an existing id (last write wins)', () {
      final registry = TranslatorRegistry()
        ..register(const _ShadowBuiltinTranslator());
      final result = registry.translate(
        const TranslationRequest(
          rawValue: '1010',
          bitWidth: 4,
          format: DisplayFormat.hexadecimal,
        ),
      );
      expect(result.text, 'SHADOWED');
    });

    test('unregister removes a translator', () {
      final registry = TranslatorRegistry()
        ..register(const _UpperEchoTranslator());
      expect(registry.unregister('test.upperEcho'), isTrue);
      expect(registry.isRegistered('test.upperEcho'), isFalse);
      expect(registry.unregister('test.upperEcho'), isFalse);
    });
  });

  group('translatorRegistryProvider', () {
    test('built-in resolves with no overrides', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final registry = container.read(translatorRegistryProvider);
      expect(registry.resolve().id, TranslatorRegistry.builtinId);
    });

    test('overriding extraTranslatorsProvider contributes a translator', () {
      final container = ProviderContainer(
        overrides: [
          extraTranslatorsProvider.overrideWithValue(
            const [_UpperEchoTranslator()],
          ),
        ],
      );
      addTearDown(container.dispose);

      final registry = container.read(translatorRegistryProvider);
      expect(registry.isRegistered('test.upperEcho'), isTrue);
      expect(registry.resolve('test.upperEcho').id, 'test.upperEcho');
      // Built-in is still present.
      expect(registry.isRegistered(TranslatorRegistry.builtinId), isTrue);
    });

    test('an extra translator can override the built-in id and wins', () {
      final container = ProviderContainer(
        overrides: [
          extraTranslatorsProvider.overrideWithValue(
            const [_ShadowBuiltinTranslator()],
          ),
        ],
      );
      addTearDown(container.dispose);

      final registry = container.read(translatorRegistryProvider);
      final result = registry.translate(
        const TranslationRequest(
          rawValue: '1010',
          bitWidth: 4,
          format: DisplayFormat.hexadecimal,
        ),
      );
      expect(result.text, 'SHADOWED');
    });
  });

  // ── Call-site parity ────────────────────────────────────────────────────────
  // The built-in translator's text must be byte-for-byte identical to the
  // legacy ValueFormatService.format() output for every DisplayFormat across a
  // representative value matrix (incl. x/z, real, narrow/wide). This is the
  // guarantee that the registry refactor introduces no rendering change.
  group('built-in parity with ValueFormatService', () {
    const service = ValueFormatService();
    final registry = TranslatorRegistry();

    final cases = <({String raw, int width, Map<String, Object?>? config})>[
      (raw: '', width: 0, config: null),
      (raw: '0', width: 1, config: null),
      (raw: '1', width: 1, config: null),
      (raw: 'x', width: 1, config: null),
      (raw: 'z', width: 1, config: null),
      (raw: '1010', width: 4, config: null),
      (raw: '10110010', width: 8, config: null),
      (raw: '1010xxzz', width: 8, config: null),
      (raw: 'b1111', width: 4, config: null),
      (raw: '11111111111111110000000000000000', width: 32, config: null),
      (
        raw: '0100000010010000000000000000000000000000000000000000000000000000',
        width: 64,
        config: null,
      ),
      (raw: '3.14', width: 0, config: null),
      (raw: 'r-1.5e-3', width: 0, config: null),
      (
        raw: '0010000000000000',
        width: 16,
        config: {'m': 1, 'n': 15, 'signed': true},
      ),
      (
        raw: '0011',
        width: 4,
        config: {
          'entries': [
            {'value': '3', 'label': 'THREE'},
          ],
        },
      ),
    ];

    for (final c in cases) {
      for (final format in DisplayFormat.values) {
        test('${format.name} | "${c.raw}" (w=${c.width})', () {
          final expected = service.format(c.raw, c.width, format, c.config);
          final actual = registry
              .translate(
                TranslationRequest(
                  rawValue: c.raw,
                  bitWidth: c.width,
                  format: format,
                  config: c.config,
                ),
              )
              .text;
          expect(actual, expected);
        });
      }
    }
  });
}
