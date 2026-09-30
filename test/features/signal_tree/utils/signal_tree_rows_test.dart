// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/utils/signal_tree_rows.dart';
import 'package:wavecrux/features/signal_tree/utils/variable_tree_order.dart';

Variable _v(String name, {String scopePath = 'top'}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'ref_${scopePath}_$name',
  scopePath: scopePath,
  bitWidth: 1,
);

Scope _s(
  String path, {
  List<Variable> variables = const [],
  List<Scope> childScopes = const [],
}) => Scope(
  name: path.split('.').last,
  path: path,
  type: ScopeType.module,
  variables: variables,
  childScopes: childScopes,
);

/// top ┬ cpu ┬ alu (x, y)
///     │     └ a, b
///     └ clk, rst
List<Scope> _tree() => [
  _s(
    'top',
    variables: [_v('clk'), _v('rst')],
    childScopes: [
      _s(
        'top.cpu',
        variables: [
          _v('a', scopePath: 'top.cpu'),
          _v('b', scopePath: 'top.cpu'),
        ],
        childScopes: [
          _s(
            'top.cpu.alu',
            variables: [
              _v('x', scopePath: 'top.cpu.alu'),
              _v('y', scopePath: 'top.cpu.alu'),
            ],
          ),
        ],
      ),
    ],
  ),
];

/// Human-readable shape for order assertions: `S:` header, `V:` leaf.
List<String> _shape(List<SignalTreeRow> rows) => [
  for (final r in rows)
    switch (r) {
      ScopeRow(:final scope, :final indentLevel) =>
        'S$indentLevel:${scope.path}',
      VariableRow(:final variable, :final indentLevel) =>
        'V$indentLevel:${variable.name}',
    },
];

void main() {
  group('signalTreeRowsInOrder', () {
    test('collapsed root yields only its header row', () {
      final rows = signalTreeRowsInOrder(_tree(), expandedPaths: const {});
      expect(_shape(rows), ['S0:top']);
    });

    test('expanded scope emits child scopes before its own variables', () {
      final rows = signalTreeRowsInOrder(
        _tree(),
        expandedPaths: const {'top'},
      );
      expect(_shape(rows), ['S0:top', 'S1:top.cpu', 'V1:clk', 'V1:rst']);
    });

    test('deep expansion nests indent levels and keeps tree order', () {
      final rows = signalTreeRowsInOrder(
        _tree(),
        expandedPaths: const {'top', 'top.cpu', 'top.cpu.alu'},
      );
      expect(_shape(rows), [
        'S0:top',
        'S1:top.cpu',
        'S2:top.cpu.alu',
        'V3:x',
        'V3:y',
        'V2:a',
        'V2:b',
        'V1:clk',
        'V1:rst',
      ]);
    });

    test('collapsed mid-level scope shows its header but nothing below', () {
      final rows = signalTreeRowsInOrder(
        _tree(),
        expandedPaths: const {'top', 'top.cpu'},
      );
      expect(_shape(rows), [
        'S0:top',
        'S1:top.cpu',
        'S2:top.cpu.alu', // header visible, contents pruned (collapsed)
        'V2:a',
        'V2:b',
        'V1:clk',
        'V1:rst',
      ]);
    });

    test('search prunes non-matching scopes and variables', () {
      final rows = signalTreeRowsInOrder(
        _tree(),
        expandedPaths: const {'top', 'top.cpu', 'top.cpu.alu'},
        searchQuery: 'clk',
      );
      // cpu/alu contain no 'clk' match → pruned entirely; top keeps clk only.
      expect(_shape(rows), ['S0:top', 'V1:clk']);
    });

    test('search with no match anywhere yields no rows', () {
      final rows = signalTreeRowsInOrder(
        _tree(),
        expandedPaths: const {'top'},
        searchQuery: 'zzz',
      );
      expect(rows, isEmpty);
    });

    test('VariableRow sequence always matches variablesInTreeOrder', () {
      // The Shift+click range resolves through variablesInTreeOrder while
      // the screen renders through signalTreeRowsInOrder — they must never
      // disagree. Checked across expansion states and search queries.
      final cases = [
        (const <String>{}, ''),
        ({'top'}, ''),
        ({'top', 'top.cpu'}, ''),
        ({'top', 'top.cpu', 'top.cpu.alu'}, ''),
        ({'top', 'top.cpu', 'top.cpu.alu'}, 'clk'),
        ({'top', 'top.cpu', 'top.cpu.alu'}, 'a'),
      ];
      for (final (expanded, query) in cases) {
        final fromRows = signalTreeRowsInOrder(
          _tree(),
          expandedPaths: expanded,
          searchQuery: query,
        ).whereType<VariableRow>().map((r) => r.variable.fullPath).toList();
        final fromOrder = variablesInTreeOrder(
          _tree(),
          expandedPaths: expanded,
          searchQuery: query,
        ).map((v) => v.fullPath).toList();
        expect(
          fromRows,
          fromOrder,
          reason: 'expanded=$expanded query="$query"',
        );
      }
    });

    test('64k-variable scope flattens in milliseconds', () {
      // The whole point of the flat model: row assembly must stay O(rows)
      // and never approach widget-build cost. 64k mirrors tb.chip_u in the
      // GF180 gate-level reference netlist.
      final big = _s(
        'big',
        variables: [
          for (var i = 0; i < 64000; i++) _v('net_$i', scopePath: 'big'),
        ],
      );
      final sw = Stopwatch()..start();
      final rows = signalTreeRowsInOrder(
        [big],
        expandedPaths: const {'big'},
      );
      sw.stop();
      expect(rows.length, 64001);
      expect(
        sw.elapsedMilliseconds,
        lessThan(500),
        reason: 'flattening 64k rows took ${sw.elapsedMilliseconds} ms',
      );
    });
  });
}
