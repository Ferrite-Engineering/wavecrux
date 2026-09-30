// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';
import 'package:wavecrux/services/riscv/rvfi_binding_set.dart';

/// Advisory `attributes` keys a `riscv.formal.trace_step` coordinate carries,
/// spelled here because they are **producer** vocabulary rather than protocol
/// vocabulary: CXP §9.9.2 (https://edacrux.app/cxp#sec-9-9-2) registers
/// `riscv.isa` and `riscv.mode` on
/// [CxpStreamCoordinate] itself, while the `riscv.formal.*` keys mirror
/// SimCrux's `RiscvFormalDriver` metric names. All of them are advisory —
/// CXP §9.9's rule 2 forbids needing any of them to *resolve* a coordinate, and
/// nothing here is read before a landing has already been established.
abstract final class RiscvCoordinateAttributes {
  /// The riscv-formal check the proof was run on (`insn_sub_ch0`).
  static const String check = 'riscv.formal.check';

  /// The check group (`insn`, `causal`, `unique`, …).
  static const String group = 'riscv.formal.group';

  /// The solver's verdict token. Only `FAIL` ever carries a coordinate.
  static const String verdict = 'riscv.formal.verdict';

  /// The bounded-proof depth the run was configured for — the *of 20* in
  /// "step 7 of 20".
  static const String depthConfigured = 'riscv.formal.depth_configured';

  /// The [CxpStreamCoordinate.riscvModeAttribute] value that marks a
  /// coordinate derived from a **replayed committed fixture** rather than a
  /// live solver run. A surface that displays such a landing must label it,
  /// and must never present it as measured.
  static const String demoMode = 'demo';
}

/// The uniform **step lattice** of a bounded-proof counterexample trace.
///
/// CXP §9.9.2's `riscv.formal.trace_step` stream is indexed by the step a
/// bounded model checker reported, counting the trace's initial state as step
/// 0. A waveform has no step domain — it has simulation *ticks* — so a
/// receiver must recover the lattice from the trace itself before it can
/// convert. This is that recovery, and it is deliberately a **measurement
/// with a refusal**, not an assumption.
///
/// ### How the grid is established
///
/// 1. Collect every tick at which **any bound RVFI signal** changes, together
///    with the trace's `startTime` and `endTime`. Only the RVFI channels
///    count: a counterexample VCD dumped with a clock carries transitions at
///    half-step boundaries that have nothing to do with the proof's steps,
///    and the stream being indexed is the RVFI bundle.
/// 2. [origin] is `startTime` — step 0 *is* the trace's initial state, by the
///    binding's own definition, so the lattice's phase is not a free
///    parameter.
/// 3. [pitch] is the **smallest positive gap** between consecutive distinct
///    ticks.
/// 4. Every collected tick must then lie on `origin + k·pitch`. A trace whose
///    RVFI activity is irregular — an ordinary simulation dump, say — fails
///    this and yields **null**: the caller declines the coordinate rather
///    than landing somewhere plausible and wrong.
///
/// ### The bound this cannot see past, stated rather than hidden
///
/// If a trace's RVFI channels happen to change only on *every other* step,
/// the smallest observed gap is two steps and this grid is coarse by a factor
/// of two. Nothing in the trace distinguishes that case — the finer lattice
/// left no evidence — so no receiver could do better from the file alone.
/// The consequence is bounded by what the caller does with the answer: the
/// step's tick is used to *find* a retirement, and a missing retirement
/// degrades to placing the cursor, never to selecting a different
/// instruction.
@immutable
class RiscvTraceStepGrid {
  /// Creates a grid. [pitch] must be positive.
  const RiscvTraceStepGrid({
    required this.origin,
    required this.pitch,
    required this.lastStep,
  }) : assert(pitch > 0, 'pitch must be positive');

  /// Tick of step 0 — the trace's initial state.
  final int origin;

  /// Ticks per step.
  final int pitch;

  /// Highest step the loaded trace can address.
  final int lastStep;

  /// The simulation tick of [step], or null when the trace does not reach it.
  int? tickForStep(int step) {
    if (step < 0 || step > lastStep) return null;
    return origin + step * pitch;
  }

