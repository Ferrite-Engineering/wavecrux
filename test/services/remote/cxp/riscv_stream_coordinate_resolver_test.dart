// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/services/remote/cxp/riscv_stream_coordinate_resolver.dart';
import 'package:wavecrux/services/riscv/riscv_retire_stream_service.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';
import 'package:wavecrux/services/riscv/rvfi_binding_set.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';

import '../../../helpers/fake_waveform_data_source.dart';

/// A width-[width] binary bit-string, the shape `WaveformDataSource` answers
/// value queries with.
String _bits(int value, int width) =>
    value.toRadixString(2).padLeft(width, '0');

const _pc0 = 0x1000;
const _pc1 = 0x1004;

/// A synthetic bounded-proof counterexample: four steps on a pitch of 10
/// ticks, with retirements at step 1 and step 3 and nothing at step 2.
///
/// Deliberately built the way `sby` dumps one — a value on every step
/// boundary and nothing between them — so the step grid is recoverable, which
/// is the property the whole `riscv.formal.trace_step` binding rests on.
FakeWaveformDataSource _counterexample({bool withOrder = true}) {
  return FakeWaveformDataSource(
    endTime: 30,
    signals: {
      'rvfi_valid': const [
        SignalChange(time: 0, value: '0'),
        SignalChange(time: 10, value: '1'),
        SignalChange(time: 20, value: '0'),
        SignalChange(time: 30, value: '1'),
      ],
      if (withOrder)
        'rvfi_order': [
          SignalChange(time: 0, value: _bits(0, 64)),
          SignalChange(time: 30, value: _bits(1, 64)),
        ],
      'rvfi_insn': [
        SignalChange(time: 0, value: _bits(0x00000013, 32)),
        SignalChange(time: 10, value: _bits(0x00000013, 32)),
        SignalChange(time: 30, value: _bits(0x00000013, 32)),
      ],
      'rvfi_pc_rdata': [
        SignalChange(time: 0, value: _bits(_pc0, 32)),
        SignalChange(time: 10, value: _bits(_pc0, 32)),
        SignalChange(time: 30, value: _bits(_pc1, 32)),
      ],
    },
  );
}

RvfiBindingSet _bindings({bool withOrder = true}) => RvfiBindingSet(
  refs: {
    RvfiChannel.valid: const {0: 'rvfi_valid'},
    if (withOrder) RvfiChannel.order: const {0: 'rvfi_order'},
    RvfiChannel.insn: const {0: 'rvfi_insn'},
    RvfiChannel.pcRdata: const {0: 'rvfi_pc_rdata'},
  },
  channelCount: 1,
);

List<RiscvRetiredInstruction> _retires(
  FakeWaveformDataSource source,
  RvfiBindingSet bindings,
) => const RiscvRetireStreamService(null).build(
  source: source,
  bindings: bindings,
  startTime: source.startTime,
  endTime: source.endTime,
);

