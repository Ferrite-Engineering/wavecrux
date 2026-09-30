// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/widgets/pipeline/pipeline_view_data.dart';
import 'package:wavecrux/services/riscv/riscv_instruction_identity.dart';

/// A five-stage, four-instruction diagonal: instruction `i` is in stage `s`
/// at cycle `i + s`.
RiscvIdentityTrackResult _diagonal({
  int instructions = 4,
  int stages = 5,
  RiscvIdentityConfidence confidence = RiscvIdentityConfidence.high,
  List<RiscvIdentityWarning> warnings = const [],
}) => RiscvIdentityTrackResult(
  source: RiscvIdentitySource.positional,
  occupancy: [
    for (var i = 0; i < instructions; i++)
      for (var s = 0; s < stages; s++)
        RiscvStageOccupancy(
          instructionId: i,
          cycleIndex: i + s,
          stageIndex: s,
          pc: 0x1000 + 4 * i,
        ),
  ],
  confidence: confidence,
  warnings: warnings,
);

List<int> _ticks(int count) => [for (var c = 0; c < count; c++) 5 + 10 * c];

void main() {
  const stageNames = ['IF', 'ID', 'EX', 'MEM', 'WB'];

  group('windowing', () {
    test('the window is anchored on the cursor cycle and centred on it', () {
      final data = buildPipelineViewData(
        result: _diagonal(instructions: 20),
        cycleTicks: _ticks(40),
        stageCount: 5,
        stageNames: stageNames,
        windowCycles: 10,
        anchorCycle: 20,
      );
      expect(data.windowStart, 15);
      expect(data.windowEnd, 25);
      expect(data.anchorCycle, 20);
      expect(data.totalCycles, 40);
    });

    test('the window clamps at both ends rather than running off the '
        'trace', () {
      final atStart = buildPipelineViewData(
        result: _diagonal(instructions: 20),
        cycleTicks: _ticks(40),
        stageCount: 5,
        stageNames: stageNames,
        windowCycles: 10,
        anchorCycle: 0,
      );
      expect(atStart.windowStart, 0);
      expect(atStart.windowEnd, 10);

      final atEnd = buildPipelineViewData(
        result: _diagonal(instructions: 20),
        cycleTicks: _ticks(40),
        stageCount: 5,
        stageNames: stageNames,
        windowCycles: 10,
        anchorCycle: 39,
      );
      expect(atEnd.windowEnd, 40);
      expect(atEnd.windowStart, 30);
    });

    test('a window wider than the trace shows the whole trace', () {
      final data = buildPipelineViewData(
        result: _diagonal(),
        cycleTicks: _ticks(8),
        stageCount: 5,
        stageNames: stageNames,
        windowCycles: 128,
        anchorCycle: 3,
      );
      expect(data.windowStart, 0);
      expect(data.windowLength, 8);
    });

    test('an empty trace does not throw or invent a cycle', () {
      final data = buildPipelineViewData(
        result: _diagonal(instructions: 0),
        cycleTicks: const [],
        stageCount: 5,
        stageNames: stageNames,
        windowCycles: 24,
        anchorCycle: 0,
      );
      expect(data.totalCycles, 0);
      expect(data.rows, isEmpty);
      expect(data.tickForCycle(0), isNull);
    });

    test('cycle indices map back to ticks, because ticks are the shared '
        'coordinate', () {
      final data = buildPipelineViewData(
        result: _diagonal(),
        cycleTicks: _ticks(8),
        stageCount: 5,
        stageNames: stageNames,
        windowCycles: 24,
        anchorCycle: 0,
      );
      expect(data.tickForCycle(0), 5);
      expect(data.tickForCycle(3), 35);
      expect(data.tickForCycle(-1), isNull);
      expect(data.tickForCycle(99), isNull);
    });
  });

  group('rows', () {
    test('only instructions with a cell inside the window get a row', () {
      final data = buildPipelineViewData(
        result: _diagonal(instructions: 6),
        cycleTicks: _ticks(12),
        stageCount: 5,
        stageNames: stageNames,
        windowCycles: 2,
        anchorCycle: 0,
      );
      // Cycles 0-1 hold instruction 0 (IF, ID) and instruction 1 (IF).
      expect(data.rows.map((r) => r.instructionId), [0, 1]);
    });

    test('rows come out in program order — deepest in the pipe first when '
        'they enter the window together', () {
      final data = buildPipelineViewData(
        result: _diagonal(instructions: 6),
        cycleTicks: _ticks(12),
        stageCount: 5,
        stageNames: stageNames,
        windowCycles: 3,
        anchorCycle: 5,
      );
      // Every row visible at the window's first cycle appears at a different
      // depth; the older instruction is the deeper one.
      final first = data.rows.first;
      expect(first.firstStage, greaterThan(data.rows.last.firstStage));
      expect(
        data.rows.map((r) => r.instructionId).toList(),
        orderedEquals(
          List<int>.from(data.rows.map((r) => r.instructionId))..sort(),
        ),
      );
    });

    test('a row carries the PC the tracker attributed to it', () {
      final data = buildPipelineViewData(
        result: _diagonal(),
        cycleTicks: _ticks(12),
        stageCount: 5,
        stageNames: stageNames,
        windowCycles: 24,
        anchorCycle: 0,
      );
      expect(data.rows.first.pc, 0x1000);
      expect(data.rows.last.pc, 0x100c);
    });

    test('cells for stages past the configured count are dropped', () {
      // A session saved at eight stages and reopened at four must not draw
      // rows through stages the user can no longer see or name.
      final data = buildPipelineViewData(
        result: _diagonal(stages: 8),
        cycleTicks: _ticks(16),
        stageCount: 4,
        stageNames: const ['A', 'B', 'C', 'D'],
        windowCycles: 24,
        anchorCycle: 0,
      );
      for (final row in data.rows) {
        for (final cell in row.cells.values) {
          expect(cell.stageIndex, lessThan(4));
        }
      }
    });
  });

  group('instruction words', () {
    test(
      'the word is sampled at the cycle the row entered the front stage',
      () {
        final sampled = <int>[];
        buildPipelineViewData(
          result: _diagonal(),
          cycleTicks: _ticks(12),
          stageCount: 5,
          stageNames: stageNames,
          windowCycles: 24,
          anchorCycle: 0,
          instructionWordAtCycle: (c) {
            sampled.add(c);
            return 0x13;
          },
        );
        // Instruction i is in stage 0 at cycle i.
        expect(sampled..sort(), [0, 1, 2, 3]);
      },
    );

    test('a row that entered before the trace started carries no word, and '
        'no guess', () {
      // Only stage 3 and 4 cells: the row never appears in the front stage,
      // so there is no cycle at which the single instruction pin held its
      // word.
      const result = RiscvIdentityTrackResult(
        source: RiscvIdentitySource.positional,
        occupancy: [
          RiscvStageOccupancy(
            instructionId: 9,
            cycleIndex: 0,
            stageIndex: 3,
            pc: 0x2000,
          ),
          RiscvStageOccupancy(
            instructionId: 9,
            cycleIndex: 1,
            stageIndex: 4,
            pc: 0x2000,
          ),
        ],
        confidence: RiscvIdentityConfidence.high,
        warnings: [],
      );
      final data = buildPipelineViewData(
        result: result,
        cycleTicks: _ticks(4),
        stageCount: 5,
        stageNames: stageNames,
        windowCycles: 24,
        anchorCycle: 0,
        instructionWordAtCycle: (_) => 0x13,
      );
      expect(data.rows.single.instructionWord, isNull);
      expect(data.rows.single.disassembly, isNull);
      expect(data.rows.single.pc, 0x2000);
    });
  });

  group('confidence', () {
    test('only high confidence is trustworthy', () {
      for (final entry in const {
        RiscvIdentityConfidence.high: true,
        RiscvIdentityConfidence.degraded: false,
        RiscvIdentityConfidence.low: false,
      }.entries) {
        final data = buildPipelineViewData(
          result: _diagonal(confidence: entry.key),
          cycleTicks: _ticks(12),
          stageCount: 5,
          stageNames: stageNames,
          windowCycles: 24,
          anchorCycle: 0,
        );
        expect(data.isTrustworthy, entry.value, reason: '${entry.key}');
      }
    });

    test('an occupancy mismatch marks the cell it names, and only that '
        'cell', () {
      // The per-cell half of the honesty requirement: the tracker adopts the
      // trace where it disagrees with its own model, so the cell stays drawn
      // — and it has to be drawn *marked*, or the diagram silently launders a
      // guess into a fact.
      final data = buildPipelineViewData(
        result: _diagonal(
          confidence: RiscvIdentityConfidence.low,
          warnings: const [
            RiscvIdentityWarning(
              kind: RiscvIdentityWarningKind.occupancyMismatch,
              cycleIndex: 2,
              stageIndex: 2,
              detail: 'the trace holds an instruction here, the model does not',
            ),
            RiscvIdentityWarning(
              kind: RiscvIdentityWarningKind.ambiguousPc,
              cycleIndex: 3,
              stageIndex: 1,
              detail: 'repeated pc',
            ),
          ],
        ),
        cycleTicks: _ticks(12),
        stageCount: 5,
        stageNames: stageNames,
        windowCycles: 24,
        anchorCycle: 0,
      );

      expect(data.mismatchCount, 1);
      expect(data.otherWarningCount, 1);

      final marked = <String>[
        for (final row in data.rows)
          for (final cell in row.cells.values)
            if (cell.mismatch) '${cell.cycleIndex}/${cell.stageIndex}',
      ];
      expect(
        marked,
        ['2/2'],
        reason:
            'an ambiguous-PC warning is not an occupancy mismatch and must '
            'not put a mismatch marker on a cell',
      );
      expect(data.rows.where((r) => r.hasMismatch), hasLength(1));
    });

    test('a stage-less warning does not mark a cell', () {
      final data = buildPipelineViewData(
        result: _diagonal(
          confidence: RiscvIdentityConfidence.low,
          warnings: const [
            RiscvIdentityWarning(
              kind: RiscvIdentityWarningKind.occupancyMismatch,
              cycleIndex: 2,
              stageIndex: -1,
              detail: 'not stage-specific',
            ),
          ],
        ),
        cycleTicks: _ticks(12),
        stageCount: 5,
        stageNames: stageNames,
        windowCycles: 24,
        anchorCycle: 0,
      );
      expect(data.rows.any((r) => r.hasMismatch), isFalse);
      expect(data.mismatchCount, 1);
    });
  });

  test('cells compare by value', () {
    const a = PipelineCell(cycleIndex: 1, stageIndex: 2, mismatch: false);
    const b = PipelineCell(cycleIndex: 1, stageIndex: 2, mismatch: false);
    const c = PipelineCell(cycleIndex: 1, stageIndex: 2, mismatch: true);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
}
