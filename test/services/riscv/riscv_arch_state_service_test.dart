// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';
import 'package:wavecrux/services/riscv/riscv_arch_state.dart';
import 'package:wavecrux/services/riscv/riscv_arch_state_service.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';
import 'package:wavecrux/services/riscv/rvfi_binding_set.dart';
import 'package:wavecrux/services/riscv/rvfi_detection_service.dart';

import '../../helpers/generated_vcd_fixture.dart';

const _fixturePath =
    'test/fixtures/protocol/riscv/generated/riscv_rvfi_retire.vcd';

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

RiscvRetiredInstruction _retire({
  required int time,
  required int order,
  int? rdAddr,
  int? rdValue,
  int? pc,
  int? pcNext,
  bool trap = false,
  bool halt = false,
  int mode = 3,
  RiscvMemoryEffect? memory,
}) => RiscvRetiredInstruction(
  time: time,
  channelIndex: 0,
  order: order,
  pc: pc,
  pcNext: pcNext,
  rdAddr: rdAddr,
  rdValue: rdValue,
  memory: memory,
  trap: trap,
  halt: halt,
  mode: mode,
);

void main() {
  late GeneratedVcdFixture fixture;
  late RvfiBindingSet bindings;
  late RiscvArchStateService service;

  setUp(() {
    fixture = GeneratedVcdFixture.load(_fixturePath);
    bindings = const RvfiDetectionService().detect(fixture.variables).bindings;
    service = RiscvArchStateService.withDisassembler(_rv32Disassembler());
  });

  RiscvArchState at(int cursor) => service.build(
    source: fixture.source,
    bindings: bindings,
    cursorTime: cursor,
  );

  group('RiscvArchStateService replay against the committed fixture', () {
    test('is empty before the first retirement', () {
      final state = at(0);
      expect(state.retiredCount, 0);
      expect(state.registers, isEmpty);
      expect(state.pc, isNull);
      expect(state.lastRetire, isNull);
    });

    test('folds register writes in retirement order', () {
      // After `addi t0, zero, 5` only x5 is known.
      final afterFirst = at(4);
      expect(afterFirst.retiredCount, 1);
      expect(afterFirst.registerValue(5), 5);
      expect(afterFirst.registerValue(6), isNull);

      // After `add t2, t0, t1`.
      final afterThird = at(24);
      expect(afterThird.retiredCount, 3);
      expect(afterThird.registerValue(5), 5);
      expect(afterThird.registerValue(6), 7);
      expect(afterThird.registerValue(7), 12);
    });

    test('tracks the architectural PC from rvfi_pc_wdata', () {
      expect(at(4).pc, 0x80000004);
      expect(at(24).pc, 0x8000000c);
      // The taken branch retires at order 6 and redirects the PC.
      expect(at(94).pc, 0x80000028);
    });

    test('x0 is hardwired zero and never appears in the register map', () {
      final state = at(fixture.source.endTime);
      expect(state.registerValue(0), 0);
      expect(state.registers.containsKey(0), isFalse);
    });

    test('collects memory effects in access order', () {
      final state = at(fixture.source.endTime);
      expect(state.memoryEffects, hasLength(2));
      expect(state.memoryEffects.first.isWrite, isTrue);
      expect(state.memoryEffects.first.address, 0x1000);
      expect(state.memoryEffects.last.isRead, isTrue);
      expect(state.memoryEffects.last.rdata, 12);
    });

    test('counts traps and carries the privilege mode', () {
      final state = at(fixture.source.endTime);
      expect(state.trapCount, 1);
      expect(state.privilegeMode, 3);
      expect(state.halted, isFalse);
    });

    // ── the stateless rebuild-on-backward-seek contract ────────────────────

    test('a backward seek rebuilds rather than retaining forward state', () {
      final late = at(fixture.source.endTime);
      expect(late.registerValue(8), 12);

      final early = at(14);
      expect(early.retiredCount, 2);
      expect(
        early.registerValue(8),
        isNull,
        reason:
            'x8 is written later in the trace; a cached fold would leak '
            'it backwards',
      );
      expect(early.registerValue(5), 5);
    });

    test('is deterministic — the same cursor rebuilds the same state', () {
      final first = at(64);
      // Walk forwards and back again before re-measuring.
      at(fixture.source.endTime);
      at(0);
      final second = at(64);
      expect(second.retiredCount, first.retiredCount);
      expect(second.pc, first.pc);
      expect(second.registers.length, first.registers.length);
      for (final entry in first.registers.entries) {
        expect(second.registers[entry.key], entry.value);
      }
    });

    test('clamps the cursor into the trace range', () {
      final beforeStart = at(-500);
      expect(beforeStart.retiredCount, 0);

      final pastEnd = at(fixture.source.endTime + 10_000);
      expect(pastEnd.retiredCount, 8);
      expect(pastEnd.cursorTime, fixture.source.endTime + 10_000);
    });
  });

  group('RiscvArchStateService.buildFromRetires', () {
    test('breaks hard on the first retirement past the cursor', () {
      final state = service.buildFromRetires(
        retires: [
          _retire(time: 10, order: 0, rdAddr: 1, rdValue: 0xaa),
          _retire(time: 20, order: 1, rdAddr: 2, rdValue: 0xbb),
          _retire(time: 30, order: 2, rdAddr: 3, rdValue: 0xcc),
        ],
        cursorTime: 20,
      );
      expect(state.retiredCount, 2);
      expect(state.registerValue(2), 0xbb);
      expect(state.registerValue(3), isNull);
    });

    test('declines to record a write to x0 whatever rd_wdata carries', () {
      // The deliberately-inconsistent case the Commit Inspector's checker
      // exists to flag: rd_addr == 0 with a non-zero rd_wdata. The replay
      // must not fabricate an architectural x0 write from it.
      final state = service.buildFromRetires(
        retires: [_retire(time: 10, order: 0, rdAddr: 0, rdValue: 0xdead)],
        cursorTime: 100,
      );
      expect(state.registers, isEmpty);
      expect(state.registerValue(0), 0);
    });

    test('ignores a register index outside the configured file', () {
      final state = service.buildFromRetires(
        retires: [_retire(time: 10, order: 0, rdAddr: 40, rdValue: 1)],
        cursorTime: 100,
      );
      expect(state.registers, isEmpty);
    });

    test('honors an RV32E-sized register file', () {
      final state = service.buildFromRetires(
        retires: [
          _retire(time: 10, order: 0, rdAddr: 8, rdValue: 1),
          _retire(time: 20, order: 1, rdAddr: 20, rdValue: 2),
        ],
        cursorTime: 100,
        config: const RiscvArchStateConfig(registerCount: 16),
      );
      expect(state.registerValue(8), 1);
      expect(state.registerValue(20), isNull);
    });

    test('keeps only the most recent N memory effects', () {
      final state = service.buildFromRetires(
        retires: [
          for (var i = 0; i < 10; i++)
            _retire(
              time: i * 10,
              order: i,
              memory: RiscvMemoryEffect(
                time: i * 10,
                order: i,
                address: 0x100 + i,
                rmask: 0xf,
                wmask: 0,
                rdata: i,
              ),
            ),
        ],
        cursorTime: 1000,
        config: const RiscvArchStateConfig(memoryEffectDepth: 3),
      );
      expect(state.memoryEffects, hasLength(3));
      expect(state.memoryEffects.first.address, 0x107);
      expect(state.memoryEffects.last.address, 0x109);
    });

    test('falls back to pc when the trace omits pc_wdata', () {
      final state = service.buildFromRetires(
        retires: [_retire(time: 10, order: 0, pc: 0x2000)],
        cursorTime: 100,
      );
      expect(state.pc, 0x2000);
    });

    test('records a halt', () {
      final state = service.buildFromRetires(
        retires: [_retire(time: 10, order: 0, halt: true)],
        cursorTime: 100,
      );
      expect(state.halted, isTrue);
    });
  });
}
