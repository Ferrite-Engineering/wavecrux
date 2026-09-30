// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// How a pipeline view decides that the instruction in stage *n* this cycle
/// is the same instruction that was in stage *n-1* last cycle.
///
/// This is stated as an explicit, honest choice rather than hidden inside an
/// algorithm, because the three answers have genuinely different accuracy and
/// the user is entitled to know which one is drawing their diagram.
enum RiscvIdentitySource {
  /// A per-stage instruction tag / ROB index bound from the design. The only
  /// source that survives out-of-order, superscalar and multi-hart pipelines.
  ///
  /// **Pro.** Open core defines the enum value and the seam; the tracker
  /// itself is registered by the Pro overlay through
  /// [RiscvIdentityTrackerRegistry].
  tag,

  /// Match the PC observed in each stage. Exact while every in-flight PC is
  /// distinct; ambiguous in a tight loop where the same PC is legitimately in
  /// two stages at once.
  pc,

  /// A shift-register model of the pipeline driven by the per-stage
  /// valid / stall / flush signals. Correct for a single-issue in-order pipe
  /// and nothing else — which is why it reports its own confidence.
  positional,
}

/// How much the tracker trusts what it produced.
enum RiscvIdentityConfidence {
  /// The observation matched the tracker's model exactly.
  high,

  /// The model held, but with ambiguity the tracker had to resolve by
  /// convention (a repeated PC, a tie between two candidates).
  degraded,

  /// The observation contradicted the model. The occupancy grid is not
  /// trustworthy and a consumer must say so rather than draw it.
  low,
}

/// Why a tracker lowered its confidence.
enum RiscvIdentityWarningKind {
  /// The model predicted a stage was occupied and the trace said it was not
  /// (or the reverse). The defining failure of positional tracking.
  occupancyMismatch,

  /// The same PC was valid in two stages in the same cycle, so PC matching
  /// could not tell the two instructions apart.
  ambiguousPc,

  /// The same instruction tag was valid in two places in the same cycle.
  ///
  /// The tag counterpart of [ambiguousPc], and a strictly worse symptom: a
  /// PC legitimately repeats in a tight loop, but a tag / ROB index is
  /// *defined* to be unique among the instructions in flight. Seeing one
  /// twice means the tag pins are mis-bound, the field is narrower than the
  /// window it indexes, or the design's tags are not what they claim — so a
  /// tracker that reports this is saying the grid is not a reconstruction.
  ///
  /// Open core never raises it: [RiscvIdentitySource.tag] is the Pro
  /// tracker. The value lives here because the warning vocabulary belongs to
  /// the identity model, not to whichever build implements a given source.
  ambiguousTag,

  /// A stage asserted stall and flush in the same cycle. The model has no
  /// defined behavior for that and declines to invent one.
  contradictoryControl,

  /// An instruction left the pipeline without reaching the last stage and
  /// without a flush to explain it.
  unexplainedDrop,
}

/// One reason a tracker lowered its confidence, located in the trace.
@immutable
class RiscvIdentityWarning {
  const RiscvIdentityWarning({
    required this.kind,
    required this.cycleIndex,
    required this.stageIndex,
    required this.detail,
  });

  final RiscvIdentityWarningKind kind;

  /// Index into the observation's cycle list — not a tick. Mapping cycles to
  /// ticks is the caller's job, via a bound clock's rising edges.
  final int cycleIndex;

  /// Stage the warning was raised at, or -1 when it is not stage-specific.
  final int stageIndex;

  /// Short, non-localized diagnostic detail. Surfaces are expected to render
  /// their own localized summary and use this for a tooltip / report.
  final String detail;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiscvIdentityWarning &&
          kind == other.kind &&
          cycleIndex == other.cycleIndex &&
          stageIndex == other.stageIndex &&
          detail == other.detail;

  @override
  int get hashCode => Object.hash(kind, cycleIndex, stageIndex, detail);

  @override
  String toString() =>
      'RiscvIdentityWarning($kind @ cycle $cycleIndex stage $stageIndex)';
}

/// What one pipeline stage looked like in one cycle.
@immutable
class RiscvStageSample {
  const RiscvStageSample({
    this.valid = false,
    this.pc,
    this.tag,
    this.stall = false,
    this.flush = false,
  });

  /// The stage holds an instruction this cycle.
  final bool valid;

  /// PC observed in the stage, when a PC signal is bound to it.
  final int? pc;

  /// Instruction tag / ROB index observed in the stage, when bound. Only the
  /// Pro tag tracker reads this; open core carries it so the observation
  /// model does not have to change when that tracker arrives.
  final int? tag;

  /// The stage could not advance this cycle.
  final bool stall;

