// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';
import 'package:wavecrux/services/riscv/riscv_consistency_checker.dart';
import 'package:wavecrux/services/riscv/riscv_retire_stream_service.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';
import 'package:wavecrux/services/riscv/rvfi_detection_service.dart';

import '../../helpers/generated_vcd_fixture.dart';

/// The pairing that is the Commit Inspector's core test surface: one
/// deliberately corrupted fixture per checker rule that **must** fire it, and
/// the clean fixture that **must not** fire anything.
///
/// A checker with a broken rule and a checker with no rules are the same
/// thing from the outside — a panel that says "no violations". Only the
/// corrupted half of this pairing can tell them apart, which is why every
/// rule is required to have one.
const _fixtureDir = 'test/fixtures/protocol/riscv/generated';
const _cleanFixture = '$_fixtureDir/riscv_rvfi_retire.vcd';

const _corruptedFixtures = <String>[
  'riscv_rvfi_bad_pc_wdata',
  'riscv_rvfi_bad_x0_write',
  'riscv_rvfi_bad_rd_addr',
  'riscv_rvfi_bad_mem_mask',
  'riscv_rvfi_bad_order',
  'riscv_rvfi_bad_trap',
];

/// RV32 set composition — XLEN-filtered, so the fixture's `slli`-adjacent
/// encodings resolve as RV32I rather than being shadowed by RV64I.
InstructionDisassembler _rv32Disassembler() {
  const names = ['RV32I', 'RV32M', 'RV32A', 'RV32F', 'RV32C-lower'];
  return InstructionDisassembler(<InstructionSet>[
    for (final n in names)
      parseInstructionSetToml(
        File('assets/decoders/isa/riscv/$n.toml').readAsStringSync(),
        sourceLabel: '$n.toml',
      ),
  ]);
}

List<RiscvRetiredInstruction> _streamFor(String path) {
  final fixture = GeneratedVcdFixture.load(path);
  final bindings = const RvfiDetectionService()
      .detect(fixture.variables)
      .bindings;
  return RiscvRetireStreamService(_rv32Disassembler()).build(
    source: fixture.source,
    bindings: bindings,
    startTime: fixture.source.startTime,
    endTime: fixture.source.endTime,
  );
}

Map<String, dynamic> _expectationFor(String name) =>
    jsonDecode(
          File(
            '$_fixtureDir/$name.expected_violations.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  const checker = RiscvConsistencyChecker();

  group('the clean fixture must not fire any rule', () {
    late List<RiscvConsistencyViolation> violations;
    late List<RiscvRetiredInstruction> stream;

    setUp(() {
      stream = _streamFor(_cleanFixture);
      violations = checker.check(stream);
    });

    test('the fixture actually decoded — otherwise "clean" is vacuous', () {
      expect(stream, hasLength(8));
      expect(stream.first.disassembly, 'addi t0, zero, 5');
    });

    test('no violations at all', () {
      expect(
        violations,
        isEmpty,
        reason: violations.map((v) => v.detail).join('\n'),
      );
    });

    test('every rule individually reports nothing', () {
      for (final rule in RiscvCheckRule.values) {
        expect(
          checker.checkRule(rule, stream),
          isEmpty,
          reason: '$rule fired on the clean RVFI fixture',
        );
      }
    });
  });

  for (final name in _corruptedFixtures) {
    group('$name — the corrupted half of the pairing', () {
      late Map<String, dynamic> expectation;
      late List<RiscvRetiredInstruction> stream;
      late RiscvCheckRule targetRule;
      late List<Map<String, dynamic>> expectedViolations;

      setUp(() {
        expectation = _expectationFor(name);
        stream = _streamFor('$_fixtureDir/$name.vcd');
        targetRule = RiscvCheckRule.values.firstWhere(
          (r) => r.name == expectation['rule'],
        );
        expectedViolations = (expectation['expectedViolations'] as List)
            .cast<Map<String, dynamic>>();
      });

      test('the program still decodes — only the RVFI claims are corrupt', () {
        expect(stream, hasLength(8));
        for (final r in stream) {
          expect(r.disassembly, isNotNull, reason: 'order ${r.order}');
        }
      });

      test('the target rule fires exactly the expected violations', () {
        final fired = checker.checkRule(targetRule, stream);
        expect(
          fired,
          hasLength(expectedViolations.length),
          reason:
              '${expectation['description']}\n'
              'fired: ${fired.map((v) => v.detail).join('; ')}',
        );
        for (var i = 0; i < expectedViolations.length; i++) {
          final e = expectedViolations[i];
          expect(fired[i].kind.name, e['kind']);
          expect(fired[i].severity.name, e['severity']);
          expect(fired[i].order, e['order']);
          // The violation must point at a real retirement, so a click on it
          // lands the cursor somewhere in the trace.
          expect(
            stream.map((r) => r.time),
            contains(fired[i].time),
            reason: 'violation time is not a retirement tick',
          );
          expect(fired[i].detail, isNotEmpty);
          expect(fired[i].args, hasLength(fired[i].kind.argCount));
        }
      });

      test('no other rule fires — the corruption is surgical', () {
        for (final rule in RiscvCheckRule.values) {
          if (rule == targetRule) continue;
          expect(
            checker.checkRule(rule, stream),
            isEmpty,
            reason:
                '$rule also fired on $name, so the fixture does not isolate '
                '${targetRule.name}',
          );
        }
      });

      test('check() surfaces the same violations as the rule alone', () {
        expect(
          checker.check(stream).map((v) => v.kind),
          checker.checkRule(targetRule, stream).map((v) => v.kind),
        );
      });
    });
  }

  group('fixture coverage', () {
    test('every checker rule has a corrupted fixture', () {
      final covered = <RiscvCheckRule>{
        for (final name in _corruptedFixtures)
          RiscvCheckRule.values.firstWhere(
            (r) => r.name == _expectationFor(name)['rule'],
          ),
      };
      expect(
        covered,
        RiscvCheckRule.values.toSet(),
        reason:
            'a rule without a fixture that fires it is indistinguishable '
            'from a rule that never fires',
      );
    });

    test('the verification tree carries the same fixtures', () {
      for (final name in _corruptedFixtures) {
        final test = File('$_fixtureDir/$name.vcd').readAsStringSync();
        final verification = File(
          'verification/fixtures/protocol/riscv/generated/$name.vcd',
        ).readAsStringSync();
        expect(verification, test, reason: '$name.vcd diverged between trees');
      }
    });
  });
}
