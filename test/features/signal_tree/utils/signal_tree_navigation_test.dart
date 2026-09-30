// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/utils/signal_tree_navigation.dart';
import 'package:wavecrux/features/signal_tree/utils/signal_tree_rows.dart';

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

/// top: cpu (alu (x, y), a, b), clk, rst
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

const _allExpanded = {'top', 'top.cpu', 'top.cpu.alu'};

String _name(SignalTreeRow row) => switch (row) {
  ScopeRow(:final scope) => scope.path,
  VariableRow(:final variable) => variable.fullPath,
};

int _indexOf(List<SignalTreeRow> rows, String path) =>
    rows.indexWhere((r) => _name(r) == path);

void main() {
  late List<Scope> scopes;
  late List<SignalTreeRow> rows;

  setUp(() {
    scopes = _tree();
    rows = signalTreeRowsInOrder(scopes, expandedPaths: _allExpanded);
  });

  test('the fixture flattens to the order the tree shows', () {
    expect(rows.map(_name), [
      'top',
      'top.cpu',
      'top.cpu.alu',
      'top.cpu.alu.x',
      'top.cpu.alu.y',
      'top.cpu.a',
      'top.cpu.b',
      'top.clk',
      'top.rst',
    ]);
  });

  group('signalTreeRowItem', () {
    test('is the scope or variable instance behind the row', () {
      expect(signalTreeRowItem(rows[0]), same(scopes.first));
      expect(
        signalTreeRowItem(rows[_indexOf(rows, 'top.clk')]),
        same(scopes.first.variables.first),
      );
    });
  });

  group('signalTreeParentIndex', () {
    test('a variable goes to the scope that holds it', () {
      expect(
        signalTreeParentIndex(rows, _indexOf(rows, 'top.cpu.b')),
        _indexOf(rows, 'top.cpu'),
      );
    });

    test('a variable after a nested scope skips over that scope', () {
      // `a` follows alu's children; its parent is cpu, not alu.
      expect(
        signalTreeParentIndex(rows, _indexOf(rows, 'top.cpu.a')),
        _indexOf(rows, 'top.cpu'),
      );
      expect(
        signalTreeParentIndex(rows, _indexOf(rows, 'top.clk')),
        _indexOf(rows, 'top'),
      );
    });

    test('a nested scope goes to its parent scope', () {
      expect(
        signalTreeParentIndex(rows, _indexOf(rows, 'top.cpu.alu')),
        _indexOf(rows, 'top.cpu'),
      );
    });

    test('a root scope and out-of-range indexes have no parent', () {
      expect(signalTreeParentIndex(rows, 0), isNull);
      expect(signalTreeParentIndex(rows, -1), isNull);
      expect(signalTreeParentIndex(rows, rows.length), isNull);
    });
  });

  group('signalTreeFirstChildIndex', () {
    test('an expanded scope goes to the row below it', () {
      expect(signalTreeFirstChildIndex(rows, 0), 1);
      expect(
        signalTreeFirstChildIndex(rows, _indexOf(rows, 'top.cpu.alu')),
        _indexOf(rows, 'top.cpu.alu.x'),
      );
    });

    test('a collapsed scope has no visible child', () {
      final collapsed = signalTreeRowsInOrder(
        scopes,
        expandedPaths: const {'top'},
      );
      expect(
        signalTreeFirstChildIndex(collapsed, _indexOf(collapsed, 'top.cpu')),
        isNull,
      );
    });

    test('a variable and the last row have no child', () {
      expect(
        signalTreeFirstChildIndex(rows, _indexOf(rows, 'top.cpu.alu.x')),
        isNull,
      );
      expect(signalTreeFirstChildIndex(rows, rows.length - 1), isNull);
    });
  });

  group('resolveSignalTreeActiveIndex', () {
    test('finds the same row after rows above it change', () {
      final item = signalTreeRowItem(rows[_indexOf(rows, 'top.clk')]);
      final fewer = signalTreeRowsInOrder(
        scopes,
        expandedPaths: const {'top'},
      );
      expect(
        resolveSignalTreeActiveIndex(fewer, item: item, previousIndex: 7),
        _indexOf(fewer, 'top.clk'),
      );
    });

    test('a collapsed-away row resolves to the nearest visible scope', () {
      final item = signalTreeRowItem(rows[_indexOf(rows, 'top.cpu.alu.y')]);
      final collapsed = signalTreeRowsInOrder(
        scopes,
        expandedPaths: const {'top', 'top.cpu'},
      );
      expect(
        resolveSignalTreeActiveIndex(collapsed, item: item, previousIndex: 4),
        _indexOf(collapsed, 'top.cpu.alu'),
      );

      final allCollapsed = signalTreeRowsInOrder(
        scopes,
        expandedPaths: const {},
      );
      expect(
        resolveSignalTreeActiveIndex(
          allCollapsed,
          item: item,
          previousIndex: 4,
        ),
        0,
      );
    });

    test('a hidden nested scope resolves to its visible ancestor', () {
      final item = signalTreeRowItem(rows[_indexOf(rows, 'top.cpu.alu')]);
      final collapsed = signalTreeRowsInOrder(
        scopes,
        expandedPaths: const {'top'},
      );
      expect(
        resolveSignalTreeActiveIndex(collapsed, item: item, previousIndex: 2),
        _indexOf(collapsed, 'top.cpu'),
      );
    });

    test('a rebuilt hierarchy matches the same path', () {
      final item = signalTreeRowItem(rows[_indexOf(rows, 'top.cpu.b')]);
      final rebuilt = signalTreeRowsInOrder(
        _tree(),
        expandedPaths: _allExpanded,
      );
      expect(
        resolveSignalTreeActiveIndex(rebuilt, item: item, previousIndex: 0),
        _indexOf(rebuilt, 'top.cpu.b'),
      );
    });

    test('of two rows with one path, the one nearest the old index wins', () {
      final twin1 = _v('dup');
      final twin2 = _v('dup');
      final twins = [
        _s('top', variables: [twin1, _v('m'), twin2]),
      ];
      final twinRows = signalTreeRowsInOrder(
        twins,
        expandedPaths: const {'top'},
      );
      // A different instance with the same path, as after a reload.
      final stranger = _v('dup');
      expect(
        resolveSignalTreeActiveIndex(
          twinRows,
          item: stranger,
          previousIndex: 3,
        ),
        3,
      );
      expect(
        resolveSignalTreeActiveIndex(
          twinRows,
          item: stranger,
          previousIndex: 1,
        ),
        1,
      );
      // The instance itself always wins over a twin that shares its path.
      expect(
        resolveSignalTreeActiveIndex(twinRows, item: twin2, previousIndex: 1),
        3,
      );
    });

    test('with nothing remembered, the old index is clamped', () {
      expect(
        resolveSignalTreeActiveIndex(rows, item: null, previousIndex: 99),
        rows.length - 1,
      );
      expect(
        resolveSignalTreeActiveIndex(rows, item: null, previousIndex: -3),
        0,
      );
      expect(
        resolveSignalTreeActiveIndex(
          const [],
          item: scopes.first,
          previousIndex: 5,
        ),
        0,
      );
    });

    test('an item from another hierarchy falls back to the old index', () {
      final foreign = _v('ghost', scopePath: 'elsewhere');
      expect(
        resolveSignalTreeActiveIndex(rows, item: foreign, previousIndex: 2),
        2,
      );
    });
  });
}