  /// The stage's contents were killed this cycle.
  final bool flush;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiscvStageSample &&
          valid == other.valid &&
          pc == other.pc &&
          tag == other.tag &&
          stall == other.stall &&
          flush == other.flush;

  @override
  int get hashCode => Object.hash(valid, pc, tag, stall, flush);

  @override
  String toString() =>
      'RiscvStageSample(valid: $valid, pc: $pc, stall: $stall, '
      'flush: $flush)';
}

/// One cycle of the pipeline, one sample per stage.
@immutable
class RiscvPipelineCycle {
  const RiscvPipelineCycle({required this.stages});

  /// Stage samples, front of the pipe first.
  final List<RiscvStageSample> stages;

  @override
  String toString() => 'RiscvPipelineCycle(${stages.length} stages)';
}

/// A window of observed pipeline cycles.
@immutable
class RiscvPipelineObservation {
  const RiscvPipelineObservation({
    required this.stageCount,
    required this.cycles,
  });

  /// Number of configured stages (2–8 in the open-core pipeline widget).
  final int stageCount;

  /// Cycles, oldest first.
  final List<RiscvPipelineCycle> cycles;
}

/// One (instruction, stage, cycle) cell of a pipeline diagram.
@immutable
class RiscvStageOccupancy {
  const RiscvStageOccupancy({
    required this.instructionId,
    required this.cycleIndex,
    required this.stageIndex,
    this.pc,
    this.tag,
  });

  /// Tracker-assigned identity. Stable across the stages one instruction
  /// passes through; meaningless across trackers.
  final int instructionId;

  final int cycleIndex;
  final int stageIndex;

  /// PC attributed to the cell, when known.
  final int? pc;

  /// Tag attributed to the cell, when known.
  final int? tag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiscvStageOccupancy &&
          instructionId == other.instructionId &&
          cycleIndex == other.cycleIndex &&
          stageIndex == other.stageIndex &&
          pc == other.pc &&
          tag == other.tag;

  @override
  int get hashCode =>
      Object.hash(instructionId, cycleIndex, stageIndex, pc, tag);

  @override
  String toString() =>
      'RiscvStageOccupancy(i$instructionId @ c$cycleIndex s$stageIndex)';
}

/// A tracked pipeline plus the tracker's own verdict on it.
@immutable
class RiscvIdentityTrackResult {
  const RiscvIdentityTrackResult({
    required this.source,
    required this.occupancy,
    required this.confidence,
    required this.warnings,
  });

  /// Which identity source produced this.
  final RiscvIdentitySource source;

  /// The occupancy grid, cycle-major then stage-major.
  final List<RiscvStageOccupancy> occupancy;

  /// The tracker's confidence in the grid.
  final RiscvIdentityConfidence confidence;

  /// Every reason confidence was lowered, in cycle order.
  final List<RiscvIdentityWarning> warnings;

  /// Whether a consumer may draw this grid without a caveat.
  ///
  /// A pipeline diagram that silently mis-attributes is worse than no
  /// diagram at all, so this is a hard gate rather than a hint.
  bool get isTrustworthy => confidence == RiscvIdentityConfidence.high;

  @override
  String toString() =>
      'RiscvIdentityTrackResult($source, $confidence, '
      '${occupancy.length} cells, ${warnings.length} warnings)';
}

/// Reconstructs instruction identity across pipeline stages.
// An extension point: the `tag` implementation is Pro and arrives through
// [RiscvIdentityTrackerRegistry], so this stays a one-member interface.
// ignore: one_member_abstracts
abstract class RiscvInstructionIdentityTracker {
  const RiscvInstructionIdentityTracker();

  /// Tracks [observation] into an occupancy grid plus a confidence verdict.
  RiscvIdentityTrackResult track(RiscvPipelineObservation observation);
}

/// Resolves an [RiscvIdentitySource] to a tracker.
///
/// Open core registers [RiscvIdentitySource.pc] and
/// [RiscvIdentitySource.positional]. [RiscvIdentitySource.tag] is
/// deliberately absent: tag-based tracking is the Pro capability, and the
/// honest open-core answer to "can you track this superscalar core?" is "no",
/// not a plausible-looking lie. The Pro overlay calls [register] at startup
/// to install it.
abstract final class RiscvIdentityTrackerRegistry {
  static final Map<
    RiscvIdentitySource,
    RiscvInstructionIdentityTracker Function()
  >
  _builders = {
    RiscvIdentitySource.pc: RiscvPcIdentityTracker.new,
    RiscvIdentitySource.positional: RiscvPositionalIdentityTracker.new,
  };