  /// Derives the grid from [source] as observed on [bindings]' RVFI channels,
  /// or null when the trace carries no uniform step lattice. See the class
  /// doc for the four rules.
  static RiscvTraceStepGrid? derive({
    required WaveformDataSource source,
    required RvfiBindingSet bindings,
  }) {
    final start = source.startTime;
    final end = source.endTime;
    if (end < start) return null;
    // With no RVFI channel there is nothing to measure the lattice ON, and
    // `{startTime, endTime}` alone would manufacture a two-step grid out of
    // the trace's duration. That is exactly the plausible-but-invented answer
    // the binding forbids.
    if (bindings.allRefs.isEmpty) return null;

    final ticks = <int>{start, end};
    for (final ref in bindings.allRefs) {
      // `changesInRange` is half-open, hence the `end + 1` idiom used
      // throughout the RISC-V substrate.
      for (final change in source.changesInRange(ref, start, end + 1)) {
        if (change.time >= start && change.time <= end) ticks.add(change.time);
      }
    }
    if (ticks.length < 2) return null;

    final sorted = ticks.toList()..sort();
    var pitch = sorted[1] - sorted[0];
    for (var i = 2; i < sorted.length; i++) {
      final gap = sorted[i] - sorted[i - 1];
      if (gap > 0 && gap < pitch) pitch = gap;
    }
    if (pitch <= 0) return null;

    for (final tick in sorted) {
      if ((tick - start) % pitch != 0) return null;
    }
    return RiscvTraceStepGrid(
      origin: start,
      pitch: pitch,
      lastStep: (end - start) ~/ pitch,
    );
  }

  @override
  String toString() =>
      'RiscvTraceStepGrid(origin: $origin, pitch: $pitch, '
      'lastStep: $lastStep)';
}

/// What resolving a CXP §9.9 coordinate against the loaded trace produced.
///
/// Three outcomes, and the difference between the last two is the whole
/// honesty contract of the binding:
///
/// * [RiscvCoordinateResolution.declined] — the coordinate could not be
///   resolved. The caller still honours the *element* (CXP §9.4) and reports
///   [reason] in the acknowledgement, so the originating app can say why
///   rather than leaving the user to wonder.
/// * [RiscvCoordinateResolution.retirement] — the coordinate resolved to a
///   specific retirement. Move the cursor to [time] and select it.
/// * [RiscvCoordinateResolution.step] — the addressed step exists in the
///   trace but no instruction retired there. Move the cursor to [time] and
///   say so; CXP §9.9.2 prescribes exactly this fallback.
@immutable
class RiscvCoordinateResolution {
  /// The coordinate names something this trace cannot answer for.
  const RiscvCoordinateResolution.declined(String this.reason)
    : time = null,
      retired = null,
      channelIndex = null;

  /// The coordinate resolved to [retired], at `retired.time`.
  RiscvCoordinateResolution.retirement(RiscvRetiredInstruction this.retired)
    : time = retired.time,
      channelIndex = retired.channelIndex,
      reason = null;

  /// The addressed step exists but holds no retirement.
  const RiscvCoordinateResolution.step({
    required int this.time,
    this.channelIndex,
  }) : retired = null,
       reason = null;

  /// The simulation tick to place the primary cursor at, or null when
  /// declined.
  final int? time;

  /// The retirement to select, or null when only a cursor placement is
  /// warranted.
  final RiscvRetiredInstruction? retired;

  /// Retirement channel the landing belongs to, when one is determined.
  final int? channelIndex;

  /// Why the coordinate was declined; null on either landing.
  final String? reason;

  /// Whether the coordinate produced a cursor placement of any kind.
  bool get landed => time != null;
}

