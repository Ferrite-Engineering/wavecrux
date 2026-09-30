// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/services/riscv/riscv_instruction_identity.dart';
import 'package:wavecrux/services/riscv/riscv_trace_values.dart';

/// The signal refs bound to one pipeline stage.
///
/// Every field is optional because a partially-instrumented pipeline is a
/// supported case: a core that exposes per-stage `valid` and nothing else
/// still produces a readable occupancy grid, it just cannot express a stall
/// or a flush and the tracker will say so.
@immutable
class RiscvPipelineStageBinding {
  const RiscvPipelineStageBinding({
    this.validRef,
    this.pcRef,
    this.stallRef,
    this.flushRef,
    this.tagRef,
  });

  /// The stage holds an instruction this cycle.
  final String? validRef;

  /// PC of the stage's occupant. Required by the `pc` identity source and
  /// used for row labels by every source.
  final String? pcRef;

  /// The stage could not advance at the end of this cycle.
  final String? stallRef;

  /// The stage's contents were killed this cycle.
  final String? flushRef;

  /// Instruction tag / ROB index.
  ///
  /// **Open core never binds this.** It exists so the Pro tag tracker
  /// (`RiscvIdentitySource.tag`, installed through
  /// [RiscvIdentityTrackerRegistry]) can reuse this service verbatim rather
  /// than forking a parallel observation path — the observation model
  /// already carries [RiscvStageSample.tag].
  final String? tagRef;

  /// Whether anything at all is bound to this stage.
  bool get isBound =>
      validRef != null ||
      pcRef != null ||
      stallRef != null ||
      flushRef != null ||
      tagRef != null;

  /// Every non-null ref, for the caller's lazy-load watch.
  List<String> get refs => <String>[
    for (final r in <String?>[validRef, pcRef, stallRef, flushRef, tagRef])
      if (r != null && r.isNotEmpty) r,
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiscvPipelineStageBinding &&
          validRef == other.validRef &&
          pcRef == other.pcRef &&
          stallRef == other.stallRef &&
          flushRef == other.flushRef &&
          tagRef == other.tagRef;

  @override
  int get hashCode => Object.hash(validRef, pcRef, stallRef, flushRef, tagRef);

  @override
  String toString() => 'RiscvPipelineStageBinding(valid: $validRef)';
}

/// An observation plus the tick each of its cycles was sampled at.
///
/// The tick list is the whole point of this type: **there is no cycle domain
/// in a waveform.** `startTime` / `endTime` / `placePrimary` are simulation
/// ticks, so a widget that wants to move the cursor to "cycle 12" has to be
/// handed the tick that cycle 12 was sampled at, and a widget that wants to
/// know which cycle the cursor is in has to search this list.
@immutable
class RiscvPipelineObservationResult {
  const RiscvPipelineObservationResult({
    required this.observation,
    required this.cycleTicks,
  });

  /// An empty result — no clock bound, or no rising edge in range.
  static const RiscvPipelineObservationResult empty =
      RiscvPipelineObservationResult(
        observation: RiscvPipelineObservation(stageCount: 0, cycles: []),
        cycleTicks: [],
      );

  /// The per-cycle, per-stage samples.
  final RiscvPipelineObservation observation;

  /// `cycleTicks[i]` is the clock rising edge that opens
  /// `observation.cycles[i]`. Strictly increasing.
  final List<int> cycleTicks;

  /// How many cycles were observed.
  int get cycleCount => cycleTicks.length;

