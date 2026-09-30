// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';
import 'package:wavecrux/services/riscv/riscv_retire_stream_service.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';
import 'package:wavecrux/services/riscv/rvfi_binding_set.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';
import 'package:wavecrux/services/riscv/rvfi_detection_service.dart';

import '../../helpers/generated_vcd_fixture.dart';

const _fixturePath =
    'test/fixtures/protocol/riscv/generated/riscv_rvfi_retire.vcd';
const _expectedPath =
    'test/fixtures/protocol/riscv/generated/'
    'riscv_rvfi_retire.expected_retire_stream.json';

/// RV32 set composition — XLEN-filtered, unlike the process-wide provider,
/// so the fixture's `slli`-adjacent encodings resolve as RV32I.
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

List<Map<String, dynamic>> _expectedStream() =>
    (jsonDecode(File(_expectedPath).readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

void main() {
  late GeneratedVcdFixture fixture;
  late RvfiBindingSet bindings;
  late RiscvRetireStreamService service;

  setUp(() {
    fixture = GeneratedVcdFixture.load(_fixturePath);
    bindings = const RvfiDetectionService().detect(fixture.variables).bindings;
    service = RiscvRetireStreamService(_rv32Disassembler());
  });

  List<RiscvRetiredInstruction> buildAll() => service.build(
    source: fixture.source,
    bindings: bindings,
    startTime: fixture.source.startTime,
    endTime: fixture.source.endTime,
  );

  group('RiscvRetireStreamService against the committed fixture', () {
    test('reconstructs exactly the known-good retire stream', () {
      final actual = buildAll();
      final expected = _expectedStream();

      expect(
        actual,
        hasLength(expected.length),
        reason:
            'back-to-back retirements hold rvfi_valid high; a reader that '
            'only watches the valid edge collapses the run',
      );

      for (var i = 0; i < expected.length; i++) {
        final e = expected[i];
        final a = actual[i];
        final where = 'retire #$i (order ${e['order']})';
        expect(a.order, e['order'], reason: where);
        expect(a.time, e['time'], reason: where);
        expect(a.channelIndex, e['channelIndex'], reason: where);
        expect(a.pc, e['pc'], reason: where);
        expect(a.pcNext, e['pcNext'], reason: where);
        expect(a.insnWord, e['insn'], reason: where);
        expect(a.disassembly, e['disasm'], reason: where);
        expect(a.mnemonic, e['mnemonic'], reason: where);
        expect(a.isaSetName, e['isa'], reason: where);
        expect(a.rdAddr, e['rdAddr'], reason: where);
        expect(a.rdValue, e['rdValue'], reason: where);
        expect(a.rs1Addr, e['rs1Addr'], reason: where);
        expect(a.rs1Value, e['rs1Value'], reason: where);
        expect(a.rs2Addr, e['rs2Addr'], reason: where);
        expect(a.rs2Value, e['rs2Value'], reason: where);
        expect(a.trap, e['trap'], reason: where);
        expect(a.halt, e['halt'], reason: where);
        expect(a.intr, e['intr'], reason: where);
        expect(a.mode, e['mode'], reason: where);
        expect(a.ixl, e['ixl'], reason: where);
        expect(a.hasUnknownBits, isFalse, reason: where);

        final em = e['memory'] as Map<String, dynamic>?;
        if (em == null) {
          expect(a.memory, isNull, reason: where);
        } else {
          expect(a.memory, isNotNull, reason: where);
          expect(a.memory!.address, em['address'], reason: where);
          expect(a.memory!.rmask, em['rmask'], reason: where);
          expect(a.memory!.wmask, em['wmask'], reason: where);
          expect(a.memory!.rdata, em['rdata'], reason: where);
          expect(a.memory!.wdata, em['wdata'], reason: where);
        }
      }
    });

    test('rvfi_order is strictly increasing across the stream', () {
      final orders = [for (final r in buildAll()) r.order!];
      for (var i = 1; i < orders.length; i++) {
        expect(orders[i], greaterThan(orders[i - 1]));
      }
    });

    test('catches back-to-back retirements held under one valid pulse', () {
      final actual = buildAll();
      // Orders 0/1/2 and 4/5 retire on consecutive cycles.
      expect(actual[0].time + 10, actual[1].time);
      expect(actual[1].time + 10, actual[2].time);
      expect(actual[4].time + 10, actual[5].time);
    });

    test(
      'reuses InstructionDisassembler rather than reimplementing decode',
      () {
        final actual = buildAll();
        final direct = _rv32Disassembler().decode(actual[2].insnWord!, 32);
        expect(actual[2].disassembly, direct!.text);
        expect(actual[2].mnemonic, direct.mnemonic);
        expect(actual[2].isaSetName, direct.setName);
      },
    );

    test('reports memory effects only where a mask asserts', () {
      final withMemory = [
        for (final r in buildAll())
          if (r.memory != null) r,
      ];
      expect(withMemory, hasLength(2));
      expect(withMemory[0].memory!.isWrite, isTrue);
      expect(withMemory[0].memory!.isRead, isFalse);
      expect(withMemory[0].memory!.byteCount, 4);
      expect(withMemory[1].memory!.isRead, isTrue);
      expect(withMemory[1].memory!.isWrite, isFalse);
    });

    test('x0 writes are reported as writesRegister == false', () {
      final nop = buildAll().firstWhere((r) => r.order == 5);
      expect(nop.rdAddr, 0);
      expect(nop.writesRegister, isFalse);
    });

    test('windows the stream to the requested tick range', () {
      final windowed = service.build(
        source: fixture.source,
        bindings: bindings,
        startTime: 0,
        endTime: 30,
      );
      expect(windowed.map((r) => r.order), [0, 1, 2]);
    });

    test('returns nothing for an inverted range', () {
      expect(
        service.build(
          source: fixture.source,
          bindings: bindings,
          startTime: 50,
          endTime: 10,
        ),
        isEmpty,
      );
    });

    test('returns nothing without a valid channel', () {
      final noValid = RvfiBindingSet(
        refs: {
          for (final entry in bindings.refs.entries)
            if (entry.key != RvfiChannel.valid) entry.key: entry.value,
        },
        channelCount: 1,
      );
      expect(
        service.build(
          source: fixture.source,
          bindings: noValid,
          startTime: 0,
          endTime: fixture.source.endTime,
        ),
        isEmpty,
      );
    });

    test('renders without a disassembler, leaving disassembly null', () {
      const bare = RiscvRetireStreamService(null);
      final actual = bare.build(
        source: fixture.source,
        bindings: bindings,
        startTime: 0,
        endTime: fixture.source.endTime,
      );
      expect(actual, hasLength(8));
      expect(actual.first.insnWord, isNotNull);
      expect(actual.first.disassembly, isNull);
    });

    test('degrades to the reduced binding set without inventing values', () {
      final reduced = RvfiBindingSet(
        refs: {
          for (final entry in bindings.refs.entries)
            if (entry.key.isReducedSetMember) entry.key: entry.value,
        },
        channelCount: 1,
      );
      final actual = service.build(
        source: fixture.source,
        bindings: reduced,
        startTime: 0,
        endTime: fixture.source.endTime,
      );
      // Without rvfi_order, only the valid edges are visible — the
      // back-to-back runs collapse, and that is reported by the stream
      // being shorter rather than by a guess.
      expect(actual.length, lessThan(8));
      expect(actual.first.order, isNull);
      expect(actual.first.memory, isNull);
      expect(actual.first.rs1Addr, isNull);
      expect(actual.first.pc, isNotNull);
      expect(actual.first.disassembly, isNotNull);
    });
  });
}
