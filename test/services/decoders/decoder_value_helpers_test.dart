// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/decoders/decoder_value_helpers.dart';

void main() {
  group('isVcdHigh', () {
    test('true only for a definite 1 (scalar or b-prefixed)', () {
      expect(isVcdHigh('1'), isTrue);
      expect(isVcdHigh('b1'), isTrue);
      expect(isVcdHigh('B1'), isTrue);
      expect(isVcdHigh(' 1 '), isTrue, reason: 'surrounding whitespace ok');
      expect(isVcdHigh('b 1'), isTrue);
    });

    test('false for low, unknown, empty, and null', () {
      expect(isVcdHigh('0'), isFalse);
      expect(isVcdHigh('b0'), isFalse);
      expect(isVcdHigh('x'), isFalse);
      expect(isVcdHigh('z'), isFalse);
      expect(isVcdHigh('bx'), isFalse);
      expect(isVcdHigh(''), isFalse);
      expect(isVcdHigh(null), isFalse);
    });

    test('a multi-bit vector is not "high" (only the exact bit 1 is)', () {
      expect(isVcdHigh('b1010'), isFalse);
      expect(isVcdHigh('10'), isFalse);
    });
  });

  group('isVcdLow', () {
    test('true only for a definite 0 (scalar or b-prefixed)', () {
      expect(isVcdLow('0'), isTrue);
      expect(isVcdLow('b0'), isTrue);
      expect(isVcdLow('B0'), isTrue);
      expect(isVcdLow(' 0 '), isTrue);
    });

    test('false for high, unknown, empty, and null — indeterminate is not '
        'low (active-low callers must not fire on x/z)', () {
      expect(isVcdLow('1'), isFalse);
      expect(isVcdLow('x'), isFalse);
      expect(isVcdLow('z'), isFalse);
      expect(isVcdLow('bz'), isFalse);
      expect(isVcdLow(''), isFalse);
      expect(isVcdLow(null), isFalse);
    });

    test('high and low are mutually exclusive across the bit domain', () {
      for (final v in ['0', '1', 'x', 'z', 'b0', 'b1', null]) {
        expect(
          isVcdHigh(v) && isVcdLow(v),
          isFalse,
          reason: 'no value is both high and low ($v)',
        );
      }
    });
  });

  group('parseVcdVectorInt', () {
    test('parses binary payloads with or without a b/B prefix', () {
      expect(parseVcdVectorInt('b1010'), 10);
      expect(parseVcdVectorInt('B1010'), 10);
      expect(parseVcdVectorInt('1010'), 10);
      expect(parseVcdVectorInt('b 1010 '), 10, reason: 'inner/outer ws ok');
      expect(parseVcdVectorInt('0'), 0);
      expect(parseVcdVectorInt('b0'), 0);
    });

    test(
      'null for any x/z bit (upper or lower case), anywhere in the word',
      () {
        expect(parseVcdVectorInt('b10x0'), isNull);
        expect(parseVcdVectorInt('b10X0'), isNull);
        expect(parseVcdVectorInt('b10z0'), isNull);
        expect(parseVcdVectorInt('b10Z0'), isNull);
        expect(parseVcdVectorInt('x'), isNull);
        expect(parseVcdVectorInt('bxxxx'), isNull);
      },
    );

    test('null for null, an empty payload, or a non-binary string', () {
      expect(parseVcdVectorInt(null), isNull);
      expect(parseVcdVectorInt(''), isNull);
      expect(parseVcdVectorInt('b'), isNull, reason: 'prefix only');
      expect(parseVcdVectorInt('b   '), isNull, reason: 'whitespace only');
      expect(parseVcdVectorInt('hello'), isNull);
      // Decimal digits >1 are not valid base-2 → parse failure → null.
      expect(parseVcdVectorInt('b129'), isNull);
    });
  });

  group('intParam', () {
    const map = <String, dynamic>{
      'native': 7,
      'strNum': '42',
      'strBad': 'not-a-number',
      'wrongType': true,
    };

    test(
      'native int returned as-is',
      () => expect(intParam(map, 'native', 0), 7),
    );
    test('numeric string parsed', () => expect(intParam(map, 'strNum', 0), 42));
    test('unparseable string → fallback', () {
      expect(intParam(map, 'strBad', 99), 99);
    });
    test('wrong type → fallback', () {
      expect(intParam(map, 'wrongType', 99), 99);
    });
    test('missing key → fallback', () {
      expect(intParam(map, 'absent', 99), 99);
    });
  });

  group('stringParam', () {
    const map = <String, dynamic>{'s': 'hello', 'n': 5};

    test('string returned as-is', () {
      expect(stringParam(map, 's', 'fb'), 'hello');
    });
    test('non-string → fallback', () {
      expect(stringParam(map, 'n', 'fb'), 'fb');
    });
    test('missing key → fallback', () {
      expect(stringParam(map, 'absent', 'fb'), 'fb');
    });
  });

  group('boolParam', () {
    test('native bool returned as-is', () {
      expect(boolParam(const {'b': true}, 'b', false), isTrue);
      expect(boolParam(const {'b': false}, 'b', true), isFalse);
    });

    test('string coercion is case-insensitive and accepts 1/0', () {
      for (final t in ['true', 'True', 'TRUE', '1']) {
        expect(boolParam({'b': t}, 'b', false), isTrue, reason: t);
      }
      for (final f in ['false', 'False', 'FALSE', '0']) {
        expect(boolParam({'b': f}, 'b', true), isFalse, reason: f);
      }
    });

    test('unrecognised string, wrong type, or missing key → fallback', () {
      expect(boolParam(const {'b': 'maybe'}, 'b', true), isTrue);
      expect(boolParam(const {'b': 'maybe'}, 'b', false), isFalse);
      expect(boolParam(const {'b': 3}, 'b', true), isTrue);
      expect(boolParam(const {}, 'absent', true), isTrue);
      expect(boolParam(const {}, 'absent', false), isFalse);
    });
  });

  _lenientAndRendererGroups();
}

