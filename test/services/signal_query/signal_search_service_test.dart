// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/search_mode.dart';
import 'package:wavecrux/domain/enums/signal_direction.dart';
import 'package:wavecrux/domain/enums/signal_type_category.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/signal_query/signal_search_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Variable _makeVar(
  String name, {
  String scopePath = 'top',
  VarType varType = VarType.wire,
  int? bitWidth = 1,
}) => Variable(
  name: name,
  varType: varType,
  direction: VarDirection.unknown,
  signalRef: '$scopePath.$name',
  scopePath: scopePath,
  bitWidth: bitWidth,
);

Scope _makeScope(
  String name, {
  List<Variable> variables = const [],
  List<Scope> childScopes = const [],
}) => Scope(
  name: name,
  type: ScopeType.module,
  path: 'top.$name',
  variables: variables,
  childScopes: childScopes,
);

/// Returns only the [Variable]s from a [search] call (drops highlight info).
List<Variable> _searchVars(
  List<Variable> variables,
  String query, {
  SearchMode mode = SearchMode.substring,
  Set<SignalTypeCategory>? selectedCategories,
  int? minBitWidth,
  int? maxBitWidth,
  String? scopePath,
  Set<SignalDirection>? selectedDirections,
}) => SignalSearchService.search(
  variables: variables,
  query: query,
  mode: mode,
  selectedCategories: selectedCategories,
  minBitWidth: minBitWidth,
  maxBitWidth: maxBitWidth,
  scopePath: scopePath,
  selectedDirections: selectedDirections,
).map((r) => r.variable).toList();

Variable _makeVarWithDirection(
  String name,
  VarDirection direction, {
  String scopePath = 'top',
}) => Variable(
  name: name,
  varType: VarType.port,
  direction: direction,
  signalRef: '$scopePath.$name',
  scopePath: scopePath,
  bitWidth: 1,
);

