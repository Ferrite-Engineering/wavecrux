// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wavecrux/services/remote/wcp_server.dart';

// ── _WcpSocket ────────────────────────────────────────────────────────────────
//
// Wraps a Socket with a single persistent listener that queues decoded WCP
// frames. Dart sockets are single-subscription streams, so every test must
// create one _WcpSocket per Socket and drain frames through it rather than
// calling socket.listen() more than once.

class _WcpSocket {
  _WcpSocket(this._socket) {
    _socket.listen(
      _onData,
      onDone: _markClosed,
      onError: (Object _) => _markClosed(),
    );
  }

  final Socket _socket;
  final List<int> _buf = [];
  final List<Map<String, dynamic>> _frames = [];
  Completer<void>? _waiting;
  final Completer<void> _closed = Completer<void>();

  /// Whether the server has hung up on this connection.
  bool get isClosed => _closed.isCompleted;

  void _markClosed() {
    if (!_closed.isCompleted) _closed.complete();
  }

  /// Completes when the server closes the connection; throws
  /// [TimeoutException] if it stays open.
  Future<void> awaitClose({
    Duration timeout = const Duration(seconds: 3),
  }) => _closed.future.timeout(timeout);

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

  Future<Map<String, dynamic>> next({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    while (_frames.isEmpty) {
      _waiting = Completer<void>();
      await _waiting!.future.timeout(timeout);
    }
    return _frames.removeAt(0);
  }

  Future<List<Map<String, dynamic>>> nextN(
    int count, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < count; i++) {
      result.add(await next(timeout: timeout));
    }
    return result;
  }

  void send(Map<String, dynamic> msg) =>
      _socket.add([...utf8.encode(jsonEncode(msg)), 0]);