/// Resolves a CXP §9.9 semantic stream coordinate into a place in **this**
/// loaded trace — the consumer half of the hand-off.
///
/// ## Two streams, and everything else ignored
///
/// * **`riscv.formal.trace_step`** is what actually arrives today. A bounded
///   model checker reports the step its assertion fired at; it cannot report
///   `rvfi_order`, because the number of instructions a core retires in *N*
///   cycles is a property of the core under proof. **Whoever holds the
///   decoded stream owns the index conversion**, and that is this class: the
///   step is mapped onto the trace's own lattice ([RiscvTraceStepGrid]) and
///   the retirement at that step, on `sub_id`'s RVFI channel, is selected.
/// * **`riscv.rvfi.retire`** is the spec's normative binding — `sequence_index`
///   is `rvfi_order` — and is accepted although nothing in the suite emits it
///   yet. It is what a trace-holding producer will send.
/// * **Any other `stream_id`** is ignored, per CXP §9.9.1's open-vocabulary rule:
///   the caller honours the element and never treats an unknown stream as an
///   error. AXI transactions, Ethernet frames, USB packets and video lines are
///   anticipated bindings, and tolerating them today is the forward
///   compatibility path.
///
/// ## Attributes are cross-checks, never inputs
///
/// CXP §9.9's rule 2: a receiver MUST be able to resolve from
/// `(stream_id, sequence_index, sub_id)` alone. `riscv.pc` is used only to
/// **disprove** a resolution — a retirement at the requested `rvfi_order`
/// whose PC disagrees with the sender's means the coordinate was resolved
/// against the wrong trace, and declining is better than selecting the wrong
/// instruction. Everything else the sender knows (`riscv.formal.check`,
/// `riscv.mode`, …) is display material and is passed through untouched.
///
/// Pure Dart — no Flutter, no Riverpod, no IO — so every decision below is
/// directly testable.
class RiscvStreamCoordinateResolver {
  /// Creates a resolver.
  const RiscvStreamCoordinateResolver();

  /// Whether this build implements [streamId] at all.
  ///
  /// Exposed so a caller can decline an unimplemented stream **without first
  /// walking the trace** — `stream_id` is an open vocabulary (CXP §9.9.1) and
  /// most values a future peer sends will not be RISC-V at all.
  static bool implementsStream(String streamId) =>
      streamId == CxpStreamCoordinate.riscvFormalTraceStepStreamId ||
      streamId == CxpStreamCoordinate.riscvRvfiRetireStreamId;

  /// The decline an unimplemented [streamId] produces. CXP §9.9.1: a receiver
  /// **MUST** ignore such a coordinate, continue processing the message, and
  /// **MUST NOT** treat it as a protocol error — so this is a reason, never
  /// an exception, and the element is honoured regardless.
  static RiscvCoordinateResolution declineUnknownStream(String streamId) =>
      RiscvCoordinateResolution.declined(
        'wavecrux does not implement the "$streamId" stream; '
        'the element was honoured without it',
      );

  /// Resolves [coordinate] against the loaded [source], the RVFI [bindings]
  /// detected in it, and the already-built [retires] stream.
  ///
  /// [retires] must have been built over the whole trace with every ref in
  /// `bindings.allRefs` loaded — the lazy-load trap (ARCHITECTURE §6.6) bites
  /// here exactly as it bites the Commit Inspector, and an unloaded channel
  /// answers `valueAt` with null rather than with an error.
  RiscvCoordinateResolution resolve({
    required CxpStreamCoordinate coordinate,
    required WaveformDataSource source,
    required RvfiBindingSet bindings,
    required List<RiscvRetiredInstruction> retires,
  }) {
    switch (coordinate.streamId) {
      case CxpStreamCoordinate.riscvFormalTraceStepStreamId:
        return _resolveFormalStep(coordinate, source, bindings, retires);
      case CxpStreamCoordinate.riscvRvfiRetireStreamId:
        return _resolveRvfiRetire(coordinate, retires);
      default:
        return declineUnknownStream(coordinate.streamId);
    }
  }

  // ── riscv.formal.trace_step ─────────────────────────────────────────────

