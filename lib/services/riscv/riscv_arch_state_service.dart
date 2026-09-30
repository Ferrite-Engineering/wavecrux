// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/riscv/riscv_arch_state.dart';
import 'package:wavecrux/services/riscv/riscv_retire_stream_service.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';
import 'package:wavecrux/services/riscv/rvfi_binding_set.dart';

/// Replays the retire stream into the architectural state at a cursor time.
///
/// **Stateless rebuild-on-backward-seek**, exactly as the Pro register-file
/// snapshot service does it and for the same reason: a cached incremental
/// fold is only correct for forward cursor motion, and the cursor is a
/// scrub bar. The contract, in full:
///
/// - the walked range is clamped to `[source.startTime, min(cursor, endTime)]`;
/// - the retire stream is rebuilt from the start of the trace every call;
/// - the fold breaks hard on the first retirement past the cursor;
/// - nothing is memoized, so seeking backwards is simply another build.
///
/// Pure Dart — no Flutter imports.
class RiscvArchStateService {
  const RiscvArchStateService(this._retireStream);

  /// Convenience constructor for callers that only have a disassembler.
  RiscvArchStateService.withDisassembler(InstructionDisassembler? disassembler)
    : _retireStream = RiscvRetireStreamService(disassembler);

  final RiscvRetireStreamService _retireStream;

  /// Decodes the trace up to [cursorTime] and folds it into a snapshot.
  RiscvArchState build({
    required WaveformDataSource source,
    required RvfiBindingSet bindings,
    required int cursorTime,
    RiscvArchStateConfig config = const RiscvArchStateConfig(),
  }) {
    final start = source.startTime;
    var end = cursorTime;
    if (end < start) end = start;
    if (end > source.endTime) end = source.endTime;

    final retires = _retireStream.build(
      source: source,
      bindings: bindings,
      startTime: start,
      endTime: end,
    );
    return buildFromRetires(
      retires: retires,
      cursorTime: cursorTime,
      config: config,
    );
  }

  /// Pure-logic entry point: folds an already-decoded stream. Tests and the
  /// consistency checker call this directly.
  RiscvArchState buildFromRetires({
    required List<RiscvRetiredInstruction> retires,
    required int cursorTime,
    RiscvArchStateConfig config = const RiscvArchStateConfig(),
  }) {
    final registers = <int, RiscvRegisterCell>{};
    final memory = <RiscvMemoryEffect>[];
    var retiredCount = 0;
    var trapCount = 0;
    var halted = false;
    int? pc;
    int? mode;
    RiscvRetiredInstruction? last;

    for (final r in retires) {
      if (r.time > cursorTime) break;
      retiredCount++;
      last = r;

      final rd = r.rdAddr;
      final value = r.rdValue;
      // x0 is hardwired zero: `rd_addr == 0` means the instruction writes
      // no register, whatever `rd_wdata` happens to carry. Recording it
      // would be the mis-reconstruction the consistency checker exists to
      // flag, so the replay declines to make it.
      if (rd != null && rd > 0 && rd < config.registerCount && value != null) {
        registers[rd] = RiscvRegisterCell(
          index: rd,
          value: value,
          lastWriteTime: r.time,
          lastWriteOrder: r.order,
        );
      }

      final effect = r.memory;
      if (effect != null) {
        memory.add(effect);
        if (memory.length > config.memoryEffectDepth) {
          memory.removeAt(0);
        }
      }

      if (r.pcNext != null) {
        pc = r.pcNext;
      } else if (r.pc != null) {
        pc = r.pc;
      }
      if (r.mode != null) mode = r.mode;
      if (r.trap ?? false) trapCount++;
      if (r.halt ?? false) halted = true;
    }

    return RiscvArchState(
      registers: Map<int, RiscvRegisterCell>.unmodifiable(registers),
      cursorTime: cursorTime,
      retiredCount: retiredCount,
      memoryEffects: List<RiscvMemoryEffect>.unmodifiable(memory),
      pc: pc,
      lastRetire: last,
      privilegeMode: mode,
      trapCount: trapCount,
      halted: halted,
    );
  }
}
