// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// One memory access performed by a retired instruction.
///
/// RVFI reports the read and write halves of an access on the same set of
/// ports, distinguished by their byte-enable masks — an instruction with a
/// zero [rmask] and a zero [wmask] performed no access at all.
@immutable
class RiscvMemoryEffect {
  const RiscvMemoryEffect({
    required this.time,
    required this.order,
    required this.address,
    required this.rmask,
    required this.wmask,
    this.rdata,
    this.wdata,
  });

  /// Simulation tick of the retirement that performed the access.
  final int time;

  /// `rvfi_order` of the retirement, or null when the trace omits it.
  final int? order;

  /// Access address.
  final int address;

  /// Byte-enable mask of the read half (0 when this is a pure write).
  final int rmask;

  /// Byte-enable mask of the write half (0 when this is a pure read).
  final int wmask;

  /// Data read; bytes outside [rmask] are don't-care.
  final int? rdata;

  /// Data written; bytes outside [wmask] are don't-care.
  final int? wdata;

  /// Whether this effect describes a read.
  bool get isRead => rmask != 0;

  /// Whether this effect describes a write.
  bool get isWrite => wmask != 0;

  /// Number of bytes touched, derived by popcount over the union of the
  /// masks. Used by the consistency checker to compare against the decoded
  /// access size.
  int get byteCount {
    var bits = rmask | wmask;
    var count = 0;
    while (bits != 0) {
      count += bits & 1;
      bits >>= 1;
    }
    return count;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiscvMemoryEffect &&
          time == other.time &&
          order == other.order &&
          address == other.address &&
          rmask == other.rmask &&
          wmask == other.wmask &&
          rdata == other.rdata &&
          wdata == other.wdata;

  @override
  int get hashCode =>
      Object.hash(time, order, address, rmask, wmask, rdata, wdata);

  @override
  String toString() =>
      'RiscvMemoryEffect(t: $time, addr: 0x${address.toRadixString(16)}, '
      'r: 0x${rmask.toRadixString(16)}, w: 0x${wmask.toRadixString(16)})';
}

/// One instruction observed retiring on an RVFI channel.
///
/// This is the substrate's central record — everything downstream (the
/// architectural-state replay, the commit log, the consistency checker) is a
/// fold over an ordered list of these. Every field is nullable because a
/// partially-instrumented core is a real and supported case: the reduced
/// binding set carries valid + pc + insn + rd and nothing else, and the
/// consumer degrades its views rather than refusing to render.
@immutable
class RiscvRetiredInstruction {
  const RiscvRetiredInstruction({
    required this.time,
    required this.channelIndex,
    this.order,
    this.pc,
    this.pcNext,
    this.insnWord,
    this.disassembly,
    this.mnemonic,
    this.isaSetName,
    this.rs1Addr,
    this.rs1Value,
    this.rs2Addr,
    this.rs2Value,
    this.rdAddr,
    this.rdValue,
    this.memory,
    this.trap,
    this.halt,
    this.intr,
    this.mode,
    this.ixl,
    this.hasUnknownBits = false,
  });

  /// Simulation tick (not cycle — there is no cycle domain) at which the
  /// retirement was observed.
  final int time;

  /// Retirement channel this instruction retired on. 0 for a single-issue
  /// core; a superscalar core retires on several per cycle.
  final int channelIndex;

  /// `rvfi_order` — the core's own monotonic retirement counter.
  final int? order;

  /// `rvfi_pc_rdata` — the address the instruction was fetched from.
  final int? pc;

  /// `rvfi_pc_wdata` — the address the *next* instruction should retire
  /// from. Disagreement with the next retirement's [pc] is a control-flow
  /// discontinuity.
  final int? pcNext;

  /// `rvfi_insn` — the raw retired instruction word.
  final int? insnWord;

  /// Disassembly text from the existing `InstructionDisassembler`, or null when
  /// the word matched no loaded instruction set.
  final String? disassembly;

  /// Mnemonic of the matched instruction (`addi`).
  final String? mnemonic;

  /// `set` name of the instruction set that matched (`RV32I`).
  final String? isaSetName;

  /// `rvfi_rs1_addr` / `rvfi_rs1_rdata`.
  final int? rs1Addr;
  final int? rs1Value;

  /// `rvfi_rs2_addr` / `rvfi_rs2_rdata`.
  final int? rs2Addr;
  final int? rs2Value;

  /// `rvfi_rd_addr` / `rvfi_rd_wdata`.
  final int? rdAddr;
  final int? rdValue;

  /// The memory access, or null when the instruction touched no memory (or
  /// the trace does not expose the memory channels).
  final RiscvMemoryEffect? memory;

  /// `rvfi_trap` — the instruction raised a trap.
  final bool? trap;

  /// `rvfi_halt` — the last retirement before the core halted.
  final bool? halt;

  /// `rvfi_intr` — the first retirement of a trap handler.
  final bool? intr;

  /// `rvfi_mode` — privilege level (0=U, 1=S, 3=M).
  final int? mode;

  /// `rvfi_ixl` — effective XLEN encoding (1=32, 2=64).
  final int? ixl;

  /// True when at least one sampled channel carried `x` or `z` at this tick.
  /// A retirement with unknown bits is surfaced, never silently zeroed.
  final bool hasUnknownBits;

  /// Whether this retirement writes an architectural register. `x0` is
  /// hardwired zero, so `rd_addr == 0` is "writes nothing", not "writes 0".
  bool get writesRegister => rdAddr != null && rdAddr != 0;

  /// The sort key used to order a retire stream: the core's own `order`
  /// where present, otherwise observation time. Falling back to time is
  /// honest — without `rvfi_order` the trace's own ordering is all there is.
  int get sortKey => order ?? time;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiscvRetiredInstruction &&
          time == other.time &&
          channelIndex == other.channelIndex &&
          order == other.order &&
          pc == other.pc &&
          pcNext == other.pcNext &&
          insnWord == other.insnWord &&
          disassembly == other.disassembly &&
          mnemonic == other.mnemonic &&
          isaSetName == other.isaSetName &&
          rs1Addr == other.rs1Addr &&
          rs1Value == other.rs1Value &&
          rs2Addr == other.rs2Addr &&
          rs2Value == other.rs2Value &&
          rdAddr == other.rdAddr &&
          rdValue == other.rdValue &&
          memory == other.memory &&
          trap == other.trap &&
          halt == other.halt &&
          intr == other.intr &&
          mode == other.mode &&
          ixl == other.ixl &&
          hasUnknownBits == other.hasUnknownBits;

  @override
  int get hashCode => Object.hash(
    time,
    channelIndex,
    order,
    pc,
    pcNext,
    insnWord,
    disassembly,
    rdAddr,
    rdValue,
    memory,
    trap,
    mode,
  );

  @override
  String toString() =>
      'RiscvRetiredInstruction(order: $order, t: $time, '
      'pc: ${pc == null ? 'null' : '0x${pc!.toRadixString(16)}'}, '
      '${disassembly ?? '?'})';
}
