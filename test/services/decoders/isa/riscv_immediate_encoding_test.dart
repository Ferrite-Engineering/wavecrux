// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Immediate reassembly, checked against the RISC-V unprivileged spec rather
// than against our own decoder.
//
// Every encoding in this file is built by a local encoder written straight
// from the spec's "Immediate Encoding Variants" tables, so the expectations
// are independent of the TOML corpus and of `InstructionDisassembler`. If
// the corpus and the encoders ever disagree, the corpus is what is wrong.
//
// Regression history: the corpus originally described B-type and J-type
// immediates by concatenating slices in instruction-bit order, which landed
// `imm[11]` in the assembled value's low bit and never inserted the implicit
// `imm[0] = 0`. Branch offsets in `[0, 2047]` survived that by coincidence —
// which is why every branch in the fixture corpus at the time was a small
// forward one — and everything outside it decoded wrong: `0xfe029ce3`
// (`bne t0, zero, -8`) rendered as `-7`, and the picorv32 capture's
// `0xFF5FF06F` (`jal zero, -12`) rendered as `-2561`. Both are pinned below.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';

InstructionSet _load(String name) => parseInstructionSetToml(
  File('assets/decoders/isa/riscv/$name.toml').readAsStringSync(),
  sourceLabel: '$name.toml',
);

// ── spec-derived encoders ────────────────────────────────────────────────────
// RISC-V unprivileged ISA, "Immediate Encoding Variants". Each of these
// scatters a byte offset into the instruction word; the decoder's job is the
// exact inverse.

int _bits(int v, int hi, int lo) => (v >> lo) & ((1 << (hi - lo + 1)) - 1);

/// B-type: `inst[31]=imm[12]`, `inst[30:25]=imm[10:5]`, `inst[11:8]=imm[4:1]`,
/// `inst[7]=imm[11]`, and `imm[0]` is architecturally 0.
int encodeB({
  required int funct3,
  required int rs1,
  required int rs2,
  required int offset,
}) {
  expect(offset.isEven, isTrue, reason: 'B-type offsets are 2-byte aligned');
  expect(offset >= -4096 && offset <= 4094, isTrue, reason: '13-bit signed');
  return ((_bits(offset, 12, 12) << 31) |
          (_bits(offset, 10, 5) << 25) |
          (rs2 << 20) |
          (rs1 << 15) |
          (funct3 << 12) |
          (_bits(offset, 4, 1) << 8) |
          (_bits(offset, 11, 11) << 7) |
          0x63)
      .toUnsigned(32);
}

/// J-type: `inst[31]=imm[20]`, `inst[30:21]=imm[10:1]`, `inst[20]=imm[11]`,
/// `inst[19:12]=imm[19:12]`, and `imm[0]` is architecturally 0.
int encodeJ({required int rd, required int offset}) {
  expect(offset.isEven, isTrue, reason: 'J-type offsets are 2-byte aligned');
  expect(
    offset >= -1048576 && offset <= 1048574,
    isTrue,
    reason: '21-bit signed',
  );
  return ((_bits(offset, 20, 20) << 31) |
          (_bits(offset, 10, 1) << 21) |
          (_bits(offset, 11, 11) << 20) |
          (_bits(offset, 19, 12) << 12) |
          (rd << 7) |
          0x6f)
      .toUnsigned(32);
}

/// CJ-type (`c.j`): `imm[11|4|9:8|10|6|7|3:1|5]` in `inst[12:2]`.
int encodeCJ({required int offset}) {
  expect(offset.isEven, isTrue);
  expect(offset >= -2048 && offset <= 2046, isTrue, reason: '12-bit signed');
  return (0xa001 |
          (_bits(offset, 11, 11) << 12) |
          (_bits(offset, 4, 4) << 11) |
          (_bits(offset, 9, 8) << 9) |
          (_bits(offset, 10, 10) << 8) |
          (_bits(offset, 6, 6) << 7) |
          (_bits(offset, 7, 7) << 6) |
          (_bits(offset, 3, 1) << 3) |
          (_bits(offset, 5, 5) << 2))
      .toUnsigned(32);
}

/// CB-type (`c.beqz` / `c.bnez`): `imm[8|4:3]` in `inst[12:10]`,
/// `imm[7:6|2:1|5]` in `inst[6:2]`.
int encodeCB({required bool nez, required int rs1p, required int offset}) {
  expect(offset.isEven, isTrue);
  expect(offset >= -256 && offset <= 254, isTrue, reason: '9-bit signed');
  return ((nez ? 0xe001 : 0xc001) |
          (_bits(offset, 8, 8) << 12) |
          (_bits(offset, 4, 3) << 10) |
          (rs1p << 7) |
          (_bits(offset, 7, 6) << 5) |
          (_bits(offset, 2, 1) << 3) |
          (_bits(offset, 5, 5) << 2))
      .toUnsigned(32);
}

