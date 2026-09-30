// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/ai_tool_registry_provider.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/ai/ai_tool_result.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

// ── Known-answer fixture ────────────────────────────────────────────────────────
//
// A hand-crafted in-memory waveform (the §8.9 "known-answer fixture" idea,
// without the FFI round-trip) so every tool assertion has an exact expected
// value and coordinate to resolve against.
//
//   top.clk   (1-bit):   0@0 1@10 0@20 1@30
//   top.data  (8-bit):   00000000@0 10101010@15
//   top.state (2-bit):   00@0 xx@5         ← goes X at tick 5, prev value "00"
//   range: [0, 40], timescale 1 ns

const _refClk = 's_clk';
const _refData = 's_data';
const _refState = 's_state';

Variable _v(String name, String ref, int width) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.input,
  signalRef: ref,
  scopePath: 'top',
  bitWidth: width,
);

List<Scope> _scopes() => [
  Scope(
    name: 'top',
    type: ScopeType.module,
    path: 'top',
    variables: [
      _v('clk', _refClk, 1),
      _v('data', _refData, 8),
      _v('state', _refState, 2),
    ],
  ),
];

Map<String, List<SignalChange>> _changes() => {
  _refClk: const [
    SignalChange(time: 0, value: '0'),
    SignalChange(time: 10, value: '1'),
    SignalChange(time: 20, value: '0'),
    SignalChange(time: 30, value: '1'),
  ],
  _refData: const [
    SignalChange(time: 0, value: '00000000'),
    SignalChange(time: 15, value: '10101010'),
  ],
  _refState: const [
    SignalChange(time: 0, value: '00'),
    SignalChange(time: 5, value: 'xx'),
  ],
};

List<ActiveDecoder> _decoders() => const [
  ActiveDecoder(
    id: 'decoder_0',
    decoderId: 'spi',
    config: DecoderConfig(signalBindings: {}),
    instanceNumber: 1,
    transactions: [
      DecodedTransaction(startTime: 5, endTime: 9, label: 'Write 0xFF'),
      DecodedTransaction(startTime: 20, endTime: 25, label: 'Read 0x00'),
    ],
  ),
  ActiveDecoder(
    id: 'decoder_1',
    decoderId: 'uart',
    config: DecoderConfig(signalBindings: {}),
    instanceNumber: 1,
    transactions: [
      DecodedTransaction(startTime: 12, endTime: 14, label: 'RX 0x41'),
    ],
  ),
];

class _FakeWaveformSource implements WaveformDataSource {
  _FakeWaveformSource({
    required this.rootScopes,
    required Map<String, List<SignalChange>> changes,
    required this.endTime,
    this.timescale,
  }) : _data = changes;

  @override
  final List<Scope> rootScopes;
  final Map<String, List<SignalChange>> _data;
  final Set<String> _loaded = {};

  @override
  int get startTime => 0;
  @override
  final int endTime;
  @override
  final Timescale? timescale;
  @override
  String? get date => null;
  @override
  String? get version => null;

  @override
  List<Variable> findVariables(SignalFilter filter) => [
    for (final s in rootScopes)
      for (final v in s.variables)
        if (filter.matches(v)) v,
  ];

  @override
  Future<void> loadSignal(String signalRef) async => _loaded.add(signalRef);

  @override
  bool isSignalLoaded(String signalRef) => _loaded.contains(signalRef);

  @override
  Future<void> unloadSignal(String signalRef) async =>
      _loaded.remove(signalRef);

  @override
  String? valueAt(String signalRef, int time) {
    if (!_loaded.contains(signalRef)) return null;
    final list = _data[signalRef];
    if (list == null) return null;
    String? v;
    for (final c in list) {
      if (c.time <= time) {
        v = c.value;
      } else {
        break;
      }
    }
    return v;
  }

  @override
  List<SignalChange> changesInRange(String signalRef, int start, int end) {
    if (!_loaded.contains(signalRef)) return const [];
    final list = _data[signalRef];
    if (list == null) return const [];
    return [
      for (final c in list)
        if (c.time >= start && c.time < end) c,
    ];
  }

  @override
  SignalChange? nextTransition(String signalRef, int afterTime) {
    if (!_loaded.contains(signalRef)) return null;
    for (final c in _data[signalRef] ?? const <SignalChange>[]) {
      if (c.time > afterTime) return c;
    }
    return null;
  }

  @override
  SignalChange? prevTransition(String signalRef, int beforeTime) {
    if (!_loaded.contains(signalRef)) return null;
    SignalChange? result;
    for (final c in _data[signalRef] ?? const <SignalChange>[]) {
      if (c.time < beforeTime) {
        result = c;
      } else {
        break;
      }
    }
    return result;
  }

  @override
  Future<void> openFile(String path) async {}
  @override
  void close() {}
}

// ── Test scaffolding ────────────────────────────────────────────────────────────

