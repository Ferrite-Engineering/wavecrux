// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/riscv/riscv_consistency_checker.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';
import 'package:wavecrux/services/riscv/rvfi_binding_set.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';

// ── encodings used below ─────────────────────────────────────────────────────
const int _addiT0Zero5 = 0x00500293; // addi t0, zero, 5   (rd = x5)
const int _addT2T0T1 = 0x006283b3; // add  t2, t0, t1    (rd = x7)
const int _swT2Sp = 0x00712023; // sw   t2, 0(sp)     (4-byte store)
const int _lwS0Sp = 0x00012403; // lw   s0, 0(sp)     (4-byte load)
const int _lhS0Sp = 0x00011403; // lh   s0, 0(sp)     (2-byte load)
const int _nop = 0x00000013; // addi zero, zero, 0
const int _ecall = 0x00000073;

RiscvRetiredInstruction _r({
  required int time,
  int? order,
  int? pc,
  int? pcNext,
  int? insn,
  String? mnemonic,
  int? rdAddr,
  int? rdValue,
  RiscvMemoryEffect? memory,
  bool? trap,
  bool? intr,
  int? mode,
}) => RiscvRetiredInstruction(
  time: time,
  channelIndex: 0,
  order: order,
  pc: pc,
  pcNext: pcNext,
  insnWord: insn,
  mnemonic: mnemonic,
  rdAddr: rdAddr,
  rdValue: rdValue,
  memory: memory,
  trap: trap,
  intr: intr,
  mode: mode,
);

/// A short, entirely consistent stream. Every rule must stay silent on it —
/// the clean half of the fixture pairing, in synthetic form.
List<RiscvRetiredInstruction> _cleanStream() => [
  _r(
    time: 10,
    order: 0,
    pc: 0x80000000,
    pcNext: 0x80000004,
    insn: _addiT0Zero5,
    mnemonic: 'addi',
    rdAddr: 5,
    rdValue: 5,
    trap: false,
    intr: false,
    mode: 3,
  ),
  _r(
    time: 20,
    order: 1,
    pc: 0x80000004,
    pcNext: 0x80000008,
    insn: _addT2T0T1,
    mnemonic: 'add',
    rdAddr: 7,
    rdValue: 12,
    trap: false,
    intr: false,
    mode: 3,
  ),
  _r(
    time: 30,
    order: 2,
    pc: 0x80000008,
    pcNext: 0x8000000c,
    insn: _swT2Sp,
    mnemonic: 'sw',
    rdAddr: 0,
    rdValue: 0,
    memory: const RiscvMemoryEffect(
      time: 30,
      order: 2,
      address: 0x1000,
      rmask: 0,
      wmask: 0xf,
      wdata: 12,
    ),
    trap: false,
    intr: false,
    mode: 3,
  ),
  _r(
    time: 40,
    order: 3,
    pc: 0x8000000c,
    pcNext: 0x80000010,
    insn: _nop,
    mnemonic: 'addi',
    rdAddr: 0,
    rdValue: 0,
    trap: false,
    intr: false,
    mode: 3,
  ),
];

