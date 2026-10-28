// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';
import 'package:wavecrux/services/riscv/riscv_retire_stream_service.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';
import 'package:wavecrux/services/riscv/rvfi_binding_set.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';
import 'package:wavecrux/services/riscv/rvfi_detection_service.dart';

import '../../helpers/fake_waveform_data_source.dart';
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
      // Without rvfi_order, the back-to-back runs held under one valid
      // pulse are still found, from the retired PC changing; the order
      // itself is not invented.
      expect(
        actual.map((r) => r.time),
        buildAll().map((r) => r.time),
        reason:
            'a core that holds rvfi_valid high across retirements must not '
            'collapse to one row per valid pulse when rvfi_order is unbound',
      );
      expect(actual.every((r) => r.order == null), isTrue);
      expect(actual.first.order, isNull);
      expect(actual.first.memory, isNull);
      expect(actual.first.rs1Addr, isNull);
      expect(actual.first.pc, isNotNull);
      expect(actual.first.disassembly, isNotNull);
    });
  });

  group('rvfi_valid held high with rvfi_order unbound', () {
    // A core that keeps rvfi_valid asserted for a whole run of retirements,
    // one per 10-tick cycle, and binds only the reduced set: no rvfi_order.
    // The PC moves on each retirement.
    final source = FakeWaveformDataSource(
      endTime: 100,
      signals: {
        'v': const [
          SignalChange(time: 0, value: '0'),
          SignalChange(time: 10, value: '1'),
          SignalChange(time: 70, value: '0'),
        ],
        'pc': const [
          SignalChange(time: 0, value: 'b0'),
          SignalChange(time: 10, value: 'b100000000'),
          SignalChange(time: 20, value: 'b100000100'),
          SignalChange(time: 30, value: 'b100001000'),
          SignalChange(time: 40, value: 'b100001100'),
        ],
        'insn': const [
          SignalChange(time: 0, value: 'b0'),
          SignalChange(time: 10, value: 'b10011'),
          SignalChange(time: 30, value: 'b110011'),
          SignalChange(time: 40, value: 'b1101111'),
        ],
      },
    );
    const reduced = RvfiBindingSet(
      refs: {
        RvfiChannel.valid: {0: 'v'},
        RvfiChannel.pcRdata: {0: 'pc'},
        RvfiChannel.insn: {0: 'insn'},
      },
      channelCount: 1,
    );

    test('a retirement is counted each time the retired PC changes', () {
      final actual = const RiscvRetireStreamService(null).build(
        source: source,
        bindings: reduced,
        startTime: 0,
        endTime: 100,
      );
      // One rising edge at 10, then the PC moves at 20, 30 and 40. The old
      // reader found only the edge and listed a single commit.
      expect(actual.map((r) => r.time), [10, 20, 30, 40]);
      expect(actual.map((r) => r.pc), [0x100, 0x104, 0x108, 0x10c]);
      expect(actual.every((r) => r.order == null), isTrue);
    });

    test('changes while rvfi_valid is low are not retirements', () {
      final actual = const RiscvRetireStreamService(null).build(
        source: source,
        bindings: reduced,
        startTime: 0,
        endTime: 100,
      );
      expect(actual.map((r) => r.time), isNot(contains(0)));
    });
  });

  group('multi-slot rvfi_mem_* ports (CV32E40X NMEM)', () {
    // Zcmp `cm.push {ra, s0}, -16` with sp = 0x380 retires once and stores
    // two words, in two 32-bit slots of the wide memory ports:
    //   slot 0: addr 0x37c, wmask 0xf, wdata 0x5a  (s0)
    //   slot 1: addr 0x378, wmask 0xf, wdata 0x123 (ra)
    String bits(BigInt v) => 'b${v.toRadixString(2)}';
    final addr = (BigInt.from(0x378) << 32) | BigInt.from(0x37c);
    final wdata = (BigInt.from(0x123) << 32) | BigInt.from(0x5a);

    FakeWaveformDataSource source({
      bool withIxl = true,
      int pcWidth = 32,
      String wmask = 'b11111111',
      String? addrBits,
      String? wdataBits,
    }) {
      Variable v(String name, int width) => Variable(
        name: name,
        varType: VarType.wire,
        direction: VarDirection.unknown,
        signalRef: name,
        scopePath: 'tb',
        bitWidth: width,
      );
      return FakeWaveformDataSource(
        endTime: 100,
        scopes: [
          Scope(
            name: 'tb',
            type: ScopeType.module,
            path: 'tb',
            variables: [
              v('rvfi_valid', 1),
              v('rvfi_pc_rdata', pcWidth),
              v('rvfi_mem_addr', 4096),
            ],
          ),
        ],
        signals: {
          'rvfi_valid': const [
            SignalChange(time: 0, value: '0'),
            SignalChange(time: 10, value: '1'),
            SignalChange(time: 20, value: '0'),
          ],
          'rvfi_pc_rdata': const [SignalChange(time: 0, value: 'b11101100')],
          'rvfi_insn': const [
            SignalChange(time: 0, value: 'b1011100001010010'),
          ],
          'rvfi_ixl': ?(withIxl
              ? const [SignalChange(time: 0, value: 'b01')]
              : null),
          'rvfi_mem_addr': [
            SignalChange(time: 0, value: addrBits ?? bits(addr)),
          ],
          'rvfi_mem_rmask': const [SignalChange(time: 0, value: 'b0')],
          'rvfi_mem_wmask': [SignalChange(time: 0, value: wmask)],
          'rvfi_mem_wdata': [
            SignalChange(time: 0, value: wdataBits ?? bits(wdata)),
          ],
        },
      );
    }

    RvfiBindingSet bindingsFor(FakeWaveformDataSource src, {bool ixl = true}) =>
        RvfiBindingSet(
          refs: {
            RvfiChannel.valid: const {0: 'rvfi_valid'},
            RvfiChannel.pcRdata: const {0: 'rvfi_pc_rdata'},
            RvfiChannel.insn: const {0: 'rvfi_insn'},
            if (ixl) RvfiChannel.ixl: const {0: 'rvfi_ixl'},
            RvfiChannel.memAddr: const {0: 'rvfi_mem_addr'},
            RvfiChannel.memRmask: const {0: 'rvfi_mem_rmask'},
            RvfiChannel.memWmask: const {0: 'rvfi_mem_wmask'},
            RvfiChannel.memWdata: const {0: 'rvfi_mem_wdata'},
          },
          channelCount: 1,
        );

    RiscvRetiredInstruction only(
      FakeWaveformDataSource src, {
      bool ixl = true,
    }) => const RiscvRetireStreamService(null)
        .build(
          source: src,
          bindings: bindingsFor(src, ixl: ixl),
          startTime: 0,
          endTime: 100,
        )
        .single;

    test('splits the ports into one access per active slot', () {
      final r = only(source());
      expect(r.memoryEffects, hasLength(2));
      final [s0, s1] = r.memoryEffects;
      expect((s0.address, s0.wmask, s0.wdata), (0x37c, 0xf, 0x5a));
      expect((s1.address, s1.wmask, s1.wdata), (0x378, 0xf, 0x123));
      expect(r.memory, s0);
      expect(r.additionalMemory, [s1]);
    });

    test('takes XLEN from the declared rvfi_pc_rdata width without ixl', () {
      final r = only(source(withIxl: false), ixl: false);
      expect(r.memoryEffects.map((e) => e.address), [0x37c, 0x378]);
    });

    test('omits a slot whose masks are both zero', () {
      // Slots 0 and 1 idle, slot 2 active: one effect, at slot 2's address.
      final r = only(
        source(
          wmask: 'b111100000000',
          addrBits: bits(BigInt.from(0x400) << 64 | BigInt.from(0x37c)),
          wdataBits: bits(BigInt.from(7) << 64),
        ),
      );
      expect(r.memoryEffects, hasLength(1));
      expect(r.memory!.address, 0x400);
      expect(r.memory!.wdata, 7);
    });

    test('a single RV64 access is not split', () {
      // An 8-byte store on a 64-bit core: wmask 0xff is one access at XLEN 64.
      final src = FakeWaveformDataSource(
        endTime: 100,
        signals: {
          'rvfi_valid': const [
            SignalChange(time: 0, value: '0'),
            SignalChange(time: 10, value: '1'),
          ],
          'rvfi_pc_rdata': const [SignalChange(time: 0, value: 'b100')],
          'rvfi_insn': const [SignalChange(time: 0, value: 'b10011')],
          'rvfi_ixl': const [SignalChange(time: 0, value: 'b10')],
          'rvfi_mem_addr': [
            SignalChange(time: 0, value: bits(BigInt.from(0x100000008))),
          ],
          'rvfi_mem_rmask': const [SignalChange(time: 0, value: 'b0')],
          'rvfi_mem_wmask': const [SignalChange(time: 0, value: 'b11111111')],
          'rvfi_mem_wdata': const [SignalChange(time: 0, value: 'b101')],
        },
      );
      final r = only(src);
      expect(r.memoryEffects, hasLength(1));
      expect(r.memory!.address, 0x100000008);
      expect(r.memory!.wmask, 0xff);
    });
  });
}
