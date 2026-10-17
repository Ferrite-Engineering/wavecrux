// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The RVFI substrate against a second real core: Chili.CHIPS' eduBOS5.
//
// The Ibex capture next door (`riscv_ibex_captured_rvfi_test.dart`) was the
// first trace in this corpus whose signal names, hierarchy and timing were
// chosen by somebody else. This is the second, from an unrelated core and
// design team: a Verilator capture of eduBOS5 (BSD-3-Clause, openPCIE commit
// `a0d80cd3cb525f911cae61be4c83a44e137ed916`) with `+define+RISCV_FORMAL`,
// observed through the core's own `wavecrux/soc_cpu_view.sv`, running an
// eight-instruction RV32I loop three times. Rebuild recipe and program
// listing under `test/fixtures/protocol/riscv/captured/helpers/edubos5/`;
// attribution in `.../captured/PROVENANCE.md`.
//
// ## What the capture shows: a retirement before the first clock edge
//
// eduBOS5 executes the program correctly. Every register write, memory
// access and PC in the stream below is the one `prog.lst` predicts. Its RVFI
// account of the start of reset is not correct: the stream begins with a
// retirement that never happened.
//
// - `rvfi_valid` is a decode of the FSM state alone,
//   `rvfi_valid = (state == FETCH_INSTR)` (`edubos5.sv:647`), with no reset
//   term, and FETCH_INSTR is encoded as `3'd0` (`edubos5.sv:72`).
// - The FSM resets asynchronously
//   (`always_ff @(negedge arst_n or posedge clk)`, `edubos5.sv:394`) into
//   EXECUTE, not FETCH_INSTR (`edubos5.sv:397`). With `arst_n` already low at
//   time zero there is no falling edge of `arst_n` to run that branch, so in
//   an event-driven simulation it first runs at the first rising clock edge,
//   5 ns into this capture.
// - Until then `state` holds its power-up value. Verilator powers registers
//   up at zero, which decodes as FETCH_INSTR. So from 0 to 5 ns, with
//   `arst_n` low, the trace shows `rvfi_valid` high, `rvfi_order` 0,
//   `rvfi_pc_rdata` 0x0 and `rvfi_pc_wdata` 0x4: retirement #0 of the stream.
// - The reset branch clears `rvfi_order` (`edubos5.sv:691`) and nothing has
//   incremented it, so the first real instruction, retired at 25 ns after
//   reset is released at 20 ns, reports `rvfi_order` 0 as well.
//
// The six-rule checker therefore reports exactly two violations, both on
// retire index 1 (the first real retirement) and both caused by the phantom
// before it: `orderRegression` (`rvfi_order` 0, then 0 again) and
// `controlFlowDiscontinuity` (retirement #0 claims `rvfi_pc_wdata` 0x4,
// retirement #1 fetched from `rvfi_pc_rdata` 0x0). The other 19 retirements
// are clean under all six rules.
//
// riscv-formal cannot observe this. Its harness asserts reset in the first
// cycle (`rvfi_testbench.sv`: `assume (reset == $initstate)`), every check
// ignores `rvfi_valid` while reset is asserted, and SymbiYosys models the
// asynchronous reset with `async2sync`, which shows the reset value from the
// first cycle on: the power-up window does not exist in the formal model.
// It exists in event-driven simulation, which is where a waveform comes from.
//
// The window depends on the simulator's power-up value for `state`, so the
// Makefile pins Verilator's default (`+verilator+rand+reset+0`, all zeros)
// explicitly rather than inheriting it.
//
// If upstream eduBOS5 later keeps `rvfi_valid` low until the reset branch has
// run (for example by qualifying it with `arst_n`), a re-capture against that
// commit will lose the phantom: 20 retirements, a dense 0..19 order run and
// no violations. These expectations would then change, and that is the
// correct outcome of a re-capture rather than a regression.

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';
import 'package:wavecrux/services/riscv/riscv_consistency_checker.dart';
import 'package:wavecrux/services/riscv/riscv_retire_stream_service.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';
import 'package:wavecrux/services/riscv/riscv_trace_values.dart';
import 'package:wavecrux/services/riscv/rvfi_binding_set.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';
import 'package:wavecrux/services/riscv/rvfi_detection_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

const _fixture =
    'test/fixtures/protocol/riscv/captured/riscv_edubos5_rvfi_reset.fst';

