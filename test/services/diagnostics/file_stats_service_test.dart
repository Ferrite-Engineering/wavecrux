// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/diagnostics/file_stats_service.dart';

class _MockSource extends Mock implements WaveformDataSource {}

Variable _var(
  String name, {
  VarType type = VarType.wire,
  VarDirection dir = VarDirection.unknown,
  int? bitWidth = 1,
}) => Variable(
  name: name,
  signalRef: name,
  varType: type,
  direction: dir,
  scopePath: 'top',
  bitWidth: bitWidth,
);

Scope _scope(
  String name, {
  List<Variable> variables = const [],
  List<Scope> children = const [],
}) => Scope(
  name: name,
  type: ScopeType.module,
  path: name,
  variables: variables,
  childScopes: children,
);

_MockSource _source({
  List<Variable> variables = const [],
  List<Scope> rootScopes = const [],
  int startTime = 0,
  int endTime = 1000,
  Timescale? timescale,
  String? date,
  String? version,
}) {
  final mock = _MockSource();
  when(() => mock.findVariables(any())).thenReturn(variables);
  when(() => mock.rootScopes).thenReturn(rootScopes);
  when(() => mock.startTime).thenReturn(startTime);
  when(() => mock.endTime).thenReturn(endTime);
  when(() => mock.timescale).thenReturn(timescale);
  when(() => mock.date).thenReturn(date);
  when(() => mock.version).thenReturn(version);
  return mock;
}