  RiscvCoordinateResolution _resolveFormalStep(
    CxpStreamCoordinate coordinate,
    WaveformDataSource source,
    RvfiBindingSet bindings,
    List<RiscvRetiredInstruction> retires,
  ) {
    final channel = _formalChannelIndex(coordinate.subId);
    if (channel == null) {
      return RiscvCoordinateResolution.declined(
        'unrecognised RVFI channel "${coordinate.subId}" — '
        "expected riscv-formal's ch<N>",
      );
    }
    if (channel >= bindings.channelCount) {
      return RiscvCoordinateResolution.declined(
        'the loaded trace binds ${bindings.channelCount} RVFI retirement '
        'channel(s); "${coordinate.subId}" is not one of them',
      );
    }

    final grid = RiscvTraceStepGrid.derive(source: source, bindings: bindings);
    if (grid == null) {
      // CXP §9.9.2: "If it cannot establish the trace's step grid it MUST decline
      // the coordinate rather than guess, and still honour the element."
      return const RiscvCoordinateResolution.declined(
        'the loaded trace has no uniform step grid, so a bounded-proof step '
        'cannot be converted to a time — the file was opened without it',
      );
    }
    final tick = grid.tickForStep(coordinate.sequenceIndex);
    if (tick == null) {
      return RiscvCoordinateResolution.declined(
        'step ${coordinate.sequenceIndex} is past the end of the loaded '
        'trace (last step ${grid.lastStep})',
      );
    }

    for (final retire in retires) {
      if (retire.time == tick && retire.channelIndex == channel) {
        return RiscvCoordinateResolution.retirement(retire);
      }
    }
    // No retirement at that step is a normal, reportable outcome — a
    // counterexample often fires on a cycle where nothing retires.
    return RiscvCoordinateResolution.step(time: tick, channelIndex: channel);
  }

  /// Parses riscv-formal's `ch<N>` channel token, or a bare decimal. A null
  /// [subId] means the single retirement channel, per CXP §9.9.2's "MAY be
  /// omitted".
  static int? _formalChannelIndex(String? subId) {
    if (subId == null || subId.isEmpty) return 0;
    final token = subId.toLowerCase().trim();
    final digits = token.startsWith('ch') ? token.substring(2) : token;
    final parsed = int.tryParse(digits);
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  // ── riscv.rvfi.retire ───────────────────────────────────────────────────

  RiscvCoordinateResolution _resolveRvfiRetire(
    CxpStreamCoordinate coordinate,
    List<RiscvRetiredInstruction> retires,
  ) {
    // CXP §9.9.2 binds `sub_id` to the hart id, and absence to hart 0. WaveCrux
    // binds ONE core's RVFI bundle at a time — the detection service picks
    // the best-covered bundle in the trace — so it has no hart axis to index.
    // Claiming to have landed on hart 3 would be a fabrication; declining
    // names the limit instead.
    final hart = coordinate.subId;
    if (hart != null && hart != '0') {
      return RiscvCoordinateResolution.declined(
        "wavecrux binds one hart's RVFI bundle per trace; "
        'hart "$hart" is not addressable',
      );
    }

    if (!retires.any((r) => r.order != null)) {
      return const RiscvCoordinateResolution.declined(
        'the loaded trace carries no rvfi_order, so an rvfi_order index '
        'cannot be resolved in it',
      );
    }

    for (final retire in retires) {
      if (retire.order != coordinate.sequenceIndex) continue;
      final claimed = _parsePc(
        coordinate.attributes[CxpStreamCoordinate.riscvPcAttribute],
      );
      // The cross-check CXP §9.9.2 recommends. A PC disagreement means this is a
      // different trace of the same program (or a different program), and
      // selecting index N of the wrong stream is the failure the whole
      // coordinate design exists to avoid.
      if (claimed != null && retire.pc != null && retire.pc != claimed) {
        return RiscvCoordinateResolution.declined(
          'rvfi_order ${coordinate.sequenceIndex} retires '
          '${_hex(retire.pc!)} here, not ${_hex(claimed)} — '
          'this is not the trace the coordinate was measured in',
        );
      }
      return RiscvCoordinateResolution.retirement(retire);
    }
    return RiscvCoordinateResolution.declined(
      'no retirement with rvfi_order ${coordinate.sequenceIndex} in the '
      'loaded trace',
    );
  }

  /// Parses the `riscv.pc` attribute — hex with a `0x` prefix per CXP §9.9.2,
  /// tolerating a bare hex word. Returns null for anything else; an
  /// unparseable advisory attribute must never sink a resolution.
  static int? _parsePc(String? raw) {
    if (raw == null) return null;
    final text = raw.trim().toLowerCase();
    final digits = text.startsWith('0x') ? text.substring(2) : text;
    if (digits.isEmpty) return null;
    return int.tryParse(digits, radix: 16);
  }

  static String _hex(int value) =>
      '0x${value.toRadixString(16).padLeft(8, '0')}';
}
