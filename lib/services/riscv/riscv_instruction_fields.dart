// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Field extraction from a retired RISC-V instruction word, for the
/// consistency checker only.
///
/// **This is not a decoder and must not become one.** `InstructionDisassembler`
/// (`services/decoders/isa/`) is the decoder; it renders a word as text from
/// the TOML corpus and does not expose the structured operand fields the
/// checker needs to say "this encoding names `rd = a0`, but `rvfi_rd_addr`
/// reports `a1`". What lives here is the two facts the checker compares
/// against RVFI, extracted straight from the base-ISA opcode map.
///
/// Every function here is **conservative by construction**: it returns `null`
/// — "I decline to judge this encoding" — for anything outside the integer
/// base ISA it can speak for with certainty. A checker rule that fires on an
/// encoding the extractor half-understands is worse than one that stays
/// quiet, because a false violation on a correct core costs the user the
/// trust the whole widget is built on.
///
/// Declined outright:
///
/// - **compressed encodings** (`insn[1:0] != 0b11`). A riscv-formal-compliant
///   core reports the *expanded* 32-bit form on `rvfi_insn`; a core that
///   reports the 16-bit form instead is outside what this can check.
/// - **floating-point opcodes** (`LOAD-FP`, `STORE-FP`, `OP-FP`, `FMADD` and
///   friends). Base RVFI models only the integer register file, and cores
///   differ in what they report on `rvfi_rd_addr` for an FP destination.
/// - **any opcode not in the base map**, including custom/vendor space.
///
/// Pure Dart — no Flutter imports.
library;

import 'package:meta/meta.dart';

/// Kind of memory access an encoding performs.
enum RiscvAccessKind {
  /// The encoding touches no memory.
  none,

  /// A load: the read half of the RVFI memory channels should assert.
  load,

  /// A store: the write half should assert.
  store,
}

/// The memory access an encoding performs.
@immutable
class RiscvDecodedAccess {
  const RiscvDecodedAccess({required this.kind, required this.sizeBytes});

  /// A non-memory encoding.
  static const RiscvDecodedAccess none = RiscvDecodedAccess(
    kind: RiscvAccessKind.none,
    sizeBytes: 0,
  );

  /// Load, store, or neither.
  final RiscvAccessKind kind;

  /// Width of the access in bytes (1 / 2 / 4 / 8), or 0 when [kind] is
  /// [RiscvAccessKind.none].
  final int sizeBytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiscvDecodedAccess &&
          kind == other.kind &&
          sizeBytes == other.sizeBytes;

  @override
  int get hashCode => Object.hash(kind, sizeBytes);

  @override
  String toString() => 'RiscvDecodedAccess($kind, $sizeBytes bytes)';
}

// ── opcode map (insn[6:0]) ───────────────────────────────────────────────────

const int _opLoad = 0x03;
const int _opLoadFp = 0x07;
const int _opMiscMem = 0x0f;
const int _opOpImm = 0x13;
const int _opAuipc = 0x17;
const int _opOpImm32 = 0x1b;
const int _opStore = 0x23;
const int _opStoreFp = 0x27;
const int _opAmo = 0x2f;
const int _opOp = 0x33;
const int _opLui = 0x37;
const int _opOp32 = 0x3b;
const int _opBranch = 0x63;
const int _opJalr = 0x67;
const int _opJal = 0x6f;
const int _opSystem = 0x73;

/// True when [insn] is a 32-bit (uncompressed) base encoding.
bool riscvIsUncompressed(int insn) => (insn & 0x3) == 0x3;

