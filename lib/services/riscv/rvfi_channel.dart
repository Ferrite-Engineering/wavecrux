// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The riscv-formal RVFI (RISC-V Formal Interface) channel set.
///
/// RVFI is the de-facto standard retirement-observation interface: a core
/// that implements it exposes, per retired instruction, what was retired and
/// what architectural effect it had. That is the one thing a raw VCD of a
/// core does not otherwise tell you, and it is what the whole RISC-V trace
/// substrate is built on.
///
/// The channel list here matches the riscv-formal `rvfi_*` port list. It is treated as the
/// *intended* set rather than gospel: [RvfiChannel] is an enum so an unknown
/// `rvfi_`-prefixed signal in a trace is simply not bound, never guessed at.
///
/// Pure Dart — no Flutter imports.
library;

/// One RVFI channel.
///
/// [signalName] is the canonical riscv-formal port name. Detection matches
/// against it modulo hierarchy prefixes, `_i` / `_o` suffixes, and a
/// multi-channel index, so a design that names its port `core_rvfi_valid_o`
/// or `rvfi_valid[1]` still resolves to the right channel.
enum RvfiChannel {
  /// Retirement strobe. Asserted for the cycle in which an instruction
  /// retires. The channel every other channel is sampled against.
  valid('rvfi_valid', nominalBitWidth: 1),

  /// Monotonically increasing retirement counter. Gaps and regressions are
  /// the cheapest correctness signal in the whole interface.
  order('rvfi_order', nominalBitWidth: 64),

  /// The retired instruction word.
  insn('rvfi_insn', nominalBitWidth: 32),

  /// Set when the retired instruction raised a trap.
  trap('rvfi_trap', nominalBitWidth: 1),

  /// Set on the last retired instruction before the core halts.
  halt('rvfi_halt', nominalBitWidth: 1),

  /// Set when the retirement was the first of a trap handler.
  intr('rvfi_intr', nominalBitWidth: 1),

  /// Privilege level the instruction retired at (0=U, 1=S, 3=M).
  mode('rvfi_mode', nominalBitWidth: 2),

  /// Effective XLEN encoding at retirement (1=32, 2=64).
  ixl('rvfi_ixl', nominalBitWidth: 2),

  /// Register index read on port 1 (0 when unused).
  rs1Addr('rvfi_rs1_addr', nominalBitWidth: 5),

  /// Value read on port 1.
  rs1Rdata('rvfi_rs1_rdata', nominalBitWidth: 32),

  /// Register index read on port 2 (0 when unused).
  rs2Addr('rvfi_rs2_addr', nominalBitWidth: 5),

  /// Value read on port 2.
  rs2Rdata('rvfi_rs2_rdata', nominalBitWidth: 32),

  /// Destination register index (0 when the instruction writes no register).
  rdAddr('rvfi_rd_addr', nominalBitWidth: 5),

  /// Value written to the destination register. Must be 0 when
  /// [rdAddr] is 0 — x0 is hardwired zero.
  rdWdata('rvfi_rd_wdata', nominalBitWidth: 32),

  /// PC the instruction was fetched from.
  pcRdata('rvfi_pc_rdata', nominalBitWidth: 32),

  /// PC of the next instruction to retire. A mismatch against the following
  /// retirement's [pcRdata] is a control-flow discontinuity.
  pcWdata('rvfi_pc_wdata', nominalBitWidth: 32),

  /// Address of the memory access, if any.
  memAddr('rvfi_mem_addr', nominalBitWidth: 32),

  /// Byte-enable mask of the read half of the access.
  memRmask('rvfi_mem_rmask', nominalBitWidth: 4),

  /// Byte-enable mask of the write half of the access.
  memWmask('rvfi_mem_wmask', nominalBitWidth: 4),

  /// Data read by the access (bytes outside [memRmask] are don't-care).
  memRdata('rvfi_mem_rdata', nominalBitWidth: 32),

  /// Data written by the access (bytes outside [memWmask] are don't-care).
  memWdata('rvfi_mem_wdata', nominalBitWidth: 32);

  const RvfiChannel(this.signalName, {required this.nominalBitWidth});

  /// Canonical riscv-formal port name.
  final String signalName;

  /// Width of one channel's slice of this port for a 32-bit core. Used only
  /// to *suspect* a packed superscalar vector (a `rvfi_valid` wider than one
  /// bit); nothing is decoded from it, because a real trace's widths depend
  /// on XLEN and ILEN.
  final int nominalBitWidth;

  /// Whether an RVFI binding set is unusable without this channel.
  ///
  /// Without [valid] there is no retirement strobe and therefore no stream at
  /// all; without [insn] there is nothing to disassemble; without [pcRdata]
  /// nothing can be located in the program. Everything else degrades a view
  /// rather than removing it.
  bool get isRequired =>
      this == RvfiChannel.valid ||
      this == RvfiChannel.insn ||
      this == RvfiChannel.pcRdata;

  /// Whether this channel is a member of the *reduced* binding set — the
  /// minimum that still supports a useful retired-instruction log with
  /// register-write reconstruction (retire valid + pc + insn + rd).
  ///
  /// A binding set that covers the reduced set but not the full one is
  /// reported as such so the consuming widget can degrade its views and say
  /// so, rather than refusing to render on an otherwise good trace.
  bool get isReducedSetMember =>
      isRequired || this == RvfiChannel.rdAddr || this == RvfiChannel.rdWdata;
}

/// The instruction encoding width the substrate disassembles at. RVFI
/// reports the full retired instruction word; compressed instructions are
/// reported in their expanded 32-bit form by riscv-formal-compliant cores.
const int kRiscvInstructionBitWidth = 32;
