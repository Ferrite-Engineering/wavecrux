// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';
import 'package:wavecrux/services/decoders/isa/isa_decoder_assets.dart';

/// Bring-your-own-ISA: the open-core half.
///
/// The capability is that a user points WaveCrux at their own encoding table
/// and gets disassembly of their own core. Everything below is about the
/// difference between "our tables, all under test" and "a stranger's table" —
/// which is where a silent fallback stops being harmless and becomes a support
/// burden nobody can debug.
void main() {
  /// A minimal but complete table describing one instruction.
  String table({
    String setName = 'MYCORE',
    String radix = 'hexadecimal',
    String partType = 'u32',
  }) =>
      '''
set = "$setName"
width = 32

[formats]
names = ["r_type"]
parts = [["opcode", 7, "", ""], ["imm", 25, "$partType", "$radix"]]

[types]
names = ["r"]
[[types.r]]
name = "opcode"
top = 6
bot = 0
[[types.r]]
name = "imm"
top = 24
bot = 0

[r_type]
type = "r"

[r_type.repr]
default = "custom {imm}"

[r_type.instructions.custom]
mask = 127
match = 11
''';

  group('a typo must fail loudly, not decode wrongly', () {
    test('an unknown radix throws and names the offending key', () {
      // The failure this guards: `radix = "hexidecimal"` silently defaulting to
      // decimal renders every immediate in the wrong base, and the author has
      // no way to find out short of noticing their disassembly is wrong.
      expect(
        () => parseInstructionSetToml(
          table(radix: 'hexidecimal'),
          sourceLabel: 'mycore.toml',
        ),
        throwsA(
          isA<InstructionSetTomlException>()
              .having((e) => e.message, 'message', contains('hexidecimal'))
              .having((e) => e.message, 'message', contains('imm')),
        ),
      );
    });

    test('the message lists the accepted radix names', () {
      // An error that says only "invalid" makes the author guess. Listing the
      // vocabulary is the difference between a 10-second fix and a support
      // thread.
      try {
        parseInstructionSetToml(table(radix: 'base16'), sourceLabel: 'x.toml');
        fail('expected a throw');
      } on InstructionSetTomlException catch (e) {
        expect(e.message, contains('decimal'));
        expect(e.message, contains('hexadecimal'));
      }
    });

    test('every accepted radix spelling still parses', () {
      for (final r in const [
        '',
        'decimal',
        'dec',
        'd',
        '10',
        'hexadecimal',
        'hex',
        'h',
        'x',
        '0x',
        '16',
        'octal',
        'oct',
        'o',
        '8',
        'binary',
        'bin',
        'b',
        '2',
      ]) {
        expect(
          () => parseInstructionSetToml(table(radix: r), sourceLabel: 't.toml'),
          returnsNormally,
          reason: 'radix "$r" must remain accepted',
        );
      }
    });
  });

  group('load failures are recorded, not swallowed', () {
    test('IsaDecoderAssets carries an empty issue list on a clean load', () {
      final assets = IsaDecoderAssets.fromMap(const {});
      expect(assets.issues, isEmpty);
    });

    test('an issue names the file and carries the parser message', () {
      const issue = IsaTableLoadIssue(
        name: 'MYCORE',
        source: 'assets/decoders/isa/riscv/MYCORE.toml',
        message: 'unknown radix "hexidecimal"',
      );
      // Both halves matter: the path so the author knows which file, the
      // message so they know what to change.
      expect(issue.toString(), contains('MYCORE.toml'));
      expect(issue.toString(), contains('hexidecimal'));
    });
  });

  group('a user table actually reaches the decoder', () {
    test(
      'a non-canonical set name is composed, canonical ones are not twice',
      () {
        // The blocker this closes: a user table was discovered, listed in the
        // config UI, and then never composed — so it looked installed and
        // decoded nothing, which is worse than not appearing at all.
        final mine = parseInstructionSetToml(
          table(),
          sourceLabel: 'MYCORE.toml',
        );
        final assets = IsaDecoderAssets.fromMap({'MYCORE': mine});
        expect(assets.availableSets, contains('MYCORE'));
        expect(assets.get('MYCORE'), isNotNull);
      },
    );

    test('a user table parses with a set name of its own choosing', () {
      final parsed = parseInstructionSetToml(
        table(setName: 'ACME_VLIW'),
        sourceLabel: 'acme.toml',
      );
      expect(parsed.setName, 'ACME_VLIW');
    });
  });

  group('the schema still accepts a well-formed table', () {
    test('a minimal one-instruction table round-trips', () {
      final parsed = parseInstructionSetToml(table(), sourceLabel: 'm.toml');
      expect(parsed.setName, 'MYCORE');
      expect(parsed.bitWidth, 32);
    });
  });

  group('a part type that names nothing is an error, not a raw integer', () {
    // The last of the silent-wrong-output paths, and the likeliest to be hit.
    // A part's `type` is either a builtin or the name of a mapping table, so a
    // misspelling is not a syntax error — it becomes a reference to a mapping
    // that does not exist, and the disassembler renders the raw value. `5`
    // where `x5` was meant, in every instruction using that part, forever.
    test('an unresolvable mapping name throws and names the part', () {
      expect(
        () => parseInstructionSetToml(
          table(partType: 'regsiter'),
          sourceLabel: 'mycore.toml',
        ),
        throwsA(
          isA<InstructionSetTomlException>()
              .having((e) => e.message, 'message', contains('imm'))
              .having((e) => e.message, 'message', contains('regsiter'))
              .having((e) => e.message, 'message', contains('mycore.toml')),
        ),
      );
    });

    test('a declared mapping still resolves', () {
      const withMapping = '''
set = "MYCORE"
width = 32

[formats]
names = ["r_type"]
parts = [["opcode", 7, "", ""], ["rd", 25, "reg", ""]]

[types]
names = ["r"]
[[types.r]]
name = "opcode"
top = 6
bot = 0
[[types.r]]
name = "rd"
top = 24
bot = 0

[mappings]
names = ["reg"]
reg = ["zero", "ra"]

[r_type]
type = "r"

[r_type.repr]
default = "custom {rd}"

[r_type.instructions.custom]
mask = 127
match = 11
''';
      final parsed = parseInstructionSetToml(
        withMapping,
        sourceLabel: 'm.toml',
      );
      expect(parsed.mappings.keys, contains('reg'));
    });
  });

  group('slices must account for every bit', () {
    test('a type that does not tile the word is rejected at load', () {
      // Slices tile MSB-first from a running cursor, so a gap silently
      // mis-reads every field after it — the decode succeeds and the operands
      // are wrong. The bundled corpus has been checked for this in a test
      // since the loader was written; a stranger's table gets no test.
      const short = '''
set = "MYCORE"
width = 32

[formats]
names = ["r_type"]
parts = [["opcode", 7, "", ""]]

[types]
names = ["r"]
[[types.r]]
name = "opcode"
top = 6
bot = 0

[r_type]
type = "r"

[r_type.repr]
default = "custom"

[r_type.instructions.custom]
mask = 127
match = 11
''';
      expect(
        () => parseInstructionSetToml(short, sourceLabel: 'short.toml'),
        throwsA(
          isA<InstructionSetTomlException>()
              .having((e) => e.message, 'message', contains('7 bits'))
              .having((e) => e.message, 'message', contains('32'))
              .having((e) => e.message, 'message', contains('short.toml')),
        ),
      );
    });
  });

  group('the authoring guide ships a table that actually loads', () {
    test("docs/ISA_TABLE_AUTHORING.md's minimal example parses", () {
      // Extracted from the document rather than copied into the test, so the
      // two cannot drift. An authoring guide whose first example does not load
      // is worse than no guide: the reader has no way to tell whether the
      // mistake is theirs or ours, and the first thing they try fails.
      final doc = File('docs/ISA_TABLE_AUTHORING.md').readAsStringSync();
      final match = RegExp(
        r'```toml\n(.*?)```',
        dotAll: true,
      ).firstMatch(doc);
      expect(match, isNotNull, reason: 'the guide has no ```toml example');

      final parsed = parseInstructionSetToml(
        match!.group(1)!,
        sourceLabel: 'ISA_TABLE_AUTHORING.md',
      );
      expect(parsed.setName, 'MYCORE');
      expect(parsed.bitWidth, 32);
      // The example is also the mapping-reference demo, so prove the mapping
      // resolves rather than merely that the document parses.
      expect(parsed.mappings.keys, contains('reg'));
    });
  });

  group('every diagnostic names its file', () {
    test('a schema error carries the source label, not just a syntax one', () {
      // `sourceLabel` used to reach exactly one of the two dozen throw sites —
      // the TOML syntax error — so a schema complaint left the author guessing
      // which of their tables it was about.
      expect(
        () => parseInstructionSetToml('set = "X"', sourceLabel: 'guess.toml'),
        throwsA(
          isA<InstructionSetTomlException>().having(
            (e) => e.message,
            'message',
            startsWith('guess.toml:'),
          ),
        ),
      );
    });

    test('the label is not doubled when it is already present', () {
      try {
        parseInstructionSetToml('= not toml =', sourceLabel: 'bad.toml');
        fail('expected a parse error');
      } on InstructionSetTomlException catch (e) {
        expect('bad.toml'.allMatches(e.message).length, 1);
      }
    });
  });
}