void main() {
  const checker = RiscvConsistencyChecker();

  group('the clean stream fires nothing', () {
    test('no rule reports a violation', () {
      for (final rule in RiscvCheckRule.values) {
        expect(
          checker.checkRule(rule, _cleanStream()),
          isEmpty,
          reason: '$rule fired on a consistent stream',
        );
      }
      expect(checker.check(_cleanStream()), isEmpty);
    });
  });

  group('rule 1 — control-flow continuity', () {
    test('fires when pc_wdata(n) disagrees with pc_rdata(n+1)', () {
      final stream = _cleanStream();
      stream[1] = _r(
        time: 20,
        order: 1,
        pc: 0x80000004,
        // Claims to go to 0x80000030; retire 2 fetches from 0x80000008.
        pcNext: 0x80000030,
        insn: _addT2T0T1,
        rdAddr: 7,
        rdValue: 12,
        trap: false,
      );
      final v = riscvCheckControlFlow(stream);
      expect(v, hasLength(1));
      expect(v.single.kind, RiscvViolationKind.controlFlowDiscontinuity);
      expect(v.single.severity, RiscvViolationSeverity.error);
      // Anchored at the retirement that fetched from the wrong place.
      expect(v.single.retireIndex, 2);
      expect(v.single.time, 30);
      expect(v.single.detail, contains('0x8000_0030'));
      expect(v.single.detail, contains('0x8000_0008'));
      expect(v.single.args, hasLength(v.single.kind.argCount));
    });

    test('a taken branch is not a discontinuity', () {
      final stream = [
        _r(time: 10, order: 0, pc: 0x80000000, pcNext: 0x80000040),
        _r(time: 20, order: 1, pc: 0x80000040, pcNext: 0x80000044),
      ];
      expect(riscvCheckControlFlow(stream), isEmpty);
    });

    test('stays silent when either PC is unbound', () {
      final stream = [
        _r(time: 10, order: 0, pc: 0x80000000),
        _r(time: 20, order: 1, pc: 0x80000040),
      ];
      expect(riscvCheckControlFlow(stream), isEmpty);
    });

    test(
      'a discontinuity the successor flags with rvfi_intr is handler entry',
      () {
        // RVFI defines `rvfi_intr` as marking an instruction whose `pc_rdata`
        // does not match the previous `pc_wdata`. riscv-formal's own
        // `rvfi_pc_fwd_check.sv` guards its assertion with `!rvfi_intr` for
        // exactly this case, so firing here reports a conforming core broken.
        final stream = [
          _r(
            time: 10,
            order: 0,
            pc: 0x80000028,
            pcNext: 0x8000002c,
            trap: true,
          ),
          _r(time: 20, order: 1, pc: 0x00000000, intr: true),
        ];
        expect(riscvCheckControlFlow(stream), isEmpty);
      },
    );

    test('the same discontinuity without rvfi_intr still fires', () {
      final stream = [
        _r(time: 10, order: 0, pc: 0x80000028, pcNext: 0x8000002c, trap: true),
        _r(time: 20, order: 1, pc: 0x00000000, intr: false),
      ];
      expect(
        riscvCheckControlFlow(stream).single.kind,
        RiscvViolationKind.controlFlowDiscontinuity,
      );
    });

    test('an unbound rvfi_intr does not silently excuse a discontinuity', () {
      // No evidence either way — the rule reports rather than passing, per
      // the file's "a check that cannot run does not pass" commitment.
      final stream = [
        _r(time: 10, order: 0, pc: 0x80000028, pcNext: 0x8000002c),
        _r(time: 20, order: 1, pc: 0x00000000),
      ];
      expect(
        riscvCheckControlFlow(stream).single.kind,
        RiscvViolationKind.controlFlowDiscontinuity,
      );
    });
  });

  group('rule 2 — x0 is hardwired zero', () {
    test('fires on a non-zero write to x0', () {
      final stream = _cleanStream();
      stream[3] = _r(
        time: 40,
        order: 3,
        pc: 0x8000000c,
        pcNext: 0x80000010,
        insn: _nop,
        rdAddr: 0,
        rdValue: 0x2a,
        trap: false,
      );
      final v = riscvCheckX0Write(stream);
      expect(v, hasLength(1));
      expect(v.single.kind, RiscvViolationKind.x0NonZeroWrite);
      expect(v.single.detail, contains('0x0000_002a'));
    });

    test('a zero write to x0 is how RVFI says "writes nothing"', () {
      expect(riscvCheckX0Write(_cleanStream()), isEmpty);
    });

    test('a non-zero write to a real register is fine', () {
      final stream = [
        _r(time: 10, order: 0, rdAddr: 5, rdValue: 0xdeadbeef),
      ];
      expect(riscvCheckX0Write(stream), isEmpty);
    });
  });

  group('rule 3 — reported rd vs the encoding', () {
    test('fires when rd_addr names a different register', () {
      final stream = [
        _r(
          time: 10,
          order: 0,
          insn: _addiT0Zero5,
          mnemonic: 'addi',
          rdAddr: 6,
          rdValue: 5,
          trap: false,
        ),
      ];
      final v = riscvCheckDestinationRegister(stream);
      expect(v, hasLength(1));
      expect(v.single.kind, RiscvViolationKind.destinationRegisterMismatch);
      expect(v.single.detail, contains('t0 (x5)'));
      expect(v.single.detail, contains('t1 (x6)'));
    });

    test('fires when a store reports a destination register', () {
      final stream = [
        _r(time: 10, order: 0, insn: _swT2Sp, rdAddr: 7, trap: false),
      ];
      expect(riscvCheckDestinationRegister(stream), hasLength(1));
    });

    test('skips a trapping retirement — it commits no register write', () {
      final stream = [
        _r(time: 10, order: 0, insn: _addiT0Zero5, rdAddr: 0, trap: true),
      ];
      expect(riscvCheckDestinationRegister(stream), isEmpty);
    });

    test('declines encodings the field extractor cannot speak for', () {
      // flw ft0, 0(sp) — an FP destination, outside base RVFI.
      final stream = [
        _r(time: 10, order: 0, insn: 0x00012007, rdAddr: 9, trap: false),
      ];
      expect(riscvCheckDestinationRegister(stream), isEmpty);
    });
  });

  group('rule 4 — memory masks vs the encoding', () {
    RiscvRetiredInstruction memRetire({
      required int insn,
      required int address,
      int rmask = 0,
      int wmask = 0,
      String? mnemonic,
    }) => _r(
      time: 10,
      order: 0,
      insn: insn,
      mnemonic: mnemonic,
      trap: false,
      memory: (rmask == 0 && wmask == 0)
          ? null
          : RiscvMemoryEffect(
              time: 10,
              order: 0,
              address: address,
              rmask: rmask,
              wmask: wmask,
            ),
    );

    test('fires when the masks cover the wrong number of bytes', () {
      final v = riscvCheckMemoryAccess([
        memRetire(insn: _swT2Sp, address: 0x1000, wmask: 0x3, mnemonic: 'sw'),
      ]);
      expect(v, hasLength(1));
      expect(v.single.kind, RiscvViolationKind.memorySizeMismatch);
      expect(v.single.detail, contains('needs 4 bytes'));
      expect(v.single.detail, contains('covers 2'));
    });

    test('fires when the mask has a hole in it', () {
      final v = riscvCheckMemoryAccess([
        memRetire(insn: _lwS0Sp, address: 0x1000, rmask: 0x9),
      ]);
      expect(v, hasLength(1));
      expect(v.single.kind, RiscvViolationKind.memoryMaskNotContiguous);
    });

    test('warns — does not error — on a misaligned access', () {
      final v = riscvCheckMemoryAccess([
        memRetire(insn: _lwS0Sp, address: 0x1002, rmask: 0xf),
      ]);
      expect(v, hasLength(1));
      expect(v.single.kind, RiscvViolationKind.memoryMisaligned);
      expect(v.single.severity, RiscvViolationSeverity.warning);
      expect(v.single.detail, contains('0x0000_1002'));
    });

    test('accepts a word-aligned address with a shifted mask', () {
      // The other convention found in the wild: `rvfi_mem_addr` is the
      // containing word and the mask is shifted into place. A 2-byte access
      // at 0x1002 is naturally aligned and must not be flagged.
      final v = riscvCheckMemoryAccess([
        memRetire(insn: _lhS0Sp, address: 0x1000, rmask: 0xc),
      ]);
      expect(v, isEmpty);
    });

    test('fires when a load retires with no mask asserted', () {
      final v = riscvCheckMemoryAccess([
        memRetire(insn: _lwS0Sp, address: 0),
      ]);
      expect(v, hasLength(1));
      expect(v.single.kind, RiscvViolationKind.memoryAccessMissing);
    });

    test('fires when a non-memory encoding reports an access', () {
      final v = riscvCheckMemoryAccess([
        memRetire(insn: _addT2T0T1, address: 0x1000, wmask: 0xf),
      ]);
      expect(v, hasLength(1));
      expect(v.single.kind, RiscvViolationKind.memoryAccessUnexpected);
    });

    test('declines atomics rather than guessing their mask shape', () {
      // lr.w a0, (sp)
      final v = riscvCheckMemoryAccess([
        memRetire(insn: 0x1001252f, address: 0x1000, rmask: 0xf),
      ]);
      expect(v, isEmpty);
    });

    test('skips a trapping access — it never completed', () {
      final stream = [
        _r(
          time: 10,
          order: 0,
          insn: _lwS0Sp,
          trap: true,
          memory: const RiscvMemoryEffect(
            time: 10,
            order: 0,
            address: 0x1001,
            rmask: 0x3,
            wmask: 0,
          ),
        ),
      ];
      expect(riscvCheckMemoryAccess(stream), isEmpty);
    });
  });

  group('rule 5 — rvfi_order continuity', () {
    test('fires on a gap and says how many are missing', () {
      final stream = [
        _r(time: 10, order: 3),
        _r(time: 20, order: 7),
      ];
      final v = riscvCheckRetireOrder(stream);
      expect(v, hasLength(1));
      expect(v.single.kind, RiscvViolationKind.orderGap);
      expect(v.single.args, ['3', '7', '3']);
      expect(v.single.detail, contains('3 retirement(s) are missing'));
    });

    test('fires on a regression', () {
      final stream = [
        _r(time: 10, order: 5),
        _r(time: 20, order: 2),
      ];
      final v = riscvCheckRetireOrder(stream);
      expect(v, hasLength(1));
      expect(v.single.kind, RiscvViolationKind.orderRegression);
    });

    test('fires on a repeat', () {
      final stream = [
        _r(time: 10, order: 4),
        _r(time: 20, order: 4),
      ];
      expect(
        riscvCheckRetireOrder(stream).single.kind,
        RiscvViolationKind.orderRegression,
      );
    });

    test('stays silent when the trace carries no order channel', () {
      final stream = [_r(time: 10), _r(time: 20)];
      expect(riscvCheckRetireOrder(stream), isEmpty);
    });
  });

  group('rule 6 — a trap must look like a trap', () {
    test('fires when pc_wdata is just the sequential next PC', () {
      final stream = [
        _r(
          time: 10,
          order: 0,
          pc: 0x80000028,
          pcNext: 0x8000002c,
          insn: _ecall,
          trap: true,
        ),
      ];
      final v = riscvCheckTrapConsistency(stream);
      expect(v, hasLength(1));
      expect(v.single.kind, RiscvViolationKind.trapNoRedirect);
      expect(v.single.detail, contains('0x8000_002c'));
    });

    test('accepts a redirect to a trap vector', () {
      final stream = [
        _r(
          time: 10,
          order: 0,
          pc: 0x80000028,
          pcNext: 0x80000100,
          insn: _ecall,
          trap: true,
        ),
      ];
      expect(riscvCheckTrapConsistency(stream), isEmpty);
    });

    test('fires when the next retirement does not assert rvfi_intr', () {
      final stream = [
        _r(
          time: 10,
          order: 0,
          pc: 0x80000028,
          pcNext: 0x80000100,
          insn: _ecall,
          trap: true,
        ),
        _r(time: 20, order: 1, pc: 0x80000100, intr: false),
      ];
      final v = riscvCheckTrapConsistency(stream);
      expect(v, hasLength(1));
      expect(v.single.kind, RiscvViolationKind.trapNoHandlerEntry);
    });

    test('a sequential pc_wdata is legal when the successor flags entry', () {
      // The Ibex shape: `ecall` retires with pc_wdata = PC+4 and the handler's
      // first retirement asserts `rvfi_intr`. Legal — see the control-flow
      // group for the spec text and the riscv-formal check that permits it.
      final stream = [
        _r(
          time: 10,
          order: 0,
          pc: 0x80000028,
          pcNext: 0x8000002c,
          insn: _ecall,
          trap: true,
        ),
        _r(time: 20, order: 1, pc: 0x00000000, intr: true),
      ];
      expect(riscvCheckTrapConsistency(stream), isEmpty);
    });

    test('a sequential pc_wdata still fires when entry is not flagged', () {
      final stream = [
        _r(
          time: 10,
          order: 0,
          pc: 0x80000028,
          pcNext: 0x8000002c,
          insn: _ecall,
          trap: true,
        ),
        _r(time: 20, order: 1, pc: 0x00000000, intr: false),
      ];
      expect(
        riscvCheckTrapConsistency(stream).map((v) => v.kind),
        containsAll(const [
          RiscvViolationKind.trapNoRedirect,
          RiscvViolationKind.trapNoHandlerEntry,
        ]),
      );
    });

    test('accepts a handler entry that asserts rvfi_intr', () {
      final stream = [
        _r(
          time: 10,
          order: 0,
          pc: 0x80000028,
          pcNext: 0x80000100,
          insn: _ecall,
          trap: true,
        ),
        _r(time: 20, order: 1, pc: 0x80000100, intr: true),
      ];
      expect(riscvCheckTrapConsistency(stream), isEmpty);
    });

    test('fires when the trap lands at a lower privilege', () {
      final stream = [
        _r(
          time: 10,
          order: 0,
          pc: 0x80000028,
          pcNext: 0x80000100,
          insn: _ecall,
          trap: true,
          intr: false,
          mode: 3,
        ),
        _r(time: 20, order: 1, pc: 0x80000100, intr: true, mode: 0),
      ];
      final v = riscvCheckTrapConsistency(stream);
      expect(v, hasLength(1));
      expect(v.single.kind, RiscvViolationKind.trapPrivilegeDrop);
      expect(v.single.args, ['M', 'U']);
    });

    test('accepts a trap taken from U into M', () {
      final stream = [
        _r(
          time: 10,
          order: 0,
          pc: 0x80000028,
          pcNext: 0x80000100,
          insn: _ecall,
          trap: true,
          mode: 0,
        ),
        _r(time: 20, order: 1, pc: 0x80000100, intr: true, mode: 3),
      ];
      expect(riscvCheckTrapConsistency(stream), isEmpty);
    });

    test('a compressed trapping encoding advances by 2, not 4', () {
      // A trapping c.addi at 0x80000028 whose pc_wdata is 0x8000002a is the
      // sequential next PC for a 16-bit encoding.
      final stream = [
        _r(
          time: 10,
          order: 0,
          pc: 0x80000028,
          pcNext: 0x8000002a,
          insn: 0x0405,
          trap: true,
        ),
      ];
      expect(
        riscvCheckTrapConsistency(stream).single.kind,
        RiscvViolationKind.trapNoRedirect,
      );
    });
  });

  group('every violation kind declares its own arg count', () {
    test('argCount is positive and matched at construction', () {
      for (final kind in RiscvViolationKind.values) {
        expect(kind.argCount, greaterThan(0), reason: '$kind');
        expect(
          () => RiscvConsistencyViolation(
            kind: kind,
            severity: RiscvViolationSeverity.error,
            retireIndex: 0,
            time: 0,
            detail: 'x',
            args: List.filled(kind.argCount, 'a'),
          ),
          returnsNormally,
        );
      }
    });

    test('a mismatched arg list is rejected', () {
      expect(
        () => RiscvConsistencyViolation(
          kind: RiscvViolationKind.orderGap,
          severity: RiscvViolationSeverity.error,
          retireIndex: 0,
          time: 0,
          detail: 'x',
          args: const ['only-one'],
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('rule gating on the bound channel set', () {
    RvfiBindingSet setOf(Iterable<RvfiChannel> channels) => RvfiBindingSet(
      refs: {
        for (final c in channels) c: {0: c.signalName},
      },
      channelCount: 1,
    );

    test('the full channel set enables every rule', () {
      final options = RiscvConsistencyCheckOptions.forBindings(
        setOf(RvfiChannel.values),
      );
      expect(options.enabledRules, RiscvCheckRule.values.toSet());
      expect(options.skippedRules, isEmpty);
    });

    test('the reduced binding set skips four of the six rules', () {
      final options = RiscvConsistencyCheckOptions.forBindings(
        setOf(RvfiChannel.values.where((c) => c.isReducedSetMember)),
      );
      // valid + insn + pc_rdata + rd_addr + rd_wdata: only the two rules that
      // need nothing else can run.
      expect(options.enabledRules, {
        RiscvCheckRule.x0Write,
        RiscvCheckRule.destinationRegister,
      });
      expect(options.skippedRules, {
        RiscvCheckRule.controlFlow,
        RiscvCheckRule.memoryAccess,
        RiscvCheckRule.retireOrder,
        RiscvCheckRule.trapConsistency,
      });
    });

    test('a disabled rule is not run by check()', () {
      final stream = [
        _r(time: 10, order: 3),
        _r(time: 20, order: 9),
      ];
      expect(
        checker.check(
          stream,
          options: const RiscvConsistencyCheckOptions(enabledRules: {}),
        ),
        isEmpty,
      );
      expect(
        checker.check(
          stream,
          options: const RiscvConsistencyCheckOptions(
            enabledRules: {RiscvCheckRule.retireOrder},
          ),
        ),
        hasLength(1),
      );
    });
  });

  group('check() output ordering', () {
    test('violations come back in stream order', () {
      final stream = [
        _r(time: 10, order: 0, rdAddr: 0, rdValue: 1),
        _r(time: 20, order: 5, rdAddr: 0, rdValue: 2),
      ];
      final v = checker.check(stream);
      expect(v.map((x) => x.retireIndex), [0, 1, 1]);
      expect(v.first.kind, RiscvViolationKind.x0NonZeroWrite);
    });
  });

  group('riscvPrivilegeModeName', () {
    test('names the architectural privilege levels', () {
      expect(riscvPrivilegeModeName(0), 'U');
      expect(riscvPrivilegeModeName(1), 'S');
      expect(riscvPrivilegeModeName(3), 'M');
      expect(riscvPrivilegeModeName(2), 'mode 2');
    });
  });

  group('riscvHexWord', () {
    test('groups nibbles the way a core designer reads an address', () {
      expect(riscvHexWord(0x80000000), '0x8000_0000');
      expect(riscvHexWord(0), '0x0000_0000');
      expect(riscvHexWord(0x2a), '0x0000_002a');
    });
  });
}
