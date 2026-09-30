// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

class _MockSource extends Mock implements WaveformDataSource {}

// WaveformSourceNotifier.build() is synchronous — returns AsyncValue directly.
class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

ProviderContainer _container({WaveformDataSource? source}) => ProviderContainer(
  overrides: [
    waveformSourceProvider.overrideWith(
      () => _FakeSourceNotifier(source),
    ),
  ],
);

Variable _variable(
  String name,
  String ref, {
  int? bitWidth,
  String scopePath = '',
}) => Variable(
  name: name,
  signalRef: ref,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  scopePath: scopePath,
  bitWidth: bitWidth,
);

Scope _scope(
  String name,
  String path, {
  List<Variable> variables = const [],
  List<Scope> childScopes = const [],
}) => Scope(
  name: name,
  path: path,
  type: ScopeType.module,
  variables: variables,
  childScopes: childScopes,
);

void main() {
  group('signalVariablesMapProvider', () {
    test('returns empty map when source is null', () {
      final container = _container();
      addTearDown(container.dispose);

      final map = container.read(signalVariablesMapProvider);
      expect(map, isEmpty);
    });

    test('builds flat map from single scope', () {
      final source = _MockSource();
      final clk = _variable('clk', 'top.clk');
      final data = _variable('data', 'top.data', bitWidth: 8);
      when(() => source.rootScopes).thenReturn([
        _scope('top', 'top', variables: [clk, data]),
      ]);

      final container = _container(source: source);
      addTearDown(container.dispose);

      final map = container.read(signalVariablesMapProvider);

      expect(map.length, 2);
      expect(map['top.clk'], clk);
      expect(map['top.data'], data);
    });

    test('flattens nested child scopes', () {
      final source = _MockSource();
      final regA = _variable('regA', 'top.sub.regA', bitWidth: 4);
      final clk = _variable('clk', 'top.clk');
      final root = _scope(
        'top',
        'top',
        variables: [clk],
        childScopes: [
          _scope('sub', 'top.sub', variables: [regA]),
        ],
      );
      when(() => source.rootScopes).thenReturn([root]);

      final container = _container(source: source);
      addTearDown(container.dispose);

      final map = container.read(signalVariablesMapProvider);

      expect(map.length, 2);
      expect(map['top.clk'], clk);
      expect(map['top.sub.regA'], regA);
    });

    test('handles multiple root scopes', () {
      final source = _MockSource();
      final a = _variable('a', 'scopeA.a');
      final b = _variable('b', 'scopeB.b');
      when(() => source.rootScopes).thenReturn([
        _scope('scopeA', 'scopeA', variables: [a]),
        _scope('scopeB', 'scopeB', variables: [b]),
      ]);

      final container = _container(source: source);
      addTearDown(container.dispose);

      final map = container.read(signalVariablesMapProvider);

      expect(map['scopeA.a'], a);
      expect(map['scopeB.b'], b);
    });

    test('scope with no variables yields empty map', () {
      final source = _MockSource();
      when(() => source.rootScopes).thenReturn([_scope('top', 'top')]);

      final container = _container(source: source);
      addTearDown(container.dispose);

      final map = container.read(signalVariablesMapProvider);
      expect(map, isEmpty);
    });

    test('deeply nested scopes are all collected', () {
      final source = _MockSource();
      final deep = _variable('deep', 'a.b.c.d.sig');
      final c = _scope('c', 'a.b.c', variables: [deep]);
      final b = _scope('b', 'a.b', childScopes: [c]);
      final a = _scope('a', 'a', childScopes: [b]);
      when(() => source.rootScopes).thenReturn([a]);

      final container = _container(source: source);
      addTearDown(container.dispose);

      final map = container.read(signalVariablesMapProvider);
      expect(map['a.b.c.d.sig'], deep);
    });
  });

  group('signalVariablesByPathProvider (FST alias regression)', () {
    test('aliased rows stay distinct when keyed by fullPath', () {
      // One underlying signal (shared signalRef) surfacing as two hierarchy
      // rows in different scopes — how wellen reports an FST net wired
      // through a port (the wb_streamer beta report). The ref-keyed map can
      // hold only one of them (last walked wins); the path-keyed map must
      // hold both, each under its own row identity.
      final source = _MockSource();
      final ramClk = _variable('wb_clk_i', 's39', scopePath: 'wb_ram0');
      final tbClk = _variable('clk', 's39', scopePath: 'tb');
      when(() => source.rootScopes).thenReturn([
        _scope('wb_ram0', 'wb_ram0', variables: [ramClk]),
        _scope('tb', 'tb', variables: [tbClk]),
      ]);

      final container = _container(source: source);
      addTearDown(container.dispose);

      final byPath = container.read(signalVariablesByPathProvider);
      expect(byPath.length, 2);
      expect(byPath['wb_ram0.wb_clk_i'], ramClk);
      expect(byPath['tb.clk'], tbClk);

      // The ref-keyed sibling collapses the aliases — documented data-map
      // behavior, and precisely why selection must not be keyed by ref.
      // Which alias wins is walk-order-dependent: with natural sort (the
      // default) `tb` sorts before `wb_ram0`, so wb_ram0's row wins.
      final byRef = container.read(signalVariablesMapProvider);
      expect(byRef.length, 1);
      expect(byRef['s39'], ramClk);
    });

    test('returns empty map when source is null', () {
      final container = _container();
      addTearDown(container.dispose);
      expect(container.read(signalVariablesByPathProvider), isEmpty);
    });
  });
}
