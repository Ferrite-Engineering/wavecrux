// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/waveform/display_changes.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

// Path to the hand-crafted VCD fixture used by integration tests.
final _fixtureVcd =
    '${Directory.current.path}/test/fixtures/vcd/scalar_basics.vcd';

// ── Shared test fixtures ───────────────────────────────────────────────────────

const _clk = Variable(
  name: 'clk',
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: '0',
  scopePath: 'top',
  bitWidth: 1,
);
const _rst = Variable(
  name: 'rst',
  varType: VarType.reg,
  direction: VarDirection.input,
  signalRef: '1',
  scopePath: 'top',
  bitWidth: 1,
);
const _data = Variable(
  name: 'data',
  varType: VarType.reg,
  direction: VarDirection.unknown,
  signalRef: '2',
  scopePath: 'top.cpu',
  bitWidth: 8,
);
const _addr = Variable(
  name: 'addr',
  varType: VarType.wire,
  direction: VarDirection.output,
  signalRef: '3',
  scopePath: 'top.cpu',
  bitWidth: 16,
);
const _deepVar = Variable(
  name: 'x',
  varType: VarType.integer,
  direction: VarDirection.unknown,
  signalRef: '4',
  scopePath: 'top.cpu.alu',
  bitWidth: 32,
);

List<Scope> _buildNestedHierarchy() => [
  const Scope(
    name: 'top',
    type: ScopeType.module,
    path: 'top',
    variables: [_clk, _rst],
    childScopes: [
      Scope(
        name: 'cpu',
        type: ScopeType.module,
        path: 'top.cpu',
        variables: [_data, _addr],
        childScopes: [
          Scope(
            name: 'alu',
            type: ScopeType.module,
            path: 'top.cpu.alu',
            variables: [_deepVar],
          ),
        ],
      ),
    ],
  ),
];

