// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/diagnostics/memory_stats_service.dart';

class _MockSource extends Mock implements WaveformDataSource {}

Variable _var(String ref) => Variable(
  name: ref,
  signalRef: ref,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  scopePath: 'top',
  bitWidth: 1,
);

_MockSource _source({
  List<Variable> variables = const [],
  Set<String> loadedRefs = const {},
}) {
  final mock = _MockSource();
  when(() => mock.findVariables(any())).thenReturn(variables);
  for (final v in variables) {
    when(
      () => mock.isSignalLoaded(v.signalRef),
    ).thenReturn(loadedRefs.contains(v.signalRef));
  }
  return mock;
}

void main() {
  setUpAll(() {
    registerFallbackValue(const SignalFilter());
  });

  const service = MemoryStatsService();

  group('totalSignalCount', () {
    test('returns 0 when no variables', () {
      final src = _source();
      final stats = service.collect(source: src);
      expect(stats.totalSignalCount, 0);
    });

    test('counts all variables regardless of loaded state', () {
      final vars = [_var('a'), _var('b'), _var('c')];
      final src = _source(variables: vars);
      final stats = service.collect(source: src);
      expect(stats.totalSignalCount, 3);
    });
  });

  group('loadedSignalCount', () {
    test('returns 0 when no signals loaded', () {
      final vars = [_var('a'), _var('b')];
      final src = _source(variables: vars);
      final stats = service.collect(source: src);
      expect(stats.loadedSignalCount, 0);
    });

    test('counts only loaded signals', () {
      final vars = [_var('a'), _var('b'), _var('c')];
      final src = _source(variables: vars, loadedRefs: {'a', 'c'});
      final stats = service.collect(source: src);
      expect(stats.loadedSignalCount, 2);
    });

    test('all signals loaded', () {
      final vars = [_var('x'), _var('y')];
      final src = _source(
        variables: vars,
        loadedRefs: {'x', 'y'},
      );
      final stats = service.collect(source: src);
      expect(stats.loadedSignalCount, 2);
      expect(stats.totalSignalCount, 2);
    });
  });

  group('wellenEstimateBytes', () {
    test('uses provided value when non-null', () {
      final src = _source();
      final stats = service.collect(source: src, wellenMemoryBytes: 12345678);
      expect(stats.wellenEstimateBytes, 12345678);
    });

    test('defaults to 0 when null (web / accounting unavailable)', () {
      final src = _source();
      final stats = service.collect(source: src);
      expect(stats.wellenEstimateBytes, 0);
    });

    test('passes through large values', () {
      final src = _source();
      final stats = service.collect(
        source: src,
        wellenMemoryBytes: 500 * 1024 * 1024,
      );
      expect(stats.wellenEstimateBytes, 500 * 1024 * 1024);
    });
  });

  group('dartProcessRssBytes', () {
    test('returns a non-negative value', () {
      final src = _source();
      final stats = service.collect(source: src);
      expect(stats.dartProcessRssBytes, greaterThanOrEqualTo(0));
    });
  });
}
