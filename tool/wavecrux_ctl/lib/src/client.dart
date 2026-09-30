// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Factory that creates a [WcpClient] for a given host and port.
typedef WcpClientFactory = WcpClient Function(String host, int port);

/// Injectable socket factory for testing.
typedef SocketFactory = Future<Socket> Function(String host, int port);

/// Thrown when a WCP call fails at the transport or protocol level.
class WcpException implements Exception {
  const WcpException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() =>
      code != null ? 'WCP error ($code): $message' : 'Error: $message';
}

/// Thrown by commands to signal a fatal CLI error without calling exit()
/// directly, allowing tests to catch it.
class CliException implements Exception {
  const CliException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thin Waveform Control Protocol (WCP) client over a persistent TCP connection.
///
/// Uses null-byte-terminated JSON frames. On [connect], exchanges a greeting
/// handshake with the server. Subsequent [call]s send command frames and read
/// response frames, silently skipping any server-push event frames.
class WcpClient {
  /// Default WCP port (54321 — WCP spec default).
  static const int defaultPort = 54321;

  /// WCP protocol version announced in the client greeting (the upstream
  /// spec pins integer version 0).
  static const String _wcpVersion = '0';

  WcpClient({
    required this.host,
    required this.port,
    this.timeout = const Duration(seconds: 10),
    SocketFactory? socketFactory,
  }) : _socketFactory = socketFactory ?? _defaultConnect;

  final String host;
  final int port;
  final Duration timeout;
  final SocketFactory _socketFactory;

  Socket? _socket;
  StreamIterator<List<int>>? _chunks;
  final List<int> _buf = [];
  int _id = 0;

  static Future<Socket> _defaultConnect(String h, int p) =>
      Socket.connect(h, p);

  /// Connects to the server, reads its greeting, then sends our greeting.
  /// Called automatically by [call] on the first invocation.
  Future<void> connect() async {
    try {
      _socket = await _socketFactory(host, port).timeout(
        timeout,
        onTimeout: () => throw TimeoutException('timeout', timeout),
      );
    } on TimeoutException {
      throw WcpException(
        'Connection to $host:$port timed out. '
        'Is WaveCrux running with Remote Control enabled?',
      );
    } on SocketException catch (e) {
      final code = e.osError?.errorCode;
      final isRefused =
          e.message.toLowerCase().contains('connection refused') ||
          (code != null && const {111, 61, 10061}.contains(code));
      throw WcpException(
        isRefused
            ? 'Could not connect to WaveCrux at $host:$port. '
                  'Is WaveCrux running with Remote Control enabled?'
            : 'Connection failed: ${e.message}',
      );
    }
    _chunks = StreamIterator(_socket!.cast<List<int>>());

    // Read and discard server greeting.
    await _readFrame();

    // Send client greeting.
    _writeFrame({
      'type': 'greeting',
      'version': _wcpVersion,
      'commands': <String>[],
    });
  }

  /// Sends a WCP command and returns the response `data` map.
  ///
  /// Connects automatically on first call. Silently skips any `event` messages
  /// received before the matching response. Throws [WcpException] on transport
  /// errors or server error responses.
  Future<Map<String, dynamic>> call(
    String command, [
    Map<String, dynamic>? data,
  ]) async {
    if (_socket == null) await connect();

    final id = ++_id;
    _writeFrame({
      'type': 'command',
      'command': command,
      'id': id,
      'data': data ?? <String, dynamic>{},
    });

    while (true) {
      final Map<String, dynamic> msg;
      try {
        msg = await _readFrame();
      } on TimeoutException {
        throw WcpException(
          'Response timed out. '
          'Is WaveCrux running with Remote Control enabled?',
        );
      }

      final type = msg['type'] as String?;

      // Server-push events are not responses — skip them.
      if (type == 'event') continue;

      if (type == 'error') {
        throw WcpException(
          msg['message'] as String? ?? 'Unknown server error',
          code: msg['code'] as int?,
        );
      }

      if (type == 'response') {
        final d = msg['data'];
        if (d is! Map<String, dynamic>) {
          throw const WcpException('Unexpected response format from server.');
        }
        return d;
      }

      // Unknown message types are ignored for forward-compatibility.
    }
  }

  /// Closes the connection.
  Future<void> close() async {
    await _chunks?.cancel();
    _chunks = null;
    _socket?.destroy();
    _socket = null;
    _buf.clear();
  }

  // ── framing ──────────────────────────────────────────────────────────────────

  void _writeFrame(Map<String, dynamic> msg) {
    _socket!.add([...utf8.encode(jsonEncode(msg)), 0]);
  }

  Future<Map<String, dynamic>> _readFrame() async {
    while (!_buf.contains(0)) {
      final hasMore = await _chunks!.moveNext().timeout(timeout);
      if (!hasMore) throw const WcpException('Connection closed unexpectedly.');
      _buf.addAll(_chunks!.current);
    }
    final idx = _buf.indexOf(0);
    final frameBytes = List<int>.from(_buf.sublist(0, idx));
    _buf.removeRange(0, idx + 1);
    try {
      return jsonDecode(utf8.decode(frameBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const WcpException('Received invalid JSON from server.');
    }
  }
}
