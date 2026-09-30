// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';

/// Loads a bundled RISC-V TOML directly from the filesystem (test-time
/// helper — bundle access via rootBundle requires a Flutter test surface).
InstructionSet loadAsset(String name) {
  final file = File('assets/decoders/isa/riscv/$name.toml');
  return parseInstructionSetToml(
    file.readAsStringSync(),
    sourceLabel: '$name.toml',
  );
}

void main() {
  group('Disassembler — RV32I', () {
    late InstructionDisassembler dis;

    setUpAll(() {
      dis = InstructionDisassembler([loadAsset('RV32I')]);
    });

    test('addi t0, t1, 10 → "addi t0, t1, 10"', () {
      // imm=10, rs1=6 (t1), funct3=0, rd=5 (t0), opcode=0010011
      final r = dis.decode(0x00a30293, 32);
      expect(r, isNotNull);
      expect(r!.text, 'addi t0, t1, 10');
      expect(r.mnemonic, 'addi');
    });

    test('addi t0, t1, -1 sign-extends correctly', () {
      // imm=0xfff = -1 (12-bit signed), rs1=6, rd=5
      final r = dis.decode(0xfff30293, 32);
      expect(r!.text, 'addi t0, t1, -1');
    });

    test('add a0, a1, a2 → "add a0, a1, a2"', () {
      // funct7=0, rs2=12, rs1=11, funct3=0, rd=10, opcode=0110011
      final r = dis.decode(0x00c58533, 32);
      expect(r!.text, 'add a0, a1, a2');
    });

    test('sub a0, a1, a2 → "sub a0, a1, a2"', () {
      final r = dis.decode(0x40c58533, 32);
      expect(r!.text, 'sub a0, a1, a2');
    });

    test('sw t1, 8(sp) reassembles split-imm correctly', () {
      // imm[11:5]=0, imm[4:0]=01000=8, rs2=6 (t1), rs1=2 (sp), opcode=0100011
      final r = dis.decode(0x00612423, 32);
      expect(r!.text, 'sw t1, 8(sp)');
    });

    test('lw a0, 12(sp) → "lw a0, 12(sp)"', () {
      // imm=12, rs1=2 (sp), funct3=010 (lw), rd=10 (a0), opcode=0000011
      final r = dis.decode(0x00c12503, 32);
      expect(r!.text, 'lw a0, 12(sp)');
    });

    test('lui a0, 0x12345 (uimm hex radix)', () {
      // imm[31:12] = 0x12345, rd=10, opcode=0110111
      final r = dis.decode(0x12345537, 32);
      expect(r!.text, 'lui a0, 0x12345');
    });

    test('auipc a0, 0x1 (uimm hex radix)', () {
      // imm[31:12] = 0x1, rd=10, opcode=0010111
      final r = dis.decode(0x00001517, 32);
      expect(r!.text, 'auipc a0, 0x1');
    });

    test('beq t0, t1, +12 renders the architectural byte offset', () {
      // beq with offset 12: imm[12]=0, imm[10:5]=0, imm[4:1]=0110, imm[11]=0.
      // Offsets across the full 13-bit signed range — including the
      // backward ones this case cannot reach — are swept in
      // riscv_immediate_encoding_test.dart.
      final r = dis.decode(0x00628663, 32);
      expect(r!.text, 'beq t0, t1, 12');
    });

    test('slli t0, t1, 4 (5-bit shamt) → "slli t0, t1, 4"', () {
      // funct7=0, shamt=4, rs1=6, funct3=001, rd=5, opcode=0010011
      final r = dis.decode(0x00431293, 32);
      expect(r!.text, 'slli t0, t1, 4');
    });

    test('ecall → "ecall"', () {
      final r = dis.decode(0x00000073, 32);
      expect(r!.text, 'ecall');
    });

    test('ebreak → "ebreak"', () {
      final r = dis.decode(0x00100073, 32);
      expect(r!.text, 'ebreak');
    });

    test('jal ra, 0 → "jal ra, 0"', () {
      // jal with rd=ra (1), opcode=1101111, all immediate bits clear.
      final r = dis.decode(0x000000ef, 32);
      expect(r!.text, 'jal ra, 0');
    });

    test('returns null on a fully-opaque pattern (no match)', () {
      // 0xffffffff is valid RV32I encoding for nothing; mask/match miss.
      final r = dis.decode(0xffffffff, 32);
      expect(r, isNull);
    });
  });

  group('Disassembler — RV32M (composes with RV32I)', () {
    late InstructionDisassembler dis;
    setUpAll(() {
      dis = InstructionDisassembler([loadAsset('RV32I'), loadAsset('RV32M')]);
    });

    test('mul a0, a1, a2 → "mul a0, a1, a2"', () {
      final r = dis.decode(0x02c58533, 32);
      expect(r!.text, 'mul a0, a1, a2');
    });

    test('div a0, a1, a2 → "div a0, a1, a2"', () {
      final r = dis.decode(0x02c5c533, 32);
      expect(r!.text, 'div a0, a1, a2');
    });
  });

  group('Disassembler — RV64I (composes with RV32I, slli widens)', () {
    late InstructionDisassembler dis;
    setUpAll(() {
      dis = InstructionDisassembler([loadAsset('RV32I'), loadAsset('RV64I')]);
    });

    test('ld a0, 16(sp) → "ld a0, 16(sp)"', () {
      // imm=16, rs1=2, funct3=011, rd=10, opcode=0000011
      final r = dis.decode(0x01013503, 32);
      expect(r!.text, 'ld a0, 16(sp)');
    });

    test('addw a0, a1, a2 → "addw a0, a1, a2"', () {
      final r = dis.decode(0x00c5853b, 32);
      expect(r!.text, 'addw a0, a1, a2');
    });

    test('slli with shamt=32 (RV64 6-bit) decodes via RV64I redefinition', () {
      // funct6=000000, shamt=100000 (32), rs1=6, funct3=001, rd=5, opcode=13
      // shamt[5]=1 means RV32I would NOT match (its mask requires bit 25=0).
      // RV64I's broader mask permits this; result: "slli t0, t1, 32"
      final r = dis.decode(0x02031293, 32);
      expect(r!.text, 'slli t0, t1, 32');
    });
  });

  group('Disassembler — bit-width filtering', () {
    test('decoder.decode(_, 16) ignores width=32 ISets', () {
      final dis = InstructionDisassembler([loadAsset('RV32I')]);
      // Even valid RV32I word, query width 16 → no matching set
      expect(dis.decode(0x00a30293, 16), isNull);
    });
  });

  group('Sign extension (parts that declare extend_top)', () {
    // We verify sign-extension by going through addi with a negative imm.
    // Already covered above; this group is for documenting intent.
    test('I-type imm is signed when no `unsigned = true`', () {
      final dis = InstructionDisassembler([loadAsset('RV32I')]);
      final r = dis.decode(0xfff30293, 32);
      expect(r!.text, contains('-1'));
    });

    test('U-type uimm with `unsigned = true` is rendered hex-unsigned', () {
      final dis = InstructionDisassembler([loadAsset('RV32I')]);
      // lui with imm[31:12] = 0xfffff
      final r = dis.decode(0xfffff537, 32);
      expect(r!.text, 'lui a0, 0xfffff');
    });
  });

  group('Cross-tool compatibility with the JKU loader', () {
    // assets/decoders/isa/riscv/NOTICE.md claims a file written for the JKU
    // `instruction-decoder` crate loads in WaveCrux unmodified. That claim
    // rests on one thing our own corpus never exercised on its own: slice
    // `top`/`bot` are positions in the decoded part's *value*, and a
    // slice's position in the instruction word comes from the running
    // MSB-first cursor. The corpus below is written in upstream's
    // conventions rather than ours — auto-generated names, registers at
    // `4 downto 0`, no `extend_top` anywhere, and upstream's own B-type
    // shape (`imm` at 12:12, 10:5, 4:1, 11:11). If our reading of the
    // schema ever drifts from theirs, this decodes to plausible-looking
    // garbage rather than failing to parse.
    const upstreamStyle = r'''
set = "RV32I-upstream-style"
width = 32

[formats]
names = ["format_1-0", "format_2-0", "format_4-0"]
parts = [
    ["rd_Register_int", 5, "Register_int"],
    ["rs1_Register_int", 5, "Register_int"],
    ["rs2_Register_int", 5, "Register_int"],
    ["imm", 32, "VInt"],
    ["none", 32, "u32"],
]

[types]
names = ["type_1-0", "type_2-0", "type_4-0"]

[[types.type_1-0]]
name = "none"
top = 31
bot = 25
[[types.type_1-0]]
name = "rs2_Register_int"
top = 4
bot = 0
[[types.type_1-0]]
name = "rs1_Register_int"
top = 4
bot = 0
[[types.type_1-0]]
name = "none"
top = 14
bot = 12
[[types.type_1-0]]
name = "rd_Register_int"
top = 4
bot = 0
[[types.type_1-0]]
name = "none"
top = 6
bot = 0

[[types.type_2-0]]
name = "imm"
top = 11
bot = 0
[[types.type_2-0]]
name = "rs1_Register_int"
top = 4
bot = 0
[[types.type_2-0]]
name = "none"
top = 14
bot = 12
[[types.type_2-0]]
name = "rd_Register_int"
top = 4
bot = 0
[[types.type_2-0]]
name = "none"
top = 6
bot = 0

[[types.type_4-0]]
name = "imm"
top = 12
bot = 12
[[types.type_4-0]]
name = "imm"
top = 10
bot = 5
[[types.type_4-0]]
name = "rs2_Register_int"
top = 4
bot = 0
[[types.type_4-0]]
name = "rs1_Register_int"
top = 4
bot = 0
[[types.type_4-0]]
name = "none"
top = 14
bot = 12
[[types.type_4-0]]
name = "imm"
top = 4
bot = 1
[[types.type_4-0]]
name = "imm"
top = 11
bot = 11
[[types.type_4-0]]
name = "none"
top = 6
bot = 0

[mappings]
names = ["Register_int"]
Register_int = [
    "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
]

[format_1-0]
type = "type_1-0"
[format_1-0.repr]
default = "$name$ %rd_Register_int%, %rs1_Register_int%, %rs2_Register_int%"
[format_1-0.instructions.add]
mask = 0xfe00707f
match = 0x00000033

[format_2-0]
type = "type_2-0"
[format_2-0.repr]
default = "$name$ %rd_Register_int%, %rs1_Register_int%, %imm%"
[format_2-0.instructions.addi]
mask = 0x0000707f
match = 0x00000013

[format_4-0]
type = "type_4-0"
[format_4-0.repr]
default = "$name$ %rs1_Register_int%, %rs2_Register_int%, %imm%"
[format_4-0.instructions.bne]
mask = 0x0000707f
match = 0x00001063
''';

    late InstructionDisassembler dis;
    setUpAll(() {
      dis = InstructionDisassembler([parseInstructionSetToml(upstreamStyle)]);
    });

    test('registers land at their architectural indices', () {
      expect(dis.decode(0x00c58533, 32)!.text, 'add a0, a1, a2');
    });

    test('I-type immediates sign-extend without an extend_top field', () {
      expect(dis.decode(0x00a30293, 32)!.text, 'addi t0, t1, 10');
      expect(dis.decode(0xfff30293, 32)!.text, 'addi t0, t1, -1');
    });

    test('upstream B-type shape yields the architectural byte offset', () {
      expect(dis.decode(0xfe029ce3, 32)!.text, 'bne t0, zero, -8');
      expect(dis.decode(0x00629663, 32)!.text, 'bne t0, t1, 12');
    });
  });
}
