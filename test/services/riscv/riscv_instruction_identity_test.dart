// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/riscv/riscv_instruction_identity.dart';

/// Builds a 5-stage cycle from a compact per-stage spec.
///
/// Each entry is `(pc, stall, flush)`; a null pc means the stage is empty.
RiscvPipelineCycle _cycle(List<(int?, bool, bool)> stages) =>
    RiscvPipelineCycle(
      stages: [
        for (final (pc, stall, flush) in stages)
          RiscvStageSample(
            valid: pc != null,
            pc: pc,
            stall: stall,
            flush: flush,
          ),
      ],
    );

/// An ideal single-issue in-order fill: one instruction enters per cycle and
/// walks straight down the pipe, no stalls, no flushes.
RiscvPipelineObservation _cleanFill({
  required int instructions,
  int stages = 5,
}) {
  final cycles = <RiscvPipelineCycle>[];
  for (var c = 0; c < instructions + stages - 1; c++) {
    cycles.add(
      _cycle([
        for (var s = 0; s < stages; s++)
          () {
            final index = c - s;
            final occupied = index >= 0 && index < instructions;
            return (occupied ? 0x1000 + index * 4 : null, false, false);
          }(),
      ]),
    );
  }
  return RiscvPipelineObservation(stageCount: stages, cycles: cycles);
}