void _lenientAndRendererGroups() {
  group('vcdVectorWidth', () {
    test('counts binary digits after prefix/whitespace stripping', () {
      expect(vcdVectorWidth('1'), 1);
      expect(vcdVectorWidth('b1'), 1);
      expect(vcdVectorWidth('b00000001'), 8);
      // Leading whitespace before the `b` defeats the prefix check — the
      // same long-standing quirk the strict parsers have; asserted so a
      // future change to `_bareVector` cannot silently diverge from them.
      expect(vcdVectorWidth('b0101  '), 4);
      expect(vcdVectorWidth('  b0101  '), 5);
      expect(vcdVectorWidth('bxxxx'), 4);
    });

    test('null and empty payloads are width 0', () {
      expect(vcdVectorWidth(null), 0);
      expect(vcdVectorWidth('b'), 0);
      expect(vcdVectorWidth('   '), 0);
    });

    test('width drives an active-low inversion mask correctly', () {
      // The defect this guards: a 1-bit active-low error line idling at 1
      // inverted under a hardcoded 0xFF mask yields 0xFE, flagging every beat.
      const idleHigh = '1';
      final width = vcdVectorWidth(idleHigh);
      final mask = (1 << width) - 1;
      final raw = parseVcdVectorIntLenient(idleHigh);
      expect((~raw) & mask, 0);
      // …and an asserted (low) beat still reports an error.
      expect((~parseVcdVectorIntLenient('0')) & mask, 1);
    });
  });

  group('parseVcdVectorIntLenient', () {
    test('coerces x/z to 0 instead of rejecting the value', () {
      expect(parseVcdVectorIntLenient('b1x1'), 5);
      expect(parseVcdVectorIntLenient('bZ0Z1'), 1);
      expect(parseVcdVectorIntLenient('bxxxx'), 0);
    });

    test('parses ordinary values identically to the strict parser', () {
      for (final v in ['0', '1', 'b1010', 'b111  ', '  b111  ']) {
        expect(
          parseVcdVectorIntLenientOrNull(v),
          parseVcdVectorInt(v),
          reason: v,
        );
      }
    });

    test('null/empty yield the fallback; OrNull yields null', () {
      expect(parseVcdVectorIntLenient(null), 0);
      expect(parseVcdVectorIntLenient('b'), 0);
      expect(parseVcdVectorIntLenient(null, fallback: 7), 7);
      expect(parseVcdVectorIntLenientOrNull(null), isNull);
      expect(parseVcdVectorIntLenientOrNull('b'), isNull);
      expect(parseVcdVectorIntLenientOrNull('b1x'), 2);
    });
  });

  group('parseVcdVectorBigLenient', () {
    test('coerces x/z to 0 and handles buses wider than 63 bits', () {
      expect(parseVcdVectorBigLenient('b1x1'), BigInt.from(5));
      expect(
        parseVcdVectorBigLenient('b${'1' * 64}'),
        (BigInt.one << 64) - BigInt.one,
      );
    });

    test('null, empty, and unparseable payloads yield zero', () {
      expect(parseVcdVectorBigLenient(null), BigInt.zero);
      expect(parseVcdVectorBigLenient('b'), BigInt.zero);
    });
  });

  group('vcdVectorBytesLsbFirst', () {
    test('matches the BigInt shift-and-mask it replaces', () {
      const value = 'b11110000101010100000111100000001';
      final big = parseVcdVectorBigLenient(value);
      final mask = BigInt.from(0xFF);
      final expected = [
        for (var i = 0; i < 4; i++) ((big >> (8 * i)) & mask).toInt(),
      ];
      expect(vcdVectorBytesLsbFirst(value, 4), expected);
    });

    test('zero-fills high bytes when the vector is narrower', () {
      expect(vcdVectorBytesLsbFirst('b1', 4), [1, 0, 0, 0]);
      expect(vcdVectorBytesLsbFirst('b100000001', 4), [1, 1, 0, 0]);
    });

    test('drops digits above the requested byte count', () {
      expect(vcdVectorBytesLsbFirst('b1111111100000001', 1), [1]);
    });

    test('x/z digits contribute 0 bits', () {
      expect(vcdVectorBytesLsbFirst('bxxxxxxx1', 1), [1]);
      expect(vcdVectorBytesLsbFirst('bzzzzzzzz', 1), [0]);
    });

    test('null, empty, and non-positive counts yield zero-filled output', () {
      expect(vcdVectorBytesLsbFirst(null, 3), [0, 0, 0]);
      expect(vcdVectorBytesLsbFirst('b', 2), [0, 0]);
      expect(vcdVectorBytesLsbFirst('b1111', 0), isEmpty);
    });
  });

  group('bytesToHex / bytesToHexCapped', () {
    test('renders two lowercase characters per byte', () {
      expect(bytesToHex([0x00, 0x0f, 0xff, 0xa5]), '000fffa5');
      expect(bytesToHex(const []), isEmpty);
    });

    test('masks values to a byte', () {
      expect(bytesToHex([0x1ff, -1]), 'ffff');
    });

    test('under the cap the capped variant is byte-identical', () {
      final bytes = List<int>.generate(kDecoderPayloadHexMaxBytes, (i) => i);
      expect(bytesToHexCapped(bytes), bytesToHex(bytes));
    });

    test('over the cap it elides and reports the remainder', () {
      final bytes = List<int>.filled(kDecoderPayloadHexMaxBytes + 10, 0xAB);
      final out = bytesToHexCapped(bytes);
      expect(out, startsWith(bytesToHex(bytes.take(4).toList())));
      expect(out, endsWith('… (+10 more bytes)'));
      expect(out.length, lessThan(bytesToHex(bytes).length));
    });

    test('a non-positive cap disables capping', () {
      final bytes = List<int>.filled(1000, 0xAB);
      expect(bytesToHexCapped(bytes, maxBytes: 0), bytesToHex(bytes));
    });
  });

  group('joinCapped', () {
    test('under the cap it is a plain join', () {
      expect(joinCapped(['a', 'b', 'c']), 'a, b, c');
      expect(joinCapped(['a', 'b'], separator: ','), 'a,b');
    });

    test('over the cap it elides and reports the remainder', () {
      final parts = List<String>.generate(
        kDecoderPayloadMaxParts + 6,
        (i) => '$i',
      );
      expect(joinCapped(parts), endsWith(', … (+6 more)'));
      expect(joinCapped(parts, maxParts: 2), startsWith('0, 1, … (+'));
      expect(joinCapped(parts, maxParts: 2), endsWith(' more)'));
    });

    test('a non-positive cap disables capping', () {
      final parts = List<String>.generate(
        kDecoderPayloadMaxParts + 6,
        (i) => '$i',
      );
      expect(joinCapped(parts, maxParts: 0), parts.join(', '));
    });
  });
}
