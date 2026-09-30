// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/services/riscv/riscv_pipeline_observation_service.dart';

import '../../helpers/fake_waveform_data_source.dart';

/// A three-cycle clock with rising edges at 5, 15 and 25.
FakeWaveformDataSource _source({
  Map<String, List<SignalChange>> extra = const {},
  int endTime = 30,
}) => FakeWaveformDataSource(
  scopes: const [],
  signals: {
    'clk': const [
      SignalChange(time: 0, value: '0'),
      SignalChange(time: 5, value: '1'),
      SignalChange(time: 10, value: '0'),
      SignalChange(time: 15, value: '1'),
      SignalChange(time: 20, value: '0'),
      SignalChange(time: 25, value: '1'),
      SignalChange(time: 30, value: '0'),
    ],
    ...extra,
  },
  endTime: endTime,
);

void main() {
  const service = RiscvPipelineObservationService();

  group('cycleTicks', () {
    test('a cycle is a clock rising edge, and nothing else is', () {
      expect(
        service.cycleTicks(
          source: _source(),
          clockRef: 'clk',
          startTime: 0,
          endTime: 30,
        ),
        [5, 15, 25],
      );
    });

    test('the half-open changesInRange contract does not eat the last '
        'cycle', () {
      // `changesInRange(ref, start, end)` excludes `end`, so an implementation
      // that passed `endTime` straight through would silently drop the cycle
      // that opens exactly on the last tick of the range.
      expect(
        service.cycleTicks(
          source: _source(),
          clockRef: 'clk',
          startTime: 0,
          endTime: 25,
        ),
        [5, 15, 25],
      );
    });

    test('a clock already high at the start of the range opens cycle 0', () {
      final source = FakeWaveformDataSource(
        scopes: const [],
        signals: {
          'clk': const [
            SignalChange(time: 0, value: '1'),
            SignalChange(time: 10, value: '0'),
            SignalChange(time: 20, value: '1'),
          ],
        },
        endTime: 30,
      );
      expect(
        service.cycleTicks(
          source: source,
          clockRef: 'clk',
          startTime: 0,
          endTime: 30,
        ),
        [0, 20],
        reason:
            'a trace that begins mid-cycle still has a first cycle; dropping '
            'it would shift every cycle index against the waveform panel',
      );
    });

    test('maxCycles truncates rather than walking an unbounded trace', () {
      expect(
        service.cycleTicks(
          source: _source(),
          clockRef: 'clk',
          startTime: 0,
          endTime: 30,
          maxCycles: 2,
        ),
        [5, 15],
      );
    });

    test('an inverted range and a non-positive cap yield nothing', () {
      expect(
        service.cycleTicks(
          source: _source(),
          clockRef: 'clk',
          startTime: 30,
          endTime: 0,
        ),
        isEmpty,
      );
      expect(
        service.cycleTicks(
          source: _source(),
          clockRef: 'clk',
          startTime: 0,
          endTime: 30,
          maxCycles: 0,
        ),
        isEmpty,
      );
    });
  });

  group('build', () {
    test('samples each stage at the rising edge', () {
      final source = _source(
        extra: {
          's0_valid': const [
            SignalChange(time: 4, value: '1'),
            SignalChange(time: 14, value: '0'),
          ],
          's0_pc': const [
            SignalChange(time: 4, value: 'b00000000000000000000000000001000'),
          ],
          's0_stall': const [
            SignalChange(time: 14, value: '1'),
            SignalChange(time: 24, value: '0'),
          ],
          's1_flush': const [
            SignalChange(time: 24, value: '1'),
          ],
        },
      );
      final result = service.build(
        source: source,
        clockRef: 'clk',
        stages: const [
          RiscvPipelineStageBinding(
            validRef: 's0_valid',
            pcRef: 's0_pc',
            stallRef: 's0_stall',
          ),
          RiscvPipelineStageBinding(flushRef: 's1_flush'),
        ],
        startTime: 0,
        endTime: 30,
      );

      expect(result.cycleCount, 3);
      expect(result.observation.stageCount, 2);
      expect(result.observation.cycles[0].stages[0].valid, isTrue);
      expect(result.observation.cycles[0].stages[0].pc, 8);
      expect(result.observation.cycles[0].stages[0].stall, isFalse);
      expect(result.observation.cycles[1].stages[0].valid, isFalse);
      expect(result.observation.cycles[1].stages[0].stall, isTrue);
      expect(result.observation.cycles[2].stages[1].flush, isTrue);
    });

    test('an unbound optional pin reads false, not unknown', () {
      final result = service.build(
        source: _source(),
        clockRef: 'clk',
        stages: const [RiscvPipelineStageBinding()],
        startTime: 0,
        endTime: 30,
      );
      final sample = result.observation.cycles.first.stages.first;
      expect(sample.valid, isFalse);
      expect(sample.stall, isFalse);
      expect(sample.flush, isFalse);
      expect(sample.pc, isNull);
      expect(
        sample.tag,
        isNull,
        reason:
            'open core never binds a tag; the field exists so the Pro tracker '
            'can reuse this service rather than fork it',
      );
    });

    test('no clock, no stages, or no rising edge is an empty result — not an '
        'invented cycle count', () {
      final noClock = service.build(
        source: _source(),
        clockRef: null,
        stages: const [RiscvPipelineStageBinding(validRef: 'x')],
        startTime: 0,
        endTime: 30,
      );
      expect(noClock.cycleCount, 0);
      expect(noClock.observation.stageCount, 0);

      final noStages = service.build(
        source: _source(),
        clockRef: 'clk',
        stages: const [],
        startTime: 0,
        endTime: 30,
      );
      expect(noStages.cycleCount, 0);

      final flat = FakeWaveformDataSource(
        scopes: const [],
        signals: {
          'clk': const [SignalChange(time: 0, value: '0')],
        },
        endTime: 30,
      );
      final noEdge = service.build(
        source: flat,
        clockRef: 'clk',
        stages: const [RiscvPipelineStageBinding(validRef: 'clk')],
        startTime: 0,
        endTime: 30,
      );
      expect(noEdge.cycleCount, 0);
    });
  });

  group('cycleAt', () {
    test('maps a tick back to the cycle it falls in', () {
      final result = service.build(
        source: _source(),
        clockRef: 'clk',
        stages: const [RiscvPipelineStageBinding(validRef: 'clk')],
        startTime: 0,
        endTime: 30,
      );
      expect(result.cycleAt(5), 0);
      expect(result.cycleAt(9), 0);
      expect(result.cycleAt(15), 1);
      expect(result.cycleAt(24), 1);
      expect(result.cycleAt(25), 2);
      expect(result.cycleAt(1000), 2);
      expect(
        result.cycleAt(0),
        0,
        reason:
            'a cursor parked before the first edge anchors on cycle 0 rather '
            'than on nothing',
      );
    });

    test('an empty result reports no cycle rather than cycle 0', () {
      expect(RiscvPipelineObservationResult.empty.cycleAt(7), -1);
    });
  });

  test('stage bindings compare by value and list their refs', () {
    const a = RiscvPipelineStageBinding(validRef: 'v', flushRef: 'f');
    const b = RiscvPipelineStageBinding(validRef: 'v', flushRef: 'f');
    const c = RiscvPipelineStageBinding(validRef: 'v');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
    expect(a.refs, ['v', 'f']);
    expect(a.isBound, isTrue);
    expect(const RiscvPipelineStageBinding().isBound, isFalse);
    expect(const RiscvPipelineStageBinding(validRef: '').refs, isEmpty);
  });
}