/// Hands a live [Ref] to the test so tool handlers can be invoked directly.
final _refProbe = Provider<Ref>((ref) => ref);

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;
  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

class _FixedDecodersNotifier extends ActiveDecodersNotifier {
  _FixedDecodersNotifier(this._initial);
  final List<ActiveDecoder> _initial;
  @override
  List<ActiveDecoder> build() => _initial;
}

ProviderContainer _container({
  WaveformDataSource? source,
  List<ActiveDecoder> decoders = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      waveformSourceProvider.overrideWith(() => _FakeSourceNotifier(source)),
      activeDecodersProvider.overrideWith(
        () => _FixedDecodersNotifier(decoders),
      ),
    ],
  );
  return container;
}

WaveformDataSource _loadedSource() => _FakeWaveformSource(
  rootScopes: _scopes(),
  changes: _changes(),
  endTime: 40,
  timescale: const Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds),
);

Future<AiToolResult> _invoke(
  ProviderContainer c,
  String tool,
  Map<String, Object?> args,
) {
  final registry = c.read(aiToolRegistryProvider);
  return registry.invoke(c.read(_refProbe), tool, args);
}

void main() {
  group('searchSignal', () {
    test('returns matching signals grounded in the hierarchy', () async {
      final c = _container(source: _loadedSource());
      addTearDown(c.dispose);

      final r = await _invoke(c, 'searchSignal', {'query': 'clk'});
      expect(r.isError, isFalse);
      final signals = r.data['signals']! as List;
      expect(signals, hasLength(1));
      expect((signals.first as Map)['path'], 'top.clk');
      expect((signals.first as Map)['signalRef'], _refClk);
      expect((signals.first as Map)['bitWidth'], 1);
    });

    test('empty query matches every signal', () async {
      final c = _container(source: _loadedSource());
      addTearDown(c.dispose);
      final r = await _invoke(c, 'searchSignal', {'query': ''});
      expect(r.data['matchCount'], 3);
    });

    test('fails (typed) when no waveform is loaded — never throws', () async {
      final c = _container();
      addTearDown(c.dispose);
      final r = await _invoke(c, 'searchSignal', {'query': 'clk'});
      expect(r.isError, isTrue);
      expect(r.error, contains('No waveform'));
    });
  });

  group('getTransitionsInWindow', () {
    test('returns real transitions and resolvable citations', () async {
      final c = _container(source: _loadedSource());
      addTearDown(c.dispose);

      final r = await _invoke(c, 'getTransitionsInWindow', {
        'signal': 'top.clk',
        'startTime': 0,
        'endTime': 25,
      });
      expect(r.isError, isFalse);
      expect(r.data['valueAtStart'], '0');
      final transitions = r.data['transitions']! as List;
      // clk changes at 0,10,20 fall in [0,25); 30 does not.
      expect(transitions.map((t) => (t as Map)['time']).toList(), [0, 10, 20]);

      // Every citation resolves to a real (signal, time): the signal loads and
      // a transition exists at the cited tick.
      final source = c.read(waveformSourceProvider).value!;
      for (final cit in r.citations) {
        expect(cit.signalRef, _refClk);
        await source.loadSignal(cit.signalRef!);
        final at = source.changesInRange(
          cit.signalRef!,
          cit.time!,
          cit.time! + 1,
        );
        expect(at, isNotEmpty, reason: 'citation @${cit.time} must be real');
      }
    });

    test('resolves a signal by signalRef as well as by path', () async {
      final c = _container(source: _loadedSource());
      addTearDown(c.dispose);
      final r = await _invoke(c, 'getTransitionsInWindow', {
        'signal': _refData,
        'startTime': 0,
        'endTime': 40,
      });
      expect(r.data['signal'], 'top.data');
      expect(r.data['transitions']! as List, hasLength(2));
    });

    test('unknown signal fails (typed)', () async {
      final c = _container(source: _loadedSource());
      addTearDown(c.dispose);
      final r = await _invoke(c, 'getTransitionsInWindow', {
        'signal': 'top.nope',
        'startTime': 0,
        'endTime': 40,
      });
      expect(r.isError, isTrue);
    });
  });

  group('listDecodedTransactions', () {
    test('lists all transactions sorted by start time', () async {
      final c = _container(source: _loadedSource(), decoders: _decoders());
      addTearDown(c.dispose);

      final r = await _invoke(c, 'listDecodedTransactions', const {});
      final txns = r.data['transactions']! as List;
      expect(txns.map((t) => (t as Map)['startTime']).toList(), [5, 12, 20]);
      expect(r.citations.map((cit) => cit.time).toList(), [5, 12, 20]);
    });

    test('filters by time window (overlap)', () async {
      final c = _container(source: _loadedSource(), decoders: _decoders());
      addTearDown(c.dispose);
      final r = await _invoke(c, 'listDecodedTransactions', {
        'startTime': 10,
        'endTime': 30,
      });
      final txns = r.data['transactions']! as List;
      // tx@5-9 excluded; tx@12-14 and tx@20-25 included.
      expect(txns.map((t) => (t as Map)['startTime']).toList(), [12, 20]);
    });

    test('filters by decoder id', () async {
      final c = _container(source: _loadedSource(), decoders: _decoders());
      addTearDown(c.dispose);
      final r = await _invoke(c, 'listDecodedTransactions', {
        'decoderId': 'spi',
      });
      final txns = r.data['transactions']! as List;
      expect(txns.map((t) => (t as Map)['startTime']).toList(), [5, 20]);
    });
  });

  group('getSelectionContext', () {
    test('is deterministic for the same selection + window', () async {
      final c = _container(source: _loadedSource(), decoders: _decoders());
      addTearDown(c.dispose);

      Future<Map<String, Object?>> run() async => (await _invoke(
        c,
        'getSelectionContext',
        {
          'signals': ['top.clk', 'top.state'],
          'startTime': 0,
          'endTime': 40,
        },
      )).data;

      final first = await run();
      final second = await run();
      expect(first, second);
    });

    test(
      'summarizes signals, grounds an X-origin, and cites real coordinates',
      () async {
        final c = _container(source: _loadedSource(), decoders: _decoders());
        addTearDown(c.dispose);

        final r = await _invoke(c, 'getSelectionContext', {
          'signals': ['top.state', 'top.clk'],
          'startTime': 0,
          'endTime': 40,
        });
        expect(r.isError, isFalse);

        final signals = r.data['signals']! as List;
        // Sorted by path: clk before state.
        expect((signals.first as Map)['path'], 'top.clk');
        final state =
            signals.firstWhere((s) => (s as Map)['path'] == 'top.state')
                as Map<String, Object?>;
        expect(state['valueAtStart'], '00');
        final xOrigin = state['xOrigin']! as Map;
        expect(xOrigin['originTime'], 5);
        expect(xOrigin['previousValue'], '00');

        // Decoded transactions overlapping [0,40] are folded in, sorted by start.
        final txns = r.data['transactions']! as List;
        expect(txns.map((t) => (t as Map)['startTime']).toList(), [5, 12, 20]);

        // Every citation resolves to a real coordinate.
        const knownRefs = {_refClk, _refData, _refState};
        for (final cit in r.citations) {
          if (cit.time != null) {
            expect(cit.time, inInclusiveRange(0, 40));
          }
          if (cit.signalRef != null) {
            expect(knownRefs, contains(cit.signalRef));
          }
        }
        // The X-origin coordinate (state @ tick 5) is among the citations.
        expect(
          r.citations.any((cit) => cit.signalRef == _refState && cit.time == 5),
          isTrue,
        );
      },
    );

    test(
      'defaults to the current tree selection when no signals are given',
      () async {
        final c = _container(source: _loadedSource());
        addTearDown(c.dispose);
        // The tree selection is keyed by fullPath (row identity), not ref.
        c.read(selectedVariablesProvider.notifier).toggle('top.data');

        final r = await _invoke(c, 'getSelectionContext', const {});
        final signals = r.data['signals']! as List;
        expect(signals, hasLength(1));
        expect((signals.first as Map)['path'], 'top.data');
      },
    );

    test('fails (typed) when no waveform is loaded', () async {
      final c = _container();
      addTearDown(c.dispose);
      final r = await _invoke(c, 'getSelectionContext', const {});
      expect(r.isError, isTrue);
    });
  });

  group('jumpCursor', () {
    test('moves the primary cursor and cites the resulting time', () async {
      final c = _container(source: _loadedSource());
      addTearDown(c.dispose);

      final r = await _invoke(c, 'jumpCursor', {'time': 25});
      expect(r.isError, isFalse);
      expect(r.data['cursorTime'], 25);
      expect(c.read(cursorStateProvider).primaryCursorTime, 25);
      expect(r.citations.single.time, 25);
    });

    test('missing time fails (typed)', () async {
      final c = _container(source: _loadedSource());
      addTearDown(c.dispose);
      final r = await _invoke(c, 'jumpCursor', const {});
      expect(r.isError, isTrue);
    });
  });

  group('addMarker', () {
    test('places a marker and picks the next free letter', () async {
      final c = _container(source: _loadedSource());
      addTearDown(c.dispose);

      final a = await _invoke(c, 'addMarker', {'time': 12});
      expect(a.data['name'], 'a');
      expect(c.read(markerStateProvider).markers['a'], 12);

      final b = await _invoke(c, 'addMarker', {'time': 18});
      expect(b.data['name'], 'b');

      final named = await _invoke(c, 'addMarker', {'time': 30, 'name': 'z'});
      expect(named.data['name'], 'z');
      expect(named.citations.single.time, 30);
    });

    test('missing time fails (typed)', () async {
      final c = _container(source: _loadedSource());
      addTearDown(c.dispose);
      final r = await _invoke(c, 'addMarker', const {});
      expect(r.isError, isTrue);
    });
  });
}
