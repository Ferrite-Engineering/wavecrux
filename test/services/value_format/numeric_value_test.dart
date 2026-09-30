// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/services/value_format/value_format_service.dart';

/// `numericValue` is the seam that lets a digital bus be drawn as a curve: it
/// answers "what number is this bit pattern" under a given display format.
///
/// The tests below exist mostly to pin the cases where the *rendered text* and
/// the *magnitude* disagree, because reaching for `double.parse(format(...))`
/// is the obvious wrong implementation and it fails silently.
void main() {
  const svc = ValueFormatService();

  double v(
    String raw,
    int width,
    DisplayFormat fmt, [
    Map<String, Object?>? cfg,
  ]) => svc.numericValue(raw, width, fmt, cfg);

  group('numericValue — radix formats read the bits as unsigned', () {
    test('hex, binary and octal all agree on the same bits', () {
      const bits = '11111111';
      expect(v(bits, 8, DisplayFormat.hexadecimal), 255);
      expect(v(bits, 8, DisplayFormat.binary), 255);
      expect(v(bits, 8, DisplayFormat.octal), 255);
      expect(v(bits, 8, DisplayFormat.unsignedDecimal), 255);
    });

    test('the radix is a display choice, not a different number', () {
      // The trap this guards: hex renders 0b000111100101 as "1e5", and
      // double.parse("1e5") is 100000 — 206× the real value.
      const bits = '000111100101';
      expect(svc.format(bits, 12, DisplayFormat.hexadecimal), '1e5');
      expect(v(bits, 12, DisplayFormat.hexadecimal), 485);
    });

    test('ASCII and named-enum fall back to the bus magnitude', () {
      // Neither has a magnitude of its own, but the bus still does, and that
      // is what GTKWave plots.
      expect(v('01000001', 8, DisplayFormat.ascii), 65);
      expect(v('00000011', 8, DisplayFormat.namedEnum), 3);
    });
  });

  group('numericValue — formats with a distinct numeric reading', () {
    test("signed decimal applies two's complement at the declared width", () {
      expect(v('11111111', 8, DisplayFormat.signedDecimal), -1);
      expect(v('10000000', 8, DisplayFormat.signedDecimal), -128);
      expect(v('01111111', 8, DisplayFormat.signedDecimal), 127);
      // Same bits, unsigned reading.
      expect(v('11111111', 8, DisplayFormat.unsignedDecimal), 255);
    });

    test(
      'a zero declared width reads unsigned rather than guessing a sign bit',
      () {
        expect(v('11111111', 0, DisplayFormat.signedDecimal), 255);
      },
    );

    test('sign-magnitude keeps negative zero distinct', () {
      expect(v('0000', 4, DisplayFormat.signedMagnitude), 0);
      // Sign-magnitude has a distinct −0 encoding. It compares equal to 0 (so
      // it plots on the zero line, which is right), but the sign bit survives
      // rather than being flattened away — `isNegative` on the double, not the
      // `isNegative` matcher, which asks `< 0` and is false for -0.0.
      final negZero = v('1000', 4, DisplayFormat.signedMagnitude);
      expect(negZero, 0);
      expect(negZero.isNegative, isTrue);
      expect(v('1011', 4, DisplayFormat.signedMagnitude), -3);
      expect(v('0011', 4, DisplayFormat.signedMagnitude), 3);
    });

    test('Gray code decodes before it is plotted', () {
      // A Gray counter is monotonic once decoded; plotting the raw bits would
      // render a sawtooth that does not exist in the design.
      const gray = ['000', '001', '011', '010', '110', '111', '101', '100'];
      final decoded = [
        for (final g in gray) v(g, 3, DisplayFormat.grayCode),
      ];
      expect(decoded, [0, 1, 2, 3, 4, 5, 6, 7]);
    });

    test('IEEE 754 single bit-casts', () {
      // 0x3F800000 == 1.0f, 0xC0000000 == -2.0f
      const one = '00111111100000000000000000000000';
      expect(one.length, 32);
      expect(v(one, 32, DisplayFormat.ieee754Single), 1.0);
      expect(
        v('11000000000000000000000000000000', 32, DisplayFormat.ieee754Single),
        -2.0,
      );
    });

    test('IEEE 754 double bit-casts', () {
      // 0x3FF0000000000000 == 1.0
      const one =
          '0011111111110000000000000000000000000000000000000000000000000000';
      expect(one.length, 64);
      expect(v(one, 64, DisplayFormat.ieee754Double), 1.0);
    });

    test('fixed-point Q scales by 2^n and keeps the fraction', () {
      // Q4.12 signed: 0x1800 == 6144 == 1.5
      const cfg = {'m': 4, 'n': 12, 'signed': true};
      expect(v('0001100000000000', 16, DisplayFormat.fixedPointQ, cfg), 1.5);
      // The same bits under hex are the raw integer — this is the whole point
      // of the format being orthogonal to the analog toggle.
      expect(v('0001100000000000', 16, DisplayFormat.hexadecimal), 6144);
    });

    test('fixed-point Q handles negative values', () {
      const cfg = {'m': 4, 'n': 12, 'signed': true};
      // -1.5 == -6144 == 0xE800 in 16-bit two's complement.
      expect(v('1110100000000000', 16, DisplayFormat.fixedPointQ, cfg), -1.5);
    });

    test('unsigned fixed-point Q never goes negative', () {
      const cfg = {'m': 4, 'n': 12, 'signed': false};
      expect(
        v('1110100000000000', 16, DisplayFormat.fixedPointQ, cfg),
        greaterThan(0),
      );
    });

    test('fixed-point Q with n == 0 is a plain integer', () {
      const cfg = {'m': 8, 'n': 0, 'signed': false};
      expect(v('00000101', 8, DisplayFormat.fixedPointQ, cfg), 5);
    });
  });

  group('numericValue — values with no magnitude become NaN, not zero', () {
    test('x and z anywhere in the bits', () {
      for (final fmt in DisplayFormat.values) {
        expect(v('0000x000', 8, fmt), isNaN, reason: '$fmt with x');
        expect(v('0000z000', 8, fmt), isNaN, reason: '$fmt with z');
      }
    });

    test('an empty value', () {
      expect(v('', 8, DisplayFormat.hexadecimal), isNaN);
    });

    test('a partially-unknown bus is a gap, never a plunge to zero', () {
      // The distinction that matters on a plot: 0 is a value the design could
      // legitimately hold, so rendering unknown as 0 invents data.
      expect(v('xxxxxxxx', 8, DisplayFormat.unsignedDecimal), isNaN);
      expect(v('00000000', 8, DisplayFormat.unsignedDecimal), 0);
    });
  });

  group('numericValue — real literals bypass the format entirely', () {
    test('a real value parses as itself', () {
      expect(v('3.14', 0, DisplayFormat.hexadecimal), closeTo(3.14, 1e-9));
      expect(v('-1.5e-3', 0, DisplayFormat.binary), closeTo(-0.0015, 1e-12));
    });

    test('the VCD r prefix is stripped', () {
      expect(v('r2.5', 0, DisplayFormat.hexadecimal), 2.5);
    });

    test('x / z / nan literals are gaps', () {
      expect(v('x', 0, DisplayFormat.hexadecimal), isNaN);
      expect(v('z', 0, DisplayFormat.hexadecimal), isNaN);
      expect(v('nan', 0, DisplayFormat.hexadecimal), isNaN);
    });

    test('an unparseable literal is a gap, not a throw', () {
      expect(v('not-a-number', 0, DisplayFormat.hexadecimal), isNaN);
    });
  });

  group('numericValue — agrees with format() where both are numeric', () {
    // Wherever the formatter already emits a decimal number, the two must not
    // disagree; a divergence would mean the value column and the curve are
    // telling the user different things about the same sample.
    const cases = <(String, int, DisplayFormat)>[
      ('11111111', 8, DisplayFormat.unsignedDecimal),
      ('11111111', 8, DisplayFormat.signedDecimal),
      ('10000001', 8, DisplayFormat.signedDecimal),
      ('0110', 4, DisplayFormat.grayCode),
    ];

    for (final (bits, width, fmt) in cases) {
      test('$fmt $bits', () {
        final text = svc.format(bits, width, fmt);
        expect(double.parse(text), v(bits, width, fmt));
      });
    }
  });
}
