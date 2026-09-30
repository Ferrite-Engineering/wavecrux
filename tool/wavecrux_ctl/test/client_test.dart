// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wavecrux_ctl/src/client.dart';

// ── WCP mock server helpers ───────────────────────────────────────────────────

void _sendFrame(Socket socket, Map<String, dynamic> msg) {
  socket.add([...utf8.encode(jsonEncode(msg)), 0]);
}

/// Starts a WCP-conformant mock server.
///
/// On each connection: sends a server greeting, discards the client greeting,
/// then calls [handler] for each command frame and writes the result back.
Future<({ServerSocket server, List<Map<String, dynamic>> received})>
_startServer(
  Map<String, dynamic> Function(Map<String, dynamic> cmd) handler,
) async {
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

Map<String, dynamic> _resp(
  Map<String, dynamic> cmd,
  Map<String, dynamic> data,
) => {'type': 'response', 'id': cmd['id'], 'data': data};

Map<String, dynamic> _err(
  Map<String, dynamic> cmd, {
  int? code,
  required String message,
}) => {'type': 'error', 'id': cmd['id'], 'code': code, 'message': message};

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('WcpClient', () {
    test('defaultPort is 54321', () {
      expect(WcpClient.defaultPort, 54321);
    });

    test('call() sends WCP command with null-byte framing', () async {
      final mock = await _startServer((cmd) => _resp(cmd, {}));
      final client = WcpClient(host: 'localhost', port: mock.server.port);
      await client.call('zoom_to_fit');
      await mock.server.close();
      await client.close();

      expect(mock.received, hasLength(1));
      expect(mock.received.first['type'], 'command');
      expect(mock.received.first['command'], 'zoom_to_fit');
      expect(mock.received.first['id'], isA<int>());
      expect(mock.received.first['data'], isA<Map>());
    });

    test('call() returns response data map', () async {
      final mock = await _startServer(
        (cmd) => _resp(cmd, {'ok': true, 'time': 500}),
      );
      final client = WcpClient(host: 'localhost', port: mock.server.port);
      final result = await client.call('set_cursor', {'timestamp': 500});
      await mock.server.close();
      await client.close();

      expect(result, {'ok': true, 'time': 500});
    });

    test('call() skips event messages and reads the next response', () async {
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
            final frame =
                jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
            if (frame['type'] == 'greeting') continue;
            // Send a server-push event first, then the real response.
            _sendFrame(socket, {
              'type': 'event',
              'name': 'waveforms_loaded',
              'data': <String, dynamic>{},
            });
            _sendFrame(socket, _resp(frame, {'cursor': 100}));
          }
        });
      });

      final client = WcpClient(host: 'localhost', port: server.port);
      final result = await client.call('wavecrux.getState');
      await server.close();
      await client.close();

      expect(result['cursor'], 100);
    });

    test('call() throws WcpException on error response', () async {
      final mock = await _startServer(
        (cmd) => _err(cmd, code: -32602, message: 'Invalid params'),
      );
      final client = WcpClient(host: 'localhost', port: mock.server.port);
      await expectLater(
        client.call('set_cursor', {'timestamp': -1}),
        throwsA(
          isA<WcpException>()
              .having((e) => e.code, 'code', -32602)
              .having((e) => e.message, 'message', 'Invalid params'),
        ),
      );
      await mock.server.close();
      await client.close();
    });

    test('call() throws WcpException on connection refused', () async {
      final client = WcpClient(host: 'localhost', port: 19999);
      await expectLater(
        client.call('wavecrux.getState'),
        throwsA(
          isA<WcpException>().having(
            (e) => e.message,
            'message',
            contains('Is WaveCrux running with Remote Control enabled?'),
          ),
        ),
      );
      await client.close();
    });

    test('call() throws WcpException on timeout', () async {
      // Server that sends greeting but never responds to commands.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((socket) {
        _sendFrame(socket, {
          'type': 'greeting',
          'version': '0',
          'commands': <String>[],
        });
        socket.listen((_) {}); // drain without responding
      });

      final client = WcpClient(
        host: 'localhost',
        port: server.port,
        timeout: const Duration(milliseconds: 100),
      );
      await expectLater(
        client.call('zoom_to_fit'),
        throwsA(isA<WcpException>()),
      );
      await server.close();
      await client.close();
    });

    test(
      'connect() reads server greeting before sending client greeting',
      () async {
        final serverReceived = <Map<String, dynamic>>[];
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
              final frame =
                  jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
              serverReceived.add(frame);
              if (frame['type'] != 'greeting') {
                _sendFrame(socket, _resp(frame, {}));
              }
            }
          });
        });

        final client = WcpClient(host: 'localhost', port: server.port);
        await client.call('zoom_to_fit');
        await server.close();
        await client.close();

        // First frame from client must be the greeting.
        expect(serverReceived.isNotEmpty, isTrue);
        expect(serverReceived.first['type'], 'greeting');
        expect(serverReceived.first.containsKey('commands'), isTrue);
        // Second frame must be the command.
        expect(serverReceived[1]['type'], 'command');
      },
    );

    test('multiple call()s reuse the same socket connection', () async {
      var connectionCount = 0;
      final received = <Map<String, dynamic>>[];
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((socket) {
        connectionCount++;
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
            final frame =
                jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
            if (frame['type'] == 'greeting') continue;
            received.add(frame);
            _sendFrame(socket, _resp(frame, {'ok': true}));
          }
        });
      });

      final client = WcpClient(host: 'localhost', port: server.port);
      await client.call('zoom_to_fit');
      await client.call('wavecrux.getState');
      await server.close();
      await client.close();

      expect(connectionCount, 1);
      expect(received, hasLength(2));
    });

    test('WcpException.toString includes code when present', () {
      const e = WcpException('bad', code: -32602);
      expect(e.toString(), contains('-32602'));
      expect(e.toString(), contains('bad'));
    });

    test('WcpException.toString without code omits code field', () {
      const e = WcpException('no connection');
      expect(e.toString(), contains('no connection'));
      expect(e.toString(), isNot(contains('null')));
    });

    test('CliException.toString returns message', () {
      const e = CliException('fatal error');
      expect(e.toString(), 'fatal error');
    });
  });
}
