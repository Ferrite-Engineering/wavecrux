// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// WCP's `wavecrux.getTransitionsInWindow` against the `transitions` command
// and the in-app assistant's `getTransitionsInWindow` tool: one answer on
// three surfaces, from the one `transitionsInWindow`. Expected changes are
// worked by hand from `test/fixtures/vcd/transitions_glitch.vcd` (clk toggles
// every 5 ticks; irq is 1 for the single tick 12; bus changes at 0, 10, 20
// and 30) and from the injected changes below.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/core/providers/ai_tool_registry_provider.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/headless/wave_commands.dart';
import 'package:wavecrux/headless/wave_file_cache.dart';
import 'package:wavecrux/headless/wavecrux_cli.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/waveform/wellen_provider_io.dart';

import '../../helpers/product_telemetry_config.dart';
import '../../helpers/wellen_ffi_library_gate.dart';

const String _command = 'wavecrux.getTransitionsInWindow';

// ── a WCP client ──────────────────────────────────────────────────────────────

class _WcpSocket {
  _WcpSocket(this._socket) {
    _socket.listen(_onData, onDone: () {}, onError: (_) {});
  }

  final Socket _socket;
  final List<int> _buf = [];
  final List<Map<String, dynamic>> _frames = [];
  Completer<void>? _waiting;

  void _onData(List<int> chunk) {
    _buf.addAll(chunk);
    while (true) {
      final idx = _buf.indexOf(0);
      if (idx < 0) break;
      final bytes = List<int>.from(_buf.sublist(0, idx));
      _buf.removeRange(0, idx + 1);
      if (bytes.isNotEmpty) {
        _frames.add(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
        _waiting?.complete();
        _waiting = null;
      }
    }
  }

  Future<Map<String, dynamic>> next() async {
    while (_frames.isEmpty) {
      _waiting = Completer<void>();
      await _waiting!.future.timeout(const Duration(seconds: 5));
    }
    return _frames.removeAt(0);
  }

  /// A spec-envelope command: parameters at the top level, no id.
  Future<Map<String, dynamic>> spec(
    String command,
    Map<String, dynamic> params,
  ) {
    _socket.add([
      ...utf8.encode(
        jsonEncode({'type': 'command', 'command': command, ...params}),
      ),
      0,
    ]);
    return next();
  }

  /// A legacy id-dialect command: parameters under `data`.
  Future<Map<String, dynamic>> legacy(
    String command,
    Map<String, dynamic> data,
  ) {
    _socket.add([
      ...utf8.encode(
        jsonEncode({
          'type': 'command',
          'id': 7,
          'command': command,
          'data': data,
        }),
      ),
      0,
    ]);
    return next();
  }
}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

/// The app with [source] in its active tab and the WCP server listening; a
/// connected client.
Future<_WcpSocket> _connect(WaveformDataSource? source) async {
  final tcm = TabContainerManager(
    extraTabOverrides: [
      waveformSourceProvider.overrideWith(() => _FakeSourceNotifier(source)),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      tabContainerManagerProvider.overrideWithValue(tcm),
      waveformSourceProvider.overrideWith(() => _FakeSourceNotifier(null)),
    ],
  );
  tcm.init(container);
  final notifier = container.read(remoteControlProvider.notifier);
  await notifier.startServer(0);
  addTearDown(() async {
    await notifier.stopServer();
    tcm.dispose();
    container.dispose();
  });
  final socket = await Socket.connect(
    '127.0.0.1',
    container.read(remoteControlProvider).port,
  );
  addTearDown(socket.destroy);
  final ws = _WcpSocket(socket);
  await ws.next(); // greeting
  return ws;
}

/// The reply's payload: the frame without its envelope.
Map<String, dynamic> _payload(Map<String, dynamic> frame) {
  expect(frame['type'], 'response', reason: '$frame');
  expect(frame['command'], _command);
  return Map<String, dynamic>.of(frame)
    ..remove('type')
    ..remove('command');
}

Future<Map<String, dynamic>> _ask(
  _WcpSocket ws,
  List<String> signals,
  int start,
  int end, {
  int? limit,
}) async => _payload(
  await ws.spec(_command, {
    'signal_paths': signals,
    'start': start,
    'end': end,
    'limit': ?limit,
  }),
);

List<Map<String, dynamic>> _signals(Map<String, dynamic> reply) =>
    (reply['signals'] as List).cast<Map<String, dynamic>>();

List<Map<String, dynamic>> _transitions(Map<String, dynamic> signal) =>
    (signal['transitions'] as List).cast<Map<String, dynamic>>();

/// [value] as it reads after a trip through JSON, so a Dart map and a decoded
/// reply compare byte for byte.
Object? _wire(Object? value) => jsonDecode(jsonEncode(value));

// ── injected sources (no native library) ──────────────────────────────────────

Variable _wire1(String name, String ref) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: ref,
  scopePath: 'top',
  bitWidth: 1,
);

