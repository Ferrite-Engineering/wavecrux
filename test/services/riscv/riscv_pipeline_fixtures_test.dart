// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/riscv/riscv_instruction_identity.dart';
import 'package:wavecrux/services/riscv/riscv_pipeline_observation_service.dart';

import '../../helpers/generated_vcd_fixture.dart';

/// **The pairing that gives this fixture family its value.**
///
/// `riscv_pipeline_5stage` and `riscv_pipeline_defeat` carry the *same*
/// occupancy — the same seven-instruction program, the same load-use stall,
/// the same back-to-back forward, the same two wrong-path instructions killed
/// in cycle 7. They differ only in how the kill is expressed: one drives the
/// `stageN_flush` pins, the other drops `valid` and leaves the flush pins low.
///
/// Positional tracking models the first exactly and **cannot** model the
/// second — and the widget's hard requirement is
/// that it says so. A tracker that returned `high` for both would produce an
/// identical, entirely plausible picture and be silently wrong half the time,
/// which is worse than drawing nothing. So the assertion here is not just
/// "the grid is right"; it is "the grid is right **and** the confidence
/// verdict distinguishes the two traces".
///
/// The expectations are read from the committed `.expected_pipeline.json`,
/// which the generator writes from a hand-drawn ASCII pipeline diagram and
/// refuses to emit unless that diagram agrees with the occupancy table the
/// VCD was rendered from. Nothing here is captured from the tracker.
void main() {
  const testDir = 'test/fixtures/protocol/riscv/generated';
  const verificationDir = 'verification/fixtures/protocol/riscv/generated';
  const scenarios = ['riscv_pipeline_5stage', 'riscv_pipeline_defeat'];

  for (final scenario in scenarios) {
    group(scenario, () {
      late GeneratedVcdFixture fixture;
      late Map<String, dynamic> expected;
      late int stageCount;

      setUp(() {
        fixture = GeneratedVcdFixture.load('$testDir/$scenario.vcd');
        expected =
            jsonDecode(
                  File(
                    '$testDir/$scenario.expected_pipeline.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        stageCount = expected['stageCount'] as int;
      });

      RiscvPipelineObservationResult observe() {
        String ref(String name) => fixture.variables.values
            .firstWhere((v) => v.name == name)
            .signalRef;
        return const RiscvPipelineObservationService().build(
          source: fixture.source,
          clockRef: ref('clk'),
          stages: <RiscvPipelineStageBinding>[
            for (var s = 1; s <= stageCount; s++)
              RiscvPipelineStageBinding(
                validRef: ref('stage${s}_valid'),
                pcRef: ref('stage${s}_pc'),
                stallRef: ref('stage${s}_stall'),
                flushRef: ref('stage${s}_flush'),
              ),
          ],
          startTime: fixture.source.startTime,
          endTime: fixture.source.endTime,
        );
      }

      test('the clock yields exactly the declared cycles, on the declared '
          'ticks', () {
        final observed = observe();
        expect(observed.cycleCount, expected['cycleCount']);
        final first = expected['firstEdgeTick'] as int;
        final stride = expected['cycleTickStride'] as int;
        for (var c = 0; c < observed.cycleCount; c++) {
          expect(
            observed.cycleTicks[c],
            first + c * stride,
            reason: 'cycle $c should open at the c-th clock rising edge',
          );
        }
      });

      for (final source in const [
        RiscvIdentitySource.positional,
        RiscvIdentitySource.pc,
      ]) {
        group(source.name, () {
          test('draws exactly the hand-authored cell grid', () {
            final result = RiscvIdentityTrackerRegistry.create(
              source,
            )!.track(observe().observation);

            // Cells are compared by (cycle, stage, pc) rather than by
            // instruction id: ids are tracker-local and meaningless across
            // trackers, while the PC is the thing a reader of the diagram is
            // actually being told.
            final drawn = <String>{
              for (final cell in result.occupancy)
                '${cell.cycleIndex}/${cell.stageIndex}/${cell.pc}',
            };
            final wanted = <String>{
              for (final cell
                  in (expected['cells'] as List).cast<Map<String, dynamic>>())
                '${cell['cycle']}/${cell['stage']}/${cell['pc']}',
            };
            expect(drawn, wanted);
          });

          test('one instruction keeps one identity across its whole path', () {
            final result = RiscvIdentityTrackerRegistry.create(
              source,
            )!.track(observe().observation);
            final pcById = <int, Set<int?>>{};
            for (final cell in result.occupancy) {
              (pcById[cell.instructionId] ??= <int?>{}).add(cell.pc);
            }
            for (final entry in pcById.entries) {
              expect(
                entry.value,
                hasLength(1),
                reason:
                    'instruction id ${entry.key} was attributed more than one '
                    'PC (${entry.value}) — a row of the diagram would be two '
                    'different instructions',
              );
            }
          });

          test('reports the confidence the fixture was authored to '
              'provoke', () {
            final result = RiscvIdentityTrackerRegistry.create(
              source,
            )!.track(observe().observation);
            final wanted =
                (expected['trackers'] as Map<String, dynamic>)[source.name]
                    as Map<String, dynamic>;
            expect(result.confidence.name, wanted['confidence']);
            expect(
              result.isTrustworthy,
              wanted['confidence'] == 'high',
              reason:
                  'isTrustworthy is what the renderer gates the "do not read '
                  'this as fact" banner on',
            );
          });

          test('warns about exactly the cells the fixture was authored to '
              'break', () {
            final result = RiscvIdentityTrackerRegistry.create(
              source,
            )!.track(observe().observation);
            final wanted =
                ((expected['trackers'] as Map<String, dynamic>)[source.name]
                        as Map<String, dynamic>)['warnings']
                    as List;
            expect(
              result.warnings
                  .map((w) => '${w.kind.name}@${w.cycleIndex}/${w.stageIndex}')
                  .toList(),
              [
                for (final w in wanted.cast<Map<String, dynamic>>())
                  '${w['kind']}@${w['cycle']}/${w['stage']}',
              ],
            );
          });
        });
      }

      test('the test/ and verification/ copies are byte-identical', () {
        for (final suffix in const ['.vcd', '.expected_pipeline.json']) {
          expect(
            File('$verificationDir/$scenario$suffix').readAsBytesSync(),
            File('$testDir/$scenario$suffix').readAsBytesSync(),
            reason:
                'the generator writes both trees; a drifted copy means one of '
                'them was hand-edited',
          );
        }
      });
    });
  }

  test('the two fixtures differ only in how the kill is signalled', () {
    final cleanFixture = GeneratedVcdFixture.load(
      '$testDir/riscv_pipeline_5stage.vcd',
    );
    final defeatFixture = GeneratedVcdFixture.load(
      '$testDir/riscv_pipeline_defeat.vcd',
    );

    List<String> trace(GeneratedVcdFixture f, String name) {
      final ref = f.variables.values
          .firstWhere((v) => v.name == name)
          .signalRef;
      return [
        for (final c in f.source.changesInRange(ref, 0, 1 << 20))
          '${c.time}=${c.value}',
      ];
    }

    // Everything but the flush pins is identical, which is what makes the
    // pair a controlled experiment rather than two unrelated traces.
    for (final name in const [
      'clk',
      'instruction',
      'stage1_pc',
      'stage1_stall',
      'stage2_stall',
      'stage4_valid',
      'stage5_valid',
    ]) {
      expect(
        trace(cleanFixture, name),
        trace(defeatFixture, name),
        reason: '$name should be identical between the two variants',
      );
    }

    for (final name in const ['stage2_flush', 'stage3_flush']) {
      expect(
        trace(cleanFixture, name).where((c) => c.endsWith('1')),
        isNotEmpty,
        reason: 'the clean fixture must actually assert $name',
      );
      expect(
        trace(defeatFixture, name).where((c) => c.endsWith('1')),
        isEmpty,
        reason:
            'the defeat fixture must express the kill without $name, which is '
            'what makes positional tracking fail honestly',
      );
    }
  });
}