void main() {
  setUpAll(() {
    registerFallbackValue(const SignalFilter());
  });

  const service = FileStatsService();

  group('format inference', () {
    test('infers VCD from .vcd extension', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: '/home/user/sim/out.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.formatName, 'VCD');
    });

    test('infers FST from .fst extension', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: '/tmp/trace.fst',
        parseTime: Duration.zero,
      );
      expect(stats.formatName, 'FST');
    });

    test('infers GHW from .ghw extension', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: 'test.ghw',
        parseTime: Duration.zero,
      );
      expect(stats.formatName, 'GHW');
    });

    test('Unknown for unrecognised extension', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: 'trace.lxt',
        parseTime: Duration.zero,
      );
      expect(stats.formatName, 'Unknown');
    });

    test('formatOverride takes precedence over extension', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: 'trace.vcd',
        parseTime: Duration.zero,
        formatOverride: 'FST',
      );
      expect(stats.formatName, 'FST');
    });

    test('case-insensitive extension matching for uppercase .VCD', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: 'DUMP.VCD',
        parseTime: Duration.zero,
      );
      expect(stats.formatName, 'VCD');
    });
  });

  group('signal type counting', () {
    test('counts scalar (1-bit wire) correctly', () {
      final src = _source(variables: [_var('clk')]);
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.scalarCount, 1);
      expect(stats.vectorCount, 0);
      expect(stats.realCount, 0);
      expect(stats.totalSignals, 1);
    });

    test('counts vector (multi-bit bus) correctly', () {
      final src = _source(
        variables: [_var('data', bitWidth: 8), _var('addr', bitWidth: 32)],
      );
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.vectorCount, 2);
      expect(stats.scalarCount, 0);
    });

    test('counts real signals as real, not vector', () {
      final src = _source(
        variables: [_var('voltage', type: VarType.real, bitWidth: null)],
      );
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.realCount, 1);
      expect(stats.vectorCount, 0);
      expect(stats.scalarCount, 0);
    });

    test('mixed signal types', () {
      final src = _source(
        variables: [
          _var('clk'),
          _var('data', bitWidth: 8),
          _var('addr', bitWidth: 16),
          _var('voltage', type: VarType.real, bitWidth: null),
        ],
      );
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.scalarCount, 1);
      expect(stats.vectorCount, 2);
      expect(stats.realCount, 1);
      expect(stats.totalSignals, 4);
    });

    test('null bitWidth treated as 1-bit (scalar)', () {
      final src = _source(variables: [_var('sig', bitWidth: null)]);
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.scalarCount, 1);
      expect(stats.vectorCount, 0);
    });
  });

  group('signal direction counting', () {
    test('counts input signals', () {
      final src = _source(
        variables: [_var('clk', dir: VarDirection.input)],
      );
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.inputCount, 1);
      expect(stats.outputCount, 0);
      expect(stats.inoutCount, 0);
      expect(stats.unknownDirectionCount, 0);
    });

    test('counts output signals', () {
      final src = _source(
        variables: [_var('q', dir: VarDirection.output)],
      );
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.outputCount, 1);
    });

    test('counts inout signals', () {
      final src = _source(
        variables: [_var('data', dir: VarDirection.inout)],
      );
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.inoutCount, 1);
    });

    test('unknown/implicit/buffer/linkage fall into unknownDirectionCount', () {
      final src = _source(
        variables: [
          _var('a'),
          _var('b', dir: VarDirection.implicit),
          _var('c', dir: VarDirection.buffer),
          _var('d', dir: VarDirection.linkage),
        ],
      );
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.unknownDirectionCount, 4);
      expect(stats.inputCount, 0);
      expect(stats.outputCount, 0);
      expect(stats.inoutCount, 0);
    });

    test('mixed directions', () {
      final src = _source(
        variables: [
          _var('clk', dir: VarDirection.input),
          _var('q', dir: VarDirection.output),
          _var('io', dir: VarDirection.inout),
          _var('internal'),
        ],
      );
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.inputCount, 1);
      expect(stats.outputCount, 1);
      expect(stats.inoutCount, 1);
      expect(stats.unknownDirectionCount, 1);
    });
  });

  group('hierarchy depth and scope count', () {
    test('empty hierarchy gives depth 0, count 0', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.hierarchyDepth, 0);
      expect(stats.scopeCount, 0);
    });

    test('single flat scope: depth 1, count 1', () {
      final src = _source(rootScopes: [_scope('top')]);
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.hierarchyDepth, 1);
      expect(stats.scopeCount, 1);
    });

    test('two sibling scopes: depth 1, count 2', () {
      final src = _source(rootScopes: [_scope('a'), _scope('b')]);
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.hierarchyDepth, 1);
      expect(stats.scopeCount, 2);
    });

    test('two-level nesting: depth 2, correct count', () {
      final top = _scope('top', children: [_scope('cpu')]);
      final src = _source(rootScopes: [top]);
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.hierarchyDepth, 2);
      expect(stats.scopeCount, 2);
    });

    test('deep nesting tracks maximum depth', () {
      final deep = _scope(
        'top',
        children: [
          _scope(
            'l2',
            children: [
              _scope(
                'l3',
                children: [
                  _scope('l4', children: [_scope('l5')]),
                ],
              ),
            ],
          ),
        ],
      );
      final src = _source(rootScopes: [deep]);
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.hierarchyDepth, 5);
      expect(stats.scopeCount, 5);
    });

    test('asymmetric tree uses deepest branch for depth', () {
      final top = _scope(
        'top',
        children: [
          _scope(
            'a',
            children: [
              _scope('a1', children: [_scope('a2')]),
            ],
          ),
          _scope('b'),
        ],
      );
      final src = _source(rootScopes: [top]);
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.hierarchyDepth, 4);
      expect(stats.scopeCount, 5);
    });
  });

  group('parse time', () {
    test('converts duration to milliseconds', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: const Duration(milliseconds: 250),
      );
      expect(stats.parseTimeMs, closeTo(250.0, 0.01));
    });

    test('sub-millisecond duration represented correctly', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: const Duration(microseconds: 500),
      );
      expect(stats.parseTimeMs, closeTo(0.5, 0.001));
    });

    test('zero parse time', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.parseTimeMs, 0.0);
    });
  });

  group('time range and metadata', () {
    test('captures startTime and endTime from source', () {
      final src = _source(startTime: 100, endTime: 50000);
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.startTime, 100);
      expect(stats.endTime, 50000);
    });

    test('timescaleDisplay from source.timescale', () {
      final src = _source(
        timescale: const Timescale(
          factor: 1,
          unit: TimescaleUnit.nanoSeconds,
        ),
      );
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.timescaleDisplay, isNotNull);
      expect(stats.timescaleDisplay, '1ns');
    });

    test('timescaleDisplay is null when source has no timescale', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.timescaleDisplay, isNull);
    });

    test('captures simulationDate and simulatorVersion', () {
      final src = _source(
        date: '2026-01-01',
        version: 'Icarus Verilog 12.0',
      );
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.simulationDate, '2026-01-01');
      expect(stats.simulatorVersion, 'Icarus Verilog 12.0');
    });

    test('null date and version remain null', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.simulationDate, isNull);
      expect(stats.simulatorVersion, isNull);
    });
  });

  group('totalTransitions', () {
    test('defaults to 0 when no override supplied', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.totalTransitions, 0);
    });

    test('uses totalTransitionsOverride when provided', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
        totalTransitionsOverride: 142000,
      );
      expect(stats.totalTransitions, 142000);
    });
  });

  group('fileSizeBytes', () {
    test('returns 0 for empty path', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: '',
        parseTime: Duration.zero,
      );
      expect(stats.fileSizeBytes, 0);
    });

    test('returns 0 for non-existent path (graceful failure)', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: '/does/not/exist/trace.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.fileSizeBytes, 0);
    });
  });

  group('filePath and empty source', () {
    test('records filePath in stats', () {
      final src = _source();
      const path = '/home/user/dump.vcd';
      final stats = service.collect(
        source: src,
        filePath: path,
        parseTime: Duration.zero,
      );
      expect(stats.filePath, path);
    });

    test('zero signals produces all-zero counts', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        filePath: 'test.vcd',
        parseTime: Duration.zero,
      );
      expect(stats.totalSignals, 0);
      expect(stats.scalarCount, 0);
      expect(stats.vectorCount, 0);
      expect(stats.realCount, 0);
    });
  });
}
