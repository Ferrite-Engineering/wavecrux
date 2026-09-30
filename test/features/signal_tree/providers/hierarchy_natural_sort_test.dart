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
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

class _MockSource extends Mock implements WaveformDataSource {}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

Variable _v(String name, {String ref = ''}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: ref.isEmpty ? 'ref_$name' : ref,
  scopePath: 'top',
  bitWidth: 1,
);

/// Dump order deliberately hostile to lexicographic sorting: bit-blasted
/// names arrive [0] [1] [10] [11] [2] (the wellen/FST order Kevin reported).
List<Scope> _dumpOrderScopes() => [
  Scope(
    name: 'top',
    type: ScopeType.module,
    path: 'top',
    variables: [_v('q[0]'), _v('q[1]'), _v('q[10]'), _v('q[11]'), _v('q[2]')],
    childScopes: const [
      Scope(name: 'u10', type: ScopeType.module, path: 'top.u10'),
      Scope(name: 'u2', type: ScopeType.module, path: 'top.u2'),
      Scope(name: 'u1', type: ScopeType.module, path: 'top.u1'),
    ],
  ),
];

ProviderContainer _container({required bool naturalSort}) {
  final source = _MockSource();
  when(() => source.rootScopes).thenReturn(_dumpOrderScopes());
  final container = ProviderContainer(
    overrides: [
      waveformSourceProvider.overrideWith(() => _FakeSourceNotifier(source)),
      signalTreeNaturalSortProvider.overrideWith((_) => naturalSort),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('hierarchyProvider natural sort', () {
    test('sorts variables and child scopes naturally when enabled', () {
      final roots = _container(
        naturalSort: true,
      ).read(hierarchyProvider).requireValue;
      expect(
        roots.first.variables.map((v) => v.name),
        ['q[0]', 'q[1]', 'q[2]', 'q[10]', 'q[11]'],
      );
      expect(
        roots.first.childScopes.map((s) => s.name),
        ['u1', 'u2', 'u10'],
      );
    });

    test('preserves dump order when disabled', () {
      final roots = _container(
        naturalSort: false,
      ).read(hierarchyProvider).requireValue;
      expect(
        roots.first.variables.map((v) => v.name),
        ['q[0]', 'q[1]', 'q[10]', 'q[11]', 'q[2]'],
      );
      expect(
        roots.first.childScopes.map((s) => s.name),
        ['u10', 'u2', 'u1'],
      );
    });

    test('sorting preserves Variable instances (identity, not copies)', () {
      // Instance identity is load-bearing: leaf rows are ObjectKey(variable)
      // and the path/ref maps hand out these exact objects.
      final source = _MockSource();
      final scopes = _dumpOrderScopes();
      when(() => source.rootScopes).thenReturn(scopes);
      final container = ProviderContainer(
        overrides: [
          waveformSourceProvider.overrideWith(
            () => _FakeSourceNotifier(source),
          ),
          signalTreeNaturalSortProvider.overrideWith((_) => true),
        ],
      );
      addTearDown(container.dispose);

      final sorted = container.read(hierarchyProvider).requireValue;
      final originals = scopes.first.variables.toSet();
      for (final v in sorted.first.variables) {
        expect(originals.any((o) => identical(o, v)), isTrue);
      }
    });

    test(
      'gate-level twins (identical names) keep dump order — stable sort',
      () {
        final twinA = _v(r'\core.valid', ref: 'ref_twin_a');
        final twinB = _v(r'\core.valid', ref: 'ref_twin_b');
        final source = _MockSource();
        when(() => source.rootScopes).thenReturn([
          Scope(
            name: 'top',
            type: ScopeType.module,
            path: 'top',
            variables: [_v('z'), twinA, twinB, _v('a')],
          ),
        ]);
        final container = ProviderContainer(
          overrides: [
            waveformSourceProvider.overrideWith(
              () => _FakeSourceNotifier(source),
            ),
            signalTreeNaturalSortProvider.overrideWith((_) => true),
          ],
        );
        addTearDown(container.dispose);

        final vars = container
            .read(hierarchyProvider)
            .requireValue
            .first
            .variables;
        // Escaped identifiers (backslash prefix, 0x5C) sort before letters;
        // the twins stay in dump order relative to each other (stable sort).
        expect(vars.map((v) => v.signalRef), [
          'ref_twin_a',
          'ref_twin_b',
          'ref_a',
          'ref_z',
        ]);
      },
    );
  });
}
