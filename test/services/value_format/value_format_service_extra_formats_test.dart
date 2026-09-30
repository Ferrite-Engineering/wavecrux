// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Extra coverage for the formats not exercised by
// `value_format_service_test.dart`: IEEE 754 single/double, Q-format fixed
// point, signed-magnitude, Gray code, and named-enum lookups. Kept in a
// separate file so the existing 777-line test stays focused on the
// integer-format-family branches.

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/services/value_format/value_format_service.dart';

const _svc = ValueFormatService();

String _bits32(int raw) => raw.toUnsigned(32).toRadixString(2).padLeft(32, '0');

void main() {
  group('ValueFormatService.format — IEEE 754 single', () {
    test('positive normal: 1.0f = 0x3F800000', () {
      final s = _svc.format(
        _bits32(0x3F800000),
        32,
        DisplayFormat.ieee754Single,
      );
      expect(double.parse(s), closeTo(1.0, 1e-9));
    });

    test('negative normal: -2.0f = 0xC0000000', () {
      final s = _svc.format(
        _bits32(0xC0000000),
        32,
        DisplayFormat.ieee754Single,
      );
      expect(double.parse(s), closeTo(-2.0, 1e-9));
    });

    test('zero', () {
      final s = _svc.format(
        _bits32(0x00000000),
        32,
        DisplayFormat.ieee754Single,
      );
      expect(double.parse(s), 0.0);
    });

    test('+Inf and -Inf', () {
      expect(
        _svc.format(_bits32(0x7F800000), 32, DisplayFormat.ieee754Single),
        '+Inf',
      );
      expect(
        _svc.format(_bits32(0xFF800000), 32, DisplayFormat.ieee754Single),
        '-Inf',
      );
    });

    test('NaN', () {
      expect(
        _svc.format(_bits32(0x7FC00000), 32, DisplayFormat.ieee754Single),
        'NaN',
      );
    });

    test('subnormal stays finite and non-zero', () {
      // Smallest positive subnormal: 0x00000001
      final s = _svc.format(
        _bits32(0x00000001),
        32,
        DisplayFormat.ieee754Single,
      );
      final value = double.parse(s);
      expect(value, greaterThan(0));
      expect(value.isFinite, isTrue);
    });

    test('x in the bit string → X', () {
      expect(
        _svc.format(
          '0011111110000000000000000000000x',
          32,
          DisplayFormat.ieee754Single,
        ),
        'X',
      );
    });

    test('z in the bit string → Z', () {
      expect(
        _svc.format(
          '0011111110000000000000000000000z',
          32,
          DisplayFormat.ieee754Single,
        ),
        'Z',
      );
    });
  });

  group('ValueFormatService.format — IEEE 754 double', () {
    String bits64(int high, int low) {
      final h = high.toUnsigned(32).toRadixString(2).padLeft(32, '0');
      final l = low.toUnsigned(32).toRadixString(2).padLeft(32, '0');
      return h + l;
    }

    test('positive normal: 1.0 = 0x3FF0_0000_0000_0000', () {
      final s = _svc.format(
        bits64(0x3FF00000, 0x00000000),
        64,
        DisplayFormat.ieee754Double,
      );
      expect(double.parse(s), closeTo(1.0, 1e-12));
    });

    test('+Inf and -Inf', () {
      expect(
        _svc.format(
          bits64(0x7FF00000, 0x00000000),
          64,
          DisplayFormat.ieee754Double,
        ),
        '+Inf',
      );
      expect(
        _svc.format(
          bits64(0xFFF00000, 0x00000000),
          64,
          DisplayFormat.ieee754Double,
        ),
        '-Inf',
      );
    });

    test('NaN', () {
      expect(
        _svc.format(
          bits64(0x7FF80000, 0x00000000),
          64,
          DisplayFormat.ieee754Double,
        ),
        'NaN',
      );
    });

    test('zero', () {
      expect(
        _svc.format(
          bits64(0x00000000, 0x00000000),
          64,
          DisplayFormat.ieee754Double,
        ),
        '0.0',
      );
    });

    test('x/z propagate to X/Z', () {
      expect(
        _svc.format(
          '${'0' * 63}x',
          64,
          DisplayFormat.ieee754Double,
        ),
        'X',
      );
      expect(
        _svc.format(
          '${'0' * 63}z',
          64,
          DisplayFormat.ieee754Double,
        ),
        'Z',
      );
    });
  });

  group('ValueFormatService.format — Q-format fixed point', () {
    test('default Q7.8 signed, value 1.5 = 0x0180 = 384', () {
      // Q7.8 → 384 / 2^8 = 1.5
      const cfg = <String, Object?>{'m': 7, 'n': 8, 'signed': true};
      // 16 bits total: 1 sign + 7 int + 8 frac.
      final s = _svc.format(
        '0000000110000000',
        16,
        DisplayFormat.fixedPointQ,
        cfg,
      );
      expect(s, '1.5');
    });

    test('signed Q7.8 negative value: -1.5 = 0xFE80', () {
      // 16-bit two's complement of 384 is 0xFE80 = 65152.
      const cfg = <String, Object?>{'m': 7, 'n': 8, 'signed': true};
      final s = _svc.format(
        '1111111010000000',
        16,
        DisplayFormat.fixedPointQ,
        cfg,
      );
      expect(s, '-1.5');
    });

    test('unsigned UQ4.4: 0x80 = 128 / 16 = 8.0', () {
      const cfg = <String, Object?>{'m': 4, 'n': 4, 'signed': false};
      final s = _svc.format('10000000', 8, DisplayFormat.fixedPointQ, cfg);
      expect(s, '8.0');
    });

    test('Q-format with n=0 yields a pure integer string', () {
      const cfg = <String, Object?>{'m': 8, 'n': 0, 'signed': true};
      final s = _svc.format(
        '0000000001111011',
        16,
        DisplayFormat.fixedPointQ,
        cfg,
      );
      // 123 with no fractional bits
      expect(s, '123');
    });

    test('x/z propagate', () {
      const cfg = <String, Object?>{'m': 7, 'n': 8, 'signed': true};
      expect(
        _svc.format('00000001x0000000', 16, DisplayFormat.fixedPointQ, cfg),
        'X',
      );
      expect(
        _svc.format('00000001z0000000', 16, DisplayFormat.fixedPointQ, cfg),
        'Z',
      );
    });

    test('null config falls back to the default Q7.8 signed', () {
      // 0x0080 = 128; with default n=8 that's 0.5.
      final s = _svc.format('0000000010000000', 16, DisplayFormat.fixedPointQ);
      expect(s, '0.5');
    });

    test('trailing zeros in fractional part trimmed but ≥ 1 digit', () {
      // 0x0100 = 256 → 256 / 256 = 1.0 — trimmed to "1.0", not "1." or "1.000000"
      const cfg = <String, Object?>{'m': 7, 'n': 8, 'signed': true};
      final s = _svc.format(
        '0000000100000000',
        16,
        DisplayFormat.fixedPointQ,
        cfg,
      );
      expect(s, '1.0');
    });
  });

  group('ValueFormatService.format — signed magnitude', () {
    test('positive value', () {
      // 0_0000101 (1+7 bits) → +5
      expect(
        _svc.format('00000101', 8, DisplayFormat.signedMagnitude),
        '5',
      );
    });

    test('negative value', () {
      // 1_0000101 → -5
      expect(
        _svc.format('10000101', 8, DisplayFormat.signedMagnitude),
        '−5',
      );
    });

    test('positive zero and negative zero are distinct outputs', () {
      expect(
        _svc.format('00000000', 8, DisplayFormat.signedMagnitude),
        '0',
      );
      // The implementation renders signed magnitude's negative-zero with a
      // unicode minus sign: "−0".
      expect(
        _svc.format('10000000', 8, DisplayFormat.signedMagnitude),
        '−0',
      );
    });

    test('x/z propagate', () {
      expect(
        _svc.format('1000000x', 8, DisplayFormat.signedMagnitude),
        'X',
      );
      expect(
        _svc.format('1000000z', 8, DisplayFormat.signedMagnitude),
        'Z',
      );
    });
  });

  group('ValueFormatService.format — Gray code', () {
    test('0b000 = gray 0 → 0', () {
      expect(_svc.format('000', 3, DisplayFormat.grayCode), '0');
    });

    test('0b001 = gray 1 → 1', () {
      expect(_svc.format('001', 3, DisplayFormat.grayCode), '1');
    });

    test('0b011 = gray 2 → 2', () {
      expect(_svc.format('011', 3, DisplayFormat.grayCode), '2');
    });

    test('0b010 = gray 3 → 3', () {
      expect(_svc.format('010', 3, DisplayFormat.grayCode), '3');
    });

    test('0b110 = gray 4 → 4', () {
      expect(_svc.format('110', 3, DisplayFormat.grayCode), '4');
    });

    test('all-bit sweep on a 3-bit Gray sequence', () {
      // Canonical 3-bit binary-reflected Gray sequence: 0..7
      const sequence = [
        ('000', '0'),
        ('001', '1'),
        ('011', '2'),
        ('010', '3'),
        ('110', '4'),
        ('111', '5'),
        ('101', '6'),
        ('100', '7'),
      ];
      for (final (gray, expected) in sequence) {
        expect(
          _svc.format(gray, 3, DisplayFormat.grayCode),
          expected,
          reason: 'gray $gray should decode to $expected',
        );
      }
    });

    test('x/z propagate', () {
      expect(_svc.format('00x', 3, DisplayFormat.grayCode), 'X');
      expect(_svc.format('00z', 3, DisplayFormat.grayCode), 'Z');
    });
  });

  group('ValueFormatService.format — named enum', () {
    final config = <String, Object?>{
      'entries': <Map<String, Object?>>[
        {'value': '0', 'label': 'IDLE'},
        {'value': '1', 'label': 'RUN'},
        {'value': '2', 'label': 'FAULT'},
      ],
    };

    test('known value resolves to label', () {
      expect(
        _svc.format('00', 2, DisplayFormat.namedEnum, config),
        'IDLE',
      );
      expect(
        _svc.format('01', 2, DisplayFormat.namedEnum, config),
        'RUN',
      );
      expect(
        _svc.format('10', 2, DisplayFormat.namedEnum, config),
        'FAULT',
      );
    });

    test('unknown value falls back to hex rendering', () {
      // 0b11 = 3 isn't in the enum table → hex fallback (3 → "3").
      expect(
        _svc.format('11', 2, DisplayFormat.namedEnum, config),
        '3',
      );
    });

    test('null config falls back to hex', () {
      expect(
        _svc.format('1010', 4, DisplayFormat.namedEnum),
        'a',
      );
    });

    test('x/z propagate', () {
      expect(_svc.format('0x', 2, DisplayFormat.namedEnum, config), 'X');
      expect(_svc.format('0z', 2, DisplayFormat.namedEnum, config), 'Z');
    });
  });

  group('ValueFormatService.defaultFormat', () {
    test('1-bit signal defaults to binary', () {
      expect(ValueFormatService.defaultFormat(1), DisplayFormat.binary);
    });

    test('multi-bit signal defaults to hexadecimal', () {
      expect(ValueFormatService.defaultFormat(2), DisplayFormat.hexadecimal);
      expect(ValueFormatService.defaultFormat(32), DisplayFormat.hexadecimal);
    });
  });

  group('ValueFormatService.format — edge cases', () {
    test('empty raw value returns unchanged', () {
      expect(_svc.format('', 8, DisplayFormat.hexadecimal), '');
    });

    test('real/analog passthrough (non-bit string skips formatting)', () {
      // A value like "3.14" doesn't normalize as bits and should pass
      // through any integer-style formatter.
      expect(_svc.format('3.14', 0, DisplayFormat.hexadecimal), '3.14');
      expect(_svc.format('r3.14', 0, DisplayFormat.hexadecimal), '3.14');
    });

    test('binary "b"-prefixed VCD vector is stripped', () {
      expect(_svc.format('b101', 4, DisplayFormat.hexadecimal), '5');
    });
  });
}
