// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:wavecrux/features/stage/widgets/pipeline/pipeline_stage_widget.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/riscv/riscv_instruction_identity.dart';

/// One drawn cell: an instruction sitting in a stage for a cycle.
@immutable
class PipelineCell {
  const PipelineCell({
    required this.cycleIndex,
    required this.stageIndex,
    required this.mismatch,
  });

  final int cycleIndex;
  final int stageIndex;

  /// The tracker's model disagreed with the trace at this (cycle, stage).
  ///
  /// The cell is still drawn — the tracker adopts the observation so the grid
  /// stays readable — but it is drawn *marked*, because at this cell the
  /// diagram is the trace's word against the model's and the model lost.
  final bool mismatch;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineCell &&
          cycleIndex == other.cycleIndex &&
          stageIndex == other.stageIndex &&
          mismatch == other.mismatch;

  @override
  int get hashCode => Object.hash(cycleIndex, stageIndex, mismatch);

  @override
  String toString() => 'PipelineCell(c$cycleIndex s$stageIndex)';
}

/// One row of the diagram: an instruction and the cells it occupies.
@immutable
class PipelineRow {
  const PipelineRow({
    required this.instructionId,
    required this.cells,
    this.pc,
    this.instructionWord,
    this.disassembly,
  });

  /// Tracker-assigned identity. Stable down the row; meaningless across
  /// trackers, which is why nothing outside this build is keyed on it.
  final int instructionId;

  /// Cells in the visible window, keyed by cycle index.
  final Map<int, PipelineCell> cells;

  /// PC attributed to the instruction, when a stage `pc` pin is bound.
  final int? pc;

  /// Instruction word sampled from the `instruction` pin as the instruction
  /// entered the front stage, when that pin is bound.
  final int? instructionWord;

  /// Disassembly of [instructionWord]. Null when the word is unknown or no
  /// bundled instruction set matches it.
  final String? disassembly;

  /// Earliest cycle this row occupies inside the window.
  int get firstCycle =>
      cells.keys.fold<int>(1 << 30, (acc, c) => c < acc ? c : acc);

  /// Stage the row sits in at [firstCycle] — how deep in the pipe it already
  /// was when the window opened.
  int get firstStage => cells[firstCycle]?.stageIndex ?? 0;

  /// Whether any cell in this row is a tracking mismatch.
  bool get hasMismatch => cells.values.any((c) => c.mismatch);
}

/// Everything the Pipeline Diagram renders, assembled once per build.
@immutable
class PipelineViewData {
  const PipelineViewData({
    required this.stageCount,
    required this.stageNames,
    required this.source,
    required this.confidence,
    required this.warnings,
    required this.rows,
    required this.cycleTicks,
    required this.windowStart,
    required this.windowLength,
    required this.anchorCycle,
  });

  /// Configured stage count, 2–8.
  final int stageCount;

  /// User-configured stage names, front of the pipe first.
  final List<String> stageNames;

  /// Which identity source drew this.
  final RiscvIdentitySource source;

  /// The tracker's verdict on its own output.
  final RiscvIdentityConfidence confidence;

  /// Every reason the tracker lowered its confidence, over the whole trace.
  final List<RiscvIdentityWarning> warnings;

  /// Rows visible in the window, in program order.
  final List<PipelineRow> rows;

  /// Tick of every observed cycle. `cycleTicks[i]` is cycle `i`.
  final List<int> cycleTicks;

  /// First cycle index of the visible window.
  final int windowStart;

  /// How many cycles the window spans.
  final int windowLength;

  /// Cycle the cursor is currently in. Inside the window by construction.
  final int anchorCycle;

  /// Total observed cycles in the trace.
  int get totalCycles => cycleTicks.length;

  /// One past the last visible cycle.
  int get windowEnd => windowStart + windowLength;

  /// Simulation tick for cycle [index], or null when out of range.
  int? tickForCycle(int index) =>
      index >= 0 && index < cycleTicks.length ? cycleTicks[index] : null;

  /// Whether the grid may be read as fact.
  ///
  /// The hard requirement of this widget:
  /// when this is false the renderer must **say so**, because a pipeline
  /// diagram that silently mis-attributes is worse than no diagram.
  bool get isTrustworthy => confidence == RiscvIdentityConfidence.high;

  /// Occupancy mismatches — the failure that defines positional tracking.
  int get mismatchCount => warnings
      .where((w) => w.kind == RiscvIdentityWarningKind.occupancyMismatch)
      .length;

  /// Warnings that are not occupancy mismatches (ambiguous PC, contradictory
  /// control), which lower confidence to `degraded` rather than `low`.
  int get otherWarningCount => warnings.length - mismatchCount;
}