void main() {
  // ── flattenVariables ──────────────────────────────────────────────────────

  group('flattenVariables', () {
    test('returns empty list for empty scopes', () {
      expect(SignalSearchService.flattenVariables([]), isEmpty);
    });

    test('returns top-level variables', () {
      final v = _makeVar('clk');
      final scope = _makeScope('cpu', variables: [v]);
      expect(SignalSearchService.flattenVariables([scope]), [v]);
    });

    test('returns variables from nested scopes in depth-first order', () {
      final v1 = _makeVar('a', scopePath: 'top.parent');
      final v2 = _makeVar('b', scopePath: 'top.parent.child');
      final child = _makeScope('child', variables: [v2]);
      final parent = _makeScope(
        'parent',
        variables: [v1],
        childScopes: [child],
      );
      expect(SignalSearchService.flattenVariables([parent]), [v1, v2]);
    });

    test('collects variables from multiple root scopes', () {
      final v1 = _makeVar('clk', scopePath: 'top.a');
      final v2 = _makeVar('data', scopePath: 'top.b');
      final result = SignalSearchService.flattenVariables([
        _makeScope('a', variables: [v1]),
        _makeScope('b', variables: [v2]),
      ]);
      expect(result, [v1, v2]);
    });
  });

  // ── Empty query ───────────────────────────────────────────────────────────

  group('empty query', () {
    test('returns all variables when query is empty', () {
      final vars = [_makeVar('clk'), _makeVar('data'), _makeVar('rst')];
      expect(_searchVars(vars, ''), vars);
    });

    test('returns empty list when variable list is empty', () {
      expect(_searchVars([], ''), isEmpty);
    });
  });

  // ── Substring matching ────────────────────────────────────────────────────

  group('substring mode', () {
    test('matches exact name', () {
      final clk = _makeVar('clk');
      final data = _makeVar('data');
      expect(_searchVars([clk, data], 'clk'), [clk]);
    });

    test('matches partial name', () {
      final axiData = _makeVar('axi_data');
      final axiValid = _makeVar('axi_valid');
      final rst = _makeVar('rst');
      expect(_searchVars([axiData, axiValid, rst], 'axi'), [axiData, axiValid]);
    });

    test('is case-insensitive for lowercase query', () {
      final clk = _makeVar('CLK');
      final data = _makeVar('data');
      expect(_searchVars([clk, data], 'clk'), [clk]);
    });

    test('is case-insensitive for uppercase query', () {
      final clk = _makeVar('CLK');
      expect(_searchVars([clk], 'CLK'), [clk]);
    });

    test('is case-insensitive for mixed-case query', () {
      final clk = _makeVar('CLK');
      expect(_searchVars([clk], 'Clk'), [clk]);
    });

    test('returns empty when no match', () {
      final vars = [_makeVar('clk'), _makeVar('data')];
      expect(_searchVars(vars, 'zzz_nomatch'), isEmpty);
    });

    test('treats * as literal character (no wildcards in substring mode)', () {
      // Only the signal whose name actually contains '*' matches.
      final star = _makeVar('axi_*_data');
      final rdata = _makeVar('axi_rdata');
      final wdata = _makeVar('axi_wdata');
      expect(_searchVars([star, rdata, wdata], 'axi_*'), [star]);
    });

    test('treats ? as literal character (no wildcards in substring mode)', () {
      final clk = _makeVar('clk');
      final c1k = _makeVar('c1k');
      // '?' is literal — neither name contains '?'.
      expect(_searchVars([clk, c1k], 'c?k'), isEmpty);
    });
  });

  // ── Glob matching ─────────────────────────────────────────────────────────

  group('glob mode', () {
    test('* matches any sequence of characters', () {
      final rdata = _makeVar('axi_rdata');
      final wdata = _makeVar('axi_wdata');
      final clk = _makeVar('clk');
      final result = _searchVars(
        [rdata, wdata, clk],
        'axi_*',
        mode: SearchMode.glob,
      );
      expect(result, [rdata, wdata]);
    });

    test('* matches the empty sequence', () {
      final clk = _makeVar('clk');
      final clkEn = _makeVar('clk_en');
      expect(_searchVars([clk, clkEn], 'clk*', mode: SearchMode.glob), [
        clk,
        clkEn,
      ]);
    });

    test('? matches exactly one character', () {
      final clk = _makeVar('clk'); // 3 chars → matches c?k
      final c1k = _makeVar('c1k'); // 3 chars → matches c?k
      final c12k = _makeVar('c12k'); // 4 chars → does NOT match c?k
      final result = _searchVars(
        [clk, c1k, c12k],
        'c?k',
        mode: SearchMode.glob,
      );
      expect(result, [clk, c1k]);
    });

    test('glob is case-insensitive', () {
      final clk = _makeVar('CLK');
      final data = _makeVar('data');
      expect(_searchVars([clk, data], 'clk*', mode: SearchMode.glob), [clk]);
    });

    test('returns empty when glob matches nothing', () {
      final vars = [_makeVar('clk'), _makeVar('data')];
      expect(_searchVars(vars, 'zzz_*', mode: SearchMode.glob), isEmpty);
    });

    test('lone * matches all signals', () {
      final vars = [_makeVar('clk'), _makeVar('data'), _makeVar('rst')];
      expect(_searchVars(vars, '*', mode: SearchMode.glob), vars);
    });

    test('pattern with multiple wildcards: data_*_valid', () {
      final axiValid = _makeVar('data_axi_valid');
      final apbValid = _makeVar('data_apb_valid');
      final invalid = _makeVar('data_invalid');
      final result = _searchVars(
        [axiValid, apbValid, invalid],
        'data_*_valid',
        mode: SearchMode.glob,
      );
      expect(result, [axiValid, apbValid]);
    });
  });

  // ── Type filtering ────────────────────────────────────────────────────────

  group('type filter', () {
    test('null selectedCategories shows all types', () {
      final wire = _makeVar('clk');
      final integer = _makeVar('cnt', varType: VarType.integer);
      final real = _makeVar('sig', varType: VarType.real, bitWidth: null);
      expect(_searchVars([wire, integer, real], ''), [wire, integer, real]);
    });

    test('empty selectedCategories shows all types', () {
      final wire = _makeVar('clk');
      final integer = _makeVar('cnt', varType: VarType.integer);
      expect(
        _searchVars([wire, integer], '', selectedCategories: {}),
        [wire, integer],
      );
    });

    test('wire category includes VarType.wire', () {
      final wire = _makeVar('clk');
      final reg = _makeVar('latch', varType: VarType.reg);
      expect(
        _searchVars(
          [wire, reg],
          '',
          selectedCategories: {SignalTypeCategory.wire},
        ),
        [wire],
      );
    });

    test('wire category includes VarType.logic', () {
      final logic = _makeVar('sig', varType: VarType.logic);
      final reg = _makeVar('cnt', varType: VarType.reg);
      expect(
        _searchVars(
          [logic, reg],
          '',
          selectedCategories: {SignalTypeCategory.wire},
        ),
        [logic],
      );
    });

    test('reg category matches VarType.reg', () {
      final wire = _makeVar('clk');
      final reg = _makeVar('latch', varType: VarType.reg);
      expect(
        _searchVars(
          [wire, reg],
          '',
          selectedCategories: {SignalTypeCategory.reg},
        ),
        [reg],
      );
    });

    test('integer category includes VarType.integer and VarType.svInt', () {
      final integer = _makeVar('cnt', varType: VarType.integer);
      final svInt = _makeVar('idx', varType: VarType.svInt);
      final wire = _makeVar('clk');
      expect(
        _searchVars(
          [integer, svInt, wire],
          '',
          selectedCategories: {SignalTypeCategory.integer},
        ),
        [integer, svInt],
      );
    });

    test('real category includes VarType.real and VarType.svShortReal', () {
      final real = _makeVar('volt', varType: VarType.real, bitWidth: null);
      final shortReal = _makeVar(
        'temp',
        varType: VarType.svShortReal,
        bitWidth: null,
      );
      final wire = _makeVar('clk');
      expect(
        _searchVars(
          [real, shortReal, wire],
          '',
          selectedCategories: {SignalTypeCategory.real},
        ),
        [real, shortReal],
      );
    });

    test('port category matches VarType.port', () {
      final port = _makeVar('out', varType: VarType.port);
      final wire = _makeVar('clk');
      expect(
        _searchVars(
          [port, wire],
          '',
          selectedCategories: {SignalTypeCategory.port},
        ),
        [port],
      );
    });

    test('multiple categories combine with OR logic', () {
      final wire = _makeVar('clk');
      final reg = _makeVar('cnt', varType: VarType.reg);
      final real = _makeVar('volt', varType: VarType.real, bitWidth: null);
      expect(
        _searchVars(
          [wire, reg, real],
          '',
          selectedCategories: {
            SignalTypeCategory.wire,
            SignalTypeCategory.reg,
          },
        ),
        [wire, reg],
      );
    });
  });

  // ── Bit-width filtering ───────────────────────────────────────────────────

  group('bit-width filter', () {
    test('minBitWidth excludes signals narrower than min', () {
      final v1 = _makeVar('a'); // default bitWidth: 1
      final v8 = _makeVar('b', bitWidth: 8);
      final v32 = _makeVar('c', bitWidth: 32);
      expect(_searchVars([v1, v8, v32], '', minBitWidth: 8), [v8, v32]);
    });

    test('maxBitWidth excludes signals wider than max', () {
      final v1 = _makeVar('a'); // default bitWidth: 1
      final v8 = _makeVar('b', bitWidth: 8);
      final v32 = _makeVar('c', bitWidth: 32);
      expect(_searchVars([v1, v8, v32], '', maxBitWidth: 8), [v1, v8]);
    });

    test('min and max together form an inclusive range', () {
      final v1 = _makeVar('a'); // default bitWidth: 1
      final v8 = _makeVar('b', bitWidth: 8);
      final v16 = _makeVar('c', bitWidth: 16);
      final v32 = _makeVar('d', bitWidth: 32);
      expect(
        _searchVars([v1, v8, v16, v32], '', minBitWidth: 8, maxBitWidth: 16),
        [v8, v16],
      );
    });

    test(
      'signals with null bitWidth are excluded when width filter is set',
      () {
        final withWidth = _makeVar('a', bitWidth: 8);
        final noWidth = _makeVar('b', bitWidth: null);
        expect(_searchVars([withWidth, noWidth], '', minBitWidth: 1), [
          withWidth,
        ]);
      },
    );

    test('no width filter shows all bit-widths', () {
      final v1 = _makeVar('a'); // default bitWidth: 1
      final v64 = _makeVar('b', bitWidth: 64);
      expect(_searchVars([v1, v64], ''), [v1, v64]);
    });
  });

  // ── Scope-path filtering ──────────────────────────────────────────────────

  group('scope-path filter', () {
    test('matches exact scope path', () {
      final inScope = _makeVar('clk', scopePath: 'top.cpu');
      final outScope = _makeVar('data', scopePath: 'top.mem');
      expect(
        _searchVars([inScope, outScope], '', scopePath: 'top.cpu'),
        [inScope],
      );
    });

    test('matches signals in child scopes of the prefix', () {
      final child = _makeVar('clk', scopePath: 'top.cpu.alu');
      final sibling = _makeVar('data', scopePath: 'top.mem');
      expect(
        _searchVars([child, sibling], '', scopePath: 'top.cpu'),
        [child],
      );
    });

    test('null scope path matches all scopes', () {
      final cpu = _makeVar('clk', scopePath: 'top.cpu');
      final mem = _makeVar('data', scopePath: 'top.mem');
      expect(_searchVars([cpu, mem], ''), [cpu, mem]);
    });

    test('empty string scope path matches all scopes', () {
      final cpu = _makeVar('clk', scopePath: 'top.cpu');
      final mem = _makeVar('data', scopePath: 'top.mem');
      expect(_searchVars([cpu, mem], '', scopePath: ''), [cpu, mem]);
    });

    test(
      'does not match scope names that merely start with the prefix string',
      () {
        final cpu = _makeVar('clk', scopePath: 'top.cpu');
        // 'top.cpuext' starts with 'top.cpu' as a string but is NOT a child.
        final cpuext = _makeVar('data', scopePath: 'top.cpuext');
        expect(
          _searchVars([cpu, cpuext], '', scopePath: 'top.cpu'),
          [cpu],
        );
      },
    );
  });

  // ── Combined filters (AND logic) ──────────────────────────────────────────

  group('combined filters', () {
    test('name + type filter are ANDed', () {
      final wireClk = _makeVar('clk');
      final regClk = _makeVar(
        'clk',
        scopePath: 'top.other',
        varType: VarType.reg,
      );
      final wireData = _makeVar('data');
      expect(
        _searchVars(
          [wireClk, regClk, wireData],
          'clk',
          selectedCategories: {SignalTypeCategory.wire},
        ),
        [wireClk],
      );
    });

    test('name + width filter are ANDed', () {
      final narrowClk = _makeVar('clk'); // default bitWidth: 1
      final wideClk = _makeVar('clk', scopePath: 'top.b', bitWidth: 32);
      final data = _makeVar('data', bitWidth: 8);
      expect(
        _searchVars([narrowClk, wideClk, data], 'clk', minBitWidth: 8),
        [wideClk],
      );
    });

    test('name + scope filter are ANDed', () {
      final cpuClk = _makeVar('clk', scopePath: 'top.cpu');
      final memClk = _makeVar('clk', scopePath: 'top.mem');
      expect(
        _searchVars([cpuClk, memClk], 'clk', scopePath: 'top.cpu'),
        [cpuClk],
      );
    });

    test('all four filters combined', () {
      final match = _makeVar('axi_data', scopePath: 'top.cpu', bitWidth: 32);
      final wrongName = _makeVar('rst', scopePath: 'top.cpu', bitWidth: 32);
      final wrongScope = _makeVar(
        'axi_data',
        scopePath: 'top.mem',
        bitWidth: 32,
      );
      final wrongWidth = _makeVar(
        'axi_data',
        scopePath: 'top.cpu',
      ); // default bitWidth: 1
      final wrongType = _makeVar(
        'axi_data',
        scopePath: 'top.cpu',
        bitWidth: 32,
        varType: VarType.reg,
      );
      expect(
        _searchVars(
          [match, wrongName, wrongScope, wrongWidth, wrongType],
          'axi',
          selectedCategories: {SignalTypeCategory.wire},
          minBitWidth: 8,
          scopePath: 'top.cpu',
        ),
        [match],
      );
    });
  });

  // ── Highlight range ───────────────────────────────────────────────────────

  group('highlight range', () {
    test('substring match returns correct start/end range', () {
      final v = _makeVar('axi_data');
      final results = SignalSearchService.search(
        variables: [v],
        query: 'data',
      );
      expect(results, hasLength(1));
      expect(results.first.hasHighlight, isTrue);
      final (start, end) = results.first.nameMatchRange!;
      // 'axi_data': 'data' occupies indices 4–8.
      expect(start, 4);
      expect(end, 8);
    });

    test('glob match returns no highlight range', () {
      final v = _makeVar('axi_data');
      final results = SignalSearchService.search(
        variables: [v],
        query: 'axi_*',
        mode: SearchMode.glob,
      );
      expect(results, hasLength(1));
      expect(results.first.hasHighlight, isFalse);
    });

    test('empty query returns no highlight range', () {
      final v = _makeVar('clk');
      final results = SignalSearchService.search(variables: [v], query: '');
      expect(results.first.hasHighlight, isFalse);
    });

    test('case-insensitive highlight preserves original casing', () {
      final v = _makeVar('CLK_EN');
      final results = SignalSearchService.search(
        variables: [v],
        query: 'clk',
      );
      expect(results.first.hasHighlight, isTrue);
      final (start, end) = results.first.nameMatchRange!;
      // The highlighted slice must be the original (uppercase) characters.
      expect(v.name.substring(start, end), 'CLK');
    });

    test('SearchResult.hasHighlight is false when nameMatchRange is null', () {
      const result = SearchResult(
        variable: Variable(
          name: 'clk',
          varType: VarType.wire,
          direction: VarDirection.unknown,
          signalRef: 'top.clk',
          scopePath: 'top',
        ),
      );
      expect(result.hasHighlight, isFalse);
    });

    test('SearchResult.hasHighlight is true when nameMatchRange is set', () {
      const result = SearchResult(
        variable: Variable(
          name: 'clk',
          varType: VarType.wire,
          direction: VarDirection.unknown,
          signalRef: 'top.clk',
          scopePath: 'top',
        ),
        nameMatchRange: (0, 3),
      );
      expect(result.hasHighlight, isTrue);
    });
  });

  // ── Direction filtering ────────────────────────────────────────────────────

  group('direction filter', () {
    late Variable inputVar;
    late Variable outputVar;
    late Variable inoutVar;
    late Variable unknownVar;

    setUp(() {
      inputVar = _makeVarWithDirection('addr', VarDirection.input);
      outputVar = _makeVarWithDirection('data', VarDirection.output);
      inoutVar = _makeVarWithDirection('bus', VarDirection.inout);
      unknownVar = _makeVarWithDirection('clk', VarDirection.unknown);
    });

    test('null selectedDirections returns all variables', () {
      final all = [inputVar, outputVar, inoutVar, unknownVar];
      expect(_searchVars(all, ''), all);
    });

    test('empty selectedDirections returns all variables', () {
      final all = [inputVar, outputVar, inoutVar, unknownVar];
      expect(_searchVars(all, '', selectedDirections: const {}), all);
    });

    test('filtering by input returns only input-direction variables', () {
      final all = [inputVar, outputVar, inoutVar, unknownVar];
      final result = _searchVars(
        all,
        '',
        selectedDirections: const {SignalDirection.input},
      );
      expect(result, [inputVar]);
    });

    test('filtering by output returns only output-direction variables', () {
      final all = [inputVar, outputVar, inoutVar, unknownVar];
      final result = _searchVars(
        all,
        '',
        selectedDirections: const {SignalDirection.output},
      );
      expect(result, [outputVar]);
    });

    test('filtering by inout returns only inout-direction variables', () {
      final all = [inputVar, outputVar, inoutVar, unknownVar];
      final result = _searchVars(
        all,
        '',
        selectedDirections: const {SignalDirection.inout},
      );
      expect(result, [inoutVar]);
    });

    test('filtering by unknown includes implicit, buffer, linkage', () {
      final implicitVar = _makeVarWithDirection('imp', VarDirection.implicit);
      final bufferVar = _makeVarWithDirection('buf', VarDirection.buffer);
      final linkageVar = _makeVarWithDirection('lnk', VarDirection.linkage);
      final all = [inputVar, implicitVar, bufferVar, linkageVar, unknownVar];
      final result = _searchVars(
        all,
        '',
        selectedDirections: const {SignalDirection.unknown},
      );
      expect(
        result,
        containsAll([implicitVar, bufferVar, linkageVar, unknownVar]),
      );
      expect(result, isNot(contains(inputVar)));
    });

    test('multi-direction filter returns union', () {
      final all = [inputVar, outputVar, inoutVar, unknownVar];
      final result = _searchVars(
        all,
        '',
        selectedDirections: const {
          SignalDirection.input,
          SignalDirection.output,
        },
      );
      expect(result, containsAll([inputVar, outputVar]));
      expect(result, isNot(contains(inoutVar)));
      expect(result, isNot(contains(unknownVar)));
    });

    test('direction filter ANDs with name query', () {
      final clkInput = _makeVarWithDirection('clk', VarDirection.input);
      final dataInput = _makeVarWithDirection('data', VarDirection.input);
      final clkOutput = _makeVarWithDirection('clk', VarDirection.output);
      final result = _searchVars(
        [clkInput, dataInput, clkOutput],
        'clk',
        selectedDirections: const {SignalDirection.input},
      );
      expect(result, [clkInput]);
    });

    test('direction filter ANDs with type filter', () {
      final portInput = _makeVarWithDirection('prt', VarDirection.input);
      const wireInput = Variable(
        name: 'wir',
        varType: VarType.wire,
        direction: VarDirection.input,
        signalRef: 'top.wir',
        scopePath: 'top',
        bitWidth: 1,
      );
      final result = _searchVars(
        [portInput, wireInput],
        '',
        selectedCategories: {SignalTypeCategory.port},
        selectedDirections: const {SignalDirection.input},
      );
      expect(result, [portInput]);
    });
  });

  // ── GTKWave direction-prefix syntax ────────────────────────────────────────

  group('GTKWave direction prefix', () {
    late Variable inputVar;
    late Variable outputVar;
    late Variable inoutVar;
    late Variable unknownVar;

    setUp(() {
      inputVar = _makeVarWithDirection('addr', VarDirection.input);
      outputVar = _makeVarWithDirection('data', VarDirection.output);
      inoutVar = _makeVarWithDirection('bus', VarDirection.inout);
      unknownVar = _makeVarWithDirection('clk', VarDirection.unknown);
    });

    test('+I+ prefix filters to inputs only', () {
      final all = [inputVar, outputVar, inoutVar, unknownVar];
      expect(_searchVars(all, '+I+'), [inputVar]);
    });

    test('+O+ prefix filters to outputs only', () {
      final all = [inputVar, outputVar, inoutVar, unknownVar];
      expect(_searchVars(all, '+O+'), [outputVar]);
    });

    test('+IO+ prefix filters to inout only', () {
      final all = [inputVar, outputVar, inoutVar, unknownVar];
      expect(_searchVars(all, '+IO+'), [inoutVar]);
    });

    test(
      '+I+ prefix strips cleanly — remaining query still filters by name',
      () {
        final addrIn = _makeVarWithDirection('addr', VarDirection.input);
        final dataIn = _makeVarWithDirection('data', VarDirection.input);
        final all = [addrIn, dataIn];
        expect(_searchVars(all, '+I+addr'), [addrIn]);
      },
    );

    test('+O+ prefix with name query filters both direction and name', () {
      final dataOut = _makeVarWithDirection('data', VarDirection.output);
      final clkOut = _makeVarWithDirection('clk', VarDirection.output);
      final dataIn = _makeVarWithDirection('data', VarDirection.input);
      final result = _searchVars([dataOut, clkOut, dataIn], '+O+data');
      expect(result, [dataOut]);
    });

    test('+IO+ prefix with name query filters both direction and name', () {
      final busInout = _makeVarWithDirection('bus', VarDirection.inout);
      final dataInout = _makeVarWithDirection('data', VarDirection.inout);
      final busOut = _makeVarWithDirection('bus', VarDirection.output);
      final result = _searchVars([busInout, dataInout, busOut], '+IO+bus');
      expect(result, [busInout]);
    });

    test('prefix overrides selectedDirections parameter', () {
      final all = [inputVar, outputVar, inoutVar];
      // query has +O+ but selectedDirections says input — prefix wins
      final result = _searchVars(
        all,
        '+O+',
        selectedDirections: const {SignalDirection.input},
      );
      expect(result, [outputVar]);
    });

    test('no prefix — selectedDirections parameter is used', () {
      final all = [inputVar, outputVar, inoutVar, unknownVar];
      final result = _searchVars(
        all,
        '',
        selectedDirections: const {SignalDirection.input},
      );
      expect(result, [inputVar]);
    });

    test(
      'empty query after stripping prefix matches all in that direction',
      () {
        final all = [inputVar, outputVar, inoutVar, unknownVar];
        expect(_searchVars(all, '+I+'), [inputVar]);
      },
    );

    test('prefix is case-sensitive — +i+ does not match', () {
      final all = [inputVar, outputVar];
      // +i+ is not a recognised prefix so it is treated as a name query
      final result = _searchVars(all, '+i+');
      // no variable name contains "+i+" → empty
      expect(result, isEmpty);
    });
  });
}