/// S-type: `inst[31:25]=imm[11:5]`, `inst[11:7]=imm[4:0]` — a control. This
/// one was always right, because for S-type the instruction-bit order and
/// the value-bit order happen to coincide.
int encodeS({
  required int funct3,
  required int rs1,
  required int rs2,
  required int offset,
}) =>
    ((_bits(offset, 11, 5) << 25) |
            (rs2 << 20) |
            (rs1 << 15) |
            (funct3 << 12) |
            (_bits(offset, 4, 0) << 7) |
            0x23)
        .toUnsigned(32);

void main() {
  late InstructionDisassembler rv32i;
  late InstructionDisassembler rvc32;
  late InstructionDisassembler rvc64;

  setUpAll(() {
    rv32i = InstructionDisassembler([_load('RV32I')]);
    rvc32 = InstructionDisassembler([_load('RV32C-lower')]);
    rvc64 = InstructionDisassembler([
      _load('RV32C-lower'),
      _load('RV64C-lower'),
    ]);
  });

  group('B-type branch offsets are architectural byte offsets', () {
    // t0 = x5, zero = x0, funct3 001 = bne.
    const cases = <int>[
      0,
      2, // smallest step — proves the value is a byte offset, not a halfword
      4,
      12,
      2046, // the largest offset the old instruction-order assembly got right
      2048, // …and the first one it got wrong (it printed 1)
      2050,
      4094, // maximum positive
      -2,
      -4,
      -8, // the anchor below, reached from the encoder side
      -12,
      -2048,
      -2050,
      -4096, // maximum negative
    ];

    for (final offset in cases) {
      test('bne t0, zero, $offset', () {
        final word = encodeB(funct3: 1, rs1: 5, rs2: 0, offset: offset);
        final r = rv32i.decode(word, 32);
        expect(r, isNotNull, reason: '0x${word.toRadixString(16)}');
        expect(r!.text, 'bne t0, zero, $offset');
      });
    }

    test('0xfe029ce3 → "bne t0, zero, -8" (regression anchor)', () {
      // Hand-verified against the spec:
      //   imm[12]=1, imm[11]=1, imm[10:5]=111111, imm[4:1]=1100, imm[0]=0
      //   → 1_1_111111_1100_0 = 0x1ff8 as 13-bit signed = -8.
      // The instruction-order assembly produced 1|111111|1100|1 = 0xff9,
      // 12 bits, = -7. This test fails against the pre-fix corpus.
      expect(encodeB(funct3: 1, rs1: 5, rs2: 0, offset: -8), 0xfe029ce3);
      expect(rv32i.decode(0xfe029ce3, 32)!.text, 'bne t0, zero, -8');
    });

    test('every B-type mnemonic reassembles the same immediate', () {
      const funct3ByName = <String, int>{
        'beq': 0,
        'bne': 1,
        'blt': 4,
        'bge': 5,
        'bltu': 6,
        'bgeu': 7,
      };
      for (final entry in funct3ByName.entries) {
        final word = encodeB(
          funct3: entry.value,
          rs1: 5,
          rs2: 6,
          offset: -2048,
        );
        expect(rv32i.decode(word, 32)!.text, '${entry.key} t0, t1, -2048');
      }
    });

    test('imm[11] is not in the low bit — every offset is even', () {
      // The defect this file exists for made every odd-looking value
      // reachable, because inst[7] (imm[11]) landed in the value's bit 0.
      // A byte offset in a 2-byte-aligned ISA can never be odd.
      for (var offset = -4096; offset <= 4094; offset += 2) {
        final word = encodeB(funct3: 0, rs1: 0, rs2: 0, offset: offset);
        final text = rv32i.decode(word, 32)!.text;
        final decoded = int.parse(text.split(', ').last);
        expect(
          decoded.isEven,
          isTrue,
          reason: 'offset $offset decoded to an odd $decoded',
        );
        expect(decoded, offset);
      }
    });
  });

  group('J-type jump offsets are architectural byte offsets', () {
    const cases = <int>[
      0,
      2,
      4,
      2046,
      2048,
      4096,
      -2,
      -4,
      -12, // the picorv32 capture's self-loop
      -2048,
      -4096,
      1048574, // maximum positive
      -1048576, // maximum negative
    ];

    for (final offset in cases) {
      test('jal ra, $offset', () {
        final word = encodeJ(rd: 1, offset: offset);
        final r = rv32i.decode(word, 32);
        expect(r, isNotNull, reason: '0x${word.toRadixString(16)}');
        expect(r!.text, 'jal ra, $offset');
      });
    }

    test('0xff5ff06f → "jal zero, -12" (captured picorv32 anchor)', () {
      // This exact word is in the committed picorv32 FST capture at
      // PC 0x14, and `captured/PROVENANCE.md` recorded it as a
      // "-12-byte backward branch" when the trace was taken. The corpus
      // rendered it as -2561 until the slice semantics were corrected.
      expect(encodeJ(rd: 0, offset: -12), 0xff5ff06f);
      expect(rv32i.decode(0xff5ff06f, 32)!.text, 'jal zero, -12');
    });

    test('J-type offsets are even across the whole 21-bit range', () {
      for (var offset = -1048576; offset <= 1048574; offset += 1022) {
        final word = encodeJ(rd: 1, offset: offset);
        final decoded = int.parse(
          rv32i.decode(word, 32)!.text.split(', ').last,
        );
        expect(decoded, offset);
        expect(decoded.isEven, isTrue);
      }
    });
  });

  group('S-type and I-type immediates (unchanged controls)', () {
    test('sw t1, offset(sp) across the 12-bit signed range', () {
      for (final offset in const [0, 1, 8, 31, 32, 2047, -1, -2048]) {
        final word = encodeS(funct3: 2, rs1: 2, rs2: 6, offset: offset);
        expect(rv32i.decode(word, 32)!.text, 'sw t1, $offset(sp)');
      }
    });

    test('addi t0, t1, imm across the 12-bit signed range', () {
      for (final imm in const [0, 1, 10, 2047, -1, -10, -2048]) {
        final word = (((imm & 0xfff) << 20) | (6 << 15) | (5 << 7) | 0x13)
            .toUnsigned(32);
        expect(rv32i.decode(word, 32)!.text, 'addi t0, t1, $imm');
      }
    });
  });

  group('Compressed branch and jump offsets', () {
    for (final offset in const [0, 2, 4, 254, 256, 2046, -2, -8, -256, -2048]) {
      test('c.j $offset', () {
        expect(rvc32.decode(encodeCJ(offset: offset), 32)!.text, 'c.j $offset');
      });
    }

    for (final offset in const [0, 2, 4, 62, 64, 254, -2, -8, -64, -256]) {
      test('c.beqz s0, $offset', () {
        final word = encodeCB(nez: false, rs1p: 0, offset: offset);
        expect(rvc32.decode(word, 32)!.text, 'c.beqz s0, $offset');
      });
      test('c.bnez a0, $offset', () {
        final word = encodeCB(nez: true, rs1p: 2, offset: offset);
        expect(rvc32.decode(word, 32)!.text, 'c.bnez a0, $offset');
      });
    }
  });

  group('Compressed stack-pointer offsets are unsigned and scaled', () {
    test('c.swsp rs2, uimm(sp) — uimm[5:2|7:6], word-scaled', () {
      // uimm[5:2] = inst[12:9], uimm[7:6] = inst[8:7], rs2 = inst[6:2].
      for (final uimm in const [0, 4, 8, 60, 64, 128, 252]) {
        final word =
            (0xc002 |
                    (_bits(uimm, 5, 2) << 9) |
                    (_bits(uimm, 7, 6) << 7) |
                    (1 << 2))
                .toUnsigned(32);
        expect(
          rvc32.decode(word, 32)!.text,
          'c.swsp ra, 0x${uimm.toRadixString(16)}(sp)',
        );
      }
    });

    test('c.sdsp rs2, uimm(sp) — uimm[5:3|8:6], doubleword-scaled', () {
      for (final uimm in const [0, 8, 16, 56, 64, 256, 504]) {
        final word =
            (0xe002 |
                    (_bits(uimm, 5, 3) << 10) |
                    (_bits(uimm, 8, 6) << 7) |
                    (1 << 2))
                .toUnsigned(32);
        expect(
          rvc64.decode(word, 32)!.text,
          'c.sdsp ra, 0x${uimm.toRadixString(16)}(sp)',
        );
      }
    });

    test('c.ldsp rd, uimm(sp) — uimm[5|4:3|8:6], doubleword-scaled', () {
      for (final uimm in const [0, 8, 16, 32, 64, 256, 504]) {
        final word =
            (0x6002 |
                    (_bits(uimm, 5, 5) << 12) |
                    (1 << 7) |
                    (_bits(uimm, 4, 3) << 5) |
                    (_bits(uimm, 8, 6) << 2))
                .toUnsigned(32);
        expect(
          rvc64.decode(word, 32)!.text,
          'c.ldsp ra, 0x${uimm.toRadixString(16)}(sp)',
        );
      }
    });
  });

  group('Corpus structure', () {
    // Slices tile the instruction word MSB-first, so a type whose slice
    // widths do not sum to `width` silently mis-reads every field after the
    // gap. Nothing else in the suite would say so.
    const names = [
      'RV32I',
      'RV32M',
      'RV32A',
      'RV32F',
      'RV32C-lower',
      'RV64I',
      'RV64M',
      'RV64A',
      'RV64D',
      'RV64C-lower',
    ];

    for (final name in names) {
      test('$name.toml: every type tiles the word exactly', () {
        final iset = _load(name);
        final seen = <InstructionType>{};
        for (final format in iset.formats) {
          if (!seen.add(format.type)) continue;
          final total = format.type.slices.fold<int>(
            0,
            (a, s) => a + s.bitWidth,
          );
          expect(
            total,
            iset.bitWidth,
            reason:
                "${format.name}'s type covers $total bits, not "
                '${iset.bitWidth} — slices tile the word MSB-first',
          );
        }
      });
    }
  });
}
