// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The RVFI substrate exercised against a *captured* trace from a real core.
//
// Every other RVFI fixture in this repo is produced by
// `tool/generate_riscv_fixtures.dart` — we write the RTL-shaped signal
// names, we choose the hierarchy depth, we decide what a retirement looks
// like. That makes those fixtures excellent regression locks and useless as
// evidence: a substrate that only ever meets its own generator has never
// been tested against anything.
//
// This fixture is a Verilator capture of lowRISC's Ibex (Apache-2.0) with
// `+define+RVFI`, running a hand-assembled RV32I program. Nothing about the
// signal naming, the hierarchy, the channel widths or the retirement timing
// was chosen by us — it is whatever Ibex actually emits. See
// `test/fixtures/protocol/riscv/captured/PROVENANCE.md` and the rebuild
// recipe under `.../captured/helpers/ibex/`.
//
// ## The interesting part: the checker is not silent
//
// The brief for this capture expected zero consistency violations, on the
// reasoning that Ibex is a correct core. Ibex *is* a correct core — it
// executes this program exactly right, and the decoded instruction stream in
// `riscv_ibex_rvfi_trap.expected_transactions.json` proves it. But its RVFI
// *reporting* deviates from the RVFI specification in one place — 19 of the
// 26 retirements — and this test pins it rather than suppressing it.
//
// It pinned 21 until 2026-08-20. The other two were **our** bug, not Ibex's:
// `controlFlow` and `trapConsistency` both fired at the `ecall`, where Ibex
// reports the sequential next PC and flags the handler entry with
// `rvfi_intr`. That pairing is what RVFI *defines* as handler entry, and
// riscv-formal's `checks/rvfi_pc_fwd_check.sv` exempts it explicitly. Both
// rules now consult `rvfi_intr`; this file is the regression lock on that.
// Details in `verification/VERIFICATION_GUIDE.md` §10B.

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';
import 'package:wavecrux/services/riscv/riscv_consistency_checker.dart';
import 'package:wavecrux/services/riscv/riscv_retire_stream_service.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';
import 'package:wavecrux/services/riscv/rvfi_binding_set.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';
import 'package:wavecrux/services/riscv/rvfi_detection_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

const _fixture =
    'test/fixtures/protocol/riscv/captured/riscv_ibex_rvfi_trap.fst';

