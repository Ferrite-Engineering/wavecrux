// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
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
///
/// Where the trace omits `rvfi_order`, rule 2 falls back to a **change of
/// `rvfi_pc_rdata` or `rvfi_insn`** while `rvfi_valid` is high: consecutive
/// retirements fetch from different addresses, so the PC moves with each one.
/// The fallback cannot see a run of one instruction retiring at the same PC
/// (a `j .` spin loop), which `rvfi_order` would count; binding it remains
/// the exact answer, and the reduced-binding notice says so.
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
    final xlen = _XlenResolver(source, bindings);
    for (var channel = 0; channel < bindings.channelCount; channel++) {
      out.addAll(
        _buildChannel(
          source: source,
          bindings: bindings,
          channelIndex: channel,
          startTime: startTime,
          endTime: endTime,
          xlen: xlen,
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
    required _XlenResolver xlen,
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
    // retirement that the valid edge alone cannot see. Without `rvfi_order`,
    // a change of the retired PC or instruction word marks it instead.
    final heldHighMarkers = orderRef != null
        ? <String>[orderRef]
        : <String>[
            ?bindings.ref(RvfiChannel.pcRdata, index: channelIndex),
            ?bindings.ref(RvfiChannel.insn, index: channelIndex),
          ];
    for (final markerRef in heldHighMarkers) {
      for (final change in source.changesInRange(
        markerRef,
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
            xlen: xlen,
          ),
    ];
  }

  RiscvRetiredInstruction _sampleAt({
    required WaveformDataSource source,
    required RvfiBindingSet bindings,
    required int channelIndex,
    required int time,
    required _XlenResolver xlen,
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

    BigInt? wide(RvfiChannel channel) {
      final ref = bindings.ref(channel, index: channelIndex);
      if (ref == null) return null;
      final decoded = riscvDecodeBigUint(source.valueAt(ref, time));
      if (decoded == null) unknown = true;
      return decoded;
    }

    final order = uint(RvfiChannel.order);
    final ixl = uint(RvfiChannel.ixl);
    final memory = _memoryEffects(
      time: time,
      order: order,
      address: wide(RvfiChannel.memAddr),
      rmask: wide(RvfiChannel.memRmask) ?? BigInt.zero,
      wmask: wide(RvfiChannel.memWmask) ?? BigInt.zero,
      rdata: () => wide(RvfiChannel.memRdata),
      wdata: () => wide(RvfiChannel.memWdata),
      xlen: () => xlen.at(ixl),
    );

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
      memory: memory.firstOrNull,
      additionalMemory: memory.length > 1 ? memory.sublist(1) : const [],
      trap: flag(RvfiChannel.trap),
      halt: flag(RvfiChannel.halt),
      intr: flag(RvfiChannel.intr),
      debugEntryCause: uint(RvfiChannel.dbg),
      mode: uint(RvfiChannel.mode),
      ixl: ixl,
      hasUnknownBits: unknown,
    );
  }

  /// The memory accesses one retirement reports, one per active slot.
  ///
  /// RVFI defines one access per retirement, and a standard core's ports are
  /// one access wide. CV32E40X widens them to `NMEM` slots (`rvfi_mem_addr`
  /// is 4096 bits, the masks 512) and uses several in one retirement, for
  /// example a Zcmp `cm.push` storing two registers. Read whole, those slots
  /// fold into one wrong address, mask and data word, so a port wider than
  /// one access is split into `XLEN`-bit slots (masks into `XLEN / 8`-bit
  /// slots) and a slot whose masks are both zero is omitted.
  ///
  /// A single-access port is never split: only a mask wider than one RV32
  /// access, or an address wider than 32 bits, asks for [xlen], and when
  /// `XLEN` cannot be established the port is read whole, as before.
  static List<RiscvMemoryEffect> _memoryEffects({
    required int time,
    required int? order,
    required BigInt? address,
    required BigInt rmask,
    required BigInt wmask,
    required BigInt? Function() rdata,
    required BigInt? Function() wdata,
    required int? Function() xlen,
  }) {
    if (address == null) return const [];
    final union = rmask | wmask;
    if (union == BigInt.zero) return const [];

    final slotBits = (union.bitLength > 4 || address.bitLength > 32)
        ? xlen()
        : null;
    final read = rmask == BigInt.zero ? null : rdata();
    final written = wmask == BigInt.zero ? null : wdata();
    if (slotBits == null) {
      return [
        RiscvMemoryEffect(
          time: time,
          order: order,
          address: riscvBigToUint(address),
          rmask: riscvBigToUint(rmask),
          wmask: riscvBigToUint(wmask),
          rdata: read == null ? null : riscvBigToUint(read),
          wdata: written == null ? null : riscvBigToUint(written),
        ),
      ];
    }

    final maskBits = slotBits ~/ 8;
    final dataMask = (BigInt.one << slotBits) - BigInt.one;
    final byteMask = (BigInt.one << maskBits) - BigInt.one;
    BigInt slice(BigInt value, int slot, int bits, BigInt mask) =>
        (value >> (slot * bits)) & mask;

    final slots = (union.bitLength + maskBits - 1) ~/ maskBits;
    return [
      for (var slot = 0; slot < slots; slot++)
        if (slice(union, slot, maskBits, byteMask) != BigInt.zero)
          RiscvMemoryEffect(
            time: time,
            order: order,
            address: riscvBigToUint(slice(address, slot, slotBits, dataMask)),
            rmask: slice(rmask, slot, maskBits, byteMask).toInt(),
            wmask: slice(wmask, slot, maskBits, byteMask).toInt(),
            rdata:
                slice(rmask, slot, maskBits, byteMask) == BigInt.zero ||
                    read == null
                ? null
                : riscvBigToUint(slice(read, slot, slotBits, dataMask)),
            wdata:
                slice(wmask, slot, maskBits, byteMask) == BigInt.zero ||
                    written == null
                ? null
                : riscvBigToUint(slice(written, slot, slotBits, dataMask)),
          ),
    ];
  }
}

/// Establishes `XLEN` for splitting a multi-slot memory port, and only when
/// one is met: from `rvfi_ixl` at the retirement where the trace binds it,
/// otherwise from the declared width of the bound `rvfi_pc_rdata`, looked up
/// once per build. Null when neither says, which keeps the port whole.
class _XlenResolver {
  _XlenResolver(this._source, this._bindings);

  final WaveformDataSource _source;
  final RvfiBindingSet _bindings;
  int? _declared;
  bool _looked = false;

  int? at(int? ixl) {
    switch (ixl) {
      case 1:
        return 32;
      case 2:
        return 64;
      case 3:
        return 128;
    }
    if (!_looked) {
      _looked = true;
      _declared = _declaredPcWidth();
    }
    return _declared;
  }

  int? _declaredPcWidth() {
    final pcRef = _bindings.ref(RvfiChannel.pcRdata);
    if (pcRef == null) return null;
    for (final v in _source.findVariables(
      const SignalFilter(namePattern: 'pc_rdata'),
    )) {
      if (v.signalRef != pcRef) continue;
      final width = v.bitWidth;
      return (width == 32 || width == 64 || width == 128) ? width : null;
    }
    return null;
  }
}
