// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';

void main() {
  group('BitFieldSpec', () {
    test('width and isValidFor', () {
      const spec = BitFieldSpec(name: 'a', hiBit: 7, loBit: 0);
      expect(spec.width, 8);
      expect(spec.isValidFor(8), isTrue);
      expect(spec.isValidFor(7), isFalse); // hiBit 7 out of range for width 7
      const bad = BitFieldSpec(name: 'b', hiBit: 2, loBit: 5);
      expect(bad.isValidFor(8), isFalse); // hi < lo
      const noName = BitFieldSpec(name: '', hiBit: 1, loBit: 0);
      expect(noName.isValidFor(8), isFalse);
    });

    test('fromMap/toMap round-trip preserves format and subConfig', () {
      const spec = BitFieldSpec(
        name: 'mode',
        hiBit: 3,
        loBit: 0,
        format: DisplayFormat.namedEnum,
        subConfig: {
          'entries': [
            {'value': '0', 'label': 'IDLE'},
          ],
        },
      );
      final restored = BitFieldSpec.fromMap(spec.toMap());
      expect(restored, spec);
      expect(restored.format, DisplayFormat.namedEnum);
      expect(restored.subConfig, isNotNull);
    });

    test('fromMap tolerates missing keys with defaults', () {
      final spec = BitFieldSpec.fromMap(const {});
      expect(spec.name, '');
      expect(spec.hiBit, 0);
      expect(spec.loBit, 0);
      expect(spec.format, DisplayFormat.hexadecimal);
    });

    test('unknown format name falls back to hexadecimal', () {
      final spec = BitFieldSpec.fromMap(const {
        'name': 'x',
        'hiBit': 1,
        'loBit': 0,
        'format': 'not_a_real_format',
      });
      expect(spec.format, DisplayFormat.hexadecimal);
    });
  });

  group('BitfieldTranslatorConfig', () {
    const config = BitfieldTranslatorConfig(
      fields: [
        BitFieldSpec(
          name: 'valid',
          hiBit: 15,
          loBit: 15,
          format: DisplayFormat.binary,
        ),
        BitFieldSpec(name: 'len', hiBit: 14, loBit: 7),
        BitFieldSpec(name: 'addr', hiBit: 6, loBit: 0),
      ],
    );

    test('fromMap/toMap round-trip', () {
      final restored = BitfieldTranslatorConfig.fromMap(config.toMap());
      expect(restored, config);
      expect(restored.fields, hasLength(3));
    });

    test('equality and hashCode', () {
      final a = BitfieldTranslatorConfig.fromMap(config.toMap());
      final b = BitfieldTranslatorConfig.fromMap(config.toMap());
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      const different = BitfieldTranslatorConfig(
        fields: [
          BitFieldSpec(name: 'only', hiBit: 0, loBit: 0),
        ],
      );
      expect(a == different, isFalse);
    });

    test('empty config round-trips', () {
      const empty = BitfieldTranslatorConfig();
      final restored = BitfieldTranslatorConfig.fromMap(empty.toMap());
      expect(restored, empty);
      expect(restored.fields, isEmpty);
    });
  });
}