  void destroy() => _socket.destroy();
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('WcpServer', () {
    late WcpServer server;
    late List<String> receivedCommands;

    setUp(() async {
      receivedCommands = [];
      server = WcpServer(
        onCommand: (command, params) async {
          receivedCommands.add(command);
          if (command == 'load') return {'status': 'ok'};
          if (command == 'get_item_list') return {'items': <int>[]};
          return null;
        },
      );
      await server.start(0);
    });

    tearDown(() async {
      await server.stop();
    });

    Future<_WcpSocket> connect() async {
      final socket = await Socket.connect('127.0.0.1', server.port!);
      addTearDown(socket.destroy);
      return _WcpSocket(socket);
    }

    test('starts and reports isRunning', () {
      expect(server.isRunning, isTrue);
      expect(server.port, isNotNull);
    });

    test('stops cleanly', () async {
      await server.stop();
      expect(server.isRunning, isFalse);
      expect(server.port, isNull);
    });

    test('sends greeting on connect with spec version 0', () async {
      final ws = await connect();
      final msg = await ws.next();
      expect(msg['type'], 'greeting');
      expect(msg['version'], WcpServer.wcpVersion);
      expect(msg['version'], '0');
      expect(msg['commands'], isA<List<dynamic>>());
      expect(msg['commands'], containsAll(['add_variables', 'add_scope']));
    });

    test('dispatches known command and returns response', () async {
      final ws = await connect();
      await ws.next(); // greeting

      ws.send({
        'type': 'command',
        'id': 7,
        'command': 'load',
        'data': <String, dynamic>{},
      });
      final msg = await ws.next();

      expect(msg['type'], 'response');
      expect(msg['id'], 7);
      expect((msg['data'] as Map<String, dynamic>)['status'], 'ok');
      expect(receivedCommands, contains('load'));
    });

    test('returns error for unknown command', () async {
      final ws = await connect();
      await ws.next();

      ws.send({
        'type': 'command',
        'id': 3,
        'command': 'not_a_real_command',
        'data': <String, dynamic>{},
      });
      final msg = await ws.next();

      expect(msg['type'], 'error');
      expect(msg['code'], 2);
      expect(msg['id'], 3);
    });

    test('returns parse error for non-integer id', () async {
      final ws = await connect();
      await ws.next();

      ws.send({
        'type': 'command',
        'id': 'not-an-int',
        'command': 'load',
        'data': <String, dynamic>{},
      });
      final msg = await ws.next();

      expect(msg['type'], 'error');
      expect(msg['code'], 1);
    });

    test('answers non-JSON bytes with a parse error, then closes', () async {
      final ws = await connect();
      await ws.next();

      ws._socket.add([...utf8.encode('not json at all'), 0]);
      final msg = await ws.next();

      expect(msg['type'], 'error');
      expect(msg['code'], 1);
      // A peer that cannot produce one parseable frame is not a client that
      // made a mistake; answering and reading on is what lets a cross-origin
      // page keep a socket to this process. The error goes out first, so the
      // close is still diagnosable.
      await ws.awaitClose();
      expect(server.connectedClients, 0);
    });

    // A web page can `fetch()` a fixed loopback port with a `text/plain` POST
    // that needs no CORS preflight. The HTTP request line arrives first and
    // is not JSON; the body that follows is whatever the page chose. A server
    // that answered the request line and read on would dispatch the body —
    // blind, from any site the user had open. Mirrors `crux_cxp`'s
    // `robustness_test.dart` for the CXP port.
    test('a browser POST is dropped and its body never dispatched', () async {
      final ws = await connect();
      await ws.next(); // greeting

      final body =
          '${jsonEncode({
            'type': 'command',
            'id': 1,
            'command': 'load',
            'data': {'path': '/etc/passwd'},
          })}${String.fromCharCode(0)}';
      ws._socket.add(
        utf8.encode(
          'POST / HTTP/1.1\r\n'
          'Host: 127.0.0.1:${server.port}\r\n'
          'Content-Type: text/plain;charset=UTF-8\r\n'
          'Origin: https://attacker.example\r\n'
          'Content-Length: ${utf8.encode(body).length}\r\n'
          '\r\n'
          '$body',
        ),
      );

      final msg = await ws.next();
      expect(msg['type'], 'error', reason: 'the request line is not a frame');
      await ws.awaitClose();
      // The whole POST shared one socket write, so the body's `load` command
      // was already readable when the request line was rejected: an empty
      // command list here is the proof it was never dispatched.
      expect(receivedCommands, isEmpty);
    });

    test(
      'drops a connection whose unterminated frame passes the cap',
      () async {
        final ws = await connect();
        await ws.next(); // greeting

        // No `\x00` anywhere: the buffer is one unfinished frame, and without a
        // cap it grows for as long as the peer keeps writing.
        final chunk = utf8.encode('x' * (64 * 1024));
        for (
          var sent = 0;
          sent <= WcpServer.maxFrameBytes;
          sent += chunk.length
        ) {
          ws._socket.add(chunk);
        }

        await ws.awaitClose();
        expect(server.connectedClients, 0);
      },
    );

    test('a frame at the cap is still served', () async {
      final ws = await connect();
      await ws.next(); // greeting

      // Well under the cap and far above any real command: the cap must bound
      // a hostile peer without narrowing what a legitimate one may send.
      ws.send({
        'type': 'command',
        'id': 7,
        'command': 'load',
        'data': {'path': '/tmp/${'a' * (256 * 1024)}.vcd'},
      });
      final msg = await ws.next();

      expect(msg['type'], 'response');
      expect(ws.isClosed, isFalse);
    });

    test('handles WcpException from handler', () async {
      final errorServer = WcpServer(
        onCommand: (command, params) async {
          throw const WcpException('test error', code: 5);
        },
      );
      await errorServer.start(0);
      addTearDown(errorServer.stop);

      final socket = await Socket.connect('127.0.0.1', errorServer.port!);
      addTearDown(socket.destroy);
      final ws = _WcpSocket(socket);

      await ws.next(); // greeting
      ws.send({
        'type': 'command',
        'id': 1,
        'command': 'load',
        'data': <String, dynamic>{},
      });
      final msg = await ws.next();

      expect(msg['type'], 'error');
      expect(msg['code'], 5);
      expect(msg['message'], 'test error');
    });

    test('handles unexpected exception from handler as code 4', () async {
      final crashServer = WcpServer(
        onCommand: (command, params) async {
          throw StateError('oops');
        },
      );
      await crashServer.start(0);
      addTearDown(crashServer.stop);

      final socket = await Socket.connect('127.0.0.1', crashServer.port!);
      addTearDown(socket.destroy);
      final ws = _WcpSocket(socket);

      await ws.next();
      ws.send({
        'type': 'command',
        'id': 9,
        'command': 'reload',
        'data': <String, dynamic>{},
      });
      final msg = await ws.next();

      expect(msg['type'], 'error');
      expect(msg['code'], 4);
    });

    test('tracks connectedClients and fires onClientCountChanged', () async {
      final counts = <int>[];
      final countServer = WcpServer(
        onCommand: (c, p) async => null,
        onClientCountChanged: counts.add,
      );
      await countServer.start(0);
      addTearDown(countServer.stop);

      expect(countServer.connectedClients, 0);

      final s1 = await Socket.connect('127.0.0.1', countServer.port!);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(countServer.connectedClients, 1);

      final s2 = await Socket.connect('127.0.0.1', countServer.port!);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(countServer.connectedClients, 2);

      s1.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(countServer.connectedClients, 1);

      s2.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(countServer.connectedClients, 0);

      expect(counts, containsAll([1, 2, 1, 0]));
    });

    test('broadcastEvent sends event to all clients', () async {
      final ws1 = await connect();
      final ws2 = await connect();

      await ws1.next(); // greetings
      await ws2.next();

      server.broadcastEvent('waveforms_loaded', {'source': 'test.vcd'});

      final m1 = await ws1.next();
      final m2 = await ws2.next();
      expect(m1['type'], 'event');
      expect(m1['event'], 'waveforms_loaded');
      expect(m2['type'], 'event');
    });

    test('ignores version-0 client greeting silently', () async {
      final ws = await connect();
      await ws.next(); // server greeting

      ws
        ..send({
          'type': 'greeting',
          'version': WcpServer.wcpVersion,
          'commands': <String>[],
        })
        ..send({
          'type': 'command',
          'id': 1,
          'command': 'get_item_list',
          'data': <String, dynamic>{},
        });
      final msg = await ws.next();

      expect(msg['type'], 'response');
      expect(msg['id'], 1);
    });

    test('handles multi-frame messages split across TCP chunks', () async {
      final ws = await connect();
      await ws.next();

      final raw = [
        ...utf8.encode(
          jsonEncode({
            'type': 'command',
            'id': 42,
            'command': 'zoom_to_fit',
            'data': <String, dynamic>{},
          }),
        ),
        0,
      ];

      ws._socket.add(raw.sublist(0, raw.length ~/ 2));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      ws._socket.add(raw.sublist(raw.length ~/ 2));

      final msg = await ws.next();
      expect(msg['type'], 'response');
      expect(msg['id'], 42);
    });

    test('processes two commands sent back-to-back', () async {
      final ws = await connect();
      await ws.next();

      ws
        ..send({
          'type': 'command',
          'id': 1,
          'command': 'load',
          'data': <String, dynamic>{},
        })
        ..send({
          'type': 'command',
          'id': 2,
          'command': 'get_item_list',
          'data': <String, dynamic>{},
        });

      final msgs = await ws.nextN(2);
      final ids = msgs.map((m) => m['id'] as int).toSet();
      expect(ids, {1, 2});
    });
  });

  // ── spec envelope ───────────────────────────────────────────────────────────
  // The upstream WCP envelope: id-less commands with top-level parameters,
  // in-order replies, command-echo responses, and spec-shaped errors.

  group('WcpServer — spec envelope', () {
    late WcpServer server;
    late List<(String, Map<String, dynamic>)> received;

    setUp(() async {
      received = [];
      server = WcpServer(
        onCommand: (command, params) async {
          received.add((command, params));
          switch (command) {
            case 'add_items':
              return {
                'items': [
                  {
                    'id': 1,
                    'name': 'clk',
                    'path': 'top.clk',
                    'type': 'Variable',
                  },
                  {
                    'id': 2,
                    'name': 'rst',
                    'path': 'top.rst',
                    'type': 'Variable',
                  },
                ],
              };
            case 'get_item_list':
              return {
                'items': [
                  {
                    'id': 1,
                    'name': 'clk',
                    'path': 'top.clk',
                    'type': 'Variable',
                  },
                ],
              };
            case 'get_item_info':
              return {
                'items': [
                  {
                    'id': 1,
                    'name': 'clk',
                    'path': 'top.clk',
                    'type': 'Variable',
                  },
                ],
              };
            case 'wavecrux.getState':
              return {'is_loaded': true, 'signal_count': 1};
            default:
              return null;
          }
        },
      );
      await server.start(0);
    });

    tearDown(() async {
      await server.stop();
    });

    Future<_WcpSocket> connect() async {
      final socket = await Socket.connect('127.0.0.1', server.port!);
      addTearDown(socket.destroy);
      final ws = _WcpSocket(socket);
      await ws.next(); // greeting
      return ws;
    }

    test('id-less command with top-level params dispatches and acks', () async {
      final ws = await connect();
      ws.send({'type': 'command', 'command': 'set_cursor', 'timestamp': 100});
      final msg = await ws.next();

      expect(msg['type'], 'response');
      expect(msg['command'], 'ack');
      expect(msg.containsKey('id'), isFalse);
      expect(received.single.$1, 'set_cursor');
      expect(received.single.$2['timestamp'], 100);
    });

    test('payload-bearing response echoes the command with ids', () async {
      final ws = await connect();
      ws.send({
        'type': 'command',
        'command': 'add_items',
        'items': ['top.clk', 'top.rst'],
      });
      final msg = await ws.next();

      expect(msg['type'], 'response');
      expect(msg['command'], 'add_items');
      expect(msg['ids'], [1, 2]);
      expect(received.single.$2['items'], ['top.clk', 'top.rst']);
    });

    test('get_item_list responds with ids only', () async {
      final ws = await connect();
      ws.send({'type': 'command', 'command': 'get_item_list'});
      final msg = await ws.next();

      expect(msg['command'], 'get_item_list');
      expect(msg['ids'], [1]);
      expect(msg.containsKey('items'), isFalse);
    });

    test('get_item_info responds with name/type/id results', () async {
      final ws = await connect();
      ws.send({
        'type': 'command',
        'command': 'get_item_info',
        'ids': [1],
      });
      final msg = await ws.next();

      expect(msg['command'], 'get_item_info');
      final results = msg['results'] as List<dynamic>;
      expect(results, hasLength(1));
      final first = results.first as Map<String, dynamic>;
      expect(first['name'], 'clk');
      expect(first['type'], 'Variable');
      expect(first['id'], 1);
    });

    test('extension command echoes name with top-level payload', () async {
      final ws = await connect();
      ws.send({'type': 'command', 'command': 'wavecrux.getState'});
      final msg = await ws.next();

      expect(msg['type'], 'response');
      expect(msg['command'], 'wavecrux.getState');
      expect(msg['is_loaded'], isTrue);
      expect(msg['signal_count'], 1);
    });

    test('unknown spec command returns spec-shaped error', () async {
      final ws = await connect();
      ws.send({'type': 'command', 'command': 'not_a_real_command'});
      final msg = await ws.next();

      expect(msg['type'], 'error');
      expect(msg['error'], 'not_a_real_command');
      expect(msg['arguments'], isA<List<dynamic>>());
      expect(msg['message'], contains('Unknown command'));
      expect(msg.containsKey('code'), isFalse);
    });

    test('WcpException surfaces as spec-shaped error', () async {
      final errorServer = WcpServer(
        onCommand: (command, params) async {
          throw const WcpException('No waveform file loaded', code: 5);
        },
      );
      await errorServer.start(0);
      addTearDown(errorServer.stop);

      final socket = await Socket.connect('127.0.0.1', errorServer.port!);
      addTearDown(socket.destroy);
      final ws = _WcpSocket(socket);
      await ws.next(); // greeting

      ws.send({'type': 'command', 'command': 'reload'});
      final msg = await ws.next();

      expect(msg['type'], 'error');
      expect(msg['error'], 'reload');
      expect(msg['message'], 'No waveform file loaded');
    });

    test('add_variables alias dispatches as add_items with items', () async {
      final ws = await connect();
      ws.send({
        'type': 'command',
        'command': 'add_variables',
        'variables': ['top.clk'],
      });
      final msg = await ws.next();

      expect(msg['type'], 'response');
      expect(msg['command'], 'add_variables');
      expect(msg['ids'], [1, 2]);
      expect(received.single.$1, 'add_items');
      expect(received.single.$2['items'], ['top.clk']);
    });

    test('add_scope alias dispatches as add_items with the scope', () async {
      final ws = await connect();
      ws.send({
        'type': 'command',
        'command': 'add_scope',
        'scope': 'top',
        'recursive': true,
      });
      final msg = await ws.next();

      expect(msg['type'], 'response');
      expect(msg['command'], 'add_scope');
      expect(received.single.$1, 'add_items');
      expect(received.single.$2['items'], ['top']);
      expect(received.single.$2['recursive'], isTrue);
    });

    test('pipelined commands reply in request order', () async {
      // The first handler completes slower than the second; in-order replies
      // require the serial dispatch queue to hold the second reply back.
      final order = <String>[];
      final slowServer = WcpServer(
        onCommand: (command, params) async {
          if (command == 'reload') {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          order.add(command);
          return null;
        },
      );
      await slowServer.start(0);
      addTearDown(slowServer.stop);

      final socket = await Socket.connect('127.0.0.1', slowServer.port!);
      addTearDown(socket.destroy);
      final ws = _WcpSocket(socket);
      await ws.next(); // greeting

      ws
        ..send({'type': 'command', 'command': 'reload'})
        ..send({'type': 'command', 'command': 'zoom_to_fit'});

      await ws.nextN(2);
      expect(order, ['reload', 'zoom_to_fit']);
    });

    test('greeting with unsupported major version gets error frame', () async {
      final ws = await connect();
      ws.send({
        'type': 'greeting',
        'version': '2',
        'commands': <String>[],
      });
      final msg = await ws.next();

      expect(msg['type'], 'error');
      expect(msg['error'], 'greeting');
      expect(msg['arguments'], ['2']);
      expect(msg['message'], contains('version 0'));
    });

    test('greeting with 0.x minor version is accepted silently', () async {
      final ws = await connect();
      ws
        ..send({
          'type': 'greeting',
          'version': '0.1.0',
          'commands': <String>[],
        })
        ..send({'type': 'command', 'command': 'zoom_to_fit'});
      final msg = await ws.next();

      // No greeting error frame — the next frame is the command's ack.
      expect(msg['type'], 'response');
      expect(msg['command'], 'ack');
    });

    test('events are spec-shaped after a spec-envelope command', () async {
      final ws = await connect();
      ws.send({'type': 'command', 'command': 'zoom_to_fit'});
      await ws.next(); // ack — latches the spec envelope

      server.broadcastEvent('waveforms_loaded', {'source': '/tmp/a.vcd'});
      final msg = await ws.next();

      expect(msg['type'], 'event');
      expect(msg['event'], 'waveforms_loaded');
      expect(msg['source'], '/tmp/a.vcd');
      expect(msg.containsKey('data'), isFalse);
    });

    test('events stay data-nested for id-dialect connections', () async {
      final ws = await connect();
      ws.send({
        'type': 'command',
        'id': 1,
        'command': 'zoom_to_fit',
        'data': <String, dynamic>{},
      });
      await ws.next(); // response

      server.broadcastEvent('waveforms_loaded', {'source': '/tmp/a.vcd'});
      final msg = await ws.next();

      expect(msg['type'], 'event');
      expect((msg['data'] as Map<String, dynamic>)['source'], '/tmp/a.vcd');
    });

    test('focus_item with a top-level item id is a spec command', () async {
      final ws = await connect();
      ws.send({'type': 'command', 'command': 'focus_item', 'id': 3});
      final msg = await ws.next();

      expect(msg['type'], 'response');
      expect(msg['command'], 'ack');
      expect(msg.containsKey('id'), isFalse);
      expect(received.single.$1, 'focus_item');
      expect(received.single.$2['id'], 3);
    });

    test('set_item_color with a top-level item id is a spec command', () async {
      final ws = await connect();
      ws.send({
        'type': 'command',
        'command': 'set_item_color',
        'id': 2,
        'color': '#00ff00',
      });
      final msg = await ws.next();

      expect(msg['command'], 'ack');
      expect(received.single.$1, 'set_item_color');
      expect(received.single.$2, {'id': 2, 'color': '#00ff00'});
    });

    test('focus_item with id and data stays in the id dialect', () async {
      final ws = await connect();
      ws.send({
        'type': 'command',
        'id': 9,
        'command': 'focus_item',
        'data': {'id': 3},
      });
      final msg = await ws.next();

      expect(msg['type'], 'response');
      expect(msg['id'], 9);
      expect(received.single.$2, {'id': 3});
    });

    test(
      'an id without data on other commands is still the id dialect',
      () async {
        final ws = await connect();
        ws.send({'type': 'command', 'id': 4, 'command': 'zoom_to_fit'});
        final msg = await ws.next();

        expect(msg['type'], 'response');
        expect(msg['id'], 4);
      },
    );

    test('one connection can mix both envelopes', () async {
      final ws = await connect();
      ws
        ..send({
          'type': 'command',
          'id': 5,
          'command': 'get_item_list',
          'data': <String, dynamic>{},
        })
        ..send({'type': 'command', 'command': 'get_item_list'});

      final first = await ws.next();
      final second = await ws.next();
      expect(first['id'], 5);
      expect(first.containsKey('data'), isTrue);
      expect(second.containsKey('id'), isFalse);
      expect(second['command'], 'get_item_list');
      expect(second['ids'], [1]);
    });
  });

  // ── id-dialect compat flag ─────────────────────────────────────────────────

  group('WcpServer — idDialectEnabled: false', () {
    test('id-framed commands are rejected with a spec error', () async {
      final server = WcpServer(
        onCommand: (command, params) async => null,
        idDialectEnabled: false,
      );
      await server.start(0);
      addTearDown(server.stop);

      final socket = await Socket.connect('127.0.0.1', server.port!);
      addTearDown(socket.destroy);
      final ws = _WcpSocket(socket);
      await ws.next(); // greeting

      ws.send({
        'type': 'command',
        'id': 1,
        'command': 'zoom_to_fit',
        'data': <String, dynamic>{},
      });
      final msg = await ws.next();

      expect(msg['type'], 'error');
      expect(msg['error'], 'zoom_to_fit');
      expect(msg['message'], contains('disabled'));
    });

    test('spec-envelope commands still work', () async {
      final server = WcpServer(
        onCommand: (command, params) async => null,
        idDialectEnabled: false,
      );
      await server.start(0);
      addTearDown(server.stop);

      final socket = await Socket.connect('127.0.0.1', server.port!);
      addTearDown(socket.destroy);
      final ws = _WcpSocket(socket);
      await ws.next(); // greeting

      ws.send({'type': 'command', 'command': 'zoom_to_fit'});
      final msg = await ws.next();

      expect(msg['type'], 'response');
      expect(msg['command'], 'ack');
    });
  });

  // ── fault reporting ────────────────────────────────────────────────────────
  //
  // The server swallows exactly one class of error: a peer that went away.
  // Everything else is a fault in this process and must reach the log, where
  // the issue reporter and the stderr sink can see it.

  group('WcpServer — fault reporting', () {
    late List<LogRecord> records;
    late StreamSubscription<LogRecord> sub;

    setUp(() {
      records = <LogRecord>[];
      Logger.root.level = Level.ALL;
      sub = Logger.root.onRecord
          .where((r) => r.loggerName == 'wavecrux.wcp')
          .listen(records.add);
    });

    tearDown(() => sub.cancel());

    Future<void> untilLogged() async {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (records.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('an error raised while accepting a connection is logged', () async {
      final boom = StateError('client-count listener failed');
      final server = WcpServer(
        onCommand: (command, params) async => null,
        // Throws on a connect only: `stop()` reports zero from outside the
        // server's zone, straight to its caller.
        onClientCountChanged: (count) {
          if (count > 0) throw boom;
        },
      );
      await server.start(0);
      addTearDown(server.stop);

      final socket = await Socket.connect('127.0.0.1', server.port!);
      addTearDown(socket.destroy);
      await untilLogged();

      expect(records, isNotEmpty);
      expect(records.first.level, Level.SEVERE);
      expect(records.first.error, same(boom));
      expect(records.first.stackTrace, isNotNull);
    });

    test('a peer that hung up is not logged', () async {
      final server = WcpServer(
        onCommand: (command, params) async => null,
        onClientCountChanged: (count) {
          if (count == 0) return;
          throw SocketException(
            'Write failed',
            osError: OSError('Connection reset by peer', peerResetErrno),
          );
        },
      );
      await server.start(0);
      addTearDown(server.stop);

      final socket = await Socket.connect('127.0.0.1', server.port!);
      addTearDown(socket.destroy);
      // Long enough for the accept path to have run and, before the fix
      // under test, for any report it produced to have landed.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(records, isEmpty);
    });

    test('a spec-envelope result that cannot be encoded is answered with an '
        'error frame rather than silence', () async {
      final server = WcpServer(
        onCommand: (command, params) async => {'when': DateTime(2026)},
      );
      await server.start(0);
      addTearDown(server.stop);

      final socket = await Socket.connect('127.0.0.1', server.port!);
      addTearDown(socket.destroy);
      final ws = _WcpSocket(socket);
      await ws.next(); // greeting

      ws.send({'type': 'command', 'command': 'wavecrux.getState'});
      final msg = await ws.next();

      expect(msg['type'], 'error');
      expect(msg['error'], 'wavecrux.getState');
      expect(msg['message'], contains('Internal error'));
    });

    test('an id-dialect result that cannot be encoded is answered with an '
        'error frame rather than silence', () async {
      final server = WcpServer(
        onCommand: (command, params) async => {'when': DateTime(2026)},
      );
      await server.start(0);
      addTearDown(server.stop);

      final socket = await Socket.connect('127.0.0.1', server.port!);
      addTearDown(socket.destroy);
      final ws = _WcpSocket(socket);
      await ws.next(); // greeting

      ws.send({
        'type': 'command',
        'id': 7,
        'command': 'wavecrux.getState',
        'data': <String, dynamic>{},
      });
      final msg = await ws.next();

      expect(msg['type'], 'error');
      expect(msg['id'], 7);
      expect(msg['code'], 4);
    });
  });

  group('isPeerGoneSocketError', () {
    SocketException withErrno(int code) =>
        SocketException('socket', osError: OSError('os', code));

    test("treats this host's reset, abort, broken-pipe and not-connected "
        'codes as a peer that went away', () {
      final codes = Platform.isWindows
          ? const [10053, 10054, 10057, 10058]
          : Platform.isLinux
          ? const [32, 103, 104, 107]
          : const [32, 53, 54, 57];
      for (final code in codes) {
        expect(isPeerGoneSocketError(withErrno(code)), isTrue, reason: '$code');
      }
    });

    test('treats every other failure as a fault', () {
      // EMFILE (24 on every POSIX host; WSAEMFILE is 10024): running out of
      // descriptors is exactly the failure an accept loop must not hide.
      expect(
        isPeerGoneSocketError(withErrno(Platform.isWindows ? 10024 : 24)),
        isFalse,
      );
      expect(
        isPeerGoneSocketError(const SocketException('no os error')),
        isFalse,
      );
      expect(isPeerGoneSocketError(StateError('not a socket error')), isFalse);
      expect(isPeerGoneSocketError(const FormatException('bad')), isFalse);
    });
  });
}

/// ECONNRESET as this host numbers it.
int get peerResetErrno => Platform.isWindows
    ? 10054
    : Platform.isLinux
    ? 104
    : 54;