/// Assembles [PipelineViewData] from a tracker result.
///
/// [instructionWordAtCycle] is consulted only for the cycle an instruction
/// first appears in the **front** stage, which is the only cycle at which the
/// widget's single `instruction` pin is carrying that instruction's word.
/// Rows that entered the pipe before the trace started therefore carry no
/// disassembly, and are labelled by PC — which is the honest answer, not a
/// guess.
PipelineViewData buildPipelineViewData({
  required RiscvIdentityTrackResult result,
  required List<int> cycleTicks,
  required int stageCount,
  required List<String> stageNames,
  required int windowCycles,
  required int anchorCycle,
  InstructionDisassembler? disassembler,
  int? Function(int cycleIndex)? instructionWordAtCycle,
}) {
  final totalCycles = cycleTicks.length;
  final window = math.max(1, math.min(windowCycles, math.max(1, totalCycles)));
  final maxStart = math.max(0, totalCycles - window);
  final anchor = totalCycles == 0 ? 0 : anchorCycle.clamp(0, totalCycles - 1);
  final start = (anchor - window ~/ 2).clamp(0, maxStart);
  final end = start + window;

  // Occupancy mismatches, keyed so a cell lookup is O(1).
  final mismatches = <int>{
    for (final w in result.warnings)
      if (w.kind == RiscvIdentityWarningKind.occupancyMismatch &&
          w.stageIndex >= 0)
        _cellKey(w.cycleIndex, w.stageIndex),
  };

  // Front-stage entry cycle per instruction, over the whole trace rather than
  // the window — an instruction visible mid-window may have entered before it.
  final entryCycle = <int, int>{};
  final pcById = <int, int>{};
  for (final cell in result.occupancy) {
    final pc = cell.pc;
    if (pc != null) pcById.putIfAbsent(cell.instructionId, () => pc);
    if (cell.stageIndex != 0) continue;
    final known = entryCycle[cell.instructionId];
    if (known == null || cell.cycleIndex < known) {
      entryCycle[cell.instructionId] = cell.cycleIndex;
    }
  }

  final byId = <int, Map<int, PipelineCell>>{};
  for (final cell in result.occupancy) {
    if (cell.cycleIndex < start || cell.cycleIndex >= end) continue;
    if (cell.stageIndex < 0 || cell.stageIndex >= stageCount) continue;
    (byId[cell.instructionId] ??=
        <int, PipelineCell>{})[cell.cycleIndex] = PipelineCell(
      cycleIndex: cell.cycleIndex,
      stageIndex: cell.stageIndex,
      mismatch: mismatches.contains(
        _cellKey(cell.cycleIndex, cell.stageIndex),
      ),
    );
  }

  final rows = <PipelineRow>[];
  for (final entry in byId.entries) {
    final entered = entryCycle[entry.key];
    final word = entered == null ? null : instructionWordAtCycle?.call(entered);
    rows.add(
      PipelineRow(
        instructionId: entry.key,
        cells: Map.unmodifiable(entry.value),
        pc: pcById[entry.key],
        instructionWord: word,
        disassembly: word == null
            ? null
            : disassembler?.decode(word, kPipelineInstructionBitWidth)?.text,
      ),
    );
  }

  // Program order: whoever appears earliest in the window first, and among
  // rows that appear in the same cycle the one deepest in the pipe is the
  // older instruction.
  rows.sort((a, b) {
    final byCycle = a.firstCycle.compareTo(b.firstCycle);
    if (byCycle != 0) return byCycle;
    final byStage = b.firstStage.compareTo(a.firstStage);
    if (byStage != 0) return byStage;
    return a.instructionId.compareTo(b.instructionId);
  });

  return PipelineViewData(
    stageCount: stageCount,
    stageNames: List.unmodifiable(stageNames),
    source: result.source,
    confidence: result.confidence,
    warnings: List.unmodifiable(result.warnings),
    rows: List.unmodifiable(rows),
    cycleTicks: List.unmodifiable(cycleTicks),
    windowStart: start,
    windowLength: math.min(window, math.max(0, totalCycles - start)),
    anchorCycle: anchor,
  );
}

/// Width the instruction pin is disassembled at.
///
/// 32 matches the expanded instruction form every bundled set is written
/// against; `kRiscvInstructionBitWidth` says the same thing for the RVFI
/// substrate, and this widget deliberately does not import that ISA-specific
/// constant.
const int kPipelineInstructionBitWidth = 32;

int _cellKey(int cycle, int stage) => cycle * kPipelineMaxStages + stage;
