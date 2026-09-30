// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/board_auto_bind_candidate.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/riscv/rvfi_binding_set.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';
import 'package:wavecrux/services/riscv/rvfi_detection_service.dart';

import '../../helpers/generated_vcd_fixture.dart';

const _service = RvfiDetectionService();

Variable _v(
  String name, {
  String scopePath = '',
  int bitWidth = 32,
  String? ref,
}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: ref ?? '$scopePath/$name',
  scopePath: scopePath,
  bitWidth: bitWidth,
);

Map<String, Variable> _map(List<Variable> vars) => {
  for (final v in vars) v.signalRef: v,
};

/// Every canonical channel name, optionally decorated.
List<Variable> _fullBundle({
  String scopePath = '',
  String namePrefix = '',
  String suffix = '',
  String indexSuffix = '',
}) => [
  for (final c in RvfiChannel.values)
    _v(
      '$namePrefix${c.signalName}$indexSuffix$suffix',
      scopePath: scopePath,
      bitWidth: c.nominalBitWidth,
    ),
];

/// Minimal non-compound widget declaring RVFI pins.
class _RvfiStub extends StageWidget {
  const _RvfiStub();
  @override
  String get id => 'riscv_commit_stub';
  @override
  String get displayName => 'RVFI stub';
  @override
  String get description => '';
  @override
  StageWidgetCategory get category => StageWidgetCategory.instrument;
  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(name: 'rvfi_valid', description: 'retire strobe'),
    SignalBinding(name: 'rvfi_insn', description: 'instruction'),
    SignalBinding(name: 'rvfi_pc_rdata', description: 'pc'),
  ];
  @override
  List<SignalBinding> get optionalSignals => const [
    SignalBinding(name: 'rvfi_mem_addr', description: 'mem addr'),
    SignalBinding(name: 'not_an_rvfi_pin', description: 'noise'),
  ];
}