/// The integer destination register the encoding **names**, `0` when it names
/// none, or `null` when this extractor declines to judge the encoding.
///
/// `0` and `null` are deliberately different answers. `0` is a positive
/// statement — "this encoding writes no architectural register, so RVFI must
/// report `rd_addr == 0`" — and is what lets the checker catch a core that
/// reports a destination for a store or a branch. `null` means the encoding
/// is outside the extractor's competence and the rule must skip it.
int? riscvDecodedIntegerRd(int insn) {
  if (!riscvIsUncompressed(insn)) return null;
  final opcode = insn & 0x7f;
  final rd = (insn >> 7) & 0x1f;
  switch (opcode) {
    // Encodings with an integer rd field.
    case _opLoad:
    case _opOpImm:
    case _opAuipc:
    case _opOpImm32:
    case _opAmo:
    case _opOp:
    case _opLui:
    case _opOp32:
    case _opJalr:
    case _opJal:
      return rd;

    // Encodings with no rd field at all — the bits are an immediate.
    case _opStore:
    case _opBranch:
      return 0;

    // FENCE / FENCE.I: rd is a reserved field that must read zero, and the
    // instruction writes no register.
    case _opMiscMem:
      return 0;

    case _opSystem:
      // funct3 == 0 is the trap/return/environment family (ECALL, EBREAK,
      // MRET, SRET, WFI, SFENCE.VMA) — no register write. funct3 4 is
      // unallocated. Everything else is a CSR instruction, which does write
      // rd (and legally writes x0 to mean "discard").
      final funct3 = (insn >> 12) & 0x7;
      if (funct3 == 0) return 0;
      if (funct3 == 4) return null;
      return rd;

    // Floating point and everything unallocated: declined, see the library
    // doc comment.
    default:
      return null;
  }
}

/// The memory access the encoding performs, or `null` when this extractor
/// declines to judge it.
///
/// Atomics (`AMO`) are declined rather than reported: `lr.w` reads without
/// writing, `sc.w` writes conditionally, and the read-modify-write forms do
/// both — cores legitimately differ in how they present that on one pair of
/// RVFI byte masks, and guessing would produce false violations on correct
/// hardware.
RiscvDecodedAccess? riscvDecodedAccess(int insn) {
  if (!riscvIsUncompressed(insn)) return null;
  final opcode = insn & 0x7f;
  final funct3 = (insn >> 12) & 0x7;
  switch (opcode) {
    case _opLoad:
      // 0=LB 1=LH 2=LW 3=LD 4=LBU 5=LHU 6=LWU; 7 is unallocated.
      final size = switch (funct3) {
        0 || 4 => 1,
        1 || 5 => 2,
        2 || 6 => 4,
        3 => 8,
        _ => 0,
      };
      if (size == 0) return null;
      return RiscvDecodedAccess(kind: RiscvAccessKind.load, sizeBytes: size);

    case _opStore:
      // 0=SB 1=SH 2=SW 3=SD; 4..7 unallocated.
      final size = switch (funct3) {
        0 => 1,
        1 => 2,
        2 => 4,
        3 => 8,
        _ => 0,
      };
      if (size == 0) return null;
      return RiscvDecodedAccess(kind: RiscvAccessKind.store, sizeBytes: size);

    // Base-ISA encodings that provably touch no memory.
    case _opOpImm:
    case _opAuipc:
    case _opOpImm32:
    case _opOp:
    case _opLui:
    case _opOp32:
    case _opBranch:
    case _opJalr:
    case _opJal:
    case _opMiscMem:
    case _opSystem:
      return RiscvDecodedAccess.none;

    // AMO, FP loads/stores, and everything unallocated.
    case _opAmo:
    case _opLoadFp:
    case _opStoreFp:
    default:
      return null;
  }
}

/// Population count of [mask], used to turn an RVFI byte-enable mask into a
/// byte count.
int riscvPopCount(int mask) {
  var bits = mask;
  var count = 0;
  while (bits != 0) {
    count += bits & 1;
    bits >>= 1;
  }
  return count;
}

/// Index of the least-significant set bit of [mask], or `-1` when [mask] is
/// zero. This is the byte offset the access starts at, relative to
/// `rvfi_mem_addr`.
int riscvLowestSetBit(int mask) {
  if (mask == 0) return -1;
  var index = 0;
  var bits = mask;
  while (bits & 1 == 0) {
    bits >>= 1;
    index++;
  }
  return index;
}

/// Whether the set bits of [mask] form one unbroken run.
///
/// A RISC-V load or store touches a contiguous byte range, so a mask with a
/// hole in it (`0b1001`) cannot describe one — whatever else is wrong, the
/// masks and the instruction disagree.
bool riscvMaskIsContiguous(int mask) {
  if (mask == 0) return true;
  final shifted = mask >> riscvLowestSetBit(mask);
  // A contiguous run starting at bit 0 is `2^n - 1`.
  return (shifted & (shifted + 1)) == 0;
}
