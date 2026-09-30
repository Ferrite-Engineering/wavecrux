// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/riscv/riscv_instruction_fields.dart';

void main() {
  group('riscvIsUncompressed', () {
    test('32-bit encodings end in 0b11', () {
      expect(riscvIsUncompressed(0x00500293), isTrue);
      expect(riscvIsUncompressed(0x00000073), isTrue);
    });

    test('compressed encodings do not', () {
      // c.addi x8, 1 — a 16-bit encoding, low bits 0b01.
      expect(riscvIsUncompressed(0x0405), isFalse);
    });
  });

  group('riscvDecodedIntegerRd', () {
    test('reads rd from encodings that name one', () {
      // addi t0, zero, 5
      expect(riscvDecodedIntegerRd(0x00500293), 5);
      // addi t1, zero, 7
      expect(riscvDecodedIntegerRd(0x00700313), 6);
      // add t2, t0, t1
      expect(riscvDecodedIntegerRd(0x006283b3), 7);
      // lw s0, 0(sp)
      expect(riscvDecodedIntegerRd(0x00012403), 8);
      // lui a0, 0x12345
      expect(riscvDecodedIntegerRd(0x12345537), 10);
    });

    test('reports 0 — "writes nothing" — for stores and branches', () {
      // sw t2, 0(sp)
      expect(riscvDecodedIntegerRd(0x00712023), 0);
      // beq t0, t0, 16
      expect(riscvDecodedIntegerRd(0x00528863), 0);
    });

    test('reports 0 for the SYSTEM trap/return family', () {
      // ecall
      expect(riscvDecodedIntegerRd(0x00000073), 0);
      // ebreak
      expect(riscvDecodedIntegerRd(0x00100073), 0);
      // mret
      expect(riscvDecodedIntegerRd(0x30200073), 0);
    });

    test('reads rd for CSR instructions', () {
      // csrrw a0, mstatus, a1  → 0x300595f3 has rd=11; use csrrs a0, mcycle, x0
      // csrrs a0, 0xb00, zero = 0xb0002573
      expect(riscvDecodedIntegerRd(0xb0002573), 10);
    });

    test('declines rather than guessing', () {
      // Compressed.
      expect(riscvDecodedIntegerRd(0x0405), isNull);
      // flw ft0, 0(sp) — LOAD-FP, an FP destination base RVFI does not model.
      expect(riscvDecodedIntegerRd(0x00012007), isNull);
      // Unallocated opcode.
      expect(riscvDecodedIntegerRd(0x0000007f), isNull);
    });
  });

  group('riscvDecodedAccess', () {
    test('sizes loads from funct3', () {
      // lb / lh / lw at 0(sp) into a0.
      expect(
        riscvDecodedAccess(0x00010503),
        const RiscvDecodedAccess(kind: RiscvAccessKind.load, sizeBytes: 1),
      );
      expect(
        riscvDecodedAccess(0x00011503),
        const RiscvDecodedAccess(kind: RiscvAccessKind.load, sizeBytes: 2),
      );
      expect(
        riscvDecodedAccess(0x00012503),
        const RiscvDecodedAccess(kind: RiscvAccessKind.load, sizeBytes: 4),
      );
      // ld a0, 16(sp) — RV64.
      expect(
        riscvDecodedAccess(0x01013503),
        const RiscvDecodedAccess(kind: RiscvAccessKind.load, sizeBytes: 8),
      );
      // lbu / lhu are the same widths as lb / lh.
      expect(riscvDecodedAccess(0x00014503)!.sizeBytes, 1);
      expect(riscvDecodedAccess(0x00015503)!.sizeBytes, 2);
    });

    test('sizes stores from funct3', () {
      // sb / sh / sw t1, 8(sp)
      expect(riscvDecodedAccess(0x00610423)!.kind, RiscvAccessKind.store);
      expect(riscvDecodedAccess(0x00610423)!.sizeBytes, 1);
      expect(riscvDecodedAccess(0x00611423)!.sizeBytes, 2);
      expect(riscvDecodedAccess(0x00612423)!.sizeBytes, 4);
      // sd t1, 24(sp) — RV64.
      expect(riscvDecodedAccess(0x00613c23)!.sizeBytes, 8);
    });

    test('reports "no access" for base-ISA non-memory encodings', () {
      expect(riscvDecodedAccess(0x00500293), RiscvDecodedAccess.none); // addi
      expect(riscvDecodedAccess(0x006283b3), RiscvDecodedAccess.none); // add
      expect(riscvDecodedAccess(0x00528863), RiscvDecodedAccess.none); // beq
      expect(riscvDecodedAccess(0x00000073), RiscvDecodedAccess.none); // ecall
      expect(riscvDecodedAccess(0x12345537), RiscvDecodedAccess.none); // lui
    });

    test('declines atomics and FP memory rather than guessing', () {
      // lr.w a0, (sp) — AMO space.
      expect(riscvDecodedAccess(0x1001252f), isNull);
      // flw ft0, 0(sp) / fsw ft0, 0(sp)
      expect(riscvDecodedAccess(0x00012007), isNull);
      expect(riscvDecodedAccess(0x00012027), isNull);
    });

    test('declines unallocated load/store widths', () {
      // funct3 == 7 in the LOAD space is unallocated.
      expect(riscvDecodedAccess(0x00017503), isNull);
      // funct3 == 4 in the STORE space is unallocated.
      expect(riscvDecodedAccess(0x00614423), isNull);
    });
  });

  group('mask helpers', () {
    test('riscvPopCount counts asserted bytes', () {
      expect(riscvPopCount(0x0), 0);
      expect(riscvPopCount(0x1), 1);
      expect(riscvPopCount(0x3), 2);
      expect(riscvPopCount(0xf), 4);
      expect(riscvPopCount(0xff), 8);
    });

    test('riscvLowestSetBit is the byte offset into the access', () {
      expect(riscvLowestSetBit(0x0), -1);
      expect(riscvLowestSetBit(0x1), 0);
      expect(riscvLowestSetBit(0xc), 2);
      expect(riscvLowestSetBit(0x8), 3);
    });

    test('riscvMaskIsContiguous rejects holes', () {
      expect(riscvMaskIsContiguous(0x0), isTrue);
      expect(riscvMaskIsContiguous(0xf), isTrue);
      expect(riscvMaskIsContiguous(0xc), isTrue);
      expect(riscvMaskIsContiguous(0x6), isTrue);
      expect(riscvMaskIsContiguous(0x9), isFalse);
      expect(riscvMaskIsContiguous(0x5), isFalse);
      expect(riscvMaskIsContiguous(0xd), isFalse);
    });
  });
}