void main() {
  const resolver = RiscvStreamCoordinateResolver();

  group('RiscvTraceStepGrid', () {
    test('recovers the lattice of a step-dumped counterexample', () {
      final grid = RiscvTraceStepGrid.derive(
        source: _counterexample(),
        bindings: _bindings(),
      );
      expect(grid, isNotNull);
      expect(grid!.origin, 0);
      expect(grid.pitch, 10);
      expect(grid.lastStep, 3);
      expect(grid.tickForStep(0), 0);
      expect(grid.tickForStep(2), 20);
      expect(grid.tickForStep(3), 30);
    });

    test('refuses a step past the end of the trace', () {
      final grid = RiscvTraceStepGrid.derive(
        source: _counterexample(),
        bindings: _bindings(),
      );
      expect(grid!.tickForStep(4), isNull);
      expect(grid.tickForStep(-1), isNull);
    });

    test('refuses a trace whose RVFI activity is not on a uniform lattice', () {
      // An ordinary simulation dump: transitions at 0, 7 and 13 lie on no
      // common pitch, so there is no step grid to convert against and the
      // honest answer is null rather than a plausible one.
      final source = FakeWaveformDataSource(
        endTime: 20,
        signals: {
          'rvfi_valid': const [
            SignalChange(time: 0, value: '0'),
            SignalChange(time: 7, value: '1'),
            SignalChange(time: 13, value: '0'),
          ],
        },
      );
      final grid = RiscvTraceStepGrid.derive(
        source: source,
        bindings: const RvfiBindingSet(
          refs: {
            RvfiChannel.valid: {0: 'rvfi_valid'},
          },
          channelCount: 1,
        ),
      );
      expect(grid, isNull);
    });

    test('refuses to manufacture a grid out of the trace duration alone', () {
      // No bound RVFI ref at all. `{startTime, endTime}` would otherwise be a
      // perfectly uniform two-point "lattice" measured on nothing.
      final grid = RiscvTraceStepGrid.derive(
        source: FakeWaveformDataSource(),
        bindings: RvfiBindingSet.empty,
      );
      expect(grid, isNull);
    });
  });

  group('riscv.formal.trace_step', () {
    RiscvCoordinateResolution resolveStep(
      int step, {
      String? subId = 'ch0',
      FakeWaveformDataSource? source,
      RvfiBindingSet? bindings,
    }) {
      final s = source ?? _counterexample();
      final b = bindings ?? _bindings();
      return resolver.resolve(
        coordinate: CxpStreamCoordinate(
          streamId: CxpStreamCoordinate.riscvFormalTraceStepStreamId,
          sequenceIndex: step,
          subId: subId,
        ),
        source: s,
        bindings: b,
        retires: _retires(s, b),
      );
    }

    test('selects the retirement at the addressed step', () {
      final result = resolveStep(1);
      expect(result.reason, isNull);
      expect(result.time, 10);
      expect(result.retired?.order, 0);
      expect(result.retired?.pc, _pc0);
      expect(result.channelIndex, 0);
    });

    test('converts a later step through the same grid', () {
      final result = resolveStep(3);
      expect(result.time, 30);
      expect(result.retired?.order, 1);
    });

    test('falls back to the cursor when nothing retired at that step', () {
      final result = resolveStep(2);
      expect(result.landed, isTrue);
      expect(result.time, 20);
      expect(result.retired, isNull);
      expect(result.reason, isNull);
    });

    test('declines a step past the end of the trace', () {
      final result = resolveStep(9);
      expect(result.landed, isFalse);
      expect(result.reason, contains('past the end'));
    });

    test('declines when the step grid cannot be established', () {
      final source = FakeWaveformDataSource(
        endTime: 20,
        signals: {
          'rvfi_valid': const [
            SignalChange(time: 0, value: '0'),
            SignalChange(time: 7, value: '1'),
            SignalChange(time: 13, value: '0'),
          ],
        },
      );
      final result = resolveStep(
        1,
        source: source,
        bindings: const RvfiBindingSet(
          refs: {
            RvfiChannel.valid: {0: 'rvfi_valid'},
          },
          channelCount: 1,
        ),
      );
      expect(result.landed, isFalse);
      expect(result.reason, contains('no uniform step grid'));
    });

    test('an absent sub_id means the single retirement channel', () {
      expect(resolveStep(1, subId: null).retired?.order, 0);
    });

    test('declines a channel the trace does not bind', () {
      final result = resolveStep(1, subId: 'ch3');
      expect(result.landed, isFalse);
      expect(result.reason, contains('is not one of them'));
    });

    test('declines an unparseable channel token rather than assuming ch0', () {
      final result = resolveStep(1, subId: 'lane-a');
      expect(result.landed, isFalse);
      expect(result.reason, contains('unrecognised RVFI channel'));
    });
  });

  group('riscv.rvfi.retire', () {
    RiscvCoordinateResolution resolveOrder(
      int order, {
      String? subId,
      Map<String, String> attributes = const {},
      bool withOrder = true,
    }) {
      final source = _counterexample(withOrder: withOrder);
      final bindings = _bindings(withOrder: withOrder);
      return resolver.resolve(
        coordinate: CxpStreamCoordinate(
          streamId: CxpStreamCoordinate.riscvRvfiRetireStreamId,
          sequenceIndex: order,
          subId: subId,
          attributes: attributes,
        ),
        source: source,
        bindings: bindings,
        retires: _retires(source, bindings),
      );
    }

    test('selects the retirement with that rvfi_order', () {
      final result = resolveOrder(1);
      expect(result.time, 30);
      expect(result.retired?.pc, _pc1);
    });

    test('accepts an explicit hart 0 and an absent hart alike', () {
      expect(resolveOrder(0, subId: '0').retired?.order, 0);
      expect(resolveOrder(0).retired?.order, 0);
    });

    test('declines a hart it cannot address rather than pretending', () {
      final result = resolveOrder(0, subId: '3');
      expect(result.landed, isFalse);
      expect(result.reason, contains('hart "3"'));
    });

    test('declines when no retirement carries that order', () {
      final result = resolveOrder(97);
      expect(result.landed, isFalse);
      expect(result.reason, contains('no retirement with rvfi_order 97'));
    });

    test('declines when the trace carries no rvfi_order at all', () {
      final result = resolveOrder(0, withOrder: false);
      expect(result.landed, isFalse);
      expect(result.reason, contains('carries no rvfi_order'));
    });

    test('the riscv.pc cross-check confirms a match', () {
      final result = resolveOrder(
        1,
        attributes: {
          CxpStreamCoordinate.riscvPcAttribute: '0x00001004',
        },
      );
      expect(result.retired?.pc, _pc1);
      expect(result.reason, isNull);
    });

    test('a riscv.pc disagreement declines instead of selecting', () {
      // CXP §9.9.2's recommended cross-check (https://edacrux.app/cxp#sec-9-9-2):
      // index 1 of THIS trace is not the
      // element the sender measured, so landing on it would be worse than
      // landing nowhere.
      final result = resolveOrder(
        1,
        attributes: {
          CxpStreamCoordinate.riscvPcAttribute: '0xdeadbeef',
        },
      );
      expect(result.landed, isFalse);
      expect(result.reason, contains('not the trace the coordinate'));
    });

    test('an unparseable riscv.pc is ignored, never fatal', () {
      final result = resolveOrder(
        1,
        attributes: const {
          CxpStreamCoordinate.riscvPcAttribute: 'somewhere',
        },
      );
      expect(result.retired?.pc, _pc1);
    });
  });

  group('unknown streams are tolerated, never errors', () {
    test('implementsStream knows exactly the two RISC-V bindings', () {
      expect(
        RiscvStreamCoordinateResolver.implementsStream(
          CxpStreamCoordinate.riscvFormalTraceStepStreamId,
        ),
        isTrue,
      );
      expect(
        RiscvStreamCoordinateResolver.implementsStream(
          CxpStreamCoordinate.riscvRvfiRetireStreamId,
        ),
        isTrue,
      );
      // The anticipated-but-unspecified bindings of CXP §9.9.3. Tolerating
      // them today is the forward-compatibility path, not a TODO.
      for (final stream in const [
        'axi.transaction',
        'ethernet.frame',
        'usb.packet',
        'video.line',
      ]) {
        expect(
          RiscvStreamCoordinateResolver.implementsStream(stream),
          isFalse,
          reason: stream,
        );
      }
    });

    test('resolving an unimplemented stream declines without throwing', () {
      final source = _counterexample();
      final bindings = _bindings();
      final result = resolver.resolve(
        coordinate: CxpStreamCoordinate(
          streamId: 'axi.transaction',
          sequenceIndex: 17,
        ),
        source: source,
        bindings: bindings,
        retires: _retires(source, bindings),
      );
      expect(result.landed, isFalse);
      expect(result.reason, contains('does not implement'));
      expect(result.reason, contains('axi.transaction'));
    });
  });

  group('RiscvCoordinateAttributes', () {
    test('spell the keys the producer actually sends', () {
      // These mirror SimCrux's `RiscvFormalDriver` metric names and the
      // advisory keys CXP §9.9.2 registers. A drift here is a silent loss of
      // the whole provenance line, so they are pinned.
      expect(RiscvCoordinateAttributes.check, 'riscv.formal.check');
      expect(RiscvCoordinateAttributes.group, 'riscv.formal.group');
      expect(RiscvCoordinateAttributes.verdict, 'riscv.formal.verdict');
      expect(
        RiscvCoordinateAttributes.depthConfigured,
        'riscv.formal.depth_configured',
      );
      expect(RiscvCoordinateAttributes.demoMode, 'demo');
      expect(CxpStreamCoordinate.riscvModeAttribute, 'riscv.mode');
      expect(CxpStreamCoordinate.riscvIsaAttribute, 'riscv.isa');
    });
  });
}