/// `top.busy` toggles at every tick from 0 to 699 (700 changes); `top.split`
/// changes at 0, twice at 5, and at 9.
WellenProvider _injected() {
  final busy = _wire1('busy', '0');
  final split = _wire1('split', '1');
  return WellenProvider()
    ..injectHierarchy([
      Scope(
        name: 'top',
        type: ScopeType.module,
        path: 'top',
        variables: [busy, split],
      ),
    ])
    ..injectLoadedSignal('0', [
      for (var t = 0; t < 700; t++)
        SignalChange(time: t, value: t.isEven ? '1' : '0'),
    ])
    ..injectLoadedSignal('1', const [
      SignalChange(time: 0, value: '0'),
      SignalChange(time: 5, value: '1'),
      SignalChange(time: 5, value: '0'),
      SignalChange(time: 9, value: '1'),
    ]);
}

// ── the tiling oracle ─────────────────────────────────────────────────────────

typedef _Window =
    Future<List<Map<String, dynamic>>> Function(int start, int end);

/// What goes wrong when [window] answers two windows that meet at a tick:
/// every split of `[0, last)` into `[0, e)` and `[e, last)` must give the
/// changes of `[0, last)`, each once. A window that drops the change at
/// exactly its end time, and then again at the next window's start, loses it;
/// one that keeps it at both returns it twice.
Future<List<String>> _tilingFaults(_Window window, int last) async {
  final whole = await window(0, last);
  final faults = <String>[];
  for (var e = 0; e <= last; e++) {
    final joined = [...await window(0, e), ...await window(e, last)];
    if (jsonEncode(joined) != jsonEncode(whole)) {
      faults.add('split at $e: $joined, not $whole');
    }
  }
  return faults;
}

