// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/services/value_format/value_format_service.dart';

void main() {
  const svc = ValueFormatService();

  // ── defaultFormat ──────────────────────────────────────────────────────────

  group('defaultFormat', () {
    test('1-bit → binary', () {
      expect(ValueFormatService.defaultFormat(1), DisplayFormat.binary);
    });

    test('4-bit → hexadecimal', () {
      expect(ValueFormatService.defaultFormat(4), DisplayFormat.hexadecimal);
    });

    test('8-bit → hexadecimal', () {
      expect(ValueFormatService.defaultFormat(8), DisplayFormat.hexadecimal);
    });

    test('64-bit → hexadecimal', () {
      expect(ValueFormatService.defaultFormat(64), DisplayFormat.hexadecimal);
    });
  });

  // ── binary format ──────────────────────────────────────────────────────────

  group('binary', () {
    test('scalar 0', () {
      expect(svc.format('0', 1, DisplayFormat.binary), '0');
    });

    test('scalar 1', () {
      expect(svc.format('1', 1, DisplayFormat.binary), '1');
    });

    test('scalar x', () {
      expect(svc.format('x', 1, DisplayFormat.binary), 'x');
    });

    test('scalar z', () {
      expect(svc.format('z', 1, DisplayFormat.binary), 'z');
    });

    test('4-bit all zeros', () {
      expect(svc.format('0000', 4, DisplayFormat.binary), '0000');
    });

    test('4-bit all ones', () {
      expect(svc.format('1111', 4, DisplayFormat.binary), '1111');
    });

    test('4-bit all x', () {
      expect(svc.format('xxxx', 4, DisplayFormat.binary), 'xxxx');
    });

    test('4-bit all z', () {
      expect(svc.format('zzzz', 4, DisplayFormat.binary), 'zzzz');
    });

    test('4-bit mixed x/z', () {
      expect(svc.format('x0x1', 4, DisplayFormat.binary), 'x0x1');
    });

    test('8-bit alternating', () {
      expect(svc.format('10101010', 8, DisplayFormat.binary), '10101010');
    });

    test('8-bit mixed x/z pattern', () {
      expect(svc.format('x0x1z0z1', 8, DisplayFormat.binary), 'x0x1z0z1');
    });

    test('strips b prefix', () {
      expect(svc.format('b1010', 4, DisplayFormat.binary), '1010');
    });

    test('strips uppercase B prefix', () {
      expect(svc.format('B1010', 4, DisplayFormat.binary), '1010');
    });

    test('shorter value is zero-padded to bitWidth', () {
      expect(svc.format('01', 4, DisplayFormat.binary), '0001');
    });

    test('16-bit', () {
      expect(
        svc.format('0101010101010101', 16, DisplayFormat.binary),
        '0101010101010101',
      );
    });

    test('32-bit all ones', () {
      expect(
        svc.format('1' * 32, 32, DisplayFormat.binary),
        '1' * 32,
      );
    });
  });

  // ── hexadecimal format ─────────────────────────────────────────────────────

  group('hexadecimal', () {
    test('scalar 0', () {
      expect(svc.format('0', 1, DisplayFormat.hexadecimal), '0');
    });

    test('scalar 1', () {
      expect(svc.format('1', 1, DisplayFormat.hexadecimal), '1');
    });

    test('scalar x → x', () {
      expect(svc.format('x', 1, DisplayFormat.hexadecimal), 'x');
    });

    test('scalar z → z', () {
      expect(svc.format('z', 1, DisplayFormat.hexadecimal), 'z');
    });

    test('4-bit 0000 → 0', () {
      expect(svc.format('0000', 4, DisplayFormat.hexadecimal), '0');
    });

    test('4-bit 1111 → f', () {
      expect(svc.format('1111', 4, DisplayFormat.hexadecimal), 'f');
    });

    test('4-bit 1010 → a', () {
      expect(svc.format('1010', 4, DisplayFormat.hexadecimal), 'a');
    });

    test('4-bit xxxx → x (all unknown)', () {
      expect(svc.format('xxxx', 4, DisplayFormat.hexadecimal), 'x');
    });

    test('4-bit zzzz → z (all hi-z)', () {
      expect(svc.format('zzzz', 4, DisplayFormat.hexadecimal), 'z');
    });

    test('4-bit 0xxx → x (partial x in nibble)', () {
      expect(svc.format('0xxx', 4, DisplayFormat.hexadecimal), 'x');
    });

    test('4-bit x0x1 → x (any x in nibble)', () {
      expect(svc.format('x0x1', 4, DisplayFormat.hexadecimal), 'x');
    });

    test('4-bit z0z1 → z (any z, no x)', () {
      expect(svc.format('z0z1', 4, DisplayFormat.hexadecimal), 'z');
    });

    test('4-bit 0001 → 1', () {
      expect(svc.format('0001', 4, DisplayFormat.hexadecimal), '1');
    });

    test('8-bit 11001010 → ca (fixture: byte8 at t=10)', () {
      expect(svc.format('11001010', 8, DisplayFormat.hexadecimal), 'ca');
    });

    test('8-bit 10101010 → aa (fixture: byte8 at t=30)', () {
      expect(svc.format('10101010', 8, DisplayFormat.hexadecimal), 'aa');
    });

    test('8-bit 0000xxxx → 0x (first nibble clean, second all-x)', () {
      expect(svc.format('0000xxxx', 8, DisplayFormat.hexadecimal), '0x');
    });

    test('8-bit 1111zzzz → fz (first nibble clean, second all-z)', () {
      expect(svc.format('1111zzzz', 8, DisplayFormat.hexadecimal), 'fz');
    });

    test('8-bit x0x1z0z1 → xz (first nibble has x, second has z but no x)', () {
      expect(svc.format('x0x1z0z1', 8, DisplayFormat.hexadecimal), 'xz');
    });

    test('16-bit 0101010101010101 → 5555', () {
      expect(
        svc.format('0101010101010101', 16, DisplayFormat.hexadecimal),
        '5555',
      );
    });

    test('16-bit all ones → ffff', () {
      expect(
        svc.format('1111111111111111', 16, DisplayFormat.hexadecimal),
        'ffff',
      );
    });

    test('32-bit alternating 10... → aaaaaaaa', () {
      expect(
        svc.format(
          '10101010101010101010101010101010',
          32,
          DisplayFormat.hexadecimal,
        ),
        'aaaaaaaa',
      );
    });

    test('64-bit all ones → ffffffffffffffff', () {
      expect(
        svc.format('1' * 64, 64, DisplayFormat.hexadecimal),
        'f' * 16,
      );
    });

    test('64-bit alternating 10... → aaaaaaaaaaaaaaaa', () {
      expect(
        svc.format('10' * 32, 64, DisplayFormat.hexadecimal),
        'a' * 16,
      );
    });

    test('256-bit all zeros → 64 hex zeros', () {
      expect(
        svc.format('0' * 256, 256, DisplayFormat.hexadecimal),
        '0' * 64,
      );
    });

    test('256-bit all ones → 64 hex f chars', () {
      expect(
        svc.format('1' * 256, 256, DisplayFormat.hexadecimal),
        'f' * 64,
      );
    });

    test('1024-bit all ones → 256 hex f chars', () {
      expect(
        svc.format('1' * 1024, 1024, DisplayFormat.hexadecimal),
        'f' * 256,
      );
    });

    test('strips b prefix before formatting', () {
      expect(svc.format('b11001010', 8, DisplayFormat.hexadecimal), 'ca');
    });
  });

  // ── octal format ───────────────────────────────────────────────────────────

  group('octal', () {
    test('scalar 0 → 0', () {
      expect(svc.format('0', 1, DisplayFormat.octal), '0');
    });

    test('scalar 1 → 1', () {
      expect(svc.format('1', 1, DisplayFormat.octal), '1');
    });

    test('scalar x → x', () {
      expect(svc.format('x', 1, DisplayFormat.octal), 'x');
    });

    test('scalar z → z', () {
      expect(svc.format('z', 1, DisplayFormat.octal), 'z');
    });

    test('3-bit 000 → 0', () {
      expect(svc.format('000', 3, DisplayFormat.octal), '0');
    });

    test('3-bit 111 → 7', () {
      expect(svc.format('111', 3, DisplayFormat.octal), '7');
    });

    test('3-bit 010 → 2', () {
      expect(svc.format('010', 3, DisplayFormat.octal), '2');
    });

    test('3-bit xxx → x', () {
      expect(svc.format('xxx', 3, DisplayFormat.octal), 'x');
    });

    test('3-bit zzz → z', () {
      expect(svc.format('zzz', 3, DisplayFormat.octal), 'z');
    });

    test('3-bit 0xx → x (partial x)', () {
      expect(svc.format('0xx', 3, DisplayFormat.octal), 'x');
    });

    test('3-bit z0z → z (partial z, no x)', () {
      expect(svc.format('z0z', 3, DisplayFormat.octal), 'z');
    });

    test('4-bit 0000 → 00 (padded to 6 bits → 000000 → 00)', () {
      expect(svc.format('0000', 4, DisplayFormat.octal), '00');
    });

    test('4-bit 1010 → 12 (padded: 001010 → 1,2)', () {
      // "1010" pads to "001010" → "001"=1, "010"=2 → "12"
      expect(svc.format('1010', 4, DisplayFormat.octal), '12');
    });

    test('8-bit 11001010 → 312', () {
      // "11001010" pads to "011001010" → "011"=3, "001"=1, "010"=2 → "312"
      expect(svc.format('11001010', 8, DisplayFormat.octal), '312');
    });

    test('8-bit 0000xxxx → 0xx', () {
      // pads to "000000xxxx" wait, "0000xxxx" is 8 bits, padLen=9
      // padded="00000xxxx"? No: padLeft(9,'0') on 8-char string → "00000xxxx"
      // wait that's 9 chars... "0000xxxx" + leading "0" = "00000xxxx"? Let me recount.
      // "0000xxxx" has 8 chars. padLeft(9,'0') = "0" + "0000xxxx" = "00000xxxx" (9 chars)
      // Groups: "000", "00x", "xxx" → "0", "x", "x" → "0xx"
      expect(svc.format('0000xxxx', 8, DisplayFormat.octal), '0xx');
    });

    test('6-bit 001010 → 12 (exact multiple of 3)', () {
      expect(svc.format('001010', 6, DisplayFormat.octal), '12');
    });
  });

  // ── unsigned decimal format ────────────────────────────────────────────────

  group('unsignedDecimal', () {
    test('0 → 0', () {
      expect(svc.format('0', 1, DisplayFormat.unsignedDecimal), '0');
    });

    test('1 → 1', () {
      expect(svc.format('1', 1, DisplayFormat.unsignedDecimal), '1');
    });

    test('scalar x → X', () {
      expect(svc.format('x', 1, DisplayFormat.unsignedDecimal), 'X');
    });

    test('scalar z → Z', () {
      expect(svc.format('z', 1, DisplayFormat.unsignedDecimal), 'Z');
    });

    test('4-bit 0000 → 0', () {
      expect(svc.format('0000', 4, DisplayFormat.unsignedDecimal), '0');
    });

    test('4-bit 1111 → 15', () {
      expect(svc.format('1111', 4, DisplayFormat.unsignedDecimal), '15');
    });

    test('4-bit 1010 → 10', () {
      expect(svc.format('1010', 4, DisplayFormat.unsignedDecimal), '10');
    });

    test('4-bit xxxx → X', () {
      expect(svc.format('xxxx', 4, DisplayFormat.unsignedDecimal), 'X');
    });

    test('4-bit zzzz → Z', () {
      expect(svc.format('zzzz', 4, DisplayFormat.unsignedDecimal), 'Z');
    });

    test('x takes priority over z: x0x1z0z1 → X', () {
      // Contains x → X (x has priority)
      expect(svc.format('x0x1z0z1', 8, DisplayFormat.unsignedDecimal), 'X');
    });

    test('partial x: 0xxx → X', () {
      expect(svc.format('0xxx', 4, DisplayFormat.unsignedDecimal), 'X');
    });

    test('partial z: z0z1 → Z', () {
      expect(svc.format('z0z1', 4, DisplayFormat.unsignedDecimal), 'Z');
    });

    test('8-bit 11001010 → 202 (fixture: byte8 at t=10)', () {
      expect(svc.format('11001010', 8, DisplayFormat.unsignedDecimal), '202');
    });

    test('8-bit 10101010 → 170', () {
      expect(svc.format('10101010', 8, DisplayFormat.unsignedDecimal), '170');
    });

    test('16-bit 0101010101010101 → 21845', () {
      expect(
        svc.format('0101010101010101', 16, DisplayFormat.unsignedDecimal),
        '21845',
      );
    });

    test('16-bit all ones → 65535', () {
      expect(
        svc.format('1111111111111111', 16, DisplayFormat.unsignedDecimal),
        '65535',
      );
    });

    test('32-bit max unsigned → 4294967295', () {
      expect(
        svc.format('1' * 32, 32, DisplayFormat.unsignedDecimal),
        '4294967295',
      );
    });

    test('64-bit max unsigned → 18446744073709551615', () {
      expect(
        svc.format('1' * 64, 64, DisplayFormat.unsignedDecimal),
        '18446744073709551615',
      );
    });

    test('256-bit all ones → large decimal value', () {
      // 2^256 - 1
      final expected = (BigInt.one << 256) - BigInt.one;
      expect(
        svc.format('1' * 256, 256, DisplayFormat.unsignedDecimal),
        expected.toString(),
      );
    });
  });

  // ── signed decimal format ──────────────────────────────────────────────────

  group('signedDecimal', () {
    test('1-bit 0 → 0', () {
      expect(svc.format('0', 1, DisplayFormat.signedDecimal), '0');
    });

    test("1-bit 1 → -1 (two's complement)", () {
      expect(svc.format('1', 1, DisplayFormat.signedDecimal), '-1');
    });

    test('scalar x → X', () {
      expect(svc.format('x', 1, DisplayFormat.signedDecimal), 'X');
    });

    test('scalar z → Z', () {
      expect(svc.format('z', 1, DisplayFormat.signedDecimal), 'Z');
    });

    test('4-bit 0000 → 0', () {
      expect(svc.format('0000', 4, DisplayFormat.signedDecimal), '0');
    });

    test('4-bit 0111 → 7 (max positive 4-bit signed)', () {
      expect(svc.format('0111', 4, DisplayFormat.signedDecimal), '7');
    });

    test('4-bit 1000 → -8 (min negative 4-bit signed)', () {
      expect(svc.format('1000', 4, DisplayFormat.signedDecimal), '-8');
    });

    test('4-bit 1111 → -1', () {
      expect(svc.format('1111', 4, DisplayFormat.signedDecimal), '-1');
    });

    test('4-bit 1010 → -6', () {
      // 1010 = 10 unsigned; 10 >= 8 (halfMax); 10 - 16 = -6
      expect(svc.format('1010', 4, DisplayFormat.signedDecimal), '-6');
    });

    test('4-bit xxxx → X', () {
      expect(svc.format('xxxx', 4, DisplayFormat.signedDecimal), 'X');
    });

    test('4-bit zzzz → Z', () {
      expect(svc.format('zzzz', 4, DisplayFormat.signedDecimal), 'Z');
    });

    test('8-bit 11001010 → -54 (fixture: byte8 at t=10)', () {
      // 11001010 = 202 unsigned; 202 - 256 = -54
      expect(svc.format('11001010', 8, DisplayFormat.signedDecimal), '-54');
    });

    test('8-bit 01111111 → 127 (max positive 8-bit)', () {
      expect(svc.format('01111111', 8, DisplayFormat.signedDecimal), '127');
    });

    test('8-bit 10000000 → -128 (min negative 8-bit)', () {
      expect(svc.format('10000000', 8, DisplayFormat.signedDecimal), '-128');
    });

    test('16-bit 0111111111111111 → 32767', () {
      expect(
        svc.format('0111111111111111', 16, DisplayFormat.signedDecimal),
        '32767',
      );
    });

    test('16-bit 1000000000000000 → -32768', () {
      expect(
        svc.format('1000000000000000', 16, DisplayFormat.signedDecimal),
        '-32768',
      );
    });

    test('32-bit max signed positive → 2147483647', () {
      expect(
        svc.format('0${'1' * 31}', 32, DisplayFormat.signedDecimal),
        '2147483647',
      );
    });

    test('32-bit min signed negative → -2147483648', () {
      expect(
        svc.format('1${'0' * 31}', 32, DisplayFormat.signedDecimal),
        '-2147483648',
      );
    });

    test('64-bit all ones → -1', () {
      expect(
        svc.format('1' * 64, 64, DisplayFormat.signedDecimal),
        '-1',
      );
    });

    test('partial x: x0x1z0z1 → X (x takes priority)', () {
      expect(svc.format('x0x1z0z1', 8, DisplayFormat.signedDecimal), 'X');
    });
  });

  // ── ascii format ───────────────────────────────────────────────────────────

  group('ascii', () {
    test(r'scalar 0 → \x00 (null character)', () {
      expect(svc.format('0', 1, DisplayFormat.ascii), r'\x00');
    });

    test(r'scalar 1 → \x01', () {
      expect(svc.format('1', 1, DisplayFormat.ascii), r'\x01');
    });

    test('scalar x → ?', () {
      expect(svc.format('x', 1, DisplayFormat.ascii), '?');
    });

    test('scalar z → ?', () {
      expect(svc.format('z', 1, DisplayFormat.ascii), '?');
    });

    test('8-bit 01000001 (0x41) → A', () {
      expect(svc.format('01000001', 8, DisplayFormat.ascii), 'A');
    });

    test('8-bit 01000010 (0x42) → B', () {
      expect(svc.format('01000010', 8, DisplayFormat.ascii), 'B');
    });

    test('8-bit 00100000 (0x20 = space) → space', () {
      expect(svc.format('00100000', 8, DisplayFormat.ascii), ' ');
    });

    test('8-bit 01111110 (0x7E = ~) → ~', () {
      expect(svc.format('01111110', 8, DisplayFormat.ascii), '~');
    });

    test(r'8-bit 01111111 (0x7F = DEL) → \x7f (non-printable)', () {
      expect(svc.format('01111111', 8, DisplayFormat.ascii), r'\x7f');
    });

    test(r'8-bit 00000000 → \x00', () {
      expect(svc.format('00000000', 8, DisplayFormat.ascii), r'\x00');
    });

    test(r'8-bit 00001010 (0x0A = newline) → \x0a', () {
      expect(svc.format('00001010', 8, DisplayFormat.ascii), r'\x0a');
    });

    test(r'8-bit 11111111 (0xFF) → \xff (non-printable high byte)', () {
      expect(svc.format('11111111', 8, DisplayFormat.ascii), r'\xff');
    });

    test('16-bit "AB" → AB (two printable bytes)', () {
      // 'A'=0x41=01000001, 'B'=0x42=01000010
      expect(
        svc.format('0100000101000010', 16, DisplayFormat.ascii),
        'AB',
      );
    });

    test('16-bit with x byte → ?B', () {
      // first byte all-x, second byte 'B'
      expect(
        svc.format('xxxxxxxx01000010', 16, DisplayFormat.ascii),
        '?B',
      );
    });

    test('8-bit with z bits → ?', () {
      expect(svc.format('zzzzzzzz', 8, DisplayFormat.ascii), '?');
    });

    test('8-bit mixed xz byte → ?', () {
      expect(svc.format('x0x1z0z1', 8, DisplayFormat.ascii), '?');
    });

    test(r'fixture: byte8=11001010 (0xCA) → \xca (non-printable)', () {
      expect(svc.format('11001010', 8, DisplayFormat.ascii), r'\xca');
    });
  });

  // ── real / analog pass-through ─────────────────────────────────────────────

  group('real/analog pass-through', () {
    test('floating point value passes through binary format', () {
      expect(svc.format('3.14', 0, DisplayFormat.binary), '3.14');
    });

    test('floating point value passes through hexadecimal format', () {
      expect(svc.format('3.14', 0, DisplayFormat.hexadecimal), '3.14');
    });

    test('negative float passes through all formats', () {
      for (final fmt in DisplayFormat.values) {
        expect(svc.format('-1.5', 0, fmt), '-1.5');
      }
    });

    test('scientific notation passes through', () {
      expect(svc.format('1e-12', 0, DisplayFormat.unsignedDecimal), '1e-12');
    });

    test('r-prefixed real value is handled', () {
      // wellen may prefix real values with 'r'
      expect(svc.format('r3.14', 0, DisplayFormat.binary), '3.14');
    });

    test('empty string returns empty string', () {
      expect(svc.format('', 4, DisplayFormat.binary), '');
    });
  });

  // ── VCD prefix stripping ───────────────────────────────────────────────────

  group('VCD b-prefix handling', () {
    test('b-prefixed binary string is stripped before formatting', () {
      expect(svc.format('b1010', 4, DisplayFormat.hexadecimal), 'a');
    });

    test('B-prefix (uppercase) is stripped', () {
      expect(svc.format('B1111', 4, DisplayFormat.hexadecimal), 'f');
    });

    test('b-prefix with x/z bits', () {
      expect(svc.format('bxxxx', 4, DisplayFormat.hexadecimal), 'x');
    });
  });

  // ── zero-extension (shorter raw value than bitWidth) ──────────────────────

  group('zero-extension / padding', () {
    test('1-bit value for 4-bit signal gets zero-padded', () {
      expect(svc.format('1', 4, DisplayFormat.binary), '0001');
    });

    test('2-bit value for 8-bit signal: hex pads correctly', () {
      // "11" padded to 8 bits → "00000011" → hex "03"
      expect(svc.format('11', 8, DisplayFormat.hexadecimal), '03');
    });

    test('zero-padding preserves x/z in bit string', () {
      // "xx" with bitWidth=4 → padded "00xx" → hex: nibble "00xx" has x → "x"
      expect(svc.format('xx', 4, DisplayFormat.hexadecimal), 'x');
    });
  });

  // ── fixture cross-checks (vector_formats.vcd known answers) ───────────────

  group('vector_formats.vcd fixture values', () {
    // top.nib4 at t=10: value "1111"
    test('nib4 at t=10: binary', () {
      expect(svc.format('1111', 4, DisplayFormat.binary), '1111');
    });

    test('nib4 at t=10: hex', () {
      expect(svc.format('1111', 4, DisplayFormat.hexadecimal), 'f');
    });

    test('nib4 at t=10: unsigned decimal', () {
      expect(svc.format('1111', 4, DisplayFormat.unsignedDecimal), '15');
    });

    test('nib4 at t=10: signed decimal', () {
      expect(svc.format('1111', 4, DisplayFormat.signedDecimal), '-1');
    });

    // top.nib4 at t=30: value "1010"
    test('nib4 at t=30: hex → a', () {
      expect(svc.format('1010', 4, DisplayFormat.hexadecimal), 'a');
    });

    test('nib4 at t=30: octal → 12', () {
      expect(svc.format('1010', 4, DisplayFormat.octal), '12');
    });

    // top.word16 at t=30: value "1111111111111111"
    test('word16 all-ones: unsigned → 65535', () {
      expect(
        svc.format('1111111111111111', 16, DisplayFormat.unsignedDecimal),
        '65535',
      );
    });

    test('word16 all-ones: signed → -1', () {
      expect(
        svc.format('1111111111111111', 16, DisplayFormat.signedDecimal),
        '-1',
      );
    });

    test('word16 all-ones: hex → ffff', () {
      expect(
        svc.format('1111111111111111', 16, DisplayFormat.hexadecimal),
        'ffff',
      );
    });

    // top.quad64 at t=10: 64-bit all-ones
    test('quad64 all-ones: hex → ffffffffffffffff', () {
      expect(
        svc.format('1' * 64, 64, DisplayFormat.hexadecimal),
        'f' * 16,
      );
    });

    test('quad64 at t=30: alternating 10... → aaaaaaaaaaaaaaaa', () {
      expect(
        svc.format('10' * 32, 64, DisplayFormat.hexadecimal),
        'a' * 16,
      );
    });

    // top.xnib: x states
    test('xnib all-x: hex → x', () {
      expect(svc.format('xxxx', 4, DisplayFormat.hexadecimal), 'x');
    });

    test('xnib 0xxx: hex → x (partial x in nibble)', () {
      expect(svc.format('0xxx', 4, DisplayFormat.hexadecimal), 'x');
    });

    test('xnib x0x1: unsigned decimal → X', () {
      expect(svc.format('x0x1', 4, DisplayFormat.unsignedDecimal), 'X');
    });

    // top.znib: z states
    test('znib all-z: hex → z', () {
      expect(svc.format('zzzz', 4, DisplayFormat.hexadecimal), 'z');
    });

    test('znib z0z1: hex → z', () {
      expect(svc.format('z0z1', 4, DisplayFormat.hexadecimal), 'z');
    });

    test('znib z0z1: unsigned decimal → Z', () {
      expect(svc.format('z0z1', 4, DisplayFormat.unsignedDecimal), 'Z');
    });

    // top.mixed_xz: 8-bit mixed
    test('mixed_xz at t=0: 0000xxxx hex → 0x', () {
      expect(svc.format('0000xxxx', 8, DisplayFormat.hexadecimal), '0x');
    });

    test('mixed_xz at t=10: 1111zzzz hex → fz', () {
      expect(svc.format('1111zzzz', 8, DisplayFormat.hexadecimal), 'fz');
    });

    test('mixed_xz at t=30: x0x1z0z1 hex → xz', () {
      expect(svc.format('x0x1z0z1', 8, DisplayFormat.hexadecimal), 'xz');
    });

    test('mixed_xz at t=0: 0000xxxx unsigned decimal → X', () {
      expect(svc.format('0000xxxx', 8, DisplayFormat.unsignedDecimal), 'X');
    });

    test('mixed_xz at t=10: 1111zzzz unsigned decimal → Z', () {
      expect(svc.format('1111zzzz', 8, DisplayFormat.unsignedDecimal), 'Z');
    });

    test('mixed_xz at t=30: x0x1z0z1 unsigned decimal → X (x priority)', () {
      expect(svc.format('x0x1z0z1', 8, DisplayFormat.unsignedDecimal), 'X');
    });
  });
}
