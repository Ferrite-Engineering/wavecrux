// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/utils/variable_tree_order.dart';

Variable _v(String name, String scopePath) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: '$scopePath.$name',
  scopePath: scopePath,
  bitWidth: 1,
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

/// ```text
/// top
/// ├── a        (x, y)
/// ├── b        (z)
/// ├── u
/// └── v
/// ```
/// Rendered order (everything expanded): child scopes before variables,
/// so rows read a.x, a.y, b.z, top.u, top.v.
List<Scope> _tree() => [
  _scope(
    'top',
    'top',
    variables: [_v('u', 'top'), _v('v', 'top')],
    childScopes: [
      _scope('a', 'top.a', variables: [_v('x', 'top.a'), _v('y', 'top.a')]),
      _scope('b', 'top.b', variables: [_v('z', 'top.b')]),
    ],
  ),
];

List<String> _refs(List<Variable> vars) => [for (final v in vars) v.signalRef];

void main() {
  group('variablesInTreeOrder — full order (expandedPaths null)', () {
    test('child scopes come before variables, matching the rendered rows', () {
      expect(_refs(variablesInTreeOrder(_tree())), [
        'top.a.x',
        'top.a.y',
        'top.b.z',
        'top.u',
        'top.v',
      ]);
    });

    test('multiple root scopes flatten in declaration order', () {
      final roots = [
        _scope('t1', 't1', variables: [_v('p', 't1')]),
        _scope('t2', 't2', variables: [_v('q', 't2')]),
      ];
      expect(_refs(variablesInTreeOrder(roots)), ['t1.p', 't2.q']);
    });

    test('empty hierarchy yields empty list', () {
      expect(variablesInTreeOrder(const []), isEmpty);
    });
  });

  group('variablesInTreeOrder — visible order (expandedPaths set)', () {
    test('collapsed root yields nothing', () {
      expect(
        variablesInTreeOrder(_tree(), expandedPaths: const {}),
        isEmpty,
      );
    });

    test('expanded root shows own variables but not collapsed children', () {
      expect(
        _refs(variablesInTreeOrder(_tree(), expandedPaths: const {'top'})),
        ['top.u', 'top.v'],
      );
    });

    test('expanding one child reveals its variables in position', () {
      expect(
        _refs(
          variablesInTreeOrder(
            _tree(),
            expandedPaths: const {'top', 'top.a'},
          ),
        ),
        ['top.a.x', 'top.a.y', 'top.u', 'top.v'],
      );
    });
  });

  group('variablesInTreeOrder — search query filter', () {
    test('drops non-matching variables and prunes non-matching scopes', () {
      expect(
        _refs(variablesInTreeOrder(_tree(), searchQuery: 'x')),
        ['top.a.x'],
      );
    });

    test('match is case-insensitive', () {
      expect(
        _refs(variablesInTreeOrder(_tree(), searchQuery: 'X')),
        ['top.a.x'],
      );
    });

    test('query composes with expansion state', () {
      // 'top.a' matches the query but is collapsed → nothing visible.
      expect(
        variablesInTreeOrder(
          _tree(),
          expandedPaths: const {'top'},
          searchQuery: 'x',
        ),
        isEmpty,
      );
    });

    test('root scope with no matching descendant is pruned entirely', () {
      expect(
        variablesInTreeOrder(_tree(), searchQuery: 'nomatch'),
        isEmpty,
      );
    });
  });

  group('ScopeMatchIndex.matchesScope', () {
    bool matches(Scope scope, String query) =>
        ScopeMatchIndex.build([scope], query).matchesScope(scope);

    test('matches a direct variable', () {
      expect(matches(_tree().single, 'u'), isTrue);
    });

    test('matches a deep descendant variable', () {
      expect(matches(_tree().single, 'z'), isTrue);
    });

    test('no match returns false', () {
      expect(matches(_tree().single, 'nope'), isFalse);
    });
  });

  // ── complexity guard ──────────────────────────────────────────────────────

  group('ScopeMatchIndex complexity', () {
    /// A single chain of [depth] scopes, each holding one variable — the
    /// shape that punishes a per-ancestor rescan hardest, because every
    /// level re-walks the entire remaining subtree.
    List<Scope> chain(int depth) {
      Scope build(int level) => _scope(
        's$level',
        List.generate(level + 1, (i) => 's$i').join('.'),
        variables: [
          _v('sig$level', List.generate(level + 1, (i) => 's$i').join('.')),
        ],
        childScopes: level + 1 < depth ? [build(level + 1)] : const [],
      );
      return [build(0)];
    }

    test('scope visits stay linear in scope count, not depth x count', () {
      const depth = 200;
      final roots = chain(depth);

      ScopeMatchIndex.build(roots, 'sig');
      expect(ScopeMatchIndex.debugLastBuildVisits, depth);

      // A filter that matches nothing must not cost more either — the
      // bottom-up pass has no early-exit asymmetry to exploit.
      ScopeMatchIndex.build(roots, 'nomatch');
      expect(ScopeMatchIndex.debugLastBuildVisits, depth);
    });

    test('an empty query does not traverse at all', () {
      ScopeMatchIndex.debugLastBuildVisits = -1;
      final index = ScopeMatchIndex.build(chain(200), '');
      expect(ScopeMatchIndex.debugLastBuildVisits, -1);
      expect(index.isEmpty, isTrue);
    });

    test('flattening a deep chain builds the index exactly once', () {
      const depth = 200;
      final roots = chain(depth);
      final expanded = {
        for (var i = 0; i < depth; i++)
          List.generate(i + 1, (j) => 's$j').join('.'),
      };

      final vars = variablesInTreeOrder(
        roots,
        expandedPaths: expanded,
        searchQuery: 'sig',
      );
      expect(vars, hasLength(depth));
      expect(ScopeMatchIndex.debugLastBuildVisits, depth);
    });

    test('a shared index is reused rather than rebuilt', () {
      const depth = 50;
      final roots = chain(depth);
      final index = ScopeMatchIndex.build(roots, 'sig');

      ScopeMatchIndex.debugLastBuildVisits = -1;
      final vars = variablesInTreeOrder(roots, matchIndex: index);
      expect(vars, hasLength(depth));
      expect(ScopeMatchIndex.debugLastBuildVisits, -1);
    });
  });
}
