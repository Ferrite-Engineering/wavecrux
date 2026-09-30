// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/search_mode.dart';
import 'package:wavecrux/domain/enums/signal_direction.dart';
import 'package:wavecrux/domain/enums/signal_type_category.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/search/providers/search_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Variable _makeVar(String name, {String scopePath = 'top'}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: '$scopePath.$name',
  scopePath: scopePath,
  bitWidth: 8,
);

Scope _makeScope(String name, {List<Variable> variables = const []}) => Scope(
  name: name,
  type: ScopeType.module,
  path: 'top.$name',
  variables: variables,
);

ProviderContainer _makeContainer({List<Scope>? scopes}) {
  final container = ProviderContainer(
    overrides: [
      if (scopes != null)
        hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  // ── SearchDialogFilter model ──────────────────────────────────────────────

  group('SearchDialogFilter', () {
    test('default filter has isDefault == true', () {
      const f = SearchDialogFilter();
      expect(f.isDefault, isTrue);
    });

    test('non-empty query makes isDefault false', () {
      const f = SearchDialogFilter(query: 'clk');
      expect(f.isDefault, isFalse);
    });

    test('selected categories makes isDefault false', () {
      const f = SearchDialogFilter(
        selectedCategories: {SignalTypeCategory.wire},
      );
      expect(f.isDefault, isFalse);
    });

    test('minBitWidth set makes isDefault false', () {
      const f = SearchDialogFilter(minBitWidth: 8);
      expect(f.isDefault, isFalse);
    });

    test('maxBitWidth set makes isDefault false', () {
      const f = SearchDialogFilter(maxBitWidth: 32);
      expect(f.isDefault, isFalse);
    });

    test('scopePath set makes isDefault false', () {
      const f = SearchDialogFilter(scopePath: 'top.cpu');
      expect(f.isDefault, isFalse);
    });

    test('empty string scopePath keeps isDefault true', () {
      const f = SearchDialogFilter(scopePath: '');
      expect(f.isDefault, isTrue);
    });

    test('copyWith updates query', () {
      const f = SearchDialogFilter();
      expect(f.copyWith(query: 'clk').query, 'clk');
    });

    test('copyWith updates mode', () {
      const f = SearchDialogFilter();
      expect(f.copyWith(mode: SearchMode.glob).mode, SearchMode.glob);
    });

    test('copyWith clears minBitWidth', () {
      const f = SearchDialogFilter(minBitWidth: 8);
      expect(f.copyWith(clearMinBitWidth: true).minBitWidth, isNull);
    });

    test('copyWith clears maxBitWidth', () {
      const f = SearchDialogFilter(maxBitWidth: 32);
      expect(f.copyWith(clearMaxBitWidth: true).maxBitWidth, isNull);
    });

    test('copyWith clears scopePath', () {
      const f = SearchDialogFilter(scopePath: 'top.cpu');
      expect(f.copyWith(clearScopePath: true).scopePath, isNull);
    });

    test('equality: two identical filters are equal', () {
      const a = SearchDialogFilter(query: 'clk', mode: SearchMode.glob);
      const b = SearchDialogFilter(query: 'clk', mode: SearchMode.glob);
      expect(a, b);
    });

    test('equality: different query → not equal', () {
      const a = SearchDialogFilter(query: 'clk');
      const b = SearchDialogFilter(query: 'data');
      expect(a, isNot(b));
    });

    test(
      'equality: selectedCategories compared as set (order-independent)',
      () {
        const a = SearchDialogFilter(
          selectedCategories: {SignalTypeCategory.wire, SignalTypeCategory.reg},
        );
        const b = SearchDialogFilter(
          selectedCategories: {SignalTypeCategory.reg, SignalTypeCategory.wire},
        );
        expect(a, b);
      },
    );

    test('hashCode: equal objects have equal hash codes', () {
      const a = SearchDialogFilter(query: 'clk');
      const b = SearchDialogFilter(query: 'clk');
      expect(a.hashCode, b.hashCode);
    });
  });

  // ── SearchDialogFilterNotifier ────────────────────────────────────────────

  group('SearchDialogFilterNotifier', () {
    test('initial state has default filter', () {
      final c = _makeContainer();
      expect(c.read(searchDialogFilterProvider).isDefault, isTrue);
    });

    test('setQuery updates the query field', () {
      final c = _makeContainer();
      c.read(searchDialogFilterProvider.notifier).setQuery('clk');
      expect(c.read(searchDialogFilterProvider).query, 'clk');
    });

    test('setMode updates the mode field', () {
      final c = _makeContainer();
      c.read(searchDialogFilterProvider.notifier).setMode(SearchMode.glob);
      expect(
        c.read(searchDialogFilterProvider).mode,
        SearchMode.glob,
      );
    });

    test('toggleCategory adds a category not present', () {
      final c = _makeContainer();
      c
          .read(searchDialogFilterProvider.notifier)
          .toggleCategory(SignalTypeCategory.wire);
      expect(
        c.read(searchDialogFilterProvider).selectedCategories,
        contains(SignalTypeCategory.wire),
      );
    });

    test('toggleCategory removes a category already present', () {
      final c = _makeContainer();
      c.read(searchDialogFilterProvider.notifier)
        ..toggleCategory(SignalTypeCategory.wire)
        ..toggleCategory(SignalTypeCategory.wire);
      expect(
        c.read(searchDialogFilterProvider).selectedCategories,
        isNot(contains(SignalTypeCategory.wire)),
      );
    });

    test('setMinBitWidth sets the value', () {
      final c = _makeContainer();
      c.read(searchDialogFilterProvider.notifier).setMinBitWidth(4);
      expect(c.read(searchDialogFilterProvider).minBitWidth, 4);
    });

    test('setMinBitWidth(null) clears the value', () {
      final c = _makeContainer();
      c.read(searchDialogFilterProvider.notifier)
        ..setMinBitWidth(4)
        ..setMinBitWidth(null);
      expect(
        c.read(searchDialogFilterProvider).minBitWidth,
        isNull,
      );
    });

    test('setMaxBitWidth sets the value', () {
      final c = _makeContainer();
      c.read(searchDialogFilterProvider.notifier).setMaxBitWidth(32);
      expect(c.read(searchDialogFilterProvider).maxBitWidth, 32);
    });

    test('setMaxBitWidth(null) clears the value', () {
      final c = _makeContainer();
      c.read(searchDialogFilterProvider.notifier)
        ..setMaxBitWidth(32)
        ..setMaxBitWidth(null);
      expect(
        c.read(searchDialogFilterProvider).maxBitWidth,
        isNull,
      );
    });

    test('setScopePath sets the value', () {
      final c = _makeContainer();
      c.read(searchDialogFilterProvider.notifier).setScopePath('top.cpu');
      expect(
        c.read(searchDialogFilterProvider).scopePath,
        'top.cpu',
      );
    });

    test('setScopePath with empty string clears the value', () {
      final c = _makeContainer();
      c.read(searchDialogFilterProvider.notifier)
        ..setScopePath('top.cpu')
        ..setScopePath('');
      expect(
        c.read(searchDialogFilterProvider).scopePath,
        isNull,
      );
    });

    test('reset returns state to default', () {
      final c = _makeContainer();
      c.read(searchDialogFilterProvider.notifier)
        ..setQuery('clk')
        ..toggleCategory(SignalTypeCategory.wire)
        ..setMinBitWidth(4)
        ..reset();
      expect(c.read(searchDialogFilterProvider).isDefault, isTrue);
    });
  });

  // ── searchResultsProvider ─────────────────────────────────────────────────

  group('searchResultsProvider', () {
    test(
      'returns all variables when filter is default and hierarchy is loaded',
      () {
        final clk = _makeVar('clk');
        final data = _makeVar('data');
        final c = _makeContainer(
          scopes: [
            _makeScope('cpu', variables: [clk, data]),
          ],
        );
        final results = c.read(searchResultsProvider);
        expect(results.map((r) => r.variable), containsAll([clk, data]));
      },
    );

    test('returns empty list when no waveform is loaded', () {
      final c = _makeContainer();
      expect(c.read(searchResultsProvider), isEmpty);
    });

    test('filters by query after setQuery', () {
      final clk = _makeVar('clk');
      final data = _makeVar('data');
      final c = _makeContainer(
        scopes: [
          _makeScope('cpu', variables: [clk, data]),
        ],
      );
      c.read(searchDialogFilterProvider.notifier).setQuery('clk');
      final results = c.read(searchResultsProvider);
      expect(results.map((r) => r.variable).toList(), [clk]);
    });

    test('filters by type category', () {
      final wire = _makeVar('clk');
      const reg = Variable(
        name: 'cnt',
        varType: VarType.reg,
        direction: VarDirection.unknown,
        signalRef: 'top.cnt',
        scopePath: 'top',
        bitWidth: 8,
      );
      final c = _makeContainer(
        scopes: [
          _makeScope('cpu', variables: [wire, reg]),
        ],
      );
      c
          .read(searchDialogFilterProvider.notifier)
          .toggleCategory(SignalTypeCategory.wire);
      final results = c.read(searchResultsProvider);
      expect(results.map((r) => r.variable).toList(), [wire]);
    });

    test('reacts to filter changes', () {
      final clk = _makeVar('clk');
      final data = _makeVar('data');
      final c = _makeContainer(
        scopes: [
          _makeScope('cpu', variables: [clk, data]),
        ],
      );

      expect(c.read(searchResultsProvider), hasLength(2));

      c.read(searchDialogFilterProvider.notifier).setQuery('clk');

      expect(c.read(searchResultsProvider), hasLength(1));
      expect(c.read(searchResultsProvider).first.variable, clk);
    });
  });

  // ── SearchDialogFilter direction field ─────────────────────────────────────

  group('SearchDialogFilter direction', () {
    test('default selectedDirections is empty set', () {
      const f = SearchDialogFilter();
      expect(f.selectedDirections, isEmpty);
    });

    test('non-empty selectedDirections makes isDefault false', () {
      const f = SearchDialogFilter(
        selectedDirections: {SignalDirection.input},
      );
      expect(f.isDefault, isFalse);
    });

    test('copyWith updates selectedDirections', () {
      const f = SearchDialogFilter();
      final updated = f.copyWith(
        selectedDirections: {SignalDirection.output},
      );
      expect(updated.selectedDirections, {SignalDirection.output});
    });

    test('copyWith clearSelectedDirections resets to empty', () {
      const f = SearchDialogFilter(
        selectedDirections: {SignalDirection.input},
      );
      final cleared = f.copyWith(clearSelectedDirections: true);
      expect(cleared.selectedDirections, isEmpty);
    });

    test('equality: same selectedDirections are equal (order-independent)', () {
      const a = SearchDialogFilter(
        selectedDirections: {SignalDirection.input, SignalDirection.output},
      );
      const b = SearchDialogFilter(
        selectedDirections: {SignalDirection.output, SignalDirection.input},
      );
      expect(a, b);
    });

    test('equality: different selectedDirections are not equal', () {
      const a = SearchDialogFilter(
        selectedDirections: {SignalDirection.input},
      );
      const b = SearchDialogFilter(
        selectedDirections: {SignalDirection.output},
      );
      expect(a, isNot(b));
    });

    test('hashCode: equal direction filters have equal hash codes', () {
      const a = SearchDialogFilter(
        selectedDirections: {SignalDirection.input},
      );
      const b = SearchDialogFilter(
        selectedDirections: {SignalDirection.input},
      );
      expect(a.hashCode, b.hashCode);
    });
  });

  // ── SearchDialogFilterNotifier.toggleDirection ─────────────────────────────

  group('SearchDialogFilterNotifier.toggleDirection', () {
    test('toggleDirection adds direction not present', () {
      final c = _makeContainer();
      c
          .read(searchDialogFilterProvider.notifier)
          .toggleDirection(SignalDirection.input);
      expect(
        c.read(searchDialogFilterProvider).selectedDirections,
        contains(SignalDirection.input),
      );
    });

    test('toggleDirection removes direction already present', () {
      final c = _makeContainer();
      c.read(searchDialogFilterProvider.notifier)
        ..toggleDirection(SignalDirection.output)
        ..toggleDirection(SignalDirection.output);
      expect(
        c.read(searchDialogFilterProvider).selectedDirections,
        isNot(contains(SignalDirection.output)),
      );
    });

    test('reset clears selectedDirections', () {
      final c = _makeContainer();
      c.read(searchDialogFilterProvider.notifier)
        ..toggleDirection(SignalDirection.input)
        ..reset();
      expect(
        c.read(searchDialogFilterProvider).selectedDirections,
        isEmpty,
      );
    });
  });

  // ── searchResultsProvider with direction filter ────────────────────────────

  group('searchResultsProvider direction filtering', () {
    Variable makeDirectionVar(String name, VarDirection dir) => Variable(
      name: name,
      varType: VarType.port,
      direction: dir,
      signalRef: 'top.$name',
      scopePath: 'top',
      bitWidth: 1,
    );

    test('direction filter restricts results via toggleDirection', () {
      final inputVar = makeDirectionVar('addr', VarDirection.input);
      final outputVar = makeDirectionVar('data', VarDirection.output);
      final c = _makeContainer(
        scopes: [
          _makeScope('cpu', variables: [inputVar, outputVar]),
        ],
      );
      c
          .read(searchDialogFilterProvider.notifier)
          .toggleDirection(SignalDirection.input);
      final results = c.read(searchResultsProvider);
      expect(results.map((r) => r.variable).toList(), [inputVar]);
    });

    test('GTKWave +I+ prefix in query filters by input direction', () {
      final inputVar = makeDirectionVar('addr', VarDirection.input);
      final outputVar = makeDirectionVar('data', VarDirection.output);
      final c = _makeContainer(
        scopes: [
          _makeScope('cpu', variables: [inputVar, outputVar]),
        ],
      );
      c.read(searchDialogFilterProvider.notifier).setQuery('+I+');
      final results = c.read(searchResultsProvider);
      expect(results.map((r) => r.variable).toList(), [inputVar]);
    });
  });
}