/// Where the RVFI bundle lives: the core's own `soc_cpu_view`, instantiated
/// as `cpu_view` the way the openPCIE simulation instantiates it.
const _expectedScope = 'tb_edubos5_rvfi.cpu_view';

/// Ticks are picoseconds (`$timescale 1ps`).
const _ns = 1000;

/// The PCs of the eight-instruction program in `helpers/edubos5/prog.lst`.
const _loopPcs = [0x08, 0x0c, 0x10, 0x14, 0x18, 0x1c];

/// RV32 set composition, matching the sibling substrate tests.
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

void main() {
  if (!requireWellenFfiLibrary('eduBOS5 captured RVFI sweep')) return;

  group('eduBOS5 captured RVFI trace', () {
    late WellenProvider provider;
    late List<Variable> variables;
    late RvfiDetectionResult detection;
    late List<RiscvRetiredInstruction> retires;

    setUpAll(() async {
      provider = WellenProvider();
      await provider.openFile(_fixture);
      variables = provider.findVariables(const SignalFilter());
      // Keyed by full path, one entry per name: the shape the app hands the
      // detector (`signalVariablesByPathProvider` for the Commit Inspector's
      // auto-bind, `{v.fullPath: v}` for the CXP hand-off). See the
      // "detection keying" group for why this matters on this capture.
      detection = const RvfiDetectionService().detect({
        for (final v in variables) v.fullPath: v,
      });
      // An unloaded signal answers `valueAt` with null, which is
      // indistinguishable from "no value yet": load every bound ref first.
      for (final ref in detection.bindings.allRefs) {
        await provider.loadSignal(ref);
      }
      retires = RiscvRetireStreamService(_rv32Disassembler()).build(
        source: provider,
        bindings: detection.bindings,
        startTime: provider.startTime,
        endTime: provider.endTime,
      );
    });

    tearDownAll(() => provider.close());

    // ---------------------------------------------------------------
    // 1. Auto-detection
    // ---------------------------------------------------------------

    test('auto-detection finds the bundle at the core view scope', () {
      expect(detection.bindings.scopePath, _expectedScope);
      expect(
        detection.bindings.namePrefix,
        isEmpty,
        reason: 'soc_cpu_view spells the channels canonically',
      );
      expect(detection.report.candidateScopes, [_expectedScope]);
    });

    test('all 21 RVFI channels resolve', () {
      expect(detection.report.completeness, RvfiBindingCompleteness.full);
      expect(detection.report.missing, isEmpty);
      expect(
        detection.bindings.foundChannels.length,
        RvfiChannel.values.length,
      );
    });

    test('the bundle is single-retirement, not a packed NRET vector', () {
      expect(detection.bindings.channelCount, 1);
      expect(detection.report.packedVectorSuspected, isFalse);
    });

    // ---------------------------------------------------------------
    // 2. Detection keying: why the map is built per full path
    // ---------------------------------------------------------------

    group('detection keying', () {
      test('rvfi_trap, rvfi_halt and rvfi_intr share one signal ref', () {
        // eduBOS5 ties all three low (`edubos5.sv:649-651`) and Verilator
        // dumps the three constant nets under a single FST identifier, so
        // the trace carries three names for one signal. A fixture property,
        // not a WaveCrux choice: pinned so a re-capture that splits them is
        // noticed.
        final trap = detection.bindings.ref(RvfiChannel.trap);
        expect(trap, isNotNull);
        expect(detection.bindings.ref(RvfiChannel.halt), trap);
        expect(detection.bindings.ref(RvfiChannel.intr), trap);
        expect(
          variables.where((v) => v.signalRef == trap).map((v) => v.name),
          unorderedEquals(['rvfi_trap', 'rvfi_halt', 'rvfi_intr']),
        );
      });

      test('a map keyed by signal ref loses two of those three channels', () {
        // One Variable per ref keeps one of the three names, so detection
        // sees one flag channel where the trace has three. The app never
        // builds this map for detection; this pins what it would cost.
        final bySignalRef = const RvfiDetectionService().detect({
          for (final v in variables) v.signalRef: v,
        });
        expect(
          bySignalRef.report.completeness,
          RvfiBindingCompleteness.reduced,
        );
        expect(bySignalRef.report.missing, hasLength(2));
        expect(
          {RvfiChannel.trap, RvfiChannel.halt, RvfiChannel.intr}.containsAll(
            bySignalRef.report.missing,
          ),
          isTrue,
        );
        expect(bySignalRef.bindings.scopePath, _expectedScope);
      });
    });

    // ---------------------------------------------------------------
    // 3. Reset as the trace records it
    // ---------------------------------------------------------------

    test(
      'reset is asserted from time zero across two rising clock edges',
      () async {
        final byPath = {for (final v in variables) v.fullPath: v};
        final clk = byPath['tb_edubos5_rvfi.clk']!.signalRef;
        final arstN = byPath['tb_edubos5_rvfi.arst_n']!.signalRef;
        for (final ref in [clk, arstN]) {
          await provider.loadSignal(ref);
        }
        expect(provider.startTime, 0);
        expect(riscvBitState(provider.valueAt(arstN, 0)), RiscvBit.low);
        final release = provider
            .changesInRange(arstN, 0, provider.endTime + 1)
            .where((c) => riscvBitState(c.value) == RiscvBit.high)
            .map((c) => c.time)
            .first;
        expect(release, 20 * _ns);
        final risingUnderReset = provider
            .changesInRange(clk, 0, release)
            .where((c) => riscvBitState(c.value) == RiscvBit.high)
            .map((c) => c.time)
            .toList();
        expect(risingUnderReset, [5 * _ns, 15 * _ns]);
      },
    );

    // ---------------------------------------------------------------
    // 4. Retire-stream reconstruction
    // ---------------------------------------------------------------

    test('reconstructs 21 retirements: one phantom plus 20 real', () {
      // 2 prologue instructions + 3 passes x 6 loop instructions = 20.
      expect(retires.length, 21);
    });

    test('retirement #0 is the phantom, before the first clock edge', () {
      final phantom = retires.first;
      expect(phantom.time, 0, reason: 'rvfi_valid is high from time zero');
      expect(phantom.time, lessThan(5 * _ns));
      expect(phantom.order, 0);
      expect(phantom.pc, 0x0);
      expect(phantom.pcNext, 0x4);
      expect(phantom.insnWord, 0x00000000);
      expect(
        phantom.mnemonic,
        isNull,
        reason: 'no instruction word was fetched: imem_rdat is still zero',
      );
      expect(phantom.rdAddr, 0);
      expect(phantom.memory, isNull);
    });

    test('rvfi_order: 0 for the phantom, then a dense 0..19 run', () {
      expect(
        retires.map((r) => r.order).toList(),
        [0, ...List<int>.generate(20, (i) => i)],
      );
    });

    test('the first real retirement follows reset release', () {
      expect(retires[1].time, 25 * _ns);
      expect(retires[1].pc, 0x0);
      expect(retires[1].mnemonic, 'addi');
    });

    test('no retirement carries unknown bits', () {
      // Verilator is two-state; see the Ibex test for the same caveat.
      expect(retires.every((r) => !r.hasUnknownBits), isTrue);
    });

    test('the PC chain follows the program, three passes of the loop', () {
      expect(retires.map((r) => r.pc).toList(), [
        0x00, // phantom
        0x00,
        0x04,
        ..._loopPcs,
        ..._loopPcs,
        ..._loopPcs,
      ]);
      // Every real retirement's pc_wdata is its successor's pc_rdata; the
      // jal at 0x1c sends the core back to 0x08.
      for (var i = 1; i < retires.length - 1; i++) {
        expect(retires[i].pcNext, retires[i + 1].pc, reason: 'retire $i');
      }
      expect(retires.last.pc, 0x1c);
      expect(retires.last.pcNext, 0x08);
    });

    test('register writes match the program', () {
      // Prologue: x1 = 0, x3 = 0x100.
      expect((retires[1].rdAddr, retires[1].rdValue), (1, 0));
      expect((retires[2].rdAddr, retires[2].rdValue), (3, 0x100));
      for (var pass = 1; pass <= 3; pass++) {
        final base = 3 + (pass - 1) * 6;
        expect(
          (retires[base].rdAddr, retires[base].rdValue),
          (1, pass),
          reason: 'addi x1, x1, 1 on pass $pass',
        );
        expect(
          (retires[base + 2].rdAddr, retires[base + 2].rdValue),
          (2, pass),
          reason: 'lw x2 reads back what sw stored on pass $pass',
        );
        expect(
          (retires[base + 3].rdAddr, retires[base + 3].rdValue),
          (4, 2 * pass),
          reason: 'add x4, x1, x2 on pass $pass',
        );
        for (final noRd in [base + 1, base + 4, base + 5]) {
          expect(retires[noRd].rdAddr, 0, reason: 'sw / sb / jal x0');
          expect(retires[noRd].writesRegister, isFalse);
        }
      }
    });

    test('load and store effects carry the real byte masks', () {
      for (var pass = 1; pass <= 3; pass++) {
        final base = 3 + (pass - 1) * 6;
        // sw x1, 0(x3): full word at 0x100.
        final sw = retires[base + 1].memory!;
        expect(sw.isWrite, isTrue);
        expect((sw.address, sw.wmask, sw.wdata), (0x100, 0xf, pass));
        // lw x2, 0(x3): full word read back.
        final lw = retires[base + 2].memory!;
        expect((lw.address, lw.rmask, lw.rdata), (0x100, 0xf, pass));
        // sb x4, 5(x3): byte 0x105. eduBOS5 reports the word address and
        // byte lane 1 (`edubos5.sv:682-684`), with the byte replicated
        // across the word as it drives the bus.
        final sb = retires[base + 4].memory!;
        final byte = 2 * pass;
        expect((sb.address, sb.wmask), (0x104, 0x2));
        expect(sb.wdata, byte * 0x01010101);
      }
    });

    // ---------------------------------------------------------------
    // 5. The six-rule consistency checker
    // ---------------------------------------------------------------

    test('every rule is enabled: the bundle supports all six', () {
      final options = RiscvConsistencyCheckOptions.forBindings(
        detection.bindings,
      );
      expect(options.skippedRules, isEmpty);
      expect(options.enabledRules.length, RiscvCheckRule.values.length);
    });

    test('the full sweep totals two violations, both on retire index 1', () {
      const checker = RiscvConsistencyChecker();
      final all = checker.check(retires);
      expect(
        all.map((v) => (v.kind, v.retireIndex)).toSet(),
        {
          (RiscvViolationKind.orderRegression, 1),
          (RiscvViolationKind.controlFlowDiscontinuity, 1),
        },
        reason:
            'a different set against a pinned capture means the checker '
            'changed behaviour or the fixture was regenerated from a '
            'different eduBOS5 commit: neither should pass silently',
      );
      expect(all, hasLength(2));
      for (final v in all) {
        expect(v.time, 25 * _ns);
        expect(v.order, 0);
        expect(v.pc, 0x0);
      }
    });

    test('orderRegression: rvfi_order 0, then 0 again', () {
      const checker = RiscvConsistencyChecker();
      final v = checker.checkRule(RiscvCheckRule.retireOrder, retires).single;
      expect(v.kind, RiscvViolationKind.orderRegression);
      expect(v.args, ['0', '0']);
    });

    test('controlFlowDiscontinuity: #0 claims 0x4, #1 fetched from 0x0', () {
      const checker = RiscvConsistencyChecker();
      final v = checker.checkRule(RiscvCheckRule.controlFlow, retires).single;
      expect(v.kind, RiscvViolationKind.controlFlowDiscontinuity);
      expect(v.args, ['0x0000_0004', '0x0000_0000', 'retirement #0']);
    });

    test('without the phantom the stream is clean under all six rules', () {
      // The control: the 20 real retirements alone. Both findings belong to
      // the phantom and to nothing else in the capture.
      const checker = RiscvConsistencyChecker();
      expect(checker.check(retires.sublist(1)), isEmpty);
    });
  });

  group('fixture corpus', () {
    test('the test/ and verification/ copies are byte-identical', () {
      for (final suffix in const [
        '.fst',
        '.fixture.json',
        '.expected_transactions.json',
      ]) {
        const name = 'riscv_edubos5_rvfi_reset';
        final a = File(
          'test/fixtures/protocol/riscv/captured/$name$suffix',
        ).readAsBytesSync();
        final b = File(
          'verification/fixtures/protocol/riscv/captured/$name$suffix',
        ).readAsBytesSync();
        expect(a, b, reason: '$name$suffix differs between the two trees');
      }
    });
  });
}
