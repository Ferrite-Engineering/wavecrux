// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/translate_filter_provider.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/translate/translate_filter_service.dart';

// ── fakes & mocks ─────────────────────────────────────────────────────────────

class _MockSource extends Mock implements WaveformDataSource {}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

class _FakeTranslateFilterNotifier extends TranslateFilterNotifier {
  _FakeTranslateFilterNotifier(this._initial);
  final Map<String, TranslateFilter> _initial;

  @override
  Map<String, TranslateFilter> build() => Map.unmodifiable(_initial);
}

// ── helpers ───────────────────────────────────────────────────────────────────

Variable _variable(
  String name,
  String ref, {
  int? bitWidth,
  VarType varType = VarType.wire,
}) => Variable(
  name: name,
  signalRef: ref,
  varType: varType,
  direction: VarDirection.unknown,
  scopePath: 'top',
  bitWidth: bitWidth,
);

Variable _v1(String name, String ref) => _variable(name, ref, bitWidth: 1);
Variable _v8(String name, String ref) => _variable(name, ref, bitWidth: 8);
Variable _v4(String name, String ref) => _variable(name, ref, bitWidth: 4);

Scope _scope(List<Variable> variables) => Scope(
  name: 'top',
  path: 'top',
  type: ScopeType.module,
  variables: variables,
);

ProviderContainer _container({
  WaveformDataSource? source,
  List<Override> extras = const [],
}) {
  final c = ProviderContainer(
    overrides: [
      waveformSourceProvider.overrideWith(
        () => _FakeSourceNotifier(source),
      ),
      ...extras,
    ],
  );
  addTearDown(c.dispose);
  return c;
}

// ── SignalValue ───────────────────────────────────────────────────────────────