  /// Index of the cycle that contains [tick] — the last cycle whose opening
  /// edge is at or before it.
  ///
  /// Returns 0 for a tick before the first edge (so a cursor parked at the
  /// start of the trace anchors on cycle 0 rather than on nothing) and -1
  /// when there are no cycles at all.
  int cycleAt(int tick) {
    if (cycleTicks.isEmpty) return -1;
    if (tick < cycleTicks.first) return 0;
    var lo = 0;
    var hi = cycleTicks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (cycleTicks[mid] <= tick) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

/// Turns a bound clock plus per-stage control signals into the
/// [RiscvPipelineObservation] the identity trackers consume.
///
/// **Architecture-neutral.** Nothing here knows what a RISC-V is; it reads
/// `valid` / `stall` / `flush` / `pc` per stage and a clock. It lives beside
/// the identity trackers because that is where the observation model lives,
/// not because it is ISA-coupled — the widget it feeds
/// (`features/stage/widgets/pipeline/`) applies unchanged to an FFT engine or
/// a packet processor.
///
/// **The cycle domain is derived, never assumed.** Cycles come from rising
/// edges of the bound clock, and every stage signal is sampled with `valueAt`
/// *at* the rising edge — i.e. the value the stage was holding going into the
/// edge, which is what a per-stage `valid` means.
///
/// `valueAt` returns null for an unloaded signal, indistinguishable from "no
/// value yet", so the caller must have watched every ref in
/// [RiscvPipelineStageBinding.refs] (and the clock) through
/// `stageBoundSignalProvider` first.
///
/// Pure Dart — no Flutter imports.
class RiscvPipelineObservationService {
  const RiscvPipelineObservationService();

  /// Hard ceiling on how many cycles a single build will walk.
  ///
  /// A 100 MHz clock over a millisecond of simulation is 100 000 cycles, and
  /// the grid can only ever show a window of a few dozen. Truncating at a
  /// stated bound beats walking an unbounded trace on every rebuild; the
  /// result's `cycleCount` is the number of cycles actually observed, so a
  /// truncated build is visible to the caller rather than silent.
  static const int defaultMaxCycles = 20000;

  /// Rising edges of [clockRef] over the inclusive tick range
  /// `[startTime, endTime]`, capped at [maxCycles].
  ///
  /// A clock already high at [startTime] counts as opening cycle 0: a trace
  /// that begins mid-cycle still has a first cycle, and dropping it would
  /// shift every cycle index by one against the user's own waveform.
  List<int> cycleTicks({
    required WaveformDataSource source,
    required String clockRef,
    required int startTime,
    required int endTime,
    int maxCycles = defaultMaxCycles,
  }) {
    if (endTime < startTime || maxCycles <= 0) return const [];
    final ticks = <int>[];
    var previous = riscvBitState(source.valueAt(clockRef, startTime));
    if (previous == RiscvBit.high) ticks.add(startTime);

    // `changesInRange` is half-open, hence the `endTime + 1` idiom.
    for (final change in source.changesInRange(
      clockRef,
      startTime,
      endTime + 1,
    )) {
      final level = riscvBitState(change.value);
      if (level == RiscvBit.high &&
          previous != RiscvBit.high &&
          change.time >= startTime) {
        ticks.add(change.time);
        if (ticks.length >= maxCycles) break;
      }
      previous = level;
    }
    return ticks;
  }

  /// Builds the observation over `[startTime, endTime]`.
  ///
  /// Returns [RiscvPipelineObservationResult.empty] when the clock is unbound
  /// or never rises — the honest answer to "how many cycles is this", not an
  /// invented one.
  RiscvPipelineObservationResult build({
    required WaveformDataSource source,
    required String? clockRef,
    required List<RiscvPipelineStageBinding> stages,
    required int startTime,
    required int endTime,
    int maxCycles = defaultMaxCycles,
  }) {
    if (clockRef == null || clockRef.isEmpty || stages.isEmpty) {
      return RiscvPipelineObservationResult.empty;
    }
    final ticks = cycleTicks(
      source: source,
      clockRef: clockRef,
      startTime: startTime,
      endTime: endTime,
      maxCycles: maxCycles,
    );
    if (ticks.isEmpty) return RiscvPipelineObservationResult.empty;

    final cycles = <RiscvPipelineCycle>[
      for (final tick in ticks)
        RiscvPipelineCycle(
          stages: <RiscvStageSample>[
            for (final stage in stages)
              RiscvStageSample(
                valid: _bit(source, stage.validRef, tick),
                pc: _uint(source, stage.pcRef, tick),
                tag: _uint(source, stage.tagRef, tick),
                stall: _bit(source, stage.stallRef, tick),
                flush: _bit(source, stage.flushRef, tick),
              ),
          ],
        ),
    ];

    return RiscvPipelineObservationResult(
      observation: RiscvPipelineObservation(
        stageCount: stages.length,
        cycles: List.unmodifiable(cycles),
      ),
      cycleTicks: List.unmodifiable(ticks),
    );
  }

  /// An unbound or unknown control signal reads false.
  ///
  /// Deliberate: `stall` and `flush` are *optional* pins, and "not bound"
  /// has to mean "this pipeline never stalls / never flushes" for the model
  /// to run at all. Where that is wrong, the positional tracker's own
  /// self-check catches it as an occupancy mismatch rather than the grid
  /// quietly being wrong — which is the whole design.
  static bool _bit(WaveformDataSource source, String? ref, int time) =>
      ref != null &&
      ref.isNotEmpty &&
      riscvBitState(source.valueAt(ref, time)) == RiscvBit.high;

  static int? _uint(WaveformDataSource source, String? ref, int time) {
    if (ref == null || ref.isEmpty) return null;
    return riscvDecodeUint(source.valueAt(ref, time)).value;
  }
}