/// The scope Ibex's RVFI bundle actually lives at in the capture. Detection
/// has to find this without being told — three levels of name to get past
/// (`tb_ibex_rvfi` → `u_ibex_top` → leaf) and 21 sibling channels to group.
const _expectedScope = 'tb_ibex_rvfi.u_ibex_top';

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
  if (!requireWellenFfiLibrary('Ibex captured RVFI sweep')) return;

  group('Ibex captured RVFI trace', () {
    late WellenProvider provider;
    late RvfiDetectionResult detection;
    late List<RiscvRetiredInstruction> retires;

    setUpAll(() async {
      provider = WellenProvider();
      await provider.openFile(_fixture);
      final variables = provider.findVariables(const SignalFilter());
      detection = const RvfiDetectionService().detect({
        for (final v in variables) v.signalRef: v,
      });
      // An unloaded signal answers `valueAt` with null, which is
      // indistinguishable from "no value yet" — load every bound ref first.
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
    // 1. Auto-detection against names nobody here chose
    // ---------------------------------------------------------------

    test('auto-detection finds the bundle at the real core scope', () {
      expect(detection.bindings.scopePath, _expectedScope);
      expect(
        detection.bindings.namePrefix,
        isEmpty,
        reason:
            'Ibex spells the channels canonically — no vendor prefix to strip',
      );
    });

    test('all 21 known RVFI channels resolve', () {
      expect(detection.report.completeness, RvfiBindingCompleteness.full);
      expect(detection.report.missing, isEmpty);
      expect(
        detection.bindings.foundChannels.length,
        RvfiChannel.values.length,
      );
    });

    test('the bundle is single-retirement, not a packed NRET vector', () {
      // Ibex's RVFI_STAGES is an internal array; the *ports* are scalar.
      expect(detection.bindings.channelCount, 1);
      expect(detection.report.packedVectorSuspected, isFalse);
    });

    test('detection is not fooled by the rvfi_ext_* siblings', () {
      // ibex_top also exposes rvfi_ext_mcycle, rvfi_ext_pre_mip, and friends.
      // None of them are RVFI channels, and none must be bound to one.
      for (final channel in RvfiChannel.values) {
        final ref = detection.bindings.ref(channel);
        expect(ref, isNotNull, reason: '${channel.signalName} unbound');
      }
    });

    // ---------------------------------------------------------------
    // 2. Retire-stream reconstruction
    // ---------------------------------------------------------------

    test('reconstructs 26 retirements', () {
      expect(retires.length, 26);
    });

    test('rvfi_order is a dense 1..26 run', () {
      expect(
        retires.map((r) => r.order).toList(),
        List<int>.generate(26, (i) => i + 1),
      );
    });

    test('no retirement carries unknown bits', () {
      // Verilator is a two-state simulator, so this fixture cannot exercise
      // X-propagation. Recorded here so the absence is deliberate rather
      // than assumed — a four-state capture would flip this expectation.
      expect(retires.every((r) => !r.hasUnknownBits), isTrue);
    });

    test('the PC chain follows the program, including both branches', () {
      final pcs = retires.map((r) => r.pc).toList();
      // Reset vector is boot_addr_i + 0x80.
      expect(pcs.first, 0x80);
      // beq at 0x9c is taken: 0xa0 is never retired.
      expect(pcs, isNot(contains(0xa0)));
      // The countdown loop re-enters 0xc0 three times via the backward bne.
      expect(pcs.where((pc) => pc == 0xc0).length, 3);
    });

    test('the ecall traps and the handler is entered at the vector', () {
      final ecall = retires[21];
      expect(ecall.pc, 0xc8);
      expect(ecall.mnemonic, 'ecall');
      expect(ecall.trap, isTrue);
      // mtvec resets to boot_addr_i, so the handler sits at 0x000.
      expect(retires[22].pc, 0x00);
      expect(retires[22].intr, isTrue);
    });

    test('load and store effects carry the real byte masks', () {
      // sw gp, 0(t0)  — full word write at 0x200
      expect(retires[5].memory!.isWrite, isTrue);
      expect(retires[5].memory!.address, 0x200);
      expect(retires[5].memory!.wmask, 0xf);
      expect(retires[5].memory!.wdata, 0x579);
      // lw t1, 0(t0)  — full word read back
      expect(retires[6].memory!.rmask, 0xf);
      expect(retires[6].memory!.rdata, 0x579);
      // sb s0, 4(t0)  — single byte
      expect(retires[9].memory!.wmask, 0x1);
      expect(retires[9].memory!.address, 0x204);
      // sh gp, 8(t0)  — halfword
      expect(retires[11].memory!.wmask, 0x3);
      expect(retires[11].memory!.address, 0x208);
    });

    test('register writes match the program', () {
      expect(retires[0].rdAddr, 1);
      expect(retires[0].rdValue, 0x123);
      expect(retires[2].rdAddr, 3);
      expect(retires[2].rdValue, 0x579); // 0x123 + 0x456
      expect(retires[13].rdValue, 0x64a); // 0x579 ^ 0x333
    });

    test('x0-targeting retirements report a zero write', () {
      // Stores and branches have no rd; Ibex reports rd_addr = 0.
      final storeRetire = retires[5];
      expect(storeRetire.rdAddr, 0);
      expect(storeRetire.writesRegister, isFalse);
    });

    // ---------------------------------------------------------------
    // 3. The six-rule consistency checker
    // ---------------------------------------------------------------

    test('every rule is enabled — the bundle supports all six', () {
      final options = RiscvConsistencyCheckOptions.forBindings(
        detection.bindings,
      );
      expect(options.skippedRules, isEmpty);
      expect(options.enabledRules.length, RiscvCheckRule.values.length);
    });

    test('five of the six rules are clean', () {
      // The five rules Ibex's RVFI satisfies. `controlFlow` and
      // `trapConsistency` were on the other list until 2026-08-20: the
      // `ecall` at 0x0c8 retires with pc_wdata = 0x0cc (PC+4) and the
      // handler's first retirement asserts `rvfi_intr`, which is exactly
      // the pairing RVFI defines as handler entry. Both rules used to fire
      // there and both were wrong; riscv-formal's own
      // `checks/rvfi_pc_fwd_check.sv` exempts the same case.
      const checker = RiscvConsistencyChecker();
      for (final rule in const [
        RiscvCheckRule.x0Write,
        RiscvCheckRule.destinationRegister,
        RiscvCheckRule.retireOrder,
        RiscvCheckRule.controlFlow,
        RiscvCheckRule.trapConsistency,
      ]) {
        expect(
          checker.checkRule(rule, retires),
          isEmpty,
          reason: '${rule.name} fired against a correct core',
        );
      }
    });

    // The one genuine Ibex RVFI deviation this capture carries.
    test('memoryAccess fires on every non-store — Ibex deviation #1', () {
      const checker = RiscvConsistencyChecker();
      final violations = checker.checkRule(
        RiscvCheckRule.memoryAccess,
        retires,
      );
      expect(
        violations.every(
          (v) => v.kind == RiscvViolationKind.memoryAccessUnexpected,
        ),
        isTrue,
        reason:
            'the deviation is exactly "a read that never happened", not a '
            'size/alignment/contiguity problem — if another kind appears, '
            'the cause is something new and must be re-investigated',
      );
      // 26 retirements, minus the six genuine memory accesses (three
      // stores, which correctly report rmask = 0, and three loads), minus
      // the trapping `ecall` — memoryAccess is skipped on trap, so the
      // deviation is present on 20 retirements but reported on 19.
      expect(violations.length, 19);
      // The real memory instructions are *not* among the complaints.
      final flagged = violations.map((v) => v.retireIndex).toSet();
      for (final memoryRetire in const [5, 6, 9, 10, 11, 12]) {
        expect(
          flagged,
          isNot(contains(memoryRetire)),
          reason: 'retire $memoryRetire is a genuine memory access',
        );
      }
    });

    test(
      'the ecall trap is handler entry, not a violation — rvfi_intr exemption',
      () {
        // pc_wdata(ecall @ 0x0c8) = 0x0cc (PC+4) and retire 22 fetches from
        // the trap vector 0x000 — a discontinuity, and the trapping retire
        // did not redirect. Both are licensed because retire 22 asserts
        // `rvfi_intr`. This is the regression lock on that exemption: if
        // either rule starts firing here again, the checker has gone back to
        // reporting a conforming core as broken.
        expect(
          retires[22].intr,
          isTrue,
          reason: 'the exemption is only sound because Ibex flags the entry',
        );
        expect(retires[21].trap, isTrue);
        expect(retires[21].pcNext, 0x0cc);
        expect(retires[22].pc, 0x000);

        const checker = RiscvConsistencyChecker();
        expect(checker.checkRule(RiscvCheckRule.controlFlow, retires), isEmpty);
        expect(
          checker.checkRule(RiscvCheckRule.trapConsistency, retires),
          isEmpty,
        );
      },
    );

    test('the full sweep totals 19 violations and nothing else', () {
      const checker = RiscvConsistencyChecker();
      final all = checker.check(retires);
      expect(all.length, 19);
      expect(
        all.map((v) => v.kind).toSet(),
        {RiscvViolationKind.memoryAccessUnexpected},
        reason:
            'a new violation kind against a pinned capture means either the '
            'checker changed behaviour or the fixture was regenerated from a '
            'different Ibex commit — neither should pass silently',
      );
    });
  });

  group('fixture corpus', () {
    test('the test/ and verification/ copies are byte-identical', () {
      for (final suffix in const [
        '.fst',
        '.fixture.json',
        '.expected_transactions.json',
      ]) {
        const name = 'riscv_ibex_rvfi_trap';
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

// ## Ibex's two RVFI deviations, as observed in this capture
//
// Both are properties of upstream RTL at commit
// `3250d99482f1963891ef1cf19356eeaeeaa71d30`, reproducible from the source
// without running anything. Neither is a WaveCrux bug, and neither is
// suppressed: the checker is reporting exactly what the RVFI specification
// says it should.
//
// #1 — `rvfi_mem_rmask` is `4'b1111` on every non-store.
// `ibex_core.sv:1653` drives
// `rvfi_stage_mem_rmask[i] <= data_we_o ? 4'b0000 : rvfi_mem_mask_int;`
// and `rvfi_mem_mask_int` is derived from `lsu_type` alone
// (`ibex_core.sv:1793-1798`). For an instruction with no memory access at
// all, `lsu_type` is the decoder's unconditional default `2'b00`
// (`ibex_decoder.sv:227`) — the "word" encoding — so the mask comes out
// all-ones. Nothing gates the assignment on whether a request was actually
// issued. RVFI defines a zero mask as "no memory access", so a literal
// reading of Ibex's bundle reports a four-byte read on every `addi`.
//
// #2 — `rvfi_pc_wdata` does not point at the handler on a trap.
// `ibex_core.sv:1652` samples
// `rvfi_stage_pc_wdata[i] <= pc_set ? branch_target_ex : pc_if;` when the ID
// stage completes, which is one cycle before the controller applies the
// exception redirect. The `ecall` at PC `0x0c8` therefore retires with
// `rvfi_trap = 1` and `rvfi_pc_wdata = 0x0cc` (PC+4), while the very next
// retirement's `rvfi_pc_rdata` is `0x000`, the trap vector. That trips both
// `controlFlow` (pc_wdata(n) != pc_rdata(n+1)) and `trapConsistency`
// (a trapping instruction whose next PC is merely PC+4).
//
// Neither field is checked by Ibex's own verification: `dv/uvm` only wires
// them into `core_ibex_rvfi_if`, and the Spike co-simulation compares
// architectural state rather than the RVFI reporting. Upstream's own
// `doc/03_reference/rvfi.rst` states that Ibex "is not yet formally
// verified", which is consistent with both gaps.
//
// The practical consequence for WaveCrux: against a real Ibex trace the
// `memoryAccess` rule is noise. If the Commit Inspector ever grows
// per-core quirk profiles, this capture is the regression lock for the
// Ibex profile — which is why the counts above are pinned exactly rather
// than asserted as "greater than zero".
