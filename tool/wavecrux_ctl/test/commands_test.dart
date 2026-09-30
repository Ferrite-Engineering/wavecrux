// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:test/test.dart';
import 'package:wavecrux_ctl/src/client.dart';
import 'package:wavecrux_ctl/src/runner.dart';

// ── WCP mock server helpers ───────────────────────────────────────────────────

void _sendFrame(Socket socket, Map<String, dynamic> msg) {
  socket.add([...utf8.encode(jsonEncode(msg)), 0]);
}

typedef _Handler = Map<String, dynamic> Function(Map<String, dynamic> cmd);

/// Starts a WCP-conformant mock server.
///
/// On each connection: sends a server greeting, discards the client greeting,
/// then calls [handler] for each command frame and writes the result back.
Future<({ServerSocket server, List<Map<String, dynamic>> received})>
_startMockServer(_Handler handler) async {
  final received = <Map<String, dynamic>>[];
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    _sendFrame(socket, {
      'type': 'greeting',
      'version': '0',
      'commands': <String>[],
    });
    final buf = <int>[];
    socket.cast<List<int>>().listen((chunk) {
      buf.addAll(chunk);
      while (true) {
        final idx = buf.indexOf(0);
        if (idx < 0) break;
        final bytes = buf.sublist(0, idx);
        buf.removeRange(0, idx + 1);
        final frame = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        if (frame['type'] == 'greeting') continue;
        received.add(frame);
        _sendFrame(socket, handler(frame));
      }
    });
  });
  return (server: server, received: received);
}

Map<String, dynamic> _wcpResponse(
  Map<String, dynamic> cmd,
  Map<String, dynamic> data,
) => {'type': 'response', 'id': cmd['id'], 'data': data};

Map<String, dynamic> _wcpError(
  Map<String, dynamic> cmd, {
  int? code,
  required String message,
}) => {'type': 'error', 'id': cmd['id'], 'code': code, 'message': message};

// ── Output capture ────────────────────────────────────────────────────────────

class _BufferSink implements IOSink {
  final StringBuffer _buf = StringBuffer();

  String get output => _buf.toString();

  @override
  void writeln([Object? obj = '']) => _buf.writeln(obj);

  @override
  void write(Object? obj) => _buf.write(obj);

  @override
  void writeAll(Iterable<dynamic> objs, [String separator = '']) {
    _buf.writeAll(objs, separator);
  }

