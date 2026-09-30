// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';

/// Tuning for [RiscvArchStateService].
@immutable
class RiscvArchStateConfig {
  const RiscvArchStateConfig({
    this.registerCount = 32,
    this.memoryEffectDepth = 16,
  });

  /// Architectural register count. 32 for RV32I/RV64I; 16 for RV32E.
  final int registerCount;

  /// How many of the most recent memory effects the snapshot retains.
  /// The replay is a fold, so keeping the full memory history would grow
  /// without bound on a long trace.
  final int memoryEffectDepth;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiscvArchStateConfig &&
          registerCount == other.registerCount &&
          memoryEffectDepth == other.memoryEffectDepth;

  @override
  int get hashCode => Object.hash(registerCount, memoryEffectDepth);
}

/// One architectural register at the cursor.
@immutable
class RiscvRegisterCell {
  const RiscvRegisterCell({
    required this.index,
    required this.value,
    required this.lastWriteTime,
    required this.lastWriteOrder,
  });

  /// Register index (`x5` → 5).
  final int index;

  /// Value after the last retirement at or before the cursor that wrote it.
  final int value;

  /// Tick of that retirement.
  final int lastWriteTime;

  /// `rvfi_order` of that retirement, when the trace carries one.
  final int? lastWriteOrder;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiscvRegisterCell &&
          index == other.index &&
          value == other.value &&
          lastWriteTime == other.lastWriteTime &&
          lastWriteOrder == other.lastWriteOrder;

  @override
  int get hashCode => Object.hash(index, value, lastWriteTime, lastWriteOrder);

  @override
  String toString() =>
      'RiscvRegisterCell(x$index = 0x${value.toRadixString(16)})';
}

/// The reconstructed architectural state at a cursor time.
///
/// "Correct by construction" in the sense that matters: every value here was
/// *reported by the core as retired*, not inferred from physical register-file
/// port activity. A register absent from [registers] was never written in the
/// replayed window — its architectural value is unknown, which is a different
/// statement from "it is zero".
@immutable
class RiscvArchState {
  const RiscvArchState({
    required this.registers,
    required this.cursorTime,
    required this.retiredCount,
    required this.memoryEffects,
    this.pc,
    this.lastRetire,
    this.privilegeMode,
    this.trapCount = 0,
    this.halted = false,
  });

  /// Written registers, keyed by index. `x0` is never present — it is
  /// hardwired zero and RVFI reports a write to it as `rd_addr == 0`.
  final Map<int, RiscvRegisterCell> registers;

  /// The cursor the state was replayed to.
  final int cursorTime;

  /// Number of retirements folded in.
  final int retiredCount;

  /// The most recent [RiscvArchStateConfig.memoryEffectDepth] accesses,
  /// oldest first.
  final List<RiscvMemoryEffect> memoryEffects;

  /// Architectural PC: `rvfi_pc_wdata` of the last folded retirement — i.e.
  /// where the core says it will retire from next.
  final int? pc;

  /// The last retirement folded in, or null when none were.
  final RiscvRetiredInstruction? lastRetire;

  /// `rvfi_mode` of the last folded retirement.
  final int? privilegeMode;

  /// How many folded retirements raised a trap.
  final int trapCount;

  /// Whether a folded retirement asserted `rvfi_halt`.
  final bool halted;

  /// Architectural value of register [index], with `x0` reading as 0 and an
  /// unwritten register reading as null.
  int? registerValue(int index) {
    if (index == 0) return 0;
    return registers[index]?.value;
  }

  @override
  String toString() =>
      'RiscvArchState(t: $cursorTime, retired: $retiredCount, '
      'pc: ${pc == null ? 'null' : '0x${pc!.toRadixString(16)}'}, '
      '${registers.length} registers)';
}
