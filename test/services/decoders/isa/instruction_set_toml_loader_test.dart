// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';

void main() {
  group('parseInstructionSetToml', () {
    test('parses a minimal valid TOML', () {
      const text = r'''
set = "TEST"
width = 32

[formats]
names = ["rtype"]
parts = [
    ["rd", 5, "Register_int"],
    ["rs1", 5, "Register_int"],
    ["rs2", 5, "Register_int"],
    ["none", 32, "u32"],
]

[types]
names = ["t_r"]

[[types.t_r]]
name = "none"
top = 31
bot = 25
[[types.t_r]]
name = "rs2"
top = 24
bot = 20
[[types.t_r]]
name = "rs1"
top = 19
bot = 15
[[types.t_r]]
name = "none"
top = 14
bot = 12
[[types.t_r]]
name = "rd"
top = 11
bot = 7
[[types.t_r]]
name = "none"
top = 6
bot = 0

[mappings]
names = ["Register_int"]
Register_int = ["zero", "ra", "sp"]

[rtype]
type = "t_r"

[rtype.repr]
default = "$name$ %rd%, %rs1%, %rs2%"

[rtype.instructions.add]
mask = 0xfe00707f
match = 0x00000033
''';
      final iset = parseInstructionSetToml(text);
      expect(iset.setName, 'TEST');
      expect(iset.bitWidth, 32);
      expect(iset.parts.length, 4);
      expect(iset.parts['rd']!.partType, PartType.mapping);
      expect(iset.parts['rd']!.mappingName, 'Register_int');
      expect(iset.mappings['Register_int']!.names[0], 'zero');
      expect(iset.formats, hasLength(1));
      expect(iset.formats[0].name, 'rtype');
      expect(iset.formats[0].instructions, hasLength(1));
      expect(iset.formats[0].instructions[0].name, 'add');
      expect(iset.formats[0].instructions[0].mask, 0xfe00707f);
      expect(iset.formats[0].instructions[0].match, 0x00000033);
    });

    test('throws on missing required top-level key', () {
      const text = 'width = 32';
      expect(
        () => parseInstructionSetToml(text),
        throwsA(isA<InstructionSetTomlException>()),
      );
    });

    test('throws on width out of range', () {
      const text = '''
set = "X"
width = 0
[formats]
names = []
parts = []
[types]
names = []
''';
      expect(
        () => parseInstructionSetToml(text),
        throwsA(isA<InstructionSetTomlException>()),
      );
    });

    test('tolerates unknown top-level keys (forward-compat)', () {
      const text = '''
set = "X"
width = 32
wavecrux_schema_version = 1
fictional_future_block = "anything"
[formats]
names = []
parts = []
[types]
names = []
''';
      final iset = parseInstructionSetToml(text);
      expect(iset.setName, 'X');
      expect(iset.bitWidth, 32);
    });

    test('parses mapping table (non-strict) form', () {
      const text = '''
set = "X"
width = 32
[formats]
names = []
parts = []
[types]
names = []
[mappings]
names = ["Custom"]
[mappings.Custom]
0 = "zero"
16 = "sixteen"
''';
      final iset = parseInstructionSetToml(text);
      final m = iset.mappings['Custom']!;
      expect(m.strict, isFalse);
      expect(m.names[0], 'zero');
      expect(m.names[16], 'sixteen');
    });

    test('parses radix variants', () {
      const text = '''
set = "X"
width = 32
[formats]
names = []
parts = [
    ["a", 8, "u8", "hex"],
    ["b", 8, "u8", "binary"],
    ["c", 8, "u8", "octal"],
    ["d", 8, "u8"],
]
[types]
names = []
''';
      final iset = parseInstructionSetToml(text);
      expect(iset.parts['a']!.numberRadix, NumberRadix.hexadecimal);
      expect(iset.parts['b']!.numberRadix, NumberRadix.binary);
      expect(iset.parts['c']!.numberRadix, NumberRadix.octal);
      expect(iset.parts['d']!.numberRadix, NumberRadix.decimal);
    });
  });

  group('Bundled RISC-V TOMLs (asset files on disk)', () {
    // These tests load the actual bundled files from the filesystem (not
    // via rootBundle, which would require a Flutter test surface) to verify
    // that every shipped TOML parses cleanly with our loader.
    final dir = Directory('assets/decoders/isa/riscv');

    for (final name in const [
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
    ]) {
      test('$name.toml parses without error', () {
        final file = File('${dir.path}/$name.toml');
        expect(
          file.existsSync(),
          isTrue,
          reason: '${file.path} must exist (asset bundled)',
        );
        final text = file.readAsStringSync();
        final iset = parseInstructionSetToml(text, sourceLabel: '$name.toml');
        expect(iset.setName, isNotEmpty);
        expect(iset.bitWidth, 32);
        expect(iset.formats, isNotEmpty);
        expect(
          iset.parts['none']?.partType,
          anyOf(PartType.u32, isNull),
          reason: 'parts["none"] when present should be a filler type',
        );
      });
    }
  });
}
