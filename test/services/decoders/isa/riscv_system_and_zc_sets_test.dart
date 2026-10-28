// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Zicsr, the privileged instructions, Zcb and Zcmp, checked against encodings
// an independent assembler produced rather than against our own tables.
//
// Every word below was assembled by LLVM's `llvm-mc -triple=riscv32
// -mattr=+zicsr,+zcmp,+zcb,+zbb,+m,+c -show-encoding` from the instruction
// text in the comment; the expected disassembly is the same instruction in
// this corpus's base-form spelling (ABI register names, no assembler aliases:
// `csrrs a2, mcause, zero` where LLVM prints `csrr a2, mcause`). Before these
// tables existed every one of them rendered as `UNKNOWN INSN` in the ISA
// trace decoder and as a null disassembly in the RVFI retire stream.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';

InstructionSet _load(String name) => parseInstructionSetToml(
  File('assets/decoders/isa/riscv/$name.toml').readAsStringSync(),
  sourceLabel: '$name.toml',
);

/// The RV32 composition a CV32E40X-class core needs, in the bundle's
/// canonical load order.
InstructionDisassembler _rv32() => InstructionDisassembler([
  for (final name in [
    'Privileged',
    'Zicsr',
    'RV32I',
    'RV32M',
    'RV32C-lower',
    'RV32Zcb-lower',
    'RV32Zcmp-lower',
  ])
    _load(name),
]);

void main() {
  final disasm = _rv32();

  String? text(int word) => disasm.decode(word, 32)?.text;

  group('Zicsr', () {
    final cases = <int, String>{
      // csrw mepc, a3 (seen on CV32E40X)
      0x34169073: 'csrrw zero, mepc, a3',
      // csrr a2, mcause (Ibex, CV32E40X)
      0x34202673: 'csrrs a2, mcause, zero',
      // csrsi mstatus, 8 (CV32E40X)
      0x30046073: 'csrrsi zero, mstatus, 8',
      // csrrc a0, mie, a1
      0x3045b573: 'csrrc a0, mie, a1',
      // csrrwi a0, mtvec, 3
      0x3051d573: 'csrrwi a0, mtvec, 3',
      // csrci mstatus, 8
      0x30047073: 'csrrci zero, mstatus, 8',
      // csrr a3, mepc (the Ibex trap handler)
      0x341026f3: 'csrrs a3, mepc, zero',
      // csrr a0, dpc
      0x7b102573: 'csrrs a0, dpc, zero',
    };
    for (final MapEntry(key: word, value: expected) in cases.entries) {
      test('0x${word.toRadixString(16)} is $expected', () {
        expect(text(word), expected);
      });
    }

    test('a CSR the table does not name renders as its hex number', () {
      // csrr a0, 0x7c0 — a custom machine-mode CSR.
      expect(text(0x7c002573), 'csrrs a0, 0x7c0, zero');
    });
  });

  group('privileged', () {
    final cases = <int, String>{
      0x30200073: 'mret',
      0x10200073: 'sret',
      0x10500073: 'wfi',
      0x7b200073: 'dret',
      0x12b50073: 'sfence.vma a0, a1',
      0x12000073: 'sfence.vma zero, zero',
    };
    for (final MapEntry(key: word, value: expected) in cases.entries) {
      test('0x${word.toRadixString(16)} is $expected', () {
        expect(text(word), expected);
      });
    }

    test('ecall and ebreak still decode from RV32I', () {
      expect(text(0x00000073), 'ecall');
      expect(text(0x00100073), 'ebreak');
    });
  });

  group('Zcmp', () {
    final cases = <int, String>{
      0xb852: 'cm.push {ra, s0}, -16',
      0xbafe: 'cm.pop {ra, s0-s11}, 112',
      0xbe42: 'cm.popret {ra}, 16',
      0xbc86: 'cm.popretz {ra, s0-s3}, 48',
      0xacea: 'cm.mva01s s1, s2',
      0xac3e: 'cm.mvsa01 s0, s7',
    };
    for (final MapEntry(key: word, value: expected) in cases.entries) {
      test('0x${word.toRadixString(16)} is $expected', () {
        expect(text(word), expected);
      });
    }

    test("the high half of the word is don't-care", () {
      expect(text(0xdead0000 | 0xb852), 'cm.push {ra, s0}, -16');
    });
  });

  group('Zcb', () {
    final cases = <int, String>{
      0x81e8: 'c.lbu a0, 3(a1)',
      0x85a8: 'c.lhu a0, 2(a1)',
      0x86f0: 'c.lh a2, 2(a3)',
      0x89c8: 'c.sb a0, 1(a1)',
      0x8da8: 'c.sh a0, 2(a1)',
      0x9d61: 'c.zext.b a0',
      0x9de5: 'c.sext.b a1',
      0x9e69: 'c.zext.h a2',
      0x9eed: 'c.sext.h a3',
      0x9f75: 'c.not a4',
      0x9d5d: 'c.mul a0, a5',
    };
    for (final MapEntry(key: word, value: expected) in cases.entries) {
      test('0x${word.toRadixString(16)} is $expected', () {
        expect(text(word), expected);
      });
    }
  });
}
