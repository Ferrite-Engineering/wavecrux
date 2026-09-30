// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Variable _makeVar(String name, {String scopePath = 'top'}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: '$scopePath.$name',
  scopePath: scopePath,
  bitWidth: 1,
);

Scope _makeScope(String name, {List<Variable> vars = const []}) => Scope(
  name: name,
  type: ScopeType.module,
  path: 'top.$name',
  variables: vars,
);

void main() {
  // ── ExpandedScopesNotifier ────────────────────────────────────────────────

  group('ExpandedScopesNotifier', () {
    test('initial state is empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(expandedScopesProvider), isEmpty);
    });

    test('toggle adds a path that was not present', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(expandedScopesProvider.notifier).toggle('top.cpu');

      expect(
        container.read(expandedScopesProvider),
        contains('top.cpu'),
      );
    });

    test('toggle removes a path that was present', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(expandedScopesProvider.notifier)
        ..toggle('top.cpu')
        ..toggle('top.cpu');

      expect(
        container.read(expandedScopesProvider),
        isNot(contains('top.cpu')),
      );
    });

    test('expandAll adds all scope paths', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final child = _makeScope('alu');
      final root = Scope(
        name: 'top',
        type: ScopeType.module,
        path: 'top',
        childScopes: [child],
      );

      container.read(expandedScopesProvider.notifier).expandAll([root]);

      final expanded = container.read(expandedScopesProvider);
      expect(expanded, containsAll(['top', 'top.alu']));
    });

    test('collapseAll empties the set', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(expandedScopesProvider.notifier)
        ..toggle('a')
        ..toggle('b')
        ..collapseAll();

      expect(container.read(expandedScopesProvider), isEmpty);
    });

    test('expandAncestorsOf expands every prefix of the scope path', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // The cross-probe reveal expands the containing scope + all ancestors so
      // the leaf row materializes.
      container
          .read(expandedScopesProvider.notifier)
          .expandAncestorsOf('top.cpu.alu');

      expect(
        container.read(expandedScopesProvider),
        containsAll(['top', 'top.cpu', 'top.cpu.alu']),
      );
    });

    test('expandAncestorsOf preserves already-expanded siblings', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(expandedScopesProvider.notifier)
        ..toggle('top.mmu')
        ..expandAncestorsOf('top.cpu.alu');

      expect(
        container.read(expandedScopesProvider),
        containsAll(['top.mmu', 'top', 'top.cpu', 'top.cpu.alu']),
      );
    });

    test('expandAncestorsOf is a no-op for an empty path', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(expandedScopesProvider.notifier).expandAncestorsOf('');

      expect(container.read(expandedScopesProvider), isEmpty);
    });

    // ── expandMatchingScopes ──────────────────────────────────────────────────

    group('expandMatchingScopes', () {
      Scope scopeWith(
        String name,
        String path, {
        List<Variable> vars = const [],
        List<Scope> children = const [],
      }) => Scope(
        name: name,
        type: ScopeType.module,
        path: path,
        variables: vars,
        childScopes: children,
      );

      Variable varNamed(String name, String scopePath) => Variable(
        name: name,
        varType: VarType.wire,
        direction: VarDirection.unknown,
        signalRef: '$scopePath.$name',
        scopePath: scopePath,
        bitWidth: 1,
      );

      test('empty query does nothing', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final root = scopeWith(
          'top',
          'top',
          vars: [varNamed('clk', 'top')],
        );
        container.read(expandedScopesProvider.notifier).expandMatchingScopes([
          root,
        ], '');

        expect(container.read(expandedScopesProvider), isEmpty);
      });

      test('no matching variables leaves expanded set empty', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final root = scopeWith(
          'top',
          'top',
          vars: [varNamed('data', 'top')],
        );
        container.read(expandedScopesProvider.notifier).expandMatchingScopes([
          root,
        ], 'zzz');

        expect(container.read(expandedScopesProvider), isEmpty);
      });

      test('expands the scope that directly contains a matching variable', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final root = scopeWith(
          'top',
          'top',
          vars: [varNamed('clk', 'top')],
        );
        container.read(expandedScopesProvider.notifier).expandMatchingScopes([
          root,
        ], 'clk');

        expect(
          container.read(expandedScopesProvider),
          contains('top'),
        );
      });

      test('expands all ancestor scopes of a deeply nested match', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final leaf = scopeWith(
          'alu',
          'top.cpu.alu',
          vars: [varNamed('clk', 'top.cpu.alu')],
        );
        final mid = scopeWith('cpu', 'top.cpu', children: [leaf]);
        final root = scopeWith('top', 'top', children: [mid]);

        container.read(expandedScopesProvider.notifier).expandMatchingScopes([
          root,
        ], 'clk');

        final expanded = container.read(expandedScopesProvider);
        expect(expanded, containsAll(['top', 'top.cpu', 'top.cpu.alu']));
      });

      test('does not expand scopes with no matching descendants', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final alu = scopeWith(
          'alu',
          'top.alu',
          vars: [varNamed('clk', 'top.alu')],
        );
        final mmu = scopeWith(
          'mmu',
          'top.mmu',
          vars: [varNamed('addr', 'top.mmu')],
        );
        final root = scopeWith('top', 'top', children: [alu, mmu]);

        container.read(expandedScopesProvider.notifier).expandMatchingScopes([
          root,
        ], 'clk');

        final expanded = container.read(expandedScopesProvider);
        expect(expanded, contains('top'));
        expect(expanded, contains('top.alu'));
        expect(expanded, isNot(contains('top.mmu')));
      });

      test('match is case-insensitive', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final root = scopeWith(
          'top',
          'top',
          vars: [varNamed('CLK_OUT', 'top')],
        );
        container.read(expandedScopesProvider.notifier).expandMatchingScopes([
          root,
        ], 'clk');

        expect(
          container.read(expandedScopesProvider),
          contains('top'),
        );
      });

      test('handles multiple root scopes', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final a = scopeWith('a', 'a', vars: [varNamed('clk', 'a')]);
        final b = scopeWith('b', 'b', vars: [varNamed('data', 'b')]);
        final c = scopeWith('c', 'c', vars: [varNamed('clk_en', 'c')]);

        container.read(expandedScopesProvider.notifier).expandMatchingScopes([
          a,
          b,
          c,
        ], 'clk');

        final expanded = container.read(expandedScopesProvider);
        expect(expanded, containsAll(['a', 'c']));
        expect(expanded, isNot(contains('b')));
      });

      test('saves pre-search state on first call', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Pre-search: user has 'top.mmu' expanded.
        container.read(expandedScopesProvider.notifier).toggle('top.mmu');

        final leaf = scopeWith(
          'alu',
          'top.alu',
          vars: [varNamed('clk', 'top.alu')],
        );
        final root = scopeWith('top', 'top', children: [leaf]);

        container.read(expandedScopesProvider.notifier).expandMatchingScopes([
          root,
        ], 'clk');

        // After expand, the set is search-driven (mmu gone, alu added).
        final expanded = container.read(expandedScopesProvider);
        expect(expanded, contains('top'));
        expect(expanded, contains('top.alu'));
        expect(expanded, isNot(contains('top.mmu')));
      });

      test(
        'successive calls with different queries do not clobber saved state',
        () {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          final aluScope = scopeWith(
            'alu',
            'top.alu',
            vars: [varNamed('clk', 'top.alu')],
          );
          final mmuScope = scopeWith(
            'mmu',
            'top.mmu',
            vars: [varNamed('addr', 'top.mmu')],
          );
          final root = scopeWith('top', 'top', children: [aluScope, mmuScope]);

          // Simulate the user having 'top.mmu' expanded before any search.
          container.read(expandedScopesProvider.notifier).toggle('top.mmu');

          container.read(expandedScopesProvider.notifier)
            // First search: saves {'top.mmu'} as the pre-search state.
            ..expandMatchingScopes([root], 'clk')
            // Second search: should NOT overwrite the saved state.
            ..expandMatchingScopes([root], 'addr')
            // Restore should bring back the original {'top.mmu'} state.
            ..restoreState();

          expect(
            container.read(expandedScopesProvider),
            equals({'top.mmu'}),
          );
        },
      );
    });

    // ── restoreState ──────────────────────────────────────────────────────────

    group('restoreState', () {
      test('no-op when no saved state exists', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(expandedScopesProvider.notifier).toggle('top');
        container.read(expandedScopesProvider.notifier).restoreState();

        // State is unchanged since nothing was saved.
        expect(
          container.read(expandedScopesProvider),
          contains('top'),
        );
      });

      test('restores saved state and clears snapshot', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        const leaf = Scope(
          name: 'alu',
          type: ScopeType.module,
          path: 'top.alu',
          variables: [
            Variable(
              name: 'clk',
              varType: VarType.wire,
              direction: VarDirection.unknown,
              signalRef: 'top.alu.clk',
              scopePath: 'top.alu',
              bitWidth: 1,
            ),
          ],
        );
        const root = Scope(
          name: 'top',
          type: ScopeType.module,
          path: 'top',
          childScopes: [leaf],
        );

        // User pre-search state: {'top.mmu'}.
        container.read(expandedScopesProvider.notifier).toggle('top.mmu');

        container.read(expandedScopesProvider.notifier).expandMatchingScopes([
          root,
        ], 'clk');

        container.read(expandedScopesProvider.notifier).restoreState();

        expect(
          container.read(expandedScopesProvider),
          equals({'top.mmu'}),
        );
      });

      test(
        'second restoreState call is a no-op after snapshot was cleared',
        () {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          const root = Scope(
            name: 'top',
            type: ScopeType.module,
            path: 'top',
            variables: [
              Variable(
                name: 'clk',
                varType: VarType.wire,
                direction: VarDirection.unknown,
                signalRef: 'top.clk',
                scopePath: 'top',
                bitWidth: 1,
              ),
            ],
          );

          container.read(expandedScopesProvider.notifier).toggle('top.saved');

          container.read(expandedScopesProvider.notifier).expandMatchingScopes([
            root,
          ], 'clk');

          // First restore — brings back {'top.saved'}.
          container.read(expandedScopesProvider.notifier).restoreState();

          // Manually change state after restore.
          container.read(expandedScopesProvider.notifier).toggle('top.new');

          // Second restore — no-op because snapshot was already cleared.
          container.read(expandedScopesProvider.notifier).restoreState();

          expect(
            container.read(expandedScopesProvider),
            containsAll(['top.saved', 'top.new']),
          );
        },
      );
    });
  });

  // ── SelectedVariablesNotifier ─────────────────────────────────────────────

  group('SelectedVariablesNotifier', () {
    test('initial state is empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(selectedVariablesProvider), isEmpty);
    });

    test('toggle adds a ref not present', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(selectedVariablesProvider.notifier).toggle('top.clk');

      expect(
        container.read(selectedVariablesProvider),
        contains('top.clk'),
      );
    });

    test('toggle removes a ref that was present', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(selectedVariablesProvider.notifier)
        ..toggle('top.clk')
        ..toggle('top.clk');

      expect(
        container.read(selectedVariablesProvider),
        isNot(contains('top.clk')),
      );
    });

    test('selectOnly replaces entire selection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(selectedVariablesProvider.notifier)
        ..toggle('a')
        ..toggle('b')
        ..selectOnly('c');

      expect(container.read(selectedVariablesProvider), {'c'});
    });

    test('clear empties the selection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(selectedVariablesProvider.notifier)
        ..toggle('a')
        ..clear();

      expect(container.read(selectedVariablesProvider), isEmpty);
    });

    group('selectRangeTo (Shift+click)', () {
      const order = ['a', 'b', 'c', 'd', 'e'];

      test('with no anchor selects only the target', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container
            .read(selectedVariablesProvider.notifier)
            .selectRangeTo('c', order);

        expect(container.read(selectedVariablesProvider), {'c'});
      });

      test('ranges downward from the toggle anchor, inclusive', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(selectedVariablesProvider.notifier)
          ..toggle('b')
          ..selectRangeTo('d', order);

        expect(container.read(selectedVariablesProvider), {'b', 'c', 'd'});
      });

      test('ranges upward when the target precedes the anchor', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(selectedVariablesProvider.notifier)
          ..toggle('d')
          ..selectRangeTo('a', order);

        expect(
          container.read(selectedVariablesProvider),
          {'a', 'b', 'c', 'd'},
        );
      });

      test('successive shift-clicks re-range from the same anchor', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(selectedVariablesProvider.notifier)
          ..toggle('c')
          ..selectRangeTo('e', order)
          ..selectRangeTo('a', order);

        expect(container.read(selectedVariablesProvider), {'a', 'b', 'c'});
      });

      test('ranges from a selectOnly anchor (the plain-tap path)', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(selectedVariablesProvider.notifier)
          ..selectOnly('b')
          ..selectRangeTo('d', order);

        expect(container.read(selectedVariablesProvider), {'b', 'c', 'd'});
      });

      test('falls back to single selection when anchor is not visible', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(selectedVariablesProvider.notifier)
          ..toggle('hidden.ref')
          ..selectRangeTo('c', order);

        expect(container.read(selectedVariablesProvider), {'c'});
      });

      test('replaces a prior toggle selection with the range', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(selectedVariablesProvider.notifier)
          ..toggle('e')
          ..toggle('a')
          ..selectRangeTo('b', order);

        expect(container.read(selectedVariablesProvider), {'a', 'b'});
      });
    });
  });

  // ── SignalSearchQueryNotifier ─────────────────────────────────────────────

  group('SignalSearchQueryNotifier', () {
    test('initial state is empty string', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(signalSearchQueryProvider), '');
    });

    test('setQuery updates the query', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(signalSearchQueryProvider.notifier).setQuery(query: 'clk');

      expect(container.read(signalSearchQueryProvider), 'clk');
    });

    test('clear resets to empty string', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(signalSearchQueryProvider.notifier)
        ..setQuery(query: 'clk')
        ..clear();

      expect(container.read(signalSearchQueryProvider), '');
    });
  });

  // ── SignalGroupsNotifier ──────────────────────────────────────────────────

  group('SignalGroupsNotifier', () {
    test('initial state is empty SignalGroup', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(signalGroupsProvider).entries, isEmpty);
    });

    test('addSignal appends one entry', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final v = _makeVar('clk');
      container.read(signalGroupsProvider.notifier).addSignal(v);

      final entries = container.read(signalGroupsProvider).entries;
      expect(entries, hasLength(1));
      expect(entries.first.signalRef, v.signalRef);
      expect(entries.first.displayName, v.name);
    });

    test('addSignal assigns a non-null argbColor', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(signalGroupsProvider.notifier).addSignal(_makeVar('clk'));

      expect(
        container.read(signalGroupsProvider).entries.first.argbColor,
        isNotNull,
      );
    });

    test('addSignals appends all variables', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final vars = [_makeVar('clk'), _makeVar('data'), _makeVar('valid')];
      container.read(signalGroupsProvider.notifier).addSignals(vars);

      expect(
        container.read(signalGroupsProvider).entries,
        hasLength(3),
      );
    });

    test('addSignals with empty list does not change state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(signalGroupsProvider.notifier).addSignals([]);

      expect(
        container.read(signalGroupsProvider).entries,
        isEmpty,
      );
    });

    test('clear resets to empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(signalGroupsProvider.notifier)
        ..addSignal(_makeVar('clk'))
        ..clear();

      expect(
        container.read(signalGroupsProvider).entries,
        isEmpty,
      );
    });

    test(
      'successive addSignal calls assign different colors cycling palette',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(signalGroupsProvider.notifier);
        for (var i = 0; i < 3; i++) {
          notifier.addSignal(_makeVar('s$i'));
        }

        final colors = container
            .read(signalGroupsProvider)
            .entries
            .map((e) => e.argbColor)
            .toList();

        // At least the first two signals should have different colors.
        expect(colors[0], isNot(equals(colors[1])));
      },
    );
  });

  // ── session-restore helpers ──────────────────────────────────────────────────

  group('ExpandedScopesNotifier.applyExpanded (restore)', () {
    test('replaces the expanded set wholesale', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(expandedScopesProvider.notifier)
        ..toggle('top')
        ..applyExpanded({'top.cpu', 'top.cpu.alu'});
      expect(
        container.read(expandedScopesProvider),
        {'top.cpu', 'top.cpu.alu'},
      );
    });

    test('copies the input (later mutation of the source does not leak)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final source = {'top'};
      container.read(expandedScopesProvider.notifier).applyExpanded(source);
      source.add('top.cpu');
      expect(container.read(expandedScopesProvider), {'top'});
    });
  });

  group('SelectedVariablesNotifier.applySelection (restore)', () {
    test('replaces the selection wholesale', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(selectedVariablesProvider.notifier)
        ..toggle('a')
        ..applySelection({'top.clk', 'top.rst'});
      expect(
        container.read(selectedVariablesProvider),
        {'top.clk', 'top.rst'},
      );
    });
  });

  group('SignalTreeScrollNotifier', () {
    test('defaults to 0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(signalTreeScrollProvider), 0.0);
    });

    test('setOffset stores the latest offset', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(signalTreeScrollProvider.notifier).setOffset(128);
      expect(container.read(signalTreeScrollProvider), 128);
    });

    test('setOffset to the same value does not emit a new state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(signalTreeScrollProvider.notifier)
        ..setOffset(50);
      var rebuilds = 0;
      container.listen(signalTreeScrollProvider, (_, _) => rebuilds++);
      notifier.setOffset(50);
      expect(rebuilds, 0);
    });
  });
}