  @override
  void writeCharCode(int charCode) => _buf.writeCharCode(charCode);

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}

  @override
  Encoding get encoding => utf8;

  @override
  set encoding(Encoding value) {}
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Argument parsing ──────────────────────────────────────────────────────

  group('argument parsing', () {
    test('runner has --host, --port, --json global options', () {
      final runner = WavecruxCtlRunner();
      final opts = runner.argParser.options;
      expect(opts.containsKey('host'), isTrue);
      expect(opts.containsKey('port'), isTrue);
      expect(opts.containsKey('json'), isTrue);
    });

    test('all 11 subcommands are registered', () {
      final runner = WavecruxCtlRunner();
      final names = runner.commands.keys.toSet();
      expect(
        names,
        containsAll([
          'load',
          'add',
          'remove',
          'cursor',
          'marker',
          'zoom',
          'fit',
          'signals',
          'value',
          'hierarchy',
          'status',
        ]),
      );
    });

    test('load requires a file argument', () async {
      final runner = WavecruxCtlRunner();
      await expectLater(runner.run(['load']), throwsA(isA<UsageException>()));
    });

    test('add requires at least one path', () async {
      final runner = WavecruxCtlRunner();
      await expectLater(runner.run(['add']), throwsA(isA<UsageException>()));
    });

    test('cursor requires an integer time', () async {
      final runner = WavecruxCtlRunner(output: _BufferSink());
      await expectLater(
        runner.run(['cursor', 'notanumber']),
        throwsA(isA<UsageException>()),
      );
    });

    test('marker requires name and time', () async {
      final runner = WavecruxCtlRunner();
      await expectLater(
        runner.run(['marker', 'a']),
        throwsA(isA<UsageException>()),
      );
    });

    test('marker name must be single lowercase letter', () async {
      final runner = WavecruxCtlRunner();
      await expectLater(
        runner.run(['marker', 'AB', '1000']),
        throwsA(isA<UsageException>()),
      );
    });

    test('zoom requires a positive number', () async {
      final runner = WavecruxCtlRunner();
      await expectLater(
        runner.run(['zoom', '-5']),
        throwsA(isA<UsageException>()),
      );
    });

    test('value requires a signal path', () async {
      final runner = WavecruxCtlRunner();
      await expectLater(runner.run(['value']), throwsA(isA<UsageException>()));
    });
  });

  // ── WCP request construction ───────────────────────────────────────────────

  group('WCP request construction', () {
    test('load sends load with source path', () async {
      final mock = await _startMockServer((cmd) => _wcpResponse(cmd, {}));
      final out = _BufferSink();
      final runner = WavecruxCtlRunner(output: out);
      await runner.run(['--port', '${mock.server.port}', 'load', '/tmp/x.vcd']);
      await mock.server.close();

      expect(mock.received, hasLength(1));
      expect(mock.received.first['command'], 'load');
      expect((mock.received.first['data'] as Map)['source'], '/tmp/x.vcd');
    });

    test('add sends add_items with paths list', () async {
      final mock = await _startMockServer(
        (cmd) => _wcpResponse(cmd, {
          'items': [
            {'id': 1, 'path': 'top.clk'},
          ],
        }),
      );
      final out = _BufferSink();
      final runner = WavecruxCtlRunner(output: out);
      await runner.run(['--port', '${mock.server.port}', 'add', 'top.clk']);
      await mock.server.close();

      expect(mock.received.first['command'], 'add_items');
      expect((mock.received.first['data'] as Map)['paths'], ['top.clk']);
    });

    test('add with multiple signals sends add_items with all paths', () async {
      final mock = await _startMockServer(
        (cmd) => _wcpResponse(cmd, {
          'items': [
            {'id': 1, 'path': 'top.clk'},
            {'id': 2, 'path': 'top.reset'},
          ],
        }),
      );
      final out = _BufferSink();
      final runner = WavecruxCtlRunner(output: out);
      await runner.run([
        '--port',
        '${mock.server.port}',
        'add',
        'top.clk',
        'top.reset',
      ]);
      await mock.server.close();

      expect(mock.received.first['command'], 'add_items');
      expect((mock.received.first['data'] as Map)['paths'], [
        'top.clk',
        'top.reset',
      ]);
    });

    test('remove sends get_item_list then remove_items by id', () async {
      final mock = await _startMockServer((cmd) {
        if (cmd['command'] == 'get_item_list') {
          return _wcpResponse(cmd, {
            'items': [
              {'id': 7, 'path': 'top.clk'},
            ],
          });
        }
        return _wcpResponse(cmd, {});
      });
      final out = _BufferSink();
      final runner = WavecruxCtlRunner(output: out);
      await runner.run(['--port', '${mock.server.port}', 'remove', 'top.clk']);
      await mock.server.close();

      expect(mock.received, hasLength(2));
      expect(mock.received[0]['command'], 'get_item_list');
      expect(mock.received[1]['command'], 'remove_items');
      expect((mock.received[1]['data'] as Map)['ids'], [7]);
    });

    test('remove unknown signal throws CliException with not found', () async {
      final mock = await _startMockServer(
        (cmd) => _wcpResponse(cmd, {'items': <dynamic>[]}),
      );
      final runner = WavecruxCtlRunner();
      await expectLater(
        runner.run(['--port', '${mock.server.port}', 'remove', 'top.unknown']),
        throwsA(
          isA<CliException>().having(
            (e) => e.message,
            'message',
            contains('not found'),
          ),
        ),
      );
      await mock.server.close();
    });

    test('cursor sends set_cursor with integer timestamp', () async {
      final mock = await _startMockServer((cmd) => _wcpResponse(cmd, {}));
      final out = _BufferSink();
      final runner = WavecruxCtlRunner(output: out);
      await runner.run(['--port', '${mock.server.port}', 'cursor', '2500']);
      await mock.server.close();

      expect(mock.received.first['command'], 'set_cursor');
      expect((mock.received.first['data'] as Map)['timestamp'], 2500);
    });

    test('marker sends add_markers with name and time', () async {
      final mock = await _startMockServer(
        (cmd) => _wcpResponse(cmd, {
          'items': [
            {'name': 'a', 'time': 1000},
          ],
        }),
      );
      final out = _BufferSink();
      final runner = WavecruxCtlRunner(output: out);
      await runner.run([
        '--port',
        '${mock.server.port}',
        'marker',
        'a',
        '1000',
      ]);
      await mock.server.close();

      expect(mock.received.first['command'], 'add_markers');
      final markers = (mock.received.first['data'] as Map)['markers'] as List;
      expect((markers.first as Map)['name'], 'a');
      expect((markers.first as Map)['time'], 1000);
    });

    test('zoom sends set_viewport_to with integer timestamp', () async {
      final mock = await _startMockServer((cmd) => _wcpResponse(cmd, {}));
      final out = _BufferSink();
      final runner = WavecruxCtlRunner(output: out);
      await runner.run(['--port', '${mock.server.port}', 'zoom', '5000']);
      await mock.server.close();

      expect(mock.received.first['command'], 'set_viewport_to');
      expect((mock.received.first['data'] as Map)['timestamp'], isA<int>());
    });

    test('fit sends zoom_to_fit with empty data', () async {
      final mock = await _startMockServer((cmd) => _wcpResponse(cmd, {}));
      final out = _BufferSink();
      final runner = WavecruxCtlRunner(output: out);
      await runner.run(['--port', '${mock.server.port}', 'fit']);
      await mock.server.close();

      expect(mock.received.first['command'], 'zoom_to_fit');
      expect((mock.received.first['data'] as Map), isEmpty);
    });

    test('signals sends get_item_list', () async {
      final mock = await _startMockServer(
        (cmd) => _wcpResponse(cmd, {'items': <dynamic>[]}),
      );
      final out = _BufferSink();
      final runner = WavecruxCtlRunner(output: out);
      await runner.run(['--port', '${mock.server.port}', 'signals']);
      await mock.server.close();

      expect(mock.received.first['command'], 'get_item_list');
    });

    test('hierarchy sends wavecrux.getHierarchy', () async {
      final mock = await _startMockServer(
        (cmd) => _wcpResponse(cmd, {'scopes': <dynamic>[]}),
      );
      final out = _BufferSink();
      final runner = WavecruxCtlRunner(output: out);
      await runner.run(['--port', '${mock.server.port}', 'hierarchy']);
      await mock.server.close();

      expect(mock.received.first['command'], 'wavecrux.getHierarchy');
    });

    test('status sends wavecrux.getState', () async {
      final mock = await _startMockServer(
        (cmd) => _wcpResponse(cmd, {
          'file': null,
          'is_loaded': false,
          'cursor': null,
          'ticks_per_pixel': 1.0,
          'signal_count': 0,
        }),
      );
      final out = _BufferSink();
      final runner = WavecruxCtlRunner(output: out);
      await runner.run(['--port', '${mock.server.port}', 'status']);
      await mock.server.close();

      expect(mock.received.first['command'], 'wavecrux.getState');
    });

    test(
      'value without time calls wavecrux.getState then wavecrux.getValueAt',
      () async {
        var callIndex = 0;
        final mock = await _startMockServer((cmd) {
          callIndex++;
          if (callIndex == 1) {
            return _wcpResponse(cmd, {
              'file': 'x.vcd',
              'is_loaded': true,
              'cursor': 750,
              'signal_count': 1,
            });
          } else {
            return _wcpResponse(cmd, {
              'signal_path': 'top.clk',
              'time': 750,
              'value': '1',
            });
          }
        });
        final out = _BufferSink();
        final runner = WavecruxCtlRunner(output: out);
        await runner.run(['--port', '${mock.server.port}', 'value', 'top.clk']);
        await mock.server.close();

        expect(mock.received, hasLength(2));
        expect(mock.received[0]['command'], 'wavecrux.getState');
        expect(mock.received[1]['command'], 'wavecrux.getValueAt');
        expect(
          (mock.received[1]['data'] as Map)['time'],
          750, // cursor time from getState
        );
        expect((mock.received[1]['data'] as Map)['signal_path'], 'top.clk');
      },
    );

    test('value with explicit time skips getState', () async {
      final mock = await _startMockServer(
        (cmd) => _wcpResponse(cmd, {
          'signal_path': 'top.clk',
          'time': 300,
          'value': '0',
        }),
      );
      final out = _BufferSink();
      final runner = WavecruxCtlRunner(output: out);
      await runner.run([
        '--port',
        '${mock.server.port}',
        'value',
        'top.clk',
        '300',
      ]);
      await mock.server.close();

      expect(mock.received, hasLength(1));
      expect(mock.received.first['command'], 'wavecrux.getValueAt');
      expect((mock.received.first['data'] as Map)['time'], 300);
    });
  });

  // ── Output formatting ──────────────────────────────────────────────────────

  group('output formatting', () {
    test('load prints loaded path in text mode', () async {
      final mock = await _startMockServer((cmd) => _wcpResponse(cmd, {}));
      final out = _BufferSink();
      final runner = WavecruxCtlRunner(output: out);
      await runner.run([
        '--port',
        '${mock.server.port}',
        'load',
        '/sim/test.fst',
      ]);
      await mock.server.close();

      expect(out.output, contains('/sim/test.fst'));
    });

    test('--json flag outputs raw JSON result', () async {
      final mock = await _startMockServer(
        (cmd) => _wcpResponse(cmd, {'loaded': true}),
      );
      final out = _BufferSink();
      final runner = WavecruxCtlRunner(output: out);
      await runner.run([
        '--port',
        '${mock.server.port}',
        '--json',
        'load',
        '/sim/test.fst',
      ]);
      await mock.server.close();

      final decoded = jsonDecode(out.output.trim()) as Map<String, dynamic>;
      expect(decoded['loaded'], isTrue);
    });

    test('status formats key-value output', () async {
      final mock = await _startMockServer(
        (cmd) => _wcpResponse(cmd, {
          'file': '/a/b.vcd',
          'is_loaded': true,
          'cursor': 100,
          'ticks_per_pixel': 2.0,
          'signal_count': 2,
        }),
      );
      final out = _BufferSink();
      final runner = WavecruxCtlRunner(output: out);
      await runner.run(['--port', '${mock.server.port}', 'status']);
      await mock.server.close();

      expect(out.output, contains('/a/b.vcd'));
      expect(out.output, contains('100 ticks'));
      expect(out.output, contains('2'));
    });

    test('signals formats as ID/PATH table', () async {
      final mock = await _startMockServer(
        (cmd) => _wcpResponse(cmd, {
          'items': [
            {'id': 1, 'path': 'top.cpu.clk'},
          ],
        }),
      );
      final out = _BufferSink();
      final runner = WavecruxCtlRunner(output: out);
      await runner.run(['--port', '${mock.server.port}', 'signals']);
      await mock.server.close();

      expect(out.output, contains('top.cpu.clk'));
      expect(out.output, contains('1'));
    });
  });

  // ── Error handling ─────────────────────────────────────────────────────────

  group('error handling', () {
    test(
      'connection refused throws CliException with helpful message',
      () async {
        final runner = WavecruxCtlRunner();
        await expectLater(
          runner.run(['--port', '19998', 'status']),
          throwsA(
            isA<CliException>().having(
              (e) => e.message,
              'message',
              contains('Is WaveCrux running with Remote Control enabled?'),
            ),
          ),
        );
      },
    );

    test('WCP error response throws CliException', () async {
      final mock = await _startMockServer(
        (cmd) =>
            _wcpError(cmd, code: -32603, message: 'No waveform file loaded'),
      );
      final runner = WavecruxCtlRunner();
      await expectLater(
        runner.run(['--port', '${mock.server.port}', 'signals']),
        throwsA(
          isA<CliException>().having(
            (e) => e.message,
            'message',
            contains('No waveform file loaded'),
          ),
        ),
      );
      await mock.server.close();
    });
  });
}