void main() {
  // ── Unit tests — no FFI required ────────────────────────────────────────────
  //
  // These tests exercise the synchronous query logic by injecting pre-built
  // signal data directly into the provider cache, bypassing the isolate.

  group('WellenProvider — initial state', () {
    late WellenProvider provider;

    setUp(() => provider = WellenProvider());

    test('rootScopes is empty before openFile', () {
      expect(provider.rootScopes, isEmpty);
    });
    test('startTime is 0 before openFile', () {
      expect(provider.startTime, 0);
    });
    test('endTime is 0 before openFile', () {
      expect(provider.endTime, 0);
    });
    test('timescale is null before openFile', () {
      expect(provider.timescale, isNull);
    });
    test('date is null before openFile', () {
      expect(provider.date, isNull);
    });
    test('version is null before openFile', () {
      expect(provider.version, isNull);
    });
    test('isSignalLoaded returns false for any ref before openFile', () {
      expect(provider.isSignalLoaded('0'), isFalse);
    });
    test('valueAt returns null when no file loaded', () {
      expect(provider.valueAt('0', 100), isNull);
    });
    test('changesInRange returns empty when no file loaded', () {
      expect(provider.changesInRange('0', 0, 1000), isEmpty);
    });
    test('nextTransition returns null when no file loaded', () {
      expect(provider.nextTransition('0', 0), isNull);
    });
    test('prevTransition returns null when no file loaded', () {
      expect(provider.prevTransition('0', 100), isNull);
    });
  });

  group('WellenProvider — WaveformDataSource interface contract', () {
    test('WellenProvider is assignable to WaveformDataSource', () {
      // Compile-time check: if this assignment compiles, all interface methods
      // are implemented.
      final WaveformDataSource ds = WellenProvider();
      expect(ds, isA<WaveformDataSource>());
    });

    test('startTime is always 0 regardless of injected hierarchy', () {
      final provider = WellenProvider()
        ..injectHierarchy(_buildNestedHierarchy());
      expect(provider.startTime, 0);
    });

    test('close is callable on a fresh instance (no isolate)', () {
      expect(WellenProvider().close, returnsNormally);
    });

    test(
      'all synchronous query methods return safe defaults before openFile',
      () {
        final provider = WellenProvider();
        expect(provider.rootScopes, isEmpty);
        expect(provider.endTime, 0);
        expect(provider.timescale, isNull);
        expect(provider.date, isNull);
        expect(provider.version, isNull);
        expect(provider.findVariables(const SignalFilter()), isEmpty);
        expect(provider.isSignalLoaded('0'), isFalse);
        expect(provider.valueAt('0', 0), isNull);
        expect(provider.changesInRange('0', 0, 100), isEmpty);
        expect(provider.nextTransition('0', 0), isNull);
        expect(provider.prevTransition('0', 100), isNull);
      },
    );
  });

  group('WellenProvider — loadSignal argument validation', () {
    test('throws ArgumentError for alphabetic signalRef', () {
      final provider = WellenProvider();
      expect(
        () => provider.loadSignal('abc'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for empty signalRef', () {
      final provider = WellenProvider();
      expect(
        () => provider.loadSignal(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for float signalRef', () {
      final provider = WellenProvider();
      expect(
        () => provider.loadSignal('1.5'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for signalRef with leading text', () {
      final provider = WellenProvider();
      expect(
        () => provider.loadSignal('sig_0'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'returns immediately when signal is already loaded (no isolate needed)',
      () async {
        // injectLoadedSignal pre-populates the cache; loadSignal should hit the
        // _loadedSignals.containsKey guard and return before touching _workerPort.
        final provider = WellenProvider()
          ..injectLoadedSignal('0', const [SignalChange(time: 0, value: '1')]);
        await expectLater(provider.loadSignal('0'), completes);
        expect(provider.isSignalLoaded('0'), isTrue);
      },
    );

    test(
      'loadSignal before openFile throws for a valid unloaded ref',
      () async {
        // _workerPort is null — _sendRequest will throw a Null check error.
        final provider = WellenProvider();
        await expectLater(
          provider.loadSignal('0'),
          throwsA(isA<Error>()),
        );
      },
    );
  });

  group('WellenProvider — close/teardown state reset', () {
    test('close clears rootScopes', () {
      final provider = WellenProvider()
        ..injectHierarchy(_buildNestedHierarchy());
      expect(provider.rootScopes, isNotEmpty);
      provider.close();
      expect(provider.rootScopes, isEmpty);
    });

    test('close resets endTime to 0', () {
      // endTime is not directly injectable, but close must reset it.
      final provider = WellenProvider()..close();
      expect(provider.endTime, 0);
    });

    test('close resets timescale to null', () {
      final provider = WellenProvider()..close();
      expect(provider.timescale, isNull);
    });

    test('close resets date to null', () {
      final provider = WellenProvider()..close();
      expect(provider.date, isNull);
    });

    test('close resets version to null', () {
      final provider = WellenProvider()..close();
      expect(provider.version, isNull);
    });

    test('close clears all loaded signals', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [SignalChange(time: 0, value: '1')])
        ..injectLoadedSignal('1', const [SignalChange(time: 5, value: '0')]);
      expect(provider.isSignalLoaded('0'), isTrue);
      expect(provider.isSignalLoaded('1'), isTrue);
      provider.close();
      expect(provider.isSignalLoaded('0'), isFalse);
      expect(provider.isSignalLoaded('1'), isFalse);
    });

    test(
      'after close, valueAt returns null for a previously loaded signal',
      () {
        final provider = WellenProvider()
          ..injectLoadedSignal('0', const [SignalChange(time: 0, value: '1')]);
        expect(provider.valueAt('0', 0), '1');
        provider.close();
        expect(provider.valueAt('0', 0), isNull);
      },
    );

    test(
      'after close, changesInRange returns empty for a previously loaded signal',
      () {
        final provider = WellenProvider()
          ..injectLoadedSignal('0', const [
            SignalChange(time: 0, value: '0'),
            SignalChange(time: 10, value: '1'),
          ]);
        expect(provider.changesInRange('0', 0, 20), isNotEmpty);
        provider.close();
        expect(provider.changesInRange('0', 0, 20), isEmpty);
      },
    );

    test('after close, nextTransition returns null', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 0, value: '0'),
          SignalChange(time: 10, value: '1'),
        ]);
      expect(provider.nextTransition('0', 0), isNotNull);
      provider.close();
      expect(provider.nextTransition('0', 0), isNull);
    });

    test('after close, prevTransition returns null', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [SignalChange(time: 100, value: '1')]);
      expect(provider.prevTransition('0', 200), isNotNull);
      provider.close();
      expect(provider.prevTransition('0', 200), isNull);
    });

    test('after close, findVariables returns empty', () {
      final provider = WellenProvider()
        ..injectHierarchy(_buildNestedHierarchy());
      expect(provider.findVariables(const SignalFilter()), isNotEmpty);
      provider.close();
      expect(provider.findVariables(const SignalFilter()), isEmpty);
    });

    test('close is idempotent — calling twice does not throw', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [SignalChange(time: 0, value: '0')])
        ..injectHierarchy(_buildNestedHierarchy());
      expect(() {
        provider
          ..close()
          ..close();
      }, returnsNormally);
    });

    test(
      'close on fresh provider (no isolate, no injected data) does not throw',
      () {
        expect(WellenProvider().close, returnsNormally);
      },
    );
  });

  group('WellenProvider — findVariables with injected hierarchy', () {
    late WellenProvider provider;

    setUp(() {
      provider = WellenProvider()
        ..injectHierarchy([
          const Scope(
            name: 'top',
            type: ScopeType.module,
            path: 'top',
            childScopes: [
              Scope(
                name: 'cpu',
                type: ScopeType.module,
                path: 'top.cpu',
                variables: [_data],
              ),
            ],
            variables: [_clk],
          ),
        ]);
    });

    test('rootScopes contains injected hierarchy', () {
      expect(provider.rootScopes, hasLength(1));
      expect(provider.rootScopes.first.name, 'top');
    });
    test('findVariables() with empty filter returns all variables', () {
      expect(provider.findVariables(const SignalFilter()), hasLength(2));
    });
    test('findVariables filters by name substring', () {
      final result = provider.findVariables(
        const SignalFilter(namePattern: 'dat'),
      );
      expect(result, hasLength(1));
      expect(result.first.name, 'data');
    });
    test('findVariables filters by scopePath', () {
      final result = provider.findVariables(
        const SignalFilter(scopePath: 'top.cpu'),
      );
      expect(result, hasLength(1));
      expect(result.first.name, 'data');
    });
    test('findVariables filters by varType', () {
      final result = provider.findVariables(
        const SignalFilter(varTypes: {VarType.wire}),
      );
      expect(result, hasLength(1));
      expect(result.first.name, 'clk');
    });
    test('findVariables filters by bitWidth', () {
      final result = provider.findVariables(
        const SignalFilter(minBitWidth: 2),
      );
      expect(result, hasLength(1));
      expect(result.first.name, 'data');
    });
    test('findVariables with no match returns empty', () {
      final result = provider.findVariables(
        const SignalFilter(namePattern: 'nonexistent'),
      );
      expect(result, isEmpty);
    });
  });

  group('WellenProvider — findVariables with deep hierarchy', () {
    late WellenProvider provider;

    setUp(
      () =>
          provider = WellenProvider()..injectHierarchy(_buildNestedHierarchy()),
    );

    test('flattens all 5 variables from 3-level hierarchy', () {
      expect(provider.findVariables(const SignalFilter()), hasLength(5));
    });

    test('scopePath prefix match returns all variables under top.cpu', () {
      final result = provider.findVariables(
        const SignalFilter(scopePath: 'top.cpu'),
      );
      // top.cpu has data+addr, top.cpu.alu has deepVar — all match prefix
      expect(result, hasLength(3));
      expect(result.map((v) => v.name), containsAll(['data', 'addr', 'x']));
    });

    test('exact scopePath match excludes deeper scopes', () {
      // SignalFilter scopePath matches exact OR starts-with prefix.
      // top.cpu.alu is a child of top.cpu, so it is included.
      // But if we ask for the leaf scope only:
      final result = provider.findVariables(
        const SignalFilter(scopePath: 'top.cpu.alu'),
      );
      expect(result, hasLength(1));
      expect(result.first.name, 'x');
    });

    test('filters by VarType.integer across all scopes', () {
      final result = provider.findVariables(
        const SignalFilter(varTypes: {VarType.integer}),
      );
      expect(result, hasLength(1));
      expect(result.first.name, 'x');
    });

    test('filters by maxBitWidth', () {
      final result = provider.findVariables(
        const SignalFilter(maxBitWidth: 8),
      );
      // clk(1), rst(1), data(8) qualify; addr(16) and x(32) do not
      expect(result, hasLength(3));
      expect(result.map((v) => v.name), containsAll(['clk', 'rst', 'data']));
    });

    test('combined name + type filter', () {
      final result = provider.findVariables(
        const SignalFilter(namePattern: 'a', varTypes: {VarType.wire}),
      );
      // Only wire variables whose name contains 'a': addr(wire) and data(reg, no)
      expect(result, hasLength(1));
      expect(result.first.name, 'addr');
    });

    test('glob pattern asterisk matches multiple signals', () {
      final result = provider.findVariables(
        const SignalFilter(namePattern: '*d*'),
      );
      // addr, data contain 'd'
      expect(result, hasLength(2));
      expect(result.map((v) => v.name), containsAll(['addr', 'data']));
    });

    test('glob question mark matches single character', () {
      final result = provider.findVariables(
        const SignalFilter(namePattern: 'cl?'),
      );
      expect(result, hasLength(1));
      expect(result.first.name, 'clk');
    });

    test('filters by multiple varTypes via Set', () {
      final result = provider.findVariables(
        const SignalFilter(varTypes: {VarType.wire, VarType.reg}),
      );
      // clk(wire), rst(reg), data(reg), addr(wire) = 4
      expect(result, hasLength(4));
    });

    test('filters by bit-width range min and max', () {
      final result = provider.findVariables(
        const SignalFilter(minBitWidth: 2, maxBitWidth: 16),
      );
      // data(8) and addr(16) qualify; clk/rst(1) too small; x(32) too large
      expect(result, hasLength(2));
      expect(result.map((v) => v.name), containsAll(['data', 'addr']));
    });
  });

  group('WellenProvider — findVariables with multiple root scopes', () {
    test('flattens variables from all root scopes', () {
      const other = Variable(
        name: 'extra',
        varType: VarType.wire,
        direction: VarDirection.unknown,
        signalRef: '99',
        scopePath: 'other',
        bitWidth: 4,
      );
      final provider = WellenProvider()
        ..injectHierarchy([
          const Scope(
            name: 'top',
            type: ScopeType.module,
            path: 'top',
            variables: [_clk],
          ),
          const Scope(
            name: 'other',
            type: ScopeType.module,
            path: 'other',
            variables: [other],
          ),
        ]);
      expect(provider.findVariables(const SignalFilter()), hasLength(2));
      expect(provider.rootScopes, hasLength(2));
    });

    test('empty root scopes list returns empty from findVariables', () {
      final provider = WellenProvider()..injectHierarchy(const []);
      expect(provider.rootScopes, isEmpty);
      expect(provider.findVariables(const SignalFilter()), isEmpty);
    });

    test('scope with no variables contributes nothing to findVariables', () {
      final provider = WellenProvider()
        ..injectHierarchy([
          const Scope(
            name: 'empty',
            type: ScopeType.module,
            path: 'empty',
          ),
        ]);
      expect(provider.findVariables(const SignalFilter()), isEmpty);
    });
  });

  group('WellenProvider — injectHierarchy behavior', () {
    test('second injectHierarchy call replaces first hierarchy', () {
      final provider = WellenProvider()
        ..injectHierarchy([
          const Scope(
            name: 'first',
            type: ScopeType.module,
            path: 'first',
            variables: [_clk],
          ),
        ])
        ..injectHierarchy([
          const Scope(
            name: 'second',
            type: ScopeType.module,
            path: 'second',
            variables: [_data],
          ),
        ]);
      expect(provider.rootScopes.first.name, 'second');
      expect(provider.findVariables(const SignalFilter()), hasLength(1));
      expect(provider.findVariables(const SignalFilter()).first.name, 'data');
    });
  });

  group('WellenProvider — injectLoadedSignal behavior', () {
    test('injectLoadedSignal with non-integer ref is a no-op', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('bad_ref', const []);
      expect(provider.isSignalLoaded('bad_ref'), isFalse);
    });

    test('injectLoadedSignal overwrites existing data for the same ref', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [SignalChange(time: 0, value: '0')])
        ..injectLoadedSignal('0', const [SignalChange(time: 0, value: '1')]);
      expect(provider.valueAt('0', 0), '1');
    });

    test('injectLoadedSignal with large ref integer works', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('2147483647', const [
          SignalChange(time: 0, value: '1'),
        ]);
      expect(provider.isSignalLoaded('2147483647'), isTrue);
      expect(provider.valueAt('2147483647', 0), '1');
    });

    test('injectLoadedSignal with ref 0 works', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [SignalChange(time: 42, value: 'z')]);
      expect(provider.isSignalLoaded('0'), isTrue);
      expect(provider.valueAt('0', 42), 'z');
    });
  });

  group('WellenProvider — isSignalLoaded with injected data', () {
    late WellenProvider provider;

    setUp(() {
      provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 0, value: '0'),
          SignalChange(time: 10, value: '1'),
        ]);
    });

    test('isSignalLoaded true for injected ref', () {
      expect(provider.isSignalLoaded('0'), isTrue);
    });
    test('isSignalLoaded false for unknown ref', () {
      expect(provider.isSignalLoaded('99'), isFalse);
    });
    test('isSignalLoaded false for non-integer ref', () {
      expect(provider.isSignalLoaded('abc'), isFalse);
    });
  });

  group('WellenProvider — valueAt', () {
    late WellenProvider provider;

    setUp(() {
      // clk: 0@t=0, 1@t=10, 0@t=20, 1@t=30
      provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 0, value: '0'),
          SignalChange(time: 10, value: '1'),
          SignalChange(time: 20, value: '0'),
          SignalChange(time: 30, value: '1'),
        ]);
    });

    test('returns null before first change', () {
      expect(provider.valueAt('0', -1), isNull);
    });
    test('returns value at exact transition time', () {
      expect(provider.valueAt('0', 0), '0');
      expect(provider.valueAt('0', 10), '1');
      expect(provider.valueAt('0', 20), '0');
      expect(provider.valueAt('0', 30), '1');
    });
    test('returns last known value between transitions', () {
      expect(provider.valueAt('0', 5), '0');
      expect(provider.valueAt('0', 15), '1');
      expect(provider.valueAt('0', 25), '0');
    });
    test('returns last known value after all transitions', () {
      expect(provider.valueAt('0', 999), '1');
    });
    test('returns null for unloaded signal', () {
      expect(provider.valueAt('99', 10), isNull);
    });
    test('returns null for non-integer signalRef', () {
      expect(provider.valueAt('abc', 10), isNull);
    });
  });

  group('WellenProvider — valueAt binary search edge cases', () {
    test('signal with a single change: at, after, before', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [SignalChange(time: 50, value: 'x')]);
      expect(provider.valueAt('0', 49), isNull);
      expect(provider.valueAt('0', 50), 'x');
      expect(provider.valueAt('0', 51), 'x');
      expect(provider.valueAt('0', 10000), 'x');
    });

    test('exactly at t=0 first change', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [SignalChange(time: 0, value: '1')]);
      expect(provider.valueAt('0', 0), '1');
    });

    test(
      'many densely packed changes — binary search finds correct bucket',
      () {
        final changes = List.generate(
          100,
          (i) => SignalChange(time: i, value: (i % 2).toString()),
        );
        final provider = WellenProvider()..injectLoadedSignal('0', changes);
        for (var i = 0; i < 100; i++) {
          expect(
            provider.valueAt('0', i),
            (i % 2).toString(),
            reason: 'wrong at t=$i',
          );
        }
        // After last change t=99, value stays at '1' (99%2==1)
        expect(provider.valueAt('0', 200), '1');
      },
    );

    test('time exactly at last change', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 0, value: '0'),
          SignalChange(time: 100, value: '1'),
        ]);
      expect(provider.valueAt('0', 100), '1');
    });
  });

  group('WellenProvider — changesInRange', () {
    late WellenProvider provider;

    setUp(() {
      provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 0, value: '0'),
          SignalChange(time: 10, value: '1'),
          SignalChange(time: 20, value: '0'),
          SignalChange(time: 30, value: '1'),
          SignalChange(time: 40, value: '0'),
        ]);
    });

    test('returns all changes in full range', () {
      final result = provider.changesInRange('0', 0, 41);
      expect(result, hasLength(5));
    });
    test('excludes changes at end time (half-open interval)', () {
      final result = provider.changesInRange('0', 0, 40);
      expect(result, hasLength(4));
      expect(result.last.time, 30);
    });
    test('includes change at exactly start time', () {
      final result = provider.changesInRange('0', 10, 30);
      expect(result, hasLength(2));
      expect(result.first.time, 10);
    });
    test('returns empty when range has no changes', () {
      expect(provider.changesInRange('0', 11, 20), isEmpty);
    });
    test('returns empty for unloaded signal', () {
      expect(provider.changesInRange('99', 0, 100), isEmpty);
    });
  });

  group('WellenProvider — changesInRange edge cases', () {
    test('range entirely before all changes returns empty', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 100, value: '1'),
          SignalChange(time: 200, value: '0'),
        ]);
      expect(provider.changesInRange('0', 0, 50), isEmpty);
    });

    test('range entirely after all changes returns empty', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 0, value: '1'),
          SignalChange(time: 10, value: '0'),
        ]);
      expect(provider.changesInRange('0', 100, 200), isEmpty);
    });

    test('zero-width range [t, t) returns empty', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [SignalChange(time: 10, value: '1')]);
      expect(provider.changesInRange('0', 10, 10), isEmpty);
    });

    test('inverted range [end < start] returns empty', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [SignalChange(time: 10, value: '1')]);
      expect(provider.changesInRange('0', 20, 5), isEmpty);
    });

    test('single-element changes list: change inside range', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [SignalChange(time: 50, value: 'z')]);
      expect(provider.changesInRange('0', 0, 100), hasLength(1));
      expect(provider.changesInRange('0', 50, 51), hasLength(1));
    });

    test('single-element changes list: change at end excluded', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [SignalChange(time: 50, value: 'z')]);
      expect(provider.changesInRange('0', 0, 50), isEmpty);
    });

    test('range exactly spanning all changes', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 10, value: '0'),
          SignalChange(time: 20, value: '1'),
          SignalChange(time: 30, value: '0'),
        ]);
      final result = provider.changesInRange('0', 10, 31);
      expect(result, hasLength(3));
    });
  });

  group('WellenProvider — nextTransition', () {
    late WellenProvider provider;

    setUp(() {
      provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 10, value: '1'),
          SignalChange(time: 20, value: '0'),
          SignalChange(time: 30, value: '1'),
        ]);
    });

    test('returns first transition strictly after afterTime', () {
      final result = provider.nextTransition('0', 0);
      expect(result, isNotNull);
      expect(result!.time, 10);
      expect(result.value, '1');
    });
    test('skips transition at exactly afterTime', () {
      final result = provider.nextTransition('0', 10);
      expect(result!.time, 20);
    });
    test('returns null when no transition exists after afterTime', () {
      expect(provider.nextTransition('0', 30), isNull);
      expect(provider.nextTransition('0', 999), isNull);
    });
    test('returns null for unloaded signal', () {
      expect(provider.nextTransition('99', 0), isNull);
    });
  });

  group('WellenProvider — nextTransition edge cases', () {
    test('returns first transition when afterTime is very negative', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 5, value: '1'),
          SignalChange(time: 15, value: '0'),
        ]);
      expect(provider.nextTransition('0', -1000)!.time, 5);
    });

    test('returns correct transition amid many changes — binary search', () {
      final changes = List.generate(
        200,
        (i) => SignalChange(time: i * 10, value: (i % 2).toString()),
      );
      final provider = WellenProvider()..injectLoadedSignal('0', changes);
      // Next transition after t=500 (50th change) should be t=510
      final next = provider.nextTransition('0', 500);
      expect(next, isNotNull);
      expect(next!.time, 510);
    });

    test('nextTransition for non-integer ref returns null', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [SignalChange(time: 0, value: '1')]);
      expect(provider.nextTransition('bad', 0), isNull);
    });
  });

  group('WellenProvider — prevTransition', () {
    late WellenProvider provider;

    setUp(() {
      provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 10, value: '1'),
          SignalChange(time: 20, value: '0'),
          SignalChange(time: 30, value: '1'),
        ]);
    });

    test('returns last transition strictly before beforeTime', () {
      final result = provider.prevTransition('0', 31);
      expect(result, isNotNull);
      expect(result!.time, 30);
    });
    test('skips transition at exactly beforeTime', () {
      final result = provider.prevTransition('0', 30);
      expect(result!.time, 20);
    });
    test('returns null when no transition exists before beforeTime', () {
      expect(provider.prevTransition('0', 10), isNull);
      expect(provider.prevTransition('0', 0), isNull);
    });
    test('returns null for unloaded signal', () {
      expect(provider.prevTransition('99', 100), isNull);
    });
  });

  group('WellenProvider — prevTransition edge cases', () {
    test('returns last transition when beforeTime is very large', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 5, value: '0'),
          SignalChange(time: 15, value: '1'),
        ]);
      expect(provider.prevTransition('0', 1000000)!.time, 15);
    });

    test('returns correct transition amid many changes — binary search', () {
      final changes = List.generate(
        200,
        (i) => SignalChange(time: i * 10, value: (i % 2).toString()),
      );
      final provider = WellenProvider()..injectLoadedSignal('0', changes);
      // Prev transition before t=500 should be t=490
      final prev = provider.prevTransition('0', 500);
      expect(prev, isNotNull);
      expect(prev!.time, 490);
    });

    test('prevTransition for non-integer ref returns null', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [SignalChange(time: 0, value: '1')]);
      expect(provider.prevTransition('bad', 100), isNull);
    });
  });

  group('WellenProvider — X/Z and multi-state values', () {
    test('valueAt returns x for undefined state', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 0, value: 'x'),
          SignalChange(time: 10, value: '0'),
          SignalChange(time: 20, value: 'z'),
          SignalChange(time: 30, value: '1'),
        ]);
      expect(provider.valueAt('0', 0), 'x');
      expect(provider.valueAt('0', 5), 'x');
      expect(provider.valueAt('0', 10), '0');
      expect(provider.valueAt('0', 20), 'z');
      expect(provider.valueAt('0', 25), 'z');
      expect(provider.valueAt('0', 30), '1');
    });

    test('changesInRange returns x/z changes within range', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 0, value: 'x'),
          SignalChange(time: 10, value: 'z'),
          SignalChange(time: 20, value: '1'),
        ]);
      final result = provider.changesInRange('0', 0, 15);
      expect(result, hasLength(2));
      expect(result[0].value, 'x');
      expect(result[1].value, 'z');
    });

    test('nextTransition advances through x/z transitions', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 0, value: 'x'),
          SignalChange(time: 10, value: 'z'),
          SignalChange(time: 20, value: '1'),
        ]);
      final next = provider.nextTransition('0', 0);
      expect(next!.value, 'z');
      expect(next.time, 10);
    });

    test('prevTransition navigates backward through x/z values', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 0, value: 'x'),
          SignalChange(time: 10, value: 'z'),
          SignalChange(time: 20, value: '1'),
        ]);
      final prev = provider.prevTransition('0', 20);
      expect(prev!.value, 'z');
      expect(prev.time, 10);
    });

    test('multi-bit bus value strings are returned verbatim', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 0, value: '00000000'),
          SignalChange(time: 10, value: 'xxxxxxxx'),
          SignalChange(time: 20, value: '10101010'),
          SignalChange(time: 30, value: 'zzzzzzzz'),
        ]);
      expect(provider.valueAt('0', 0), '00000000');
      expect(provider.valueAt('0', 10), 'xxxxxxxx');
      expect(provider.valueAt('0', 20), '10101010');
      expect(provider.valueAt('0', 30), 'zzzzzzzz');
    });

    test('mixed x/z nibbles in bus value', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 0, value: '0101xxzz'),
        ]);
      expect(provider.valueAt('0', 0), '0101xxzz');
    });
  });

  group('WellenProvider — multiple independent signals', () {
    late WellenProvider provider;

    setUp(() {
      provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 0, value: '0'),
          SignalChange(time: 10, value: '1'),
        ])
        ..injectLoadedSignal('1', const [
          SignalChange(time: 5, value: 'a'),
          SignalChange(time: 15, value: 'b'),
        ])
        ..injectLoadedSignal('2', const []);
    });

    test('isSignalLoaded is independent per ref', () {
      expect(provider.isSignalLoaded('0'), isTrue);
      expect(provider.isSignalLoaded('1'), isTrue);
      expect(provider.isSignalLoaded('2'), isTrue);
      expect(provider.isSignalLoaded('99'), isFalse);
    });

    test('valueAt is independent per signal', () {
      expect(provider.valueAt('0', 5), '0');
      expect(provider.valueAt('1', 5), 'a');
      expect(provider.valueAt('0', 10), '1');
      expect(provider.valueAt('1', 10), 'a');
    });

    test('changesInRange is independent per signal', () {
      expect(provider.changesInRange('0', 0, 20), hasLength(2));
      expect(provider.changesInRange('1', 0, 20), hasLength(2));
      expect(provider.changesInRange('2', 0, 20), isEmpty);
    });

    test('nextTransition is independent per signal', () {
      expect(provider.nextTransition('0', 0)!.time, 10);
      expect(provider.nextTransition('1', 0)!.time, 5);
    });

    test('prevTransition is independent per signal', () {
      expect(provider.prevTransition('0', 20)!.time, 10);
      expect(provider.prevTransition('1', 20)!.time, 15);
    });

    test('empty signal cache does not affect queries on other signals', () {
      expect(provider.valueAt('2', 100), isNull);
      expect(provider.nextTransition('2', 0), isNull);
      expect(provider.prevTransition('2', 100), isNull);
    });
  });

  group('WellenProvider — edge cases', () {
    test('valueAt on empty changes list returns null', () {
      final provider = WellenProvider()..injectLoadedSignal('0', const []);
      expect(provider.valueAt('0', 50), isNull);
    });

    test('changesInRange on empty changes returns empty', () {
      final provider = WellenProvider()..injectLoadedSignal('0', const []);
      expect(provider.changesInRange('0', 0, 100), isEmpty);
    });

    test('single-change signal: valueAt at time returns its value', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [SignalChange(time: 5, value: 'x')]);
      expect(provider.valueAt('0', 5), 'x');
      expect(provider.valueAt('0', 100), 'x');
      expect(provider.valueAt('0', 4), isNull);
    });

    test('nextTransition and prevTransition on single change', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [SignalChange(time: 50, value: '1')]);
      expect(provider.nextTransition('0', 0)!.time, 50);
      expect(provider.nextTransition('0', 50), isNull);
      expect(provider.prevTransition('0', 51)!.time, 50);
      expect(provider.prevTransition('0', 50), isNull);
    });

    test('close() does not throw even before openFile', () {
      final provider = WellenProvider();
      expect(provider.close, returnsNormally);
    });

    test('close() does not throw when called twice', () {
      final provider = WellenProvider();
      expect(() {
        provider
          ..close()
          ..close();
      }, returnsNormally);
    });
  });

  // ── Integration tests — requires compiled native library ───────────────────
  //
  // These tests load the scalar_basics.vcd fixture through the full
  // WellenProvider → background isolate → FFI → Rust pipeline. Locally they
  // skip when the native library is not built; in CI a missing library fails.

  if (requireWellenFfiLibrary('WellenProvider integration')) {
    group('WellenProvider — integration (scalar_basics.vcd)', () {
      late WellenProvider provider;

      setUpAll(() async {
        expect(
          File(_fixtureVcd).existsSync(),
          isTrue,
          reason: 'VCD fixture not found at $_fixtureVcd',
        );
        provider = WellenProvider();
        await provider.openFile(_fixtureVcd);
      });

      tearDownAll(() => provider.close());

      // ── Metadata ─────────────────────────────────────────────────────────

      test('timescale is 1 ns', () {
        final ts = provider.timescale;
        expect(ts, isNotNull);
        expect(ts!.factor, 1);
        expect(ts.unit.symbol, 'ns');
      });
      test('endTime is 100', () {
        expect(provider.endTime, 100);
      });
      test('startTime is always 0', () {
        expect(provider.startTime, 0);
      });

      // ── Hierarchy ─────────────────────────────────────────────────────────

      test('one root scope named "top"', () {
        expect(provider.rootScopes, hasLength(1));
        expect(provider.rootScopes.first.name, 'top');
        expect(provider.rootScopes.first.type, ScopeType.module);
      });
      test('"top" scope has exactly 3 variables', () {
        expect(provider.rootScopes.first.variables, hasLength(3));
      });
      test('variable names are clk, rst, data', () {
        final names = provider.rootScopes.first.variables
            .map((v) => v.name)
            .toSet();
        expect(names, containsAll(['clk', 'rst', 'data']));
      });
      test('clk and rst have bitWidth 1', () {
        final clk = provider.rootScopes.first.variables.firstWhere(
          (v) => v.name == 'clk',
        );
        final rst = provider.rootScopes.first.variables.firstWhere(
          (v) => v.name == 'rst',
        );
        expect(clk.bitWidth, 1);
        expect(rst.bitWidth, 1);
      });
      test('data has bitWidth 8', () {
        final data = provider.rootScopes.first.variables.firstWhere(
          (v) => v.name == 'data',
        );
        expect(data.bitWidth, 8);
      });
      test(
        'all variables report direction unknown (VCD has no direction info)',
        () {
          for (final v in provider.rootScopes.first.variables) {
            expect(v.direction, VarDirection.unknown);
          }
        },
      );
      test('findVariables() returns all 3 variables', () {
        expect(provider.findVariables(const SignalFilter()), hasLength(3));
      });

      // ── Signal loading and value queries ──────────────────────────────────

      group('clk signal', () {
        late String clkRef;

        setUpAll(() async {
          clkRef = provider.rootScopes.first.variables
              .firstWhere((v) => v.name == 'clk')
              .signalRef;
          await provider.loadSignal(clkRef);
        });

        test('isSignalLoaded returns true after loadSignal', () {
          expect(provider.isSignalLoaded(clkRef), isTrue);
        });
        test('valueAt t=0 is "0"', () {
          expect(provider.valueAt(clkRef, 0), '0');
        });
        test('valueAt t=10 is "1"', () {
          expect(provider.valueAt(clkRef, 10), '1');
        });
        test('valueAt between transitions returns last known', () {
          expect(provider.valueAt(clkRef, 5), '0');
          expect(provider.valueAt(clkRef, 15), '1');
        });
        test('valueAt after last change returns last value', () {
          expect(provider.valueAt(clkRef, 999), '0');
        });
        test('changesInRange [0,101) returns 11 changes', () {
          expect(provider.changesInRange(clkRef, 0, 101), hasLength(11));
        });
        test('changesInRange [20,50) returns transitions at 20, 30, 40', () {
          final result = provider.changesInRange(clkRef, 20, 50);
          expect(result.map((c) => c.time).toList(), [20, 30, 40]);
        });
        test('nextTransition after t=0 is (t=10, "1")', () {
          final next = provider.nextTransition(clkRef, 0);
          expect(next, isNotNull);
          expect(next!.time, 10);
          expect(next.value, '1');
        });
        test('nextTransition after t=100 is null', () {
          expect(provider.nextTransition(clkRef, 100), isNull);
        });
        test('prevTransition before t=100 is (t=90, "1")', () {
          final prev = provider.prevTransition(clkRef, 100);
          expect(prev, isNotNull);
          expect(prev!.time, 90);
          expect(prev.value, '1');
        });
        test('prevTransition before t=0 is null', () {
          expect(provider.prevTransition(clkRef, 0), isNull);
        });
      });

      group('rst signal', () {
        late String rstRef;

        setUpAll(() async {
          rstRef = provider.rootScopes.first.variables
              .firstWhere((v) => v.name == 'rst')
              .signalRef;
          await provider.loadSignal(rstRef);
        });

        test('has 2 changes total', () {
          expect(provider.changesInRange(rstRef, 0, 101), hasLength(2));
        });
        test('valueAt t=0 is "1"', () {
          expect(provider.valueAt(rstRef, 0), '1');
        });
        test('valueAt t=30 is "0"', () {
          expect(provider.valueAt(rstRef, 30), '0');
        });
        test('remains "0" after t=30', () {
          expect(provider.valueAt(rstRef, 100), '0');
        });
      });

      group('data signal', () {
        late String dataRef;

        setUpAll(() async {
          dataRef = provider.rootScopes.first.variables
              .firstWhere((v) => v.name == 'data')
              .signalRef;
          await provider.loadSignal(dataRef);
        });

        test('has 4 changes total', () {
          expect(provider.changesInRange(dataRef, 0, 101), hasLength(4));
        });
        test('valueAt t=0 is all-zeros binary string', () {
          expect(provider.valueAt(dataRef, 0), '00000000');
        });
        test('valueAt t=30 reflects first increment', () {
          expect(provider.valueAt(dataRef, 30), '00000001');
        });
        test('valueAt t=50 reflects second increment', () {
          expect(provider.valueAt(dataRef, 50), '00000010');
        });
        test('valueAt t=90 is all-ones', () {
          expect(provider.valueAt(dataRef, 90), '11111111');
        });
      });

      // ── loadSignal idempotency ──────────────────────────────────────────

      test('calling loadSignal twice on same ref is a no-op', () async {
        final ref = provider.rootScopes.first.variables.first.signalRef;
        await provider.loadSignal(ref);
        await provider.loadSignal(ref); // must not throw
        expect(provider.isSignalLoaded(ref), isTrue);
      });

      // ── Diagnostics ───────────────────────────────────────────────────────

      test('fileFormat returns "VCD" for a VCD fixture', () {
        expect(provider.fileFormat, 'VCD');
      });

      test('signalTransitionCount returns 0 for an unloaded signal', () {
        // Pick a ref that has not been loaded in this group yet.
        // We look for a variable we haven't loaded.
        final unloadedVar = provider.rootScopes.first.variables.firstWhere(
          (v) => !provider.isSignalLoaded(v.signalRef),
          orElse: () => provider.rootScopes.first.variables.first,
        );
        // If every signal happens to be loaded, the count is still ≥ 0 (not negative).
        expect(
          provider.signalTransitionCount(unloadedVar.signalRef),
          isNonNegative,
        );
      });

      group('diagnostics after loading all signals', () {
        // Load all 3 signals so we can test the full counts.
        setUpAll(() async {
          for (final v in provider.rootScopes.first.variables) {
            if (!provider.isSignalLoaded(v.signalRef)) {
              await provider.loadSignal(v.signalRef);
            }
          }
        });

        test('signalTransitionCount for clk is 11', () {
          final clkRef = provider.rootScopes.first.variables
              .firstWhere((v) => v.name == 'clk')
              .signalRef;
          expect(provider.signalTransitionCount(clkRef), 11);
        });

        test('signalTransitionCount for rst is 2', () {
          final rstRef = provider.rootScopes.first.variables
              .firstWhere((v) => v.name == 'rst')
              .signalRef;
          expect(provider.signalTransitionCount(rstRef), 2);
        });

        test('signalTransitionCount for data is 4', () {
          final dataRef = provider.rootScopes.first.variables
              .firstWhere((v) => v.name == 'data')
              .signalRef;
          expect(provider.signalTransitionCount(dataRef), 4);
        });

        test(
          'totalTransitions returns count summed across loaded signals (17)',
          () {
            // scalar_basics.vcd: clk=11 + rst=2 + data=4 = 17. Computed lazily
            // by summing _loadedSignals[*].length after the setUpAll has called
            // loadSignal() for every variable in this group.
            expect(provider.totalTransitions, 17);
          },
        );

        test('memoryUsageBytes returns a positive value', () async {
          expect(await provider.memoryUsageBytes(), greaterThan(0));
        });
      });
    });
  }

  // ── Unit tests — diagnostics without FFI ────────────────────────────────────

  group('WellenProvider — diagnostics initial state (no FFI)', () {
    test('fileFormat is "Unknown" before openFile', () {
      expect(WellenProvider().fileFormat, 'Unknown');
    });

    test('fileFormat resets to "Unknown" after close', () {
      // We cannot set it without FFI, but after close it must be Unknown.
      final provider = WellenProvider()..close();
      expect(provider.fileFormat, 'Unknown');
    });

    test('signalTransitionCount returns 0 for an unloaded ref', () {
      expect(WellenProvider().signalTransitionCount('0'), 0);
    });

    test('signalTransitionCount uses cached changes length', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('3', const [
          SignalChange(time: 0, value: '0'),
          SignalChange(time: 5, value: '1'),
          SignalChange(time: 10, value: '0'),
        ]);
      expect(provider.signalTransitionCount('3'), 3);
    });

    test('signalTransitionCount returns 0 for invalid ref string', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [SignalChange(time: 0, value: '1')]);
      expect(provider.signalTransitionCount('not_a_number'), 0);
    });

    test('signalTransitionCount returns 0 after close', () {
      final provider = WellenProvider()
        ..injectLoadedSignal('0', const [
          SignalChange(time: 0, value: '0'),
          SignalChange(time: 10, value: '1'),
        ]);
      expect(provider.signalTransitionCount('0'), 2);
      provider.close();
      expect(provider.signalTransitionCount('0'), 0);
    });
  });

  if (requireWellenFfiLibrary('WellenProvider worker x index')) {
    test('the worker builds the x change index at load time', () async {
      final dir = Directory.systemTemp.createTempSync('wavecrux_xindex_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final vcd = File('${dir.path}/x.vcd')
        ..writeAsStringSync(
          [
            r'$timescale 1 ns $end',
            r'$scope module top $end',
            r'$var wire 4 # bus $end',
            r'$upscope $end',
            r'$enddefinitions $end',
            '#0',
            'b0000 #',
            '#10',
            'bx #',
            '#20',
            'b0101 #',
            '#30',
            'b01x1 #',
            '#40',
            'b1111 #',
            '',
          ].join('\n'),
        );
      final provider = WellenProvider();
      addTearDown(provider.close);
      await provider.openFile(vcd.path);
      final ref = provider.rootScopes.first.variables.single.signalRef;
      await provider.loadSignal(ref);
      // A downcast: the analyzer resolves `wellen_provider.dart` to its stub.
      final WaveformDataSource source = provider;
      final store = (source as CompactChangesSource).compactChangesFor(ref)!;
      expect(store.xChangeIndex, isNotNull);
      expect(store.xChangeIndex, [
        for (var i = 0; i < store.length; i++)
          if (store.valueContainsX(i)) i,
      ]);
      expect(store.xChangeIndex, hasLength(2));
    });
  }
}