  /// Registers (or replaces) the tracker for [source].
  static void register(
    RiscvIdentitySource source,
    RiscvInstructionIdentityTracker Function() builder,
  ) {
    _builders[source] = builder;
  }

  /// Removes a registration. Used by tests to restore the open-core set.
  static void unregister(RiscvIdentitySource source) {
    _builders.remove(source);
  }

  /// Whether a tracker is available for [source] in this build.
  static bool supports(RiscvIdentitySource source) =>
      _builders.containsKey(source);

  /// The identity sources this build can actually track.
  static Set<RiscvIdentitySource> get availableSources =>
      _builders.keys.toSet();

  /// Builds a tracker for [source], or null when this build has none.
  static RiscvInstructionIdentityTracker? create(RiscvIdentitySource source) =>
      _builders[source]?.call();
}

/// Stage [s] of [cycle], or an empty sample when the cycle carries fewer
/// stages than the observation declares (a short row is a missing binding,
/// not an occupied stage).
RiscvStageSample _sample(RiscvPipelineCycle? cycle, int s) {
  if (cycle == null || s < 0 || s >= cycle.stages.length) {
    return const RiscvStageSample();
  }
  return cycle.stages[s];
}

/// Matches instructions across stages by the PC observed in each stage.
///
/// Exact whenever every in-flight PC is distinct. The failure mode it must
/// report rather than hide is a tight loop, where the same PC is genuinely in
/// two stages at once and PC alone cannot say which cell belongs to which
/// iteration.
class RiscvPcIdentityTracker extends RiscvInstructionIdentityTracker {
  const RiscvPcIdentityTracker();

  @override
  RiscvIdentityTrackResult track(RiscvPipelineObservation observation) {
    final occupancy = <RiscvStageOccupancy>[];
    final warnings = <RiscvIdentityWarning>[];
    // PC → identity, for instructions currently in flight.
    final inFlight = <int, int>{};
    var nextId = 0;
    var degraded = false;

    for (var c = 0; c < observation.cycles.length; c++) {
      final cycle = observation.cycles[c];
      final seenThisCycle = <int, int>{};
      final stillInFlight = <int>{};

      for (var s = 0; s < observation.stageCount; s++) {
        if (s >= cycle.stages.length) continue;
        final sample = cycle.stages[s];
        if (sample.stall && sample.flush) {
          warnings.add(
            RiscvIdentityWarning(
              kind: RiscvIdentityWarningKind.contradictoryControl,
              cycleIndex: c,
              stageIndex: s,
              detail: 'stage asserted stall and flush in the same cycle',
            ),
          );
          degraded = true;
        }
        if (!sample.valid || sample.flush) continue;
        final pc = sample.pc;
        if (pc == null) continue;

        if (seenThisCycle.containsKey(pc)) {
          // The same PC in two stages in one cycle: a loop body short enough
          // to be in flight twice. PC matching cannot separate the two.
          warnings.add(
            RiscvIdentityWarning(
              kind: RiscvIdentityWarningKind.ambiguousPc,
              cycleIndex: c,
              stageIndex: s,
              detail:
                  'pc 0x${pc.toRadixString(16)} is valid in more than one '
                  'stage this cycle',
            ),
          );
          degraded = true;
          final id = nextId++;
          occupancy.add(
            RiscvStageOccupancy(
              instructionId: id,
              cycleIndex: c,
              stageIndex: s,
              pc: pc,
              tag: sample.tag,
            ),
          );
          continue;
        }

        final id = inFlight[pc] ?? nextId++;
        inFlight[pc] = id;
        seenThisCycle[pc] = id;
        stillInFlight.add(pc);
        occupancy.add(
          RiscvStageOccupancy(
            instructionId: id,
            cycleIndex: c,
            stageIndex: s,
            pc: pc,
            tag: sample.tag,
          ),
        );
      }

      inFlight.removeWhere((pc, _) => !stillInFlight.contains(pc));
    }

    return RiscvIdentityTrackResult(
      source: RiscvIdentitySource.pc,
      occupancy: List.unmodifiable(occupancy),
      confidence: degraded
          ? RiscvIdentityConfidence.degraded
          : RiscvIdentityConfidence.high,
      warnings: List.unmodifiable(warnings),
    );
  }
}

