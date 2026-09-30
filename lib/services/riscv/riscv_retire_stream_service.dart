// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';
import 'package:wavecrux/services/riscv/riscv_trace_values.dart';
import 'package:wavecrux/services/riscv/rvfi_binding_set.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';

/// Reconstructs the ordered stream of retired instructions from an
/// RVFI-instrumented trace.
///
/// **How a retirement is located.** There is no cycle domain in a waveform —
/// `startTime` / `endTime` are simulation ticks — so the service cannot walk
/// cycles. It walks `rvfi_valid` instead and treats two things as marking a
/// retirement:
///
/// 1. a **rising edge** of `rvfi_valid`, and
/// 2. a **change of `rvfi_order`** while `rvfi_valid` is already high.
///
/// The second rule is what makes back-to-back retirement work: a core that
/// retires on consecutive cycles holds `rvfi_valid` high across them, and an
/// edge-only reader would silently collapse the run into one instruction.
/// Where the trace omits `rvfi_order`, only rule 1 applies and that
/// limitation is visible in the reconstructed stream rather than hidden.
///
/// **Sampling.** Every other bound channel is sampled with `valueAt` at the
/// retirement tick. `valueAt` returns null for an unloaded signal, which is
/// indistinguishable from "no value yet" — the caller is responsible for
/// having watched every ref in `RvfiBindingSet.allRefs` through
/// `stageBoundSignalProvider` first.
///
/// The disassembler is **injected**, never constructed here: composing one
/// costs an async asset load, the app already builds one at startup, and the
/// substrate must stay pure Dart.
///
/// Pure Dart — no Flutter imports.
class RiscvRetireStreamService {
  const RiscvRetireStreamService(this._disassembler);

  final InstructionDisassembler? _disassembler;

  /// Builds the retire stream over the inclusive tick range
  /// `[startTime, endTime]`.
  ///
  /// Returns an empty list when the binding set cannot support a stream
  /// (no `rvfi_valid`) or the range is empty. Ordering is by
  /// `RiscvRetiredInstruction.sortKey` — the core's own `rvfi_order` where
  /// the trace carries it, observation time otherwise — with the retirement
  /// channel index as a stable tiebreak.
  List<RiscvRetiredInstruction> build({
    required WaveformDataSource source,
    required RvfiBindingSet bindings,
    required int startTime,
    required int endTime,
  }) {
    if (endTime < startTime) return const [];
    final out = <RiscvRetiredInstruction>[];
    for (var channel = 0; channel < bindings.channelCount; channel++) {
      out.addAll(
        _buildChannel(
          source: source,
          bindings: bindings,
          channelIndex: channel,
          startTime: startTime,
          endTime: endTime,
        ),
      );
    }
    out.sort((a, b) {
      final byOrder = a.sortKey.compareTo(b.sortKey);
      if (byOrder != 0) return byOrder;
      final byTime = a.time.compareTo(b.time);
      if (byTime != 0) return byTime;
      return a.channelIndex.compareTo(b.channelIndex);
    });
    return out;
  }

  // ── private ───────────────────────────────────────────────────────────────

  List<RiscvRetiredInstruction> _buildChannel({
    required WaveformDataSource source,
    required RvfiBindingSet bindings,
    required int channelIndex,
    required int startTime,
    required int endTime,
  }) {
    final validRef = bindings.ref(RvfiChannel.valid, index: channelIndex);
    if (validRef == null) return const [];
    final orderRef = bindings.ref(RvfiChannel.order, index: channelIndex);

    final ticks = <int>[];
    var prevValid = riscvBitState(source.valueAt(validRef, startTime));
    if (prevValid == RiscvBit.high) ticks.add(startTime);

    // `changesInRange` is half-open, hence the `endTime + 1` idiom.
    for (final change in source.changesInRange(
      validRef,
      startTime,
      endTime + 1,
    )) {
      final level = riscvBitState(change.value);
      if (level == RiscvBit.high && prevValid != RiscvBit.high) {
        ticks.add(change.time);
      }
      prevValid = level;
    }

    // Rule 2 — an `rvfi_order` change while valid is high is a further
    // retirement that the valid edge alone cannot see.
    if (orderRef != null) {
      for (final change in source.changesInRange(
        orderRef,
        startTime,
        endTime + 1,
      )) {
        if (riscvBitState(source.valueAt(validRef, change.time)) !=
            RiscvBit.high) {
          continue;
        }
        ticks.add(change.time);
      }
    }

    final unique = ticks.toSet().toList()..sort();
    return [
      for (final t in unique)
        if (t >= startTime && t <= endTime)
          _sampleAt(
            source: source,
            bindings: bindings,
            channelIndex: channelIndex,
            time: t,
          ),
    ];
  }

  RiscvRetiredInstruction _sampleAt({
    required WaveformDataSource source,
    required RvfiBindingSet bindings,
    required int channelIndex,
    required int time,
  }) {
    var unknown = false;

    int? uint(RvfiChannel channel) {
      final ref = bindings.ref(channel, index: channelIndex);
      if (ref == null) return null;
      final decoded = riscvDecodeUint(source.valueAt(ref, time));
      if (decoded.hasUnknown) unknown = true;
      return decoded.value;
    }

    bool? flag(RvfiChannel channel) {
      final ref = bindings.ref(channel, index: channelIndex);
      if (ref == null) return null;
      final bit = riscvBitState(source.valueAt(ref, time));
      if (bit == RiscvBit.unknown) {
        unknown = true;
        return null;
      }
      return bit == RiscvBit.high;
    }

    final insnWord = uint(RvfiChannel.insn);
    final disasm = insnWord == null
        ? null
        : _disassembler?.decode(insnWord, kRiscvInstructionBitWidth);

    final memAddr = uint(RvfiChannel.memAddr);
    final rmask = uint(RvfiChannel.memRmask) ?? 0;
    final wmask = uint(RvfiChannel.memWmask) ?? 0;
    final order = uint(RvfiChannel.order);
    final memory = (memAddr != null && (rmask != 0 || wmask != 0))
        ? RiscvMemoryEffect(
            time: time,
            order: order,
            address: memAddr,
            rmask: rmask,
            wmask: wmask,
            rdata: rmask == 0 ? null : uint(RvfiChannel.memRdata),
            wdata: wmask == 0 ? null : uint(RvfiChannel.memWdata),
          )
        : null;

    return RiscvRetiredInstruction(
      time: time,
      channelIndex: channelIndex,
      order: order,
      pc: uint(RvfiChannel.pcRdata),
      pcNext: uint(RvfiChannel.pcWdata),
      insnWord: insnWord,
      disassembly: disasm?.text,
      mnemonic: disasm?.mnemonic,
      isaSetName: disasm?.setName,
      rs1Addr: uint(RvfiChannel.rs1Addr),
      rs1Value: uint(RvfiChannel.rs1Rdata),
      rs2Addr: uint(RvfiChannel.rs2Addr),
      rs2Value: uint(RvfiChannel.rs2Rdata),
      rdAddr: uint(RvfiChannel.rdAddr),
      rdValue: uint(RvfiChannel.rdWdata),
      memory: memory,
      trap: flag(RvfiChannel.trap),
      halt: flag(RvfiChannel.halt),
      intr: flag(RvfiChannel.intr),
      mode: uint(RvfiChannel.mode),
      ixl: uint(RvfiChannel.ixl),
      hasUnknownBits: unknown,
    );
  }
}
