// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';
import 'package:wavecrux/services/value_format/riscv_disasm_translator.dart';

InstructionSet _load(String name) => parseInstructionSetToml(
  File('assets/decoders/isa/riscv/$name.toml').readAsStringSync(),
  sourceLabel: '$name.toml',
);

/// 32-bit MSB-first bit string for an instruction word.
String _bits(int word, [int width = 32]) =>
    word.toUnsigned(width).toRadixString(2).padLeft(width, '0');

void main() {
  late RiscvDisasmTranslator translator;

  setUpAll(() {
    translator = RiscvDisasmTranslator(
      InstructionDisassembler([
        _load('RV32I'),
        _load('RV64I'),
        _load('RV32C-lower'),
      ]),
    );
  });

  TranslationResultText decode(int word, {int width = 32}) {
    final r = translator.translate(
      TranslationRequest(
        rawValue: _bits(word, width),
        bitWidth: width,
        format: DisplayFormat.hexadecimal,
      ),
    );
    return (
      text: r.text,
      mnemonic: r.fields.isEmpty ? '' : r.fields.first.text,
    );
  }

  test('id is open-core, never Pro-gated', () {
    expect(translator.id, 'builtin.riscvDisasm');
  });

  test('RV32I: addi t0, t1, 10', () {
    final r = decode(0x00a30293);
    expect(r.text, 'addi t0, t1, 10');
    expect(r.mnemonic, 'addi');
  });

  test('RV32I: add a0, a1, a2', () {
    expect(decode(0x00c58533).text, 'add a0, a1, a2');
  });

  test('RV64I: addiw a0, a1, 1 (word-form, RV64-only)', () {
    // 0x0015859b = addiw a1->a0, imm 1
    final r = decode(0x0015859b);
    expect(r.text, contains('addiw'));
  });

  test('compressed: c.li disassembles to a c.* mnemonic', () {
    // c.li a0, 0  →  0x4501 in the low 16 bits of the 32-bit container.
    final r = decode(0x00004501);
    expect(r.mnemonic, 'c.li');
    expect(r.text, isNot('4501')); // not the flat hex fallback
  });

  test('mnemonic + operand fields are surfaced', () {
    final r = translator.translate(
      const TranslationRequest(
        rawValue: '00000000101000110000001010010011', // addi t0, t1, 10
        bitWidth: 32,
        format: DisplayFormat.hexadecimal,
      ),
    );
    expect(r.fields.first.name, 'mnemonic');
    expect(r.fields.first.text, 'addi');
    // operands op0..opN
    expect(r.fields.where((f) => f.name.startsWith('op')), isNotEmpty);
  });

  test('unknown instruction falls back to flat hex', () {
    final r = translator.translate(
      const TranslationRequest(
        rawValue: '00000000000000000000000000000000',
        bitWidth: 32,
        format: DisplayFormat.hexadecimal,
      ),
    );
    // All-zero is not a valid instruction in these sets → flat hex "0".
    expect(r.fields, isEmpty);
  });

  test('x bits fall back to flat format', () {
    final r = translator.translate(
      const TranslationRequest(
        rawValue: '0000000000000000000000000000xxxx',
        bitWidth: 32,
        format: DisplayFormat.hexadecimal,
      ),
    );
    expect(r.fields, isEmpty);
  });
}

typedef TranslationResultText = ({String text, String mnemonic});