/// Models the pipeline as a shift register driven by per-stage
/// valid / stall / flush.
///
/// Stall is read **from the previous cycle**, because that is what the signal
/// means: a stage asserting stall in cycle *c* is saying it will not release
/// its occupant at the end of *c*, so the effect lands in *c+1*. Flush and
/// valid are read from the current cycle, where they are concurrent with the
/// emptiness they describe. Per cycle, then: a flushed stage is emptied; a
/// stage that stalled last cycle keeps its occupant; a stage whose
/// predecessor stalled last cycle takes a bubble; otherwise a stage takes the
/// occupant of the stage in front of it. Stage 0 admits a new instruction
/// when it is valid and did not stall last cycle.
///
/// **The model is only correct for a single-issue in-order pipe**, so the
/// tracker checks itself every cycle: it compares its predicted occupancy
/// against the observed `valid` bit of every stage and records an
/// [RiscvIdentityWarningKind.occupancyMismatch] on every disagreement. A run
/// with any mismatch is reported as [RiscvIdentityConfidence.low] and must
/// not be drawn as fact. Silent mis-attribution is a defect, not a
/// limitation.
class RiscvPositionalIdentityTracker extends RiscvInstructionIdentityTracker {
  const RiscvPositionalIdentityTracker();

  @override
  RiscvIdentityTrackResult track(RiscvPipelineObservation observation) {
    final stageCount = observation.stageCount;
    final occupancy = <RiscvStageOccupancy>[];
    final warnings = <RiscvIdentityWarning>[];
    var occupants = List<int?>.filled(stageCount, null);
    var pcs = List<int?>.filled(stageCount, null);
    var nextId = 0;
    var mismatches = 0;
    var degraded = false;

    for (var c = 0; c < observation.cycles.length; c++) {
      final cycle = observation.cycles[c];
      final previous = c > 0 ? observation.cycles[c - 1] : null;
      final next = List<int?>.filled(stageCount, null);
      final nextPcs = List<int?>.filled(stageCount, null);

      for (var s = stageCount - 1; s >= 0; s--) {
        final sample = _sample(cycle, s);

        if (sample.stall && sample.flush) {
          warnings.add(
            RiscvIdentityWarning(
              kind: RiscvIdentityWarningKind.contradictoryControl,
              cycleIndex: c,
              stageIndex: s,
              detail: 'stage asserted stall and flush in the same cycle',
            ),
          );
          degraded = true;
        }

        if (sample.flush) {
          // Killed: the stage empties and nothing advances into it.
          continue;
        }
        if (_sample(previous, s).stall) {
          // Held over from last cycle — the stage did not release.
          next[s] = occupants[s];
          nextPcs[s] = pcs[s] ?? sample.pc;
          continue;
        }
        if (s == 0) {
          if (sample.valid) {
            next[0] = nextId++;
            nextPcs[0] = sample.pc;
          }
          continue;
        }
        // Advance from the stage in front, unless it was holding last cycle
        // — in which case this stage takes a bubble.
        if (_sample(previous, s - 1).stall) continue;
        next[s] = occupants[s - 1];
        nextPcs[s] = pcs[s - 1] ?? sample.pc;
      }

      // Self-check: the model's occupancy must agree with the trace's own
      // `valid` bits. Where it does not, the model is wrong about this core.
      for (var s = 0; s < stageCount; s++) {
        final sample = _sample(cycle, s);
        final modelled = next[s] != null;
        final observed = sample.valid && !sample.flush;
        if (modelled != observed) {
          mismatches++;
          warnings.add(
            RiscvIdentityWarning(
              kind: RiscvIdentityWarningKind.occupancyMismatch,
              cycleIndex: c,
              stageIndex: s,
              detail: modelled
                  ? 'model holds an instruction here, the trace does not'
                  : 'the trace holds an instruction here, the model does not',
            ),
          );
          // Trust the trace over the model: adopt the observation so the
          // grid stays readable, and let the confidence verdict carry the
          // fact that it is not reliable.
          if (observed) {
            next[s] = nextId++;
            nextPcs[s] = sample.pc;
          } else {
            next[s] = null;
            nextPcs[s] = null;
          }
        }
      }

      for (var s = 0; s < stageCount; s++) {
        final id = next[s];
        if (id == null) continue;
        occupancy.add(
          RiscvStageOccupancy(
            instructionId: id,
            cycleIndex: c,
            stageIndex: s,
            pc: nextPcs[s],
            tag: _sample(cycle, s).tag,
          ),
        );
      }

      occupants = next;
      pcs = nextPcs;
    }

    final RiscvIdentityConfidence confidence;
    if (mismatches > 0) {
      confidence = RiscvIdentityConfidence.low;
    } else if (degraded) {
      confidence = RiscvIdentityConfidence.degraded;
    } else {
      confidence = RiscvIdentityConfidence.high;
    }

    return RiscvIdentityTrackResult(
      source: RiscvIdentitySource.positional,
      occupancy: List.unmodifiable(occupancy),
      confidence: confidence,
      warnings: List.unmodifiable(warnings),
    );
  }
}