void main() {
  group('RvfiDetectionService.parseName', () {
    test('resolves every canonical channel name', () {
      for (final c in RvfiChannel.values) {
        final match = RvfiDetectionService.parseName(c.signalName);
        expect(match, isNotNull, reason: c.signalName);
        expect(match!.channel, c);
        expect(match.channelIndex, 0);
        expect(match.namePrefix, isEmpty);
        expect(match.exact, isTrue);
      }
    });

    test('strips _i / _o port-direction suffixes', () {
      expect(
        RvfiDetectionService.parseName('rvfi_valid_o')!.channel,
        RvfiChannel.valid,
      );
      expect(
        RvfiDetectionService.parseName('rvfi_insn_i')!.channel,
        RvfiChannel.insn,
      );
      expect(
        RvfiDetectionService.parseName('rvfi_mem_wdata_o')!.channel,
        RvfiChannel.memWdata,
      );
      expect(RvfiDetectionService.parseName('rvfi_valid_o')!.exact, isFalse);
    });

    test('keeps a flattened hierarchy prefix', () {
      final m = RvfiDetectionService.parseName('core0_rvfi_rs1_addr');
      expect(m!.channel, RvfiChannel.rs1Addr);
      expect(m.namePrefix, 'core0_');
    });

    test('reads a bracketed multi-channel index', () {
      final m = RvfiDetectionService.parseName('rvfi_valid[2]');
      expect(m!.channel, RvfiChannel.valid);
      expect(m.channelIndex, 2);
    });

    test('reads an underscore multi-channel index', () {
      final m = RvfiDetectionService.parseName('rvfi_pc_wdata_1');
      expect(m!.channel, RvfiChannel.pcWdata);
      expect(m.channelIndex, 1);
    });

    test('never mistakes a channel name suffix for an index', () {
      // rs1/rs2 end in digits mid-name; the parse must not eat `_addr`.
      expect(
        RvfiDetectionService.parseName('rvfi_rs1_addr')!.channel,
        RvfiChannel.rs1Addr,
      );
      expect(
        RvfiDetectionService.parseName('rvfi_rs2_rdata')!.channel,
        RvfiChannel.rs2Rdata,
      );
      expect(RvfiDetectionService.parseName('rvfi_rs1_addr')!.channelIndex, 0);
    });

    test('prefers the longest matching channel name', () {
      expect(
        RvfiDetectionService.parseName('rvfi_mem_rdata')!.channel,
        RvfiChannel.memRdata,
      );
      expect(
        RvfiDetectionService.parseName('rvfi_pc_rdata')!.channel,
        RvfiChannel.pcRdata,
      );
    });

    test('returns null for non-RVFI names', () {
      expect(RvfiDetectionService.parseName('clk'), isNull);
      expect(RvfiDetectionService.parseName('cpu_pc'), isNull);
      expect(RvfiDetectionService.parseName('rvfi'), isNull);
    });
  });

  group('RvfiDetectionService.detect', () {
    test('binds a canonical top-level bundle as full', () {
      final result = _service.detect(_map(_fullBundle()));
      expect(result.report.completeness, RvfiBindingCompleteness.full);
      expect(result.report.missing, isEmpty);
      expect(result.report.found.length, RvfiChannel.values.length);
      expect(result.report.channelCount, 1);
      expect(result.report.isUsable, isTrue);
      expect(result.report.reducedBindingSetApplies, isFalse);
      expect(result.bindings.allRefs.length, RvfiChannel.values.length);
    });

    test('binds a hierarchy-prefixed bundle and reports the scope', () {
      final result = _service.detect(
        _map([
          _v('clk', scopePath: 'tb', bitWidth: 1),
          ..._fullBundle(scopePath: 'tb.core'),
        ]),
      );
      expect(result.report.completeness, RvfiBindingCompleteness.full);
      expect(result.bindings.scopePath, 'tb.core');
      expect(result.bindings.displayPath, 'tb.core.*');
    });

    test('binds an _o-suffixed bundle', () {
      final result = _service.detect(_map(_fullBundle(suffix: '_o')));
      expect(result.report.completeness, RvfiBindingCompleteness.full);
    });

    test('binds a flattened-prefix bundle and reports the prefix', () {
      final result = _service.detect(_map(_fullBundle(namePrefix: 'core0_')));
      expect(result.report.completeness, RvfiBindingCompleteness.full);
      expect(result.bindings.namePrefix, 'core0_');
    });

    test('binds a two-channel superscalar bundle', () {
      final result = _service.detect(
        _map([
          ..._fullBundle(indexSuffix: '[0]'),
          ..._fullBundle(indexSuffix: '[1]'),
        ]),
      );
      expect(result.report.channelCount, 2);
      expect(result.bindings.channelCount, 2);
      expect(result.bindings.ref(RvfiChannel.valid), isNotNull);
      expect(result.bindings.ref(RvfiChannel.valid, index: 1), isNotNull);
      expect(
        result.bindings.ref(RvfiChannel.valid),
        isNot(result.bindings.ref(RvfiChannel.valid, index: 1)),
      );
    });

    test('suspects — and refuses to slice — a packed NRET vector', () {
      final vars = _fullBundle()
        ..removeWhere((v) => v.name == 'rvfi_valid')
        ..add(_v('rvfi_valid', bitWidth: 2));
      final result = _service.detect(_map(vars));
      expect(result.report.packedVectorSuspected, isTrue);
      // One channel only — the vector is never split into two.
      expect(result.report.channelCount, 1);
    });

    test(
      'reports the reduced binding set when optional channels are absent',
      () {
        final reduced = [
          for (final c in RvfiChannel.values)
            if (c.isReducedSetMember)
              _v(c.signalName, bitWidth: c.nominalBitWidth),
        ];
        final result = _service.detect(_map(reduced));
        expect(result.report.completeness, RvfiBindingCompleteness.reduced);
        expect(result.report.reducedBindingSetApplies, isTrue);
        expect(result.report.isUsable, isTrue);
        expect(result.report.missing, contains(RvfiChannel.memAddr));
        expect(result.report.found, contains(RvfiChannel.rdWdata));
      },
    );

    test('reports unusable when a required channel is missing', () {
      final vars = _fullBundle()
        ..removeWhere((v) => v.name == RvfiChannel.insn.signalName);
      final result = _service.detect(_map(vars));
      expect(result.report.completeness, RvfiBindingCompleteness.unusable);
      expect(result.report.isUsable, isFalse);
      expect(result.report.missing, contains(RvfiChannel.insn));
    });

    test('returns the empty result when the trace has no RVFI signals', () {
      final result = _service.detect(
        _map([_v('clk', bitWidth: 1), _v('data')]),
      );
      expect(result.bindings, RvfiBindingSet.empty);
      expect(result.report.isUsable, isFalse);
      expect(
        result.report.missing.length,
        RvfiChannel.values.length,
        reason: 'nothing found means everything missing',
      );
    });

    test('picks the most complete bundle when a trace holds two cores', () {
      final partial = [
        for (final c in RvfiChannel.values)
          if (c.isRequired) _v(c.signalName, scopePath: 'tb.core1'),
      ];
      final result = _service.detect(
        _map([..._fullBundle(scopePath: 'tb.core0'), ...partial]),
      );
      expect(result.bindings.scopePath, 'tb.core0');
      expect(result.report.candidateScopes, contains('tb.core1'));
      expect(result.report.candidateScopes.first, 'tb.core0');
    });

    test('prefers the canonical spelling over a decorated duplicate', () {
      final result = _service.detect(
        _map([
          ..._fullBundle(),
          _v('rvfi_valid_o', bitWidth: 1, ref: 'decorated'),
        ]),
      );
      expect(result.bindings.ref(RvfiChannel.valid), isNot('decorated'));
    });

    test('binds the committed RVFI fixture end to end', () {
      final fixture = GeneratedVcdFixture.load(
        'test/fixtures/protocol/riscv/generated/riscv_rvfi_retire.vcd',
      );
      final result = _service.detect(fixture.variables);
      expect(result.report.completeness, RvfiBindingCompleteness.full);
      expect(result.bindings.scopePath, 'tb.core');
      expect(result.bindings.channelCount, 1);
      expect(
        result.bindings.ref(RvfiChannel.valid),
        fixture.refFor('tb.core.rvfi_valid'),
      );
      expect(
        result.bindings.ref(RvfiChannel.memWmask),
        fixture.refFor('tb.core.rvfi_mem_wmask'),
      );
      // The clock is not part of the bundle.
      expect(
        result.bindings.allRefs,
        isNot(contains(fixture.refFor('tb.core.clk'))),
      );
    });
  });

  group('RvfiDetectionService as a StageAutoBindService', () {
    test("maps detected channels onto a widget's declared pins", () {
      final result = _service.autoBind(
        widget: const _RvfiStub(),
        availableSignals: _map(_fullBundle(scopePath: 'tb.core')),
      );
      expect(result.candidates.keys, hasLength(5));
      expect(
        result.candidates['rvfi_valid']!.confidence,
        BoardAutoBindConfidence.knownAlias,
        reason: 'a hierarchy-prefixed bundle is a match, but not a bare one',
      );
      expect(result.candidates['rvfi_insn']!.binding, isNotNull);
      expect(result.candidates['rvfi_mem_addr']!.binding, isNotNull);
    });

    test('reports an unbindable pin rather than dropping it', () {
      final result = _service.autoBind(
        widget: const _RvfiStub(),
        availableSignals: _map(_fullBundle()),
      );
      final noise = result.candidates['not_an_rvfi_pin']!;
      expect(noise.confidence, BoardAutoBindConfidence.noMatch);
      expect(noise.binding, isNull);
      expect(noise.matchReason, contains('not an RVFI channel'));
    });

    test('reports a missing channel with its name', () {
      final vars = _fullBundle()
        ..removeWhere((v) => v.name == RvfiChannel.memAddr.signalName);
      final result = _service.autoBind(
        widget: const _RvfiStub(),
        availableSignals: _map(vars),
      );
      final mem = result.candidates['rvfi_mem_addr']!;
      expect(mem.confidence, BoardAutoBindConfidence.noMatch);
      expect(mem.matchReason, contains('rvfi_mem_addr'));
    });

    test('never overwrites a manual binding', () {
      final result = _service.autoBind(
        widget: const _RvfiStub(),
        availableSignals: _map(_fullBundle()),
        existingBindings: const {
          'rvfi_valid': StageSignalBinding(signalRef: 'hand-picked'),
        },
      );
      expect(
        result.candidates['rvfi_valid']!.binding!.signalRef,
        'hand-picked',
      );
      expect(result.candidates['rvfi_valid']!.matchReason, 'manually bound');
    });

    test('grades a bare canonical bundle as an exact match', () {
      final result = _service.autoBind(
        widget: const _RvfiStub(),
        availableSignals: _map(_fullBundle()),
      );
      expect(
        result.candidates['rvfi_valid']!.confidence,
        BoardAutoBindConfidence.exactMatch,
      );
    });
  });
}