void main() {
  group('bounds', () {
    test(
      'the signal count and limits are those of the transitions command',
      () {
        expect(kWcpTransitionsMaxSignals, kMaxSignalsPerCall);
        expect(kWcpTransitionsLimitDefault, kTransitionsLimitDefault);
        expect(kWcpTransitionsLimitMax, kTransitionsLimitMax);
      },
    );

    test('the window maximum lowers the limit of every signal alike', () {
      expect(kWcpTransitionsWindowMax, 20000);
      expect(wcpTransitionsLimit(200, 1), 200);
      expect(wcpTransitionsLimit(10000, 1), 10000);
      expect(wcpTransitionsLimit(10000, 2), 10000);
      expect(wcpTransitionsLimit(10000, 3), 6666); // 20000 ~/ 3
      expect(wcpTransitionsLimit(10000, 32), 625); // 20000 ~/ 32
      expect(wcpTransitionsLimit(200, 32), 200);
    });

    test('32 signals at the largest limit carry at most the window '
        'maximum, and each says where to go on', () async {
      final ws = await _connect(_injected());
      final reply = await _ask(
        ws,
        List.filled(32, 'top.busy'),
        0,
        1000,
        limit: 10000,
      );
      expect(reply['limit'], 625);
      expect(reply['truncated'], isTrue);
      final signals = _signals(reply);
      expect(signals, hasLength(32));
      for (final s in signals) {
        expect(s['transitionCount'], 700);
        expect(s['returned'], 625);
        expect(s['truncated'], isTrue);
        // The 625th change is at tick 624.
        expect(_transitions(s).last['time'], 624);
        expect(s['next_from'], 625);
      }
    });

    test(
      'limit defaults to 200; an answer that fits is not truncated',
      () async {
        final ws = await _connect(_injected());
        final reply = await _ask(ws, ['top.busy', 'top.split'], 0, 1000);
        expect(reply['limit'], 200);
        expect(reply['truncated'], isTrue);
        final [busy, split] = _signals(reply);
        expect(busy['returned'], 200);
        expect(busy['next_from'], 200);
        expect(split['truncated'], isFalse);
        expect(split['next_from'], isNull);
        expect(reply['same_tick_split'], isEmpty);
      },
    );

    test('a limit that falls among the changes at one tick is named', () async {
      final ws = await _connect(_injected());
      final reply = await _ask(ws, ['top.split'], 0, 10, limit: 2);
      expect(_transitions(_signals(reply).single).map((t) => t['time']), [
        0,
        5,
      ]);
      expect(_signals(reply).single['next_from'], 6);
      expect(reply['same_tick_split'], ['top.split']);
    });

    final refusals = <String, Map<String, dynamic>>{
      'no signal_paths': {'start': 0, 'end': 10},
      'an empty signal_paths': {
        'signal_paths': <String>[],
        'start': 0,
        'end': 10,
      },
      'a path that is not a string': {
        'signal_paths': [3],
        'start': 0,
        'end': 10,
      },
      '33 signals': {
        'signal_paths': List.filled(33, 'top.busy'),
        'start': 0,
        'end': 10,
      },
      'no end': {
        'signal_paths': ['top.busy'],
        'start': 0,
      },
      'a time that is not whole': {
        'signal_paths': ['top.busy'],
        'start': 0,
        'end': 2.5,
      },
      'a negative start': {
        'signal_paths': ['top.busy'],
        'start': -1,
        'end': 10,
      },
      'a start after the end': {
        'signal_paths': ['top.busy'],
        'start': 11,
        'end': 10,
      },
      'a limit of 0': {
        'signal_paths': ['top.busy'],
        'start': 0,
        'end': 10,
        'limit': 0,
      },
      'a limit past the most': {
        'signal_paths': ['top.busy'],
        'start': 0,
        'end': 10,
        'limit': 10001,
      },
    };
    for (final MapEntry(key: what, value: data) in refusals.entries) {
      test('$what is refused with code 3', () async {
        final ws = await _connect(_injected());
        final reply = await ws.legacy(_command, data);
        expect(reply['type'], 'error');
        expect(reply['code'], 3, reason: '${reply['message']}');
      });
    }

    test('an unknown signal is refused with code 6, naming it', () async {
      final ws = await _connect(_injected());
      final reply = await ws.legacy(_command, {
        'signal_paths': ['top.busy', 'top.nope'],
        'start': 0,
        'end': 10,
      });
      expect(reply['type'], 'error');
      expect(reply['code'], 6);
      expect(reply['message'], contains('top.nope'));
    });

    test('no waveform is refused with code 5', () async {
      final ws = await _connect(null);
      final reply = await ws.legacy(_command, {
        'signal_paths': ['top.busy'],
        'start': 0,
        'end': 10,
      });
      expect(reply['type'], 'error');
      expect(reply['code'], 5);
    });

    test('the greeting announces the command', () async {
      final tcm = TabContainerManager();
      final container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          tabContainerManagerProvider.overrideWithValue(tcm),
        ],
      );
      tcm.init(container);
      final notifier = container.read(remoteControlProvider.notifier);
      await notifier.startServer(0);
      addTearDown(() async {
        await notifier.stopServer();
        tcm.dispose();
        container.dispose();
      });
      final socket = await Socket.connect(
        '127.0.0.1',
        container.read(remoteControlProvider).port,
      );
      addTearDown(socket.destroy);
      final greeting = await _WcpSocket(socket).next();
      expect(greeting['commands'], contains(_command));
    });
  });

  if (!requireWellenFfiLibrary('WCP transitions on a fixture')) return;

  group('one answer on three surfaces', () {
    final fixture = p.absolute(
      'test',
      'fixtures',
      'vcd',
      'transitions_glitch.vcd',
    );
    late WaveFile wave;
    late _WcpSocket ws;

    setUp(() async {
      wave = await openWithWellen(fixture);
      addTearDown(wave.close);
      ws = await _connect(wave.source);
    });

    /// `wavecrux transitions --json`'s signals, each without its location.
    Future<List<Map<String, dynamic>>> cli(
      List<String> signals,
      int start,
      int end,
      int limit,
    ) async {
      final out = StringBuffer();
      final code = await WaveCruxCli(telemetry: () => null).run(
        [
          'transitions',
          fixture,
          for (final s in signals) ...['--signal', s],
          '--from',
          '$start',
          '--to',
          '$end',
          '--limit',
          '$limit',
          '--json',
        ],
        out: out,
        err: StringBuffer(),
      );
      expect(code, 0, reason: '$out');
      final body =
          (jsonDecode(out.toString()) as Map<String, dynamic>)['body']
              as Map<String, dynamic>;
      return [
        for (final s in (body['signals'] as List).cast<Map<String, dynamic>>())
          Map<String, dynamic>.of(s)..remove('location'),
      ];
    }

    /// The in-app assistant's `getTransitionsInWindow` answer for [signal].
    Future<Object?> assistant(
      String signal,
      int start,
      int end,
      int limit,
    ) async {
      final probe = Provider<Ref>((ref) => ref);
      final c = ProviderContainer(
        overrides: [
          waveformSourceProvider.overrideWith(
            () => _FakeSourceNotifier(wave.source),
          ),
        ],
      );
      addTearDown(c.dispose);
      final r = await c.read(aiToolRegistryProvider).invoke(
        c.read(probe),
        'getTransitionsInWindow',
        {
          'signal': signal,
          'startTime': start,
          'endTime': end,
          'limit': limit,
        },
      );
      expect(r.isError, isFalse, reason: r.error);
      return _wire(r.data);
    }

    final cases = <(List<String>, int, int, int)>[
      (['top.clk', 'top.irq', 'top.bus'], 0, 40, 200),
      (['top.clk'], 0, 41, 3),
      (['top.irq'], 10, 20, 200),
      (['top.bus'], 0, 30, 200),
      (['top.bus'], 30, 40, 200),
      (['top.bus', 'top.irq'], 12, 12, 200),
    ];
    for (final (signals, start, end, limit) in cases) {
      test('$signals in [$start, $end), limit $limit: WCP, the command line '
          'and the assistant agree', () async {
        final viaWcp = _signals(
          await _ask(ws, signals, start, end, limit: limit),
        );
        final legacy = await ws.legacy(_command, {
          'signal_paths': signals,
          'start': start,
          'end': end,
          'limit': limit,
        });
        final viaCli = await cli(signals, start, end, limit);
        expect(jsonEncode(viaWcp), jsonEncode(viaCli));
        expect(
          jsonEncode((legacy['data'] as Map)['signals']),
          jsonEncode(viaCli),
        );
        for (var i = 0; i < signals.length; i++) {
          final withoutNext = Map<String, dynamic>.of(viaWcp[i])
            ..remove('next_from');
          expect(
            jsonEncode(withoutNext),
            jsonEncode(await assistant(signals[i], start, end, limit)),
          );
        }
      });
    }

    test('a one-tick pulse between clock edges is returned, where sampling '
        'at every clock change misses it', () async {
      final irq = _signals(await _ask(ws, ['top.irq'], 10, 20)).single;
      expect(irq['valueAtStart'], '0');
      expect(_transitions(irq), [
        {'time': 12, 'value': '1'},
        {'time': 13, 'value': '0'},
      ]);
      for (var t = 0; t <= 40; t += 5) {
        final sample = await ws.spec('wavecrux.getValueAt', {
          'signal_path': 'top.irq',
          'time': t,
        });
        expect(sample['value'], '0', reason: 'tick $t');
      }
    });

    test('a change at exactly the end time is left out of its window and '
        'opens the next one', () async {
      final before = _signals(await _ask(ws, ['top.bus'], 0, 30)).single;
      expect(_transitions(before), [
        {'time': 0, 'value': 'xxxx'},
        {'time': 10, 'value': '0001'},
        {'time': 20, 'value': '0010'},
      ]);
      final after = _signals(await _ask(ws, ['top.bus'], 30, 40)).single;
      expect(after['valueAtStart'], '0011');
      expect(_transitions(after), [
        {'time': 30, 'value': '0011'},
      ]);
    });

    Future<List<Map<String, dynamic>>> wcpWindow(
      String signal,
      int start,
      int end,
    ) async =>
        _transitions(_signals(await _ask(ws, [signal], start, end)).single);

    test('windows that meet at a tick give every change once', () async {
      for (final signal in ['top.clk', 'top.irq', 'top.bus']) {
        expect(
          await _tilingFaults((s, e) => wcpWindow(signal, s, e), 41),
          isEmpty,
          reason: signal,
        );
      }
    });

    test('mutation proof: the tiling oracle fails a window that drops the '
        'change at exactly its end time, or keeps it twice', () async {
      // Drops the change at a seam: left out of the window it ends, as it
      // must be, and left out of the window it starts too.
      Future<List<Map<String, dynamic>>> dropsSeam(int s, int e) async => [
        for (final t in await wcpWindow('top.bus', s, e))
          if (s == 0 || t['time'] != s) t,
      ];
      // Keeps the change at the end time in the window it ends.
      Future<List<Map<String, dynamic>>> closed(int s, int e) =>
          wcpWindow('top.bus', s, e + 1);
      expect(await _tilingFaults(dropsSeam, 41), isNotEmpty);
      expect(await _tilingFaults(closed, 41), isNotEmpty);
    });

    test('paging from next_from returns every change once', () async {
      final whole = await wcpWindow('top.clk', 0, 41);
      final paged = <Map<String, dynamic>>[];
      int? from = 0;
      while (from != null) {
        final s = _signals(
          await _ask(ws, ['top.clk'], from, 41, limit: 3),
        ).single;
        paged.addAll(_transitions(s));
        from = s['next_from'] as int?;
      }
      expect(jsonEncode(paged), jsonEncode(whole));
      expect(whole.map((t) => t['time']), [0, 5, 10, 15, 20, 25, 30, 35, 40]);
    });
  });
}
