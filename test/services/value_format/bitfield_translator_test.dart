// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/value_validity.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/services/value_format/bitfield_translator.dart';

void main() {
  const translator = BitfieldTranslator();

  Map<String, Object?> cfg(BitfieldTranslatorConfig c) => {
    ...c.toMap(),
    kTranslatorIdConfigKey: BitfieldTranslator.translatorId,
  };

  group('BitfieldTranslator', () {
    test('id', () {
      expect(translator.id, 'builtin.bitfield');
    });

    test('decodes simple fields (MSB-indexed slices)', () {
      const config = BitfieldTranslatorConfig(
        fields: [
          BitFieldSpec(
            name: 'valid',
            hiBit: 15,
            loBit: 15,
            format: DisplayFormat.binary,
          ),
          BitFieldSpec(name: 'len', hiBit: 14, loBit: 8),
          BitFieldSpec(name: 'addr', hiBit: 7, loBit: 0),
        ],
      );
      // bit15=1, bits14..8 = 0001000 (0x08), bits7..0 = 10000001 (0x81)
      const raw = '1000100010000001';
      final result = translator.translate(
        TranslationRequest(
          rawValue: raw,
          bitWidth: 16,
          format: DisplayFormat.hexadecimal,
          config: cfg(config),
        ),
      );

      expect(result.fields, hasLength(3));
      expect(result.fields[0].name, 'valid');
      expect(result.fields[0].text, '1');
      expect(result.fields[0].hiBit, 15);
      expect(result.fields[1].name, 'len');
      expect(result.fields[1].text, '08'); // 7-bit hex pads to a nibble
      expect(result.fields[2].name, 'addr');
      expect(result.fields[2].text, '81');
      expect(result.text, '{valid=1, len=08, addr=81}');
      expect(result.validity, ValueValidity.ok);
    });

    test('enum subfield resolves via subConfig table', () {
      const config = BitfieldTranslatorConfig(
        fields: [
          BitFieldSpec(
            name: 'state',
            hiBit: 1,
            loBit: 0,
            format: DisplayFormat.namedEnum,
            subConfig: {
              'entries': [
                {'value': '2', 'label': 'RUN'},
              ],
            },
          ),
        ],
      );
      final result = translator.translate(
        TranslationRequest(
          rawValue: '10', // value 2
          bitWidth: 2,
          format: DisplayFormat.hexadecimal,
          config: cfg(config),
        ),
      );
      expect(result.fields.single.text, 'RUN');
    });

    test('nested struct-in-struct decomposes recursively', () {
      const inner = BitfieldTranslatorConfig(
        fields: [
          BitFieldSpec(name: 'hi', hiBit: 3, loBit: 2),
          BitFieldSpec(name: 'lo', hiBit: 1, loBit: 0),
        ],
      );
      final config = BitfieldTranslatorConfig(
        fields: [
          BitFieldSpec(
            name: 'nibble',
            hiBit: 3,
            loBit: 0,
            subConfig: inner.toMap(),
          ),
        ],
      );
      final result = translator.translate(
        TranslationRequest(
          rawValue: '1001',
          bitWidth: 4,
          format: DisplayFormat.hexadecimal,
          config: cfg(config),
        ),
      );
      final nibble = result.fields.single;
      expect(nibble.name, 'nibble');
      expect(nibble.fields, hasLength(2));
      expect(nibble.fields[0].name, 'hi');
      expect(nibble.fields[1].name, 'lo');
    });

    test('x/z propagate per field and to overall validity', () {
      const config = BitfieldTranslatorConfig(
        fields: [
          BitFieldSpec(name: 'a', hiBit: 3, loBit: 2),
          BitFieldSpec(name: 'b', hiBit: 1, loBit: 0),
        ],
      );
      final result = translator.translate(
        TranslationRequest(
          rawValue: '11xx',
          bitWidth: 4,
          format: DisplayFormat.hexadecimal,
          config: cfg(config),
        ),
      );
      expect(result.validity, ValueValidity.hasX);
      expect(result.fields[0].text, '3');
      expect(result.fields[1].text, 'x'); // hex of "xx"
    });

    test('invalid config (no valid specs) falls back to flat format', () {
      const config = BitfieldTranslatorConfig(
        fields: [
          BitFieldSpec(name: 'oops', hiBit: 99, loBit: 50),
        ],
      );
      final result = translator.translate(
        TranslationRequest(
          rawValue: '1111',
          bitWidth: 4,
          format: DisplayFormat.hexadecimal,
          config: cfg(config),
        ),
      );
      expect(result.fields, isEmpty);
      expect(result.text, 'f'); // flat hex
    });

    test('missing config falls back to flat format', () {
      final result = translator.translate(
        const TranslationRequest(
          rawValue: '1010',
          bitWidth: 4,
          format: DisplayFormat.hexadecimal,
        ),
      );
      expect(result.fields, isEmpty);
      expect(result.text, 'a');
    });

    test(
      'an out-of-range field among valid ones renders X but keeps its row',
      () {
        const config = BitfieldTranslatorConfig(
          fields: [
            BitFieldSpec(name: 'good', hiBit: 3, loBit: 0),
            BitFieldSpec(name: 'bad', hiBit: 99, loBit: 0),
          ],
        );
        final result = translator.translate(
          TranslationRequest(
            rawValue: '1111',
            bitWidth: 4,
            format: DisplayFormat.hexadecimal,
            config: cfg(config),
          ),
        );
        // Row count stays 2 so it matches the reserved child-row geometry.
        expect(result.fields, hasLength(2));
        expect(result.fields[1].text, 'X');
      },
    );

    test('web/desktop parity: pure-Dart output is identical and deterministic', () {
      // The translator uses only String slicing + the built-in formatter — no
      // FFI, no platform channels — so it must produce byte-identical output on
      // the VM (desktop/mobile) and the WASM (web) build. We assert determinism
      // here; the same code path runs unchanged under dart2wasm.
      const config = BitfieldTranslatorConfig(
        fields: [
          BitFieldSpec(name: 'a', hiBit: 7, loBit: 4),
          BitFieldSpec(name: 'b', hiBit: 3, loBit: 0),
        ],
      );
      final req = TranslationRequest(
        rawValue: '10110010',
        bitWidth: 8,
        format: DisplayFormat.hexadecimal,
        config: cfg(config),
      );
      final first = translator.translate(req);
      final second = translator.translate(req);
      expect(first, second);
      expect(first.text, '{a=b, b=2}');
    });

    test('childRowCount counts declared fields (ChildRowTranslator)', () {
      const config = BitfieldTranslatorConfig(
        fields: [
          BitFieldSpec(name: 'a', hiBit: 1, loBit: 0),
          BitFieldSpec(name: 'b', hiBit: 3, loBit: 2),
        ],
      );
      // One reserved child row per declared field. The translator-id marker is
      // matched by the registry before this is called, so the count itself is
      // purely the field tally.
      expect(translator.childRowCount(cfg(config)), 2);
      // No `fields` payload → no child rows.
      expect(
        translator.childRowCount(
          const {kTranslatorIdConfigKey: BitfieldTranslator.translatorId},
        ),
        0,
      );
      expect(translator.childRowCount(null), 0);
    });
  });
}