void main() {
  group('RiscvIdentityTrackerRegistry', () {
    test('open core tracks pc and positional', () {
      expect(
        RiscvIdentityTrackerRegistry.supports(RiscvIdentitySource.pc),
        isTrue,
      );
      expect(
        RiscvIdentityTrackerRegistry.supports(RiscvIdentitySource.positional),
        isTrue,
      );
      expect(
        RiscvIdentityTrackerRegistry.create(RiscvIdentitySource.pc),
        isA<RiscvPcIdentityTracker>(),
      );
      expect(
        RiscvIdentityTrackerRegistry.create(RiscvIdentitySource.positional),
        isA<RiscvPositionalIdentityTracker>(),
      );
    });

    test('tag tracking is absent in open core rather than faked', () {
      expect(
        RiscvIdentityTrackerRegistry.supports(RiscvIdentitySource.tag),
        isFalse,
        reason:
            'tag-based identity is the Pro capability; open core must say '
            'no rather than draw a plausible lie',
      );
      expect(
        RiscvIdentityTrackerRegistry.create(RiscvIdentitySource.tag),
        isNull,
      );
      expect(
        RiscvIdentityTrackerRegistry.availableSources,
        {RiscvIdentitySource.pc, RiscvIdentitySource.positional},
      );
    });

    test('the Pro overlay can register a tag tracker through the seam', () {
      addTearDown(
        () => RiscvIdentityTrackerRegistry.unregister(RiscvIdentitySource.tag),
      );
      RiscvIdentityTrackerRegistry.register(
        RiscvIdentitySource.tag,
        _FakeTagTracker.new,
      );
      expect(
        RiscvIdentityTrackerRegistry.supports(RiscvIdentitySource.tag),
        isTrue,
      );
      expect(
        RiscvIdentityTrackerRegistry.create(RiscvIdentitySource.tag),
        isA<_FakeTagTracker>(),
      );
    });
  });

  group('RiscvPcIdentityTracker', () {
    test('follows one instruction down the pipe under a single identity', () {
      final result = const RiscvPcIdentityTracker().track(
        _cleanFill(instructions: 3),
      );
      expect(result.source, RiscvIdentitySource.pc);
      expect(result.confidence, RiscvIdentityConfidence.high);
      expect(result.isTrustworthy, isTrue);
      expect(result.warnings, isEmpty);

      final first = [
        for (final o in result.occupancy)
          if (o.pc == 0x1000) o,
      ];
      expect(first, hasLength(5), reason: 'one cell per stage');
      expect(first.map((o) => o.instructionId).toSet(), hasLength(1));
      expect(first.map((o) => o.stageIndex), [0, 1, 2, 3, 4]);
    });

    test('gives distinct instructions distinct identities', () {
      final result = const RiscvPcIdentityTracker().track(
        _cleanFill(instructions: 4),
      );
      final ids = <int, Set<int>>{};
      for (final o in result.occupancy) {
        ids.putIfAbsent(o.pc!, () => <int>{}).add(o.instructionId);
      }
      expect(ids, hasLength(4));
      for (final set in ids.values) {
        expect(set, hasLength(1));
      }
    });

    test('reports ambiguity when one pc is valid in two stages at once', () {
      // A two-instruction loop body: 0x1000 is in flight twice.
      final observation = RiscvPipelineObservation(
        stageCount: 3,
        cycles: [
          _cycle([
            (0x1000, false, false),
            (null, false, false),
            (null, false, false),
          ]),
          _cycle([
            (0x1004, false, false),
            (0x1000, false, false),
            (null, false, false),
          ]),
          _cycle([
            (0x1000, false, false),
            (0x1004, false, false),
            (0x1000, false, false),
          ]),
        ],
      );
      final result = const RiscvPcIdentityTracker().track(observation);
      expect(result.confidence, RiscvIdentityConfidence.degraded);
      expect(result.isTrustworthy, isFalse);
      expect(
        result.warnings.map((w) => w.kind),
        contains(RiscvIdentityWarningKind.ambiguousPc),
      );
      expect(result.warnings.first.cycleIndex, 2);
    });

    test('reports a stage asserting stall and flush together', () {
      final observation = RiscvPipelineObservation(
        stageCount: 2,
        cycles: [
          _cycle([(0x1000, false, false), (null, true, true)]),
        ],
      );
      final result = const RiscvPcIdentityTracker().track(observation);
      expect(
        result.warnings.single.kind,
        RiscvIdentityWarningKind.contradictoryControl,
      );
      expect(result.confidence, RiscvIdentityConfidence.degraded);
    });
  });

  group('RiscvPositionalIdentityTracker', () {
    test('tracks an ideal single-issue in-order pipe with high confidence', () {
      final result = const RiscvPositionalIdentityTracker().track(
        _cleanFill(instructions: 4),
      );
      expect(result.source, RiscvIdentitySource.positional);
      expect(result.confidence, RiscvIdentityConfidence.high);
      expect(result.isTrustworthy, isTrue);
      expect(result.warnings, isEmpty);

      // Four instructions, each occupying five stages.
      final byId = <int, List<RiscvStageOccupancy>>{};
      for (final o in result.occupancy) {
        byId.putIfAbsent(o.instructionId, () => []).add(o);
      }
      expect(byId, hasLength(4));
      for (final cells in byId.values) {
        expect(cells.map((c) => c.stageIndex), [0, 1, 2, 3, 4]);
      }
    });

    test('models a load-use stall without losing the instruction', () {
      // 3 stages. Cycle 1 stalls stage 1, so stage 0 holds too and stage 2
      // takes a bubble.
      final observation = RiscvPipelineObservation(
        stageCount: 3,
        cycles: [
          _cycle([
            (0x100, false, false),
            (null, false, false),
            (null, false, false),
          ]),
          _cycle([
            (0x104, true, false),
            (0x100, true, false),
            (null, false, false),
          ]),
          _cycle([
            (0x104, false, false),
            (0x100, false, false),
            (null, false, false),
          ]),
          _cycle([
            (0x108, false, false),
            (0x104, false, false),
            (0x100, false, false),
          ]),
        ],
      );
      final result = const RiscvPositionalIdentityTracker().track(observation);
      expect(result.confidence, RiscvIdentityConfidence.high);
      final firstId = result.occupancy.first.instructionId;
      final firstCells = [
        for (final o in result.occupancy)
          if (o.instructionId == firstId) o,
      ];
      expect(
        firstCells.map((c) => (c.cycleIndex, c.stageIndex)),
        [(0, 0), (1, 1), (2, 1), (3, 2)],
        reason: 'the stalled instruction holds stage 1 for two cycles',
      );
    });

    test('drops flushed instructions', () {
      final observation = RiscvPipelineObservation(
        stageCount: 3,
        cycles: [
          _cycle([
            (0x100, false, false),
            (null, false, false),
            (null, false, false),
          ]),
          _cycle([
            (0x104, false, false),
            (0x100, false, false),
            (null, false, false),
          ]),
          // Branch resolves: stages 0 and 1 are killed.
          _cycle([
            (null, false, true),
            (null, false, true),
            (0x100, false, false),
          ]),
        ],
      );
      final result = const RiscvPositionalIdentityTracker().track(observation);
      expect(result.confidence, RiscvIdentityConfidence.high);
      final lastCycle = [
        for (final o in result.occupancy)
          if (o.cycleIndex == 2) o,
      ];
      expect(lastCycle, hasLength(1));
      expect(lastCycle.single.stageIndex, 2);
    });

    // ── the hard requirement ───────────────────────────────────────────────

    test(
      'reports low confidence when the trace defeats the shift-register model',
      () {
        // Superscalar: two instructions enter and both stages 0 and 1 are
        // occupied in cycle 0, which a single-issue shift register cannot
        // produce. This must be *reported*, not silently mis-attributed.
        final observation = RiscvPipelineObservation(
          stageCount: 3,
          cycles: [
            _cycle([
              (0x100, false, false),
              (0x104, false, false),
              (null, false, false),
            ]),
            _cycle([
              (0x108, false, false),
              (0x10c, false, false),
              (0x100, false, false),
            ]),
          ],
        );
        final result = const RiscvPositionalIdentityTracker().track(
          observation,
        );
        expect(result.confidence, RiscvIdentityConfidence.low);
        expect(result.isTrustworthy, isFalse);
        expect(
          result.warnings.map((w) => w.kind),
          contains(RiscvIdentityWarningKind.occupancyMismatch),
        );
        expect(result.warnings.first.cycleIndex, 0);
        expect(result.warnings.first.stageIndex, 1);
      },
    );

    test('reports a stage the model expected to be occupied but was not', () {
      // An instruction vanishes from stage 1 with no flush to explain it.
      final observation = RiscvPipelineObservation(
        stageCount: 2,
        cycles: [
          _cycle([(0x100, false, false), (null, false, false)]),
          _cycle([(null, false, false), (null, false, false)]),
        ],
      );
      final result = const RiscvPositionalIdentityTracker().track(observation);
      expect(result.confidence, RiscvIdentityConfidence.low);
      final mismatch = result.warnings.firstWhere(
        (w) => w.kind == RiscvIdentityWarningKind.occupancyMismatch,
      );
      expect(mismatch.cycleIndex, 1);
      expect(mismatch.stageIndex, 1);
      expect(mismatch.detail, contains('model holds an instruction here'));
    });

    test('adopts the observed occupancy so the grid stays readable', () {
      final observation = RiscvPipelineObservation(
        stageCount: 3,
        cycles: [
          _cycle([
            (0x100, false, false),
            (0x104, false, false),
            (null, false, false),
          ]),
        ],
      );
      final result = const RiscvPositionalIdentityTracker().track(observation);
      // Both observed-valid stages are rendered, with distinct identities,
      // but the run is flagged untrustworthy.
      expect(result.occupancy, hasLength(2));
      expect(
        result.occupancy.map((o) => o.instructionId).toSet(),
        hasLength(2),
      );
      expect(result.isTrustworthy, isFalse);
    });

    test('handles an empty observation', () {
      final result = const RiscvPositionalIdentityTracker().track(
        const RiscvPipelineObservation(stageCount: 5, cycles: []),
      );
      expect(result.occupancy, isEmpty);
      expect(result.confidence, RiscvIdentityConfidence.high);
    });
  });

  group('RiscvIdentityWarningKind — the tag vocabulary is Pro-only', () {
    // `ambiguousTag` is declared here so the warning vocabulary stays with
    // the identity model, but no open-core tracker may ever raise it: open
    // core has no tag tracker, and a warning about a signal open core never
    // reads would be a lie about what this build can see. If a future
    // open-core tracker starts emitting it, that is a tier-line question,
    // not a test to update.
    test('neither open-core tracker emits ambiguousTag on any input', () {
      final observations = <RiscvPipelineObservation>[
        _cleanFill(instructions: 4),
        // Tags populated in every stage, including a deliberate duplicate —
        // the exact input that would provoke a tag tracker.
        const RiscvPipelineObservation(
          stageCount: 3,
          cycles: [
            RiscvPipelineCycle(stages: _duplicateTagStages),
            RiscvPipelineCycle(stages: _duplicateTagStages),
            RiscvPipelineCycle(stages: _duplicateTagStages),
            RiscvPipelineCycle(stages: _duplicateTagStages),
          ],
        ),
      ];
      for (final observation in observations) {
        for (final tracker in const <RiscvInstructionIdentityTracker>[
          RiscvPcIdentityTracker(),
          RiscvPositionalIdentityTracker(),
        ]) {
          expect(
            tracker.track(observation).warnings.map((w) => w.kind),
            isNot(contains(RiscvIdentityWarningKind.ambiguousTag)),
            reason: '$tracker must not raise a tag warning',
          );
        }
      }
    });
  });
}

/// Three occupied stages carrying tags, two of which deliberately collide.
///
/// The input a tag tracker would flag as [RiscvIdentityWarningKind
/// .ambiguousTag] — and which the two open-core trackers must ignore,
/// because neither of them reads the tag field at all.
const _duplicateTagStages = <RiscvStageSample>[
  RiscvStageSample(valid: true, pc: 0x100, tag: 7),
  RiscvStageSample(valid: true, pc: 0x104, tag: 7),
  RiscvStageSample(valid: true, pc: 0x108, tag: 8),
];

class _FakeTagTracker extends RiscvInstructionIdentityTracker {
  const _FakeTagTracker();

  @override
  RiscvIdentityTrackResult track(RiscvPipelineObservation observation) =>
      const RiscvIdentityTrackResult(
        source: RiscvIdentitySource.tag,
        occupancy: [],
        confidence: RiscvIdentityConfidence.high,
        warnings: [],
      );
}