void main() {
  group('SignalValue', () {
    test('hasX true when rawValue contains x', () {
      const sv = SignalValue(formatted: 'x', rawValue: 'x');
      expect(sv.hasX, isTrue);
      expect(sv.hasZ, isFalse);
    });

    test('hasX true for uppercase X', () {
      const sv = SignalValue(formatted: 'X', rawValue: 'X');
      expect(sv.hasX, isTrue);
    });

    test('hasZ true when rawValue contains z but no x', () {
      const sv = SignalValue(formatted: 'z', rawValue: 'z');
      expect(sv.hasZ, isTrue);
      expect(sv.hasX, isFalse);
    });

    test('hasZ false when rawValue contains both x and z', () {
      const sv = SignalValue(formatted: 'xz', rawValue: 'xz');
      expect(sv.hasX, isTrue);
      expect(sv.hasZ, isFalse);
    });

    test('neither flag set for normal binary value', () {
      const sv = SignalValue(formatted: '0', rawValue: '0');
      expect(sv.hasX, isFalse);
      expect(sv.hasZ, isFalse);
    });

    test('equality and hashCode', () {
      const a = SignalValue(formatted: '0xff', rawValue: '11111111');
      const b = SignalValue(formatted: '0xff', rawValue: '11111111');
      const c = SignalValue(formatted: '0x00', rawValue: '00000000');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  // ── WaveformScrollNotifier ─────────────────────────────────────────────────

  group('WaveformScrollNotifier', () {
    test('starts at 0', () {
      final c = _container();
      expect(c.read(waveformScrollProvider), 0);
    });

    test('setOffset updates state', () {
      final c = _container();
      c.read(waveformScrollProvider.notifier).setOffset(42.5);
      expect(c.read(waveformScrollProvider), 42.5);
    });

    test('setOffset with same value is a no-op', () {
      final c = _container();
      c.read(waveformScrollProvider.notifier).setOffset(10);
      final before = c.read(waveformScrollProvider);
      c.read(waveformScrollProvider.notifier).setOffset(10);
      final after = c.read(waveformScrollProvider);
      expect(before, after);
    });
  });

  // ── CanvasViewportHeightNotifier ───────────────────────────────────────────

  group('CanvasViewportHeightNotifier', () {
    test('starts at 0 (value column falls back to filling its pane)', () {
      final c = _container();
      expect(c.read(canvasViewportHeightProvider), 0);
    });

    test('setHeight publishes the canvas viewport height', () {
      final c = _container();
      c.read(canvasViewportHeightProvider.notifier).setHeight(152);
      expect(c.read(canvasViewportHeightProvider), 152);
    });

    test('setHeight with same value is a no-op', () {
      final c = _container();
      c.read(canvasViewportHeightProvider.notifier).setHeight(200);
      final before = c.read(canvasViewportHeightProvider);
      c.read(canvasViewportHeightProvider.notifier).setHeight(200);
      expect(c.read(canvasViewportHeightProvider), before);
    });
  });

  // ── signalValuesAtCursorProvider ──────────────────────────────────────────

  group('signalValuesAtCursor', () {
    test('returns empty map when source is null', () {
      final c = _container();
      expect(c.read(signalValuesAtCursorProvider), isEmpty);
    });

    test('returns empty map when no signals in group', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([]);

      final c = _container(source: source);
      expect(c.read(signalValuesAtCursorProvider), isEmpty);
    });

    test('returns empty map when signal is not loaded', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v1('clk', 'ref_clk')]),
      ]);
      when(() => source.isSignalLoaded('ref_clk')).thenReturn(false);

      final c = _container(source: source);
      c
          .read(signalGroupsProvider.notifier)
          .addSignal(
            _v1('clk', 'ref_clk'),
          );

      expect(c.read(signalValuesAtCursorProvider), isEmpty);
    });

    test('formats loaded signal value at start time when no cursor', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v1('clk', 'ref_clk')]),
      ]);
      when(() => source.isSignalLoaded('ref_clk')).thenReturn(true);
      when(() => source.valueAt('ref_clk', 0)).thenReturn('1');

      final c = _container(source: source);
      c
          .read(signalGroupsProvider.notifier)
          .addSignal(
            _v1('clk', 'ref_clk'),
          );

      final values = c.read(signalValuesAtCursorProvider);
      expect(values['ref_clk']?.formatted, '1');
      expect(values['ref_clk']?.rawValue, '1');
    });

    test('uses cursor time when primary cursor is placed', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v4('d', 'ref_d')]),
      ]);
      when(() => source.isSignalLoaded('ref_d')).thenReturn(true);
      when(() => source.valueAt('ref_d', 100)).thenReturn('1010');
      when(() => source.valueAt('ref_d', 0)).thenReturn('0000');

      final c = _container(source: source);
      c.read(signalGroupsProvider.notifier).addSignal(_v4('d', 'ref_d'));
      c.read(cursorStateProvider.notifier).placePrimary(100);

      expect(c.read(signalValuesAtCursorProvider)['ref_d']?.rawValue, '1010');
    });

    test('formats 8-bit hex signal correctly', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v8('data', 'ref_data')]),
      ]);
      when(() => source.isSignalLoaded('ref_data')).thenReturn(true);
      when(() => source.valueAt('ref_data', 0)).thenReturn('11111111');

      final c = _container(source: source);
      c
          .read(signalGroupsProvider.notifier)
          .addSignal(
            _v8('data', 'ref_data'),
          );

      // Default format for 8-bit is hex → 'ff'
      expect(c.read(signalValuesAtCursorProvider)['ref_data']?.formatted, 'ff');
    });

    test('respects per-signal DisplayFormat from SignalEntry', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v8('data', 'ref_data')]),
      ]);
      when(() => source.isSignalLoaded('ref_data')).thenReturn(true);
      when(() => source.valueAt('ref_data', 0)).thenReturn('11111111');

      final c = _container(source: source);
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v8('data', 'ref_data'))
        ..setSignalFormat(0, DisplayFormat.binary);

      expect(
        c.read(signalValuesAtCursorProvider)['ref_data']?.formatted,
        '11111111',
      );
    });

    test('reports hasX true for x-valued signal', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v1('clk', 'ref_clk')]),
      ]);
      when(() => source.isSignalLoaded('ref_clk')).thenReturn(true);
      when(() => source.valueAt('ref_clk', 0)).thenReturn('x');

      final c = _container(source: source);
      c
          .read(signalGroupsProvider.notifier)
          .addSignal(
            _v1('clk', 'ref_clk'),
          );

      expect(c.read(signalValuesAtCursorProvider)['ref_clk']?.hasX, isTrue);
    });

    test('reports hasZ true for z-valued signal', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v1('bus', 'ref_bus')]),
      ]);
      when(() => source.isSignalLoaded('ref_bus')).thenReturn(true);
      when(() => source.valueAt('ref_bus', 0)).thenReturn('z');

      final c = _container(source: source);
      c
          .read(signalGroupsProvider.notifier)
          .addSignal(
            _v1('bus', 'ref_bus'),
          );

      expect(c.read(signalValuesAtCursorProvider)['ref_bus']?.hasZ, isTrue);
    });

    test('omits signal when valueAt returns null', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v1('clk', 'ref_clk')]),
      ]);
      when(() => source.isSignalLoaded('ref_clk')).thenReturn(true);
      when(() => source.valueAt('ref_clk', 0)).thenReturn(null);

      final c = _container(source: source);
      c
          .read(signalGroupsProvider.notifier)
          .addSignal(
            _v1('clk', 'ref_clk'),
          );

      expect(c.read(signalValuesAtCursorProvider), isEmpty);
    });

    test('processes signals at top level', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v1('d', 'ref_d')]),
      ]);
      when(() => source.isSignalLoaded('ref_d')).thenReturn(true);
      when(() => source.valueAt('ref_d', 0)).thenReturn('1');

      final c = _container(source: source);
      c.read(signalGroupsProvider.notifier).addSignal(_v1('d', 'ref_d'));

      expect(c.read(signalValuesAtCursorProvider).containsKey('ref_d'), isTrue);
    });
  });

  // ── setSignalFormatByRef ───────────────────────────────────────────────────

  group('SignalGroupsNotifier.setSignalFormatByRef', () {
    test('updates format on top-level signal', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v8('d', 'ref_d'))
        ..setSignalFormatByRef('ref_d', DisplayFormat.binary);
      expect(
        c.read(signalGroupsProvider).entries.first.format,
        DisplayFormat.binary,
      );
    });

    test('no-op when signalRef not found', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v8('d', 'ref_d'));
      final before = c.read(signalGroupsProvider).entries.first.format;
      c
          .read(signalGroupsProvider.notifier)
          .setSignalFormatByRef('nonexistent', DisplayFormat.octal);
      expect(
        c.read(signalGroupsProvider).entries.first.format,
        before,
      );
    });

    test('updates format on signal found by ref', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v1('a', 'ref_a'))
        ..addSignal(_v8('d', 'ref_d'))
        ..setSignalFormatByRef('ref_d', DisplayFormat.ascii);
      final entry = c
          .read(signalGroupsProvider)
          .entries
          .firstWhere((e) => e.signalRef == 'ref_d');
      expect(entry.format, DisplayFormat.ascii);
    });

    test('does not affect other signals when updating one', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v1('clk', 'ref_clk'))
        ..addSignal(_v8('data', 'ref_data'))
        ..setSignalFormatByRef('ref_data', DisplayFormat.binary);
      final clkEntry = c
          .read(signalGroupsProvider)
          .entries
          .firstWhere((e) => e.signalRef == 'ref_clk');
      // clk (1-bit) defaults to binary; unchanged
      expect(clkEntry.format, DisplayFormat.hexadecimal);
    });
  });

  // ── translate filter integration ──────────────────────────────────────────

  group('signalValuesAtCursor with translate filter', () {
    TranslateFilter makeFilter(Map<String, String> labelMap) {
      final content = labelMap.entries
          .map((e) => '${e.key} ${e.value}')
          .join('\n');
      return const TranslateFilterService().parse(content);
    }

    ProviderContainer containerWithFilter({
      required WaveformDataSource source,
      required String signalRef,
      required TranslateFilter filter,
    }) {
      final c = ProviderContainer(
        overrides: [
          waveformSourceProvider.overrideWith(
            () => _FakeSourceNotifier(source),
          ),
          translateFilterProvider.overrideWith(
            () => _FakeTranslateFilterNotifier({signalRef: filter}),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('returns translated label as formatted when filter matches', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v8('state', 'ref_state')]),
      ]);
      when(() => source.isSignalLoaded('ref_state')).thenReturn(true);
      // decimal 2 == binary 00000010 → "RUNNING"
      when(() => source.valueAt('ref_state', 0)).thenReturn('00000010');

      final filter = makeFilter({'2': 'RUNNING'});
      final c = containerWithFilter(
        source: source,
        signalRef: 'ref_state',
        filter: filter,
      );
      c
          .read(signalGroupsProvider.notifier)
          .addSignal(
            _v8('state', 'ref_state'),
          );

      final value = c.read(signalValuesAtCursorProvider)['ref_state'];
      expect(value?.formatted, 'RUNNING');
    });

    test('isFiltered true when filter label is applied', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v8('state', 'ref_state')]),
      ]);
      when(() => source.isSignalLoaded('ref_state')).thenReturn(true);
      when(() => source.valueAt('ref_state', 0)).thenReturn('00000001');

      final filter = makeFilter({'1': 'IDLE'});
      final c = containerWithFilter(
        source: source,
        signalRef: 'ref_state',
        filter: filter,
      );
      c
          .read(signalGroupsProvider.notifier)
          .addSignal(
            _v8('state', 'ref_state'),
          );

      expect(
        c.read(signalValuesAtCursorProvider)['ref_state']?.isFiltered,
        isTrue,
      );
    });

    test('isFiltered false when no filter applied', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v8('data', 'ref_data')]),
      ]);
      when(() => source.isSignalLoaded('ref_data')).thenReturn(true);
      when(() => source.valueAt('ref_data', 0)).thenReturn('11111111');

      final c = _container(source: source);
      c
          .read(signalGroupsProvider.notifier)
          .addSignal(
            _v8('data', 'ref_data'),
          );

      expect(
        c.read(signalValuesAtCursorProvider)['ref_data']?.isFiltered,
        isFalse,
      );
    });

    test(
      'falls back to numeric format when filter returns null (no match)',
      () {
        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.rootScopes).thenReturn([
          _scope([_v8('state', 'ref_state')]),
        ]);
        when(() => source.isSignalLoaded('ref_state')).thenReturn(true);
        // Value 0xFF (11111111) has no entry in filter → falls back to hex
        when(() => source.valueAt('ref_state', 0)).thenReturn('11111111');

        final filter = makeFilter({'0': 'ZERO'});
        final c = containerWithFilter(
          source: source,
          signalRef: 'ref_state',
          filter: filter,
        );
        c
            .read(signalGroupsProvider.notifier)
            .addSignal(
              _v8('state', 'ref_state'),
            );

        final value = c.read(signalValuesAtCursorProvider)['ref_state'];
        expect(value?.formatted, 'ff');
        expect(value?.isFiltered, isFalse);
      },
    );

    test('falls back to numeric format for x-value (filter returns null)', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v8('state', 'ref_state')]),
      ]);
      when(() => source.isSignalLoaded('ref_state')).thenReturn(true);
      when(() => source.valueAt('ref_state', 0)).thenReturn('xxxxxxxx');

      final filter = makeFilter({'0': 'ZERO', '1': 'ONE'});
      final c = containerWithFilter(
        source: source,
        signalRef: 'ref_state',
        filter: filter,
      );
      c
          .read(signalGroupsProvider.notifier)
          .addSignal(
            _v8('state', 'ref_state'),
          );

      final value = c.read(signalValuesAtCursorProvider)['ref_state'];
      expect(value?.isFiltered, isFalse);
      expect(value?.hasX, isTrue);
    });

    test('rawValue is unchanged regardless of filter', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v8('state', 'ref_state')]),
      ]);
      when(() => source.isSignalLoaded('ref_state')).thenReturn(true);
      when(() => source.valueAt('ref_state', 0)).thenReturn('00000011');

      final filter = makeFilter({'3': 'ERROR'});
      final c = containerWithFilter(
        source: source,
        signalRef: 'ref_state',
        filter: filter,
      );
      c
          .read(signalGroupsProvider.notifier)
          .addSignal(
            _v8('state', 'ref_state'),
          );

      expect(
        c.read(signalValuesAtCursorProvider)['ref_state']?.rawValue,
        '00000011',
      );
    });
  });

  // ── signalValueAtCursorProvider (per-signal family — cursor-scrub hot
  //    path; see provider docs for rationale).
  // ─────────────────────────────────────────────────────────────────────────

  group('signalValueAtCursor (family)', () {
    test('returns null when source is null', () {
      final c = _container();
      expect(
        c.read(
          signalValueAtCursorProvider('ref_a', DisplayFormat.hexadecimal, null),
        ),
        isNull,
      );
    });

    test('returns null when signal is not loaded', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(1000);
      when(() => source.rootScopes).thenReturn([
        _scope([_v1('a', 'ref_a')]),
      ]);
      when(() => source.isSignalLoaded('ref_a')).thenReturn(false);

      final c = _container(source: source);
      expect(
        c.read(
          signalValueAtCursorProvider('ref_a', DisplayFormat.hexadecimal, null),
        ),
        isNull,
      );
    });

    test('returns formatted SignalValue at cursor time when loaded', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(1000);
      when(() => source.rootScopes).thenReturn([
        _scope([_v8('data', 'ref_data')]),
      ]);
      when(() => source.isSignalLoaded('ref_data')).thenReturn(true);
      when(() => source.valueAt('ref_data', 500)).thenReturn('11111111');

      final c = _container(source: source);
      c.read(cursorStateProvider.notifier).placePrimary(500);

      final value = c.read(
        signalValueAtCursorProvider(
          'ref_data',
          DisplayFormat.hexadecimal,
          null,
        ),
      );
      expect(value, isNotNull);
      expect(value!.formatted, 'ff');
      expect(value.rawValue, '11111111');
      expect(value.hasX, isFalse);
      expect(value.hasZ, isFalse);
    });

    test('uses startTime when no cursor placed', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(100);
      when(() => source.endTime).thenReturn(1000);
      when(() => source.rootScopes).thenReturn([
        _scope([_v1('clk', 'ref_clk')]),
      ]);
      when(() => source.isSignalLoaded('ref_clk')).thenReturn(true);
      when(() => source.valueAt('ref_clk', 100)).thenReturn('1');

      final c = _container(source: source);
      // No placePrimary call — cursor is null, so provider should fall back
      // to source.startTime (100).
      final value = c.read(
        signalValueAtCursorProvider('ref_clk', DisplayFormat.binary, null),
      );
      expect(value?.rawValue, '1');
    });

    test('updates when cursor moves', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(1000);
      when(() => source.rootScopes).thenReturn([
        _scope([_v8('d', 'ref_d')]),
      ]);
      when(() => source.isSignalLoaded('ref_d')).thenReturn(true);
      when(() => source.valueAt('ref_d', 100)).thenReturn('00000001');
      when(() => source.valueAt('ref_d', 200)).thenReturn('00000010');

      final c = _container(source: source);
      c.read(cursorStateProvider.notifier).placePrimary(100);
      expect(
        c
            .read(
              signalValueAtCursorProvider(
                'ref_d',
                DisplayFormat.hexadecimal,
                null,
              ),
            )
            ?.formatted,
        '01',
      );

      c.read(cursorStateProvider.notifier).placePrimary(200);
      expect(
        c
            .read(
              signalValueAtCursorProvider(
                'ref_d',
                DisplayFormat.hexadecimal,
                null,
              ),
            )
            ?.formatted,
        '02',
      );
    });

    test('different formats produce different formatted strings', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(1000);
      when(() => source.rootScopes).thenReturn([
        _scope([_v4('n', 'ref_n')]),
      ]);
      when(() => source.isSignalLoaded('ref_n')).thenReturn(true);
      when(() => source.valueAt('ref_n', 0)).thenReturn('1010');

      final c = _container(source: source);
      final hex = c.read(
        signalValueAtCursorProvider('ref_n', DisplayFormat.hexadecimal, null),
      );
      final bin = c.read(
        signalValueAtCursorProvider('ref_n', DisplayFormat.binary, null),
      );
      expect(hex?.formatted, 'a');
      expect(bin?.formatted, '1010');
    });

    test('static translate filter is applied when present', () {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(1000);
      when(() => source.rootScopes).thenReturn([
        _scope([_v8('state', 'ref_state')]),
      ]);
      when(() => source.isSignalLoaded('ref_state')).thenReturn(true);
      when(() => source.valueAt('ref_state', 0)).thenReturn('00000001');

      final filter = TranslateFilter({
        BigInt.from(1): 'IDLE',
        BigInt.from(2): 'BUSY',
      });
      final c = _container(
        source: source,
        extras: [
          translateFilterProvider.overrideWith(
            () => _FakeTranslateFilterNotifier({'ref_state': filter}),
          ),
        ],
      );

      final value = c.read(
        signalValueAtCursorProvider(
          'ref_state',
          DisplayFormat.hexadecimal,
          null,
        ),
      );
      expect(value?.formatted, 'IDLE');
      expect(value?.isFiltered, isTrue);
    });

    test('does NOT depend on signalGroupsProvider', () async {
      // Critical performance contract: the family provider must NOT watch
      // signalGroups, otherwise any signal-list edit (drag-reorder, color
      // cycle, format change, etc.) would invalidate the per-signal value
      // for every visible row, defeating the laziness optimisation.
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(1000);
      when(() => source.rootScopes).thenReturn([
        _scope([_v1('a', 'ref_a')]),
      ]);
      when(() => source.isSignalLoaded('ref_a')).thenReturn(true);
      when(() => source.valueAt('ref_a', any())).thenReturn('1');

      final c = _container(source: source);
      // Read once to materialise the provider state.
      final first = c.read(
        signalValueAtCursorProvider('ref_a', DisplayFormat.binary, null),
      );
      expect(first, isNotNull);

      // Mutate the signal group — the family provider should not invalidate.
      c.read(signalGroupsProvider.notifier).addGroup('Bus signals');

      // Re-read; should be the same SignalValue *instance* (provider cached).
      final second = c.read(
        signalValueAtCursorProvider('ref_a', DisplayFormat.binary, null),
      );
      expect(
        identical(first, second),
        isTrue,
        reason: 'family provider must not depend on signalGroupsProvider',
      );
    });
  });
}
