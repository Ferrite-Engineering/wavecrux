// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

/// Faults inside the server — anything other than a peer going away — are
/// reported here, which puts them in the issue reporter's buffer and, at
/// SEVERE, on stderr.
final _log = Logger('wavecrux.wcp');

/// Whether [error] means only that the peer went away: the connection was
/// reset or aborted, or a write found it already closed.
///
/// A client that disconnects while the server is still writing to it — the
/// greeting goes out the instant a connection is accepted — surfaces as one of
/// these on the socket's write side. That is ordinary client behaviour, so it
/// is the one error class the server drops without a word. Every other error
/// is a fault and is logged; running out of file descriptors on accept, a
/// listener that throws, and a reply that cannot be encoded all look nothing
/// like a hang-up and must not be filed with one.
bool isPeerGoneSocketError(Object error) {
  if (error is! SocketException) return false;
  final code = error.osError?.errorCode;
  return code != null && _peerGoneErrnos.contains(code);
}

/// ECONNABORTED, ECONNRESET, EPIPE and ENOTCONN (plus WSAESHUTDOWN, which
/// Windows reports for a write after the peer's shutdown), in the host's own
/// numbering: the values differ between the BSD family, Linux, and Winsock.
final Set<int> _peerGoneErrnos = Platform.isWindows
    ? const {10053, 10054, 10057, 10058}
    : (Platform.isLinux || Platform.isAndroid)
    ? const {32, 103, 104, 107}
    : const {32, 53, 54, 57};

// ── Exception ─────────────────────────────────────────────────────────────────

/// Thrown by a WCP command handler to return a structured error response.
class WcpException implements Exception {
  const WcpException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => 'WcpException(${code ?? '?'}): $message';
}

// ── Handler typedef ───────────────────────────────────────────────────────────

/// Invoked when the server receives a WCP command.
///
/// [params] holds the command parameters regardless of which wire envelope
/// carried them (nested `data` for the legacy id dialect, top-level fields
/// for the spec envelope — see [WcpServer]).
///
/// Return `null` to send an empty response, or a non-null map to populate the
/// response payload. Throw [WcpException] to send an error response with the
/// exception's code and message.
typedef WcpCommandHandler =
    Future<Map<String, dynamic>?> Function(
      String command,
      Map<String, dynamic> params,
    );

// ── Per-connection state ──────────────────────────────────────────────────────

class _WcpConnection {
  _WcpConnection(this.socket);

  final Socket socket;
  final List<int> buffer = [];

  /// Serial dispatch queue: each received frame's handler is chained onto the
  /// previous one, so replies always go out in request order (the spec
  /// envelope carries no correlation id — clients match replies by order).
  Future<void> tail = Future<void>.value();

  /// Latched to `true` once the client sends an id-less (spec-envelope)
  /// command; controls how broadcast events are shaped for this connection.
  bool usesSpecEnvelope = false;
}

// ── Server ────────────────────────────────────────────────────────────────────

/// WCP (Waveform Control Protocol) TCP server.
///
/// Implements the upstream WCP wire protocol as specified by the Surfer
/// project's `surfer-wcp` crate (`surfer-wcp/src/proto.rs` in the
/// `surfer-project/surfer` repository, pinned at commit
/// `4281e79afec3fed8759aa45ade689a181aaad533`). Protocol version `"0"`.
///
/// Spec envelope (upstream, the default for third-party WCP clients):
/// - Null-byte (`\x00`) delimited JSON framing.
/// - Commands are id-less: `{"type":"command","command":<name>,...params}`
///   with parameters as top-level fields.
/// - Replies are correlated by order: every command receives exactly one
///   response/error frame, in request order (enforced by a per-connection
///   serial dispatch queue).
/// - Payload-bearing responses echo the command name
///   (`{"type":"response","command":"add_items","ids":[...]}`); commands
///   without a payload are acknowledged as `{"type":"response","command":"ack"}`.
/// - Errors are `{"type":"error","error":<name>,"arguments":[...],"message":…}`.
/// - Events are `{"type":"event","event":<name>,...fields}`.
/// - The deprecated spec commands `add_variables` / `add_scope` are accepted
///   and dispatched as `add_items` (responses echo the original name).
///
/// Legacy id dialect (WaveCrux's original envelope, used by `wavecrux_ctl`;
/// retained behind [idDialectEnabled]):
/// - Commands carry a mandatory integer `id` and nest parameters under
///   `data`: `{"type":"command","id":N,"command":<name>,"data":{...}}`.
/// - Replies echo the id: `{"type":"response","id":N,"data":{...}}` /
///   `{"type":"error","id":N,"code":C,"message":…}`.
/// - Events nest their fields: `{"type":"event","event":<name>,"data":{...}}`.
///
/// A `command` frame carrying an `id` selects the id dialect when it also
/// nests its parameters under `data`, or when the command's spec parameters
/// do not themselves include an `id`. `focus_item` and `set_item_color` take an item `id` as a
/// spec parameter, so for those two an `id` without `data` is that parameter
/// and the frame is spec-envelope. Detection is per message, so one
/// connection may mix both; broadcast events follow the envelope of the most
/// recent style latched for the connection (legacy until a spec-envelope
/// command is seen).
///
/// Greeting handshake: the server sends
/// `{"type":"greeting","version":"0","commands":[...]}` immediately on
/// connect. A client greeting is optional (permissive deviation from
/// upstream, which requires it before any command), but when one arrives its
/// `version` is checked: a major version other than 0 receives a spec-shaped
/// `error: "greeting"` frame. The connection stays open either way.
class WcpServer {
  WcpServer({
    required this.onCommand,
    this.onClientCountChanged,
    this.idDialectEnabled = true,
  });

  static const int defaultPort = 54321;

  /// Upper bound on one `\x00`-delimited inbound frame, in bytes.
  ///
  /// WCP framing is a delimiter scan over a growing buffer, so a peer that
  /// never sends the delimiter is a peer that grows this process's heap for
  /// as long as it keeps writing — the same unbounded-accumulation shape
  /// CXP closes with its own frame cap, and the reason a frame cap is
  /// mandatory rather than advisory. A connection whose buffer passes this
  /// without yielding a frame is dropped; the bound is generous next to the
  /// largest legitimate command (an `add_items` naming a few thousand
  /// signals is tens of kilobytes).
  static const int maxFrameBytes = 1 << 20;

  /// Advertised protocol version. The upstream spec pins integer version 0
  /// (serialized as a string); minor/patch suffixes are tolerated when
  /// checking client greetings.
  static const String wcpVersion = '0';

  static const List<String> _supportedCommands = [
    'load',
    'reload',
    'clear',
    'shutdown',
    'add_items',
    'add_variables',
    'add_scope',
    'remove_items',
    'get_item_list',
    'get_item_info',
    'set_cursor',
    'set_viewport_range',
    'set_viewport_to',
    'zoom_to_fit',
    'set_item_color',
    'focus_item',
    'add_markers',
    'wavecrux.getValueAt',
    'wavecrux.getHierarchy',
    'wavecrux.getState',
    'wavecrux.setActiveTab',
  ];

  /// Spec commands with a top-level parameter named `id` (an item id, not a
  /// correlation id). An `id` on one of these selects the id dialect only
  /// when the frame also nests its parameters under `data`.
  static const Set<String> _specCommandsWithIdParam = {
    'focus_item',
    'set_item_color',
  };

  /// Deprecated spec commands dispatched as `add_items` with their
  /// parameters mapped to the canonical shape. Responses echo the original
  /// command name.
  static const Map<String, String> _commandAliases = {
    'add_variables': 'add_items',
    'add_scope': 'add_items',
  };

  final WcpCommandHandler onCommand;

  /// Called whenever the number of connected clients changes.
  final void Function(int count)? onClientCountChanged;

  /// Compat flag for the legacy id dialect. When `false`, id-framed commands
  /// are rejected with a spec-shaped error instead of being dispatched.
  final bool idDialectEnabled;

  ServerSocket? _serverSocket;
  final Map<Socket, _WcpConnection> _clients = {};

  bool get isRunning => _serverSocket != null;
  int get connectedClients => _clients.length;

  /// The bound port, or `null` when not running.
  int? get port => _serverSocket?.port;

  /// Binds to `127.0.0.1:[port]` and begins accepting connections.
  Future<void> start(int port) async {
    _serverSocket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
    );
    // Every accepted socket is created inside this zone, so its write-side
    // failures — which arrive on the socket's `done` future, awaited by
    // nobody — land in the zone handler instead of the caller's zone. The
    // common one is a client disconnecting during or just after accept, while
    // the greeting is still being written (ECONNRESET / EPIPE), and that is
    // dropped. Anything else reaching the handler is a fault — a listener
    // throwing, the accept loop failing — and is logged.
    runZonedGuarded(
      () => _serverSocket!.listen(
        _handleConnection,
        onError: _reportUnexpected,
        cancelOnError: false,
      ),
      _reportUnexpected,
    );
  }

  /// Drops a peer hang-up; logs every other error with its stack.
  void _reportUnexpected(Object error, StackTrace stack) {
    if (isPeerGoneSocketError(error)) return;
    _log.severe('WCP server error outside any command', error, stack);
  }

  /// Closes all connections and the server socket.
  Future<void> stop() async {
    for (final socket in List<Socket>.of(_clients.keys)) {
      socket.destroy();
    }
    _clients.clear();
    await _serverSocket?.close();
    _serverSocket = null;
    onClientCountChanged?.call(0);
  }

  /// Sends [event] as a `\x00`-terminated frame to every connected client,
  /// shaped for each connection's latched envelope: spec-envelope clients
  /// receive the fields of [data] at the top level, legacy clients receive
  /// them nested under `data`.
  void broadcastEvent(String event, Map<String, dynamic> data) {
    for (final conn in List<_WcpConnection>.of(_clients.values)) {
      final msg = conn.usesSpecEnvelope
          ? {'type': 'event', 'event': event, ...data}
          : {'type': 'event', 'event': event, 'data': data};
      _writeMsg(conn.socket, msg);
    }
  }

  // ── connection handling ───────────────────────────────────────────────────

  void _handleConnection(Socket socket) {
    final conn = _WcpConnection(socket);
    _clients[socket] = conn;
    onClientCountChanged?.call(_clients.length);

    // Send greeting immediately on connect.
    _writeMsg(socket, {
      'type': 'greeting',
      'version': wcpVersion,
      'commands': _supportedCommands,
    });

    socket.listen(
      (chunk) => _onData(conn, chunk),
      onDone: () => _disconnect(socket),
      onError: (Object _) => _disconnect(socket),
      cancelOnError: false,
    );
  }

  void _disconnect(Socket socket) {
    if (_clients.remove(socket) == null) return;
    onClientCountChanged?.call(_clients.length);
    socket.destroy();
  }

  /// Drops [socket] the way [_disconnect] does, but only once the bytes
  /// already handed to it have gone out.
  ///
  /// `Socket.add` buffers, and `destroy()` discards that buffer — so a plain
  /// [_disconnect] straight after writing an error frame closes the
  /// connection with the explanation still queued, and the peer sees an
  /// unexplained hang-up. Every close-with-a-reason goes through here.
  void _disconnectAfterFlush(Socket socket) {
    if (_clients.remove(socket) == null) return;
    onClientCountChanged?.call(_clients.length);
    unawaited(() async {
      try {
        await socket.flush();
      } on Object {
        // The peer is already gone; the frame it explains is moot.
      }
      socket.destroy();
    }());
  }

  void _onData(_WcpConnection conn, List<int> chunk) {
    conn.buffer.addAll(chunk);
    // Checked before the delimiter scan, so a peer that never terminates a
    // frame is dropped rather than buffered without limit. Checked on the
    // whole buffer rather than per frame because the buffer IS the partial
    // frame: anything ahead of the first `\x00` is one unfinished message.
    if (conn.buffer.length > maxFrameBytes) {
      _disconnect(conn.socket);
      return;
    }
    while (true) {
      final idx = conn.buffer.indexOf(0);
      if (idx < 0) break;
      final msgBytes = List<int>.from(conn.buffer.sublist(0, idx));
      conn.buffer.removeRange(0, idx + 1);
      if (msgBytes.isEmpty) continue;
      // Chain onto the connection's serial queue so a frame's handler
      // completes (and its reply is written) before the next frame is
      // dispatched — the spec envelope correlates replies by order.
      // [_handleMessage] answers every failure it anticipates with an error
      // frame, so an error escaping it is a fault; it is logged, and the
      // queue carries on so later frames are still answered.
      conn.tail = conn.tail
          .then((_) => _handleMessage(conn, msgBytes))
          .catchError(_reportUnexpected);
    }
  }

  Future<void> _handleMessage(_WcpConnection conn, List<int> bytes) async {
    final socket = conn.socket;
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected JSON object');
      }
      msg = decoded;
    } on Object {
      // Answer, then close. A peer that cannot produce one parseable frame
      // is not a WCP client that made a mistake — it is a browser form POST,
      // a TLS ClientHello, or a scanner, and every byte it sends after this
      // is more of the same. Keeping the connection open answers each of
      // those bytes with another error frame and leaves a cross-origin page
      // holding a socket to this process; closing is what ends that, and is
      // what CXP's own framing layer does on its first unparseable frame.
      // The error still goes out first, so a genuine client's one bad frame
      // is diagnosable rather than a silent hang-up.
      if (conn.usesSpecEnvelope) {
        _writeSpecError(socket, 'parse', const [], 'Parse error');
        _disconnectAfterFlush(socket);
      } else {
        _writeMsg(socket, {
          'type': 'error',
          'id': null,
          'code': 1,
          'message': 'Parse error',
        });
        _disconnectAfterFlush(socket);
      }
      return;
    }

    final type = msg['type'];

    if (type == 'greeting') {
      _handleClientGreeting(socket, msg);
      return;
    }

    if (type != 'command') return;

    final id = msg['id'];
    final command = msg['command'];
    final isIdDialect =
        id != null &&
        (msg.containsKey('data') ||
            !_specCommandsWithIdParam.contains(command));

    if (command is! String) {
      if (isIdDialect && id is int) {
        _writeMsg(socket, {
          'type': 'error',
          'id': id,
          'code': 1,
          'message': 'Parse error: command must be a string',
        });
      } else {
        _writeSpecError(
          socket,
          'parse',
          const [],
          'Parse error: command must be a string',
        );
      }
      return;
    }

    if (!isIdDialect) {
      conn.usesSpecEnvelope = true;
      final params = Map<String, dynamic>.from(msg)
        ..remove('type')
        ..remove('command');
      await _dispatchSpec(socket, command, params);
      return;
    }

    if (id is! int) {
      _writeMsg(socket, {
        'type': 'error',
        'id': null,
        'code': 1,
        'message': 'Parse error: id must be an integer or absent',
      });
      return;
    }

    if (!idDialectEnabled) {
      _writeSpecError(
        socket,
        command,
        const [],
        'The id-framed command envelope is disabled on this server',
      );
      return;
    }

    final rawData = msg['data'];
    final data = rawData is Map<String, dynamic>
        ? rawData
        : <String, dynamic>{};
    await _dispatchIdDialect(socket, command, id, data);
  }

  void _handleClientGreeting(Socket socket, Map<String, dynamic> msg) {
    final version = msg['version'];
    final versionString = version is String ? version : version?.toString();
    final major = versionString?.split('.').first;
    if (major == wcpVersion) return;
    _writeSpecError(
      socket,
      'greeting',
      [versionString ?? 'null'],
      'WaveCrux only supports WCP version $wcpVersion, '
          'client requested $versionString',
    );
  }

  // ── spec-envelope dispatch ────────────────────────────────────────────────

  Future<void> _dispatchSpec(
    Socket socket,
    String command,
    Map<String, dynamic> params,
  ) async {
    if (!_supportedCommands.contains(command)) {
      _writeSpecError(socket, command, const [], 'Unknown command: $command');
      return;
    }
    try {
      final result = await onCommand(
        _commandAliases[command] ?? command,
        _normalizeAliasParams(command, params),
      );
      _writeMsg(socket, _specResponse(command, result));
    } on WcpException catch (e) {
      _writeSpecError(socket, command, const [], e.message);
    } on Object catch (e, stack) {
      // A handler that throws anything but a WcpException has a bug; the
      // client hears "Internal error", and the stack stays here.
      _log.severe('WCP command "$command" failed', e, stack);
      _writeSpecError(socket, command, const [], 'Internal error: $e');
    }
  }

  /// Shapes a handler payload into the spec response for [command].
  ///
  /// Item-producing commands reply with `ids` (add family, `get_item_list`)
  /// or `results` (`get_item_info`) per the upstream response enum; commands
  /// without a spec payload acknowledge as `command: "ack"`. WaveCrux
  /// extension commands (outside the spec surface) echo their name and carry
  /// the payload at the top level.
  Map<String, dynamic> _specResponse(
    String command,
    Map<String, dynamic>? result,
  ) {
    switch (command) {
      case 'add_items':
      case 'add_variables':
      case 'add_scope':
      case 'add_markers':
      case 'get_item_list':
        final items = (result?['items'] as List?) ?? const [];
        return {
          'type': 'response',
          'command': command,
          'ids': [
            for (final item in items.whereType<Map<String, dynamic>>())
              item['id'],
          ],
        };
      case 'get_item_info':
        final items = (result?['items'] as List?) ?? const [];
        return {
          'type': 'response',
          'command': command,
          'results': [
            for (final item in items.whereType<Map<String, dynamic>>())
              {
                'name': item['name'],
                'type': item['type'] ?? 'Variable',
                'id': item['id'],
              },
          ],
        };
      default:
        if (command.startsWith('wavecrux.') &&
            result != null &&
            result.isNotEmpty) {
          return {'type': 'response', 'command': command, ...result};
        }
        return {'type': 'response', 'command': 'ack'};
    }
  }

  /// Maps deprecated-alias parameters onto the canonical `add_items` shape.
  Map<String, dynamic> _normalizeAliasParams(
    String command,
    Map<String, dynamic> params,
  ) {
    switch (command) {
      case 'add_variables':
        return {'items': params['variables']};
      case 'add_scope':
        return {
          'items': [params['scope']],
          'recursive': params['recursive'] == true,
        };
      default:
        return params;
    }
  }

  // ── id-dialect dispatch ───────────────────────────────────────────────────

  Future<void> _dispatchIdDialect(
    Socket socket,
    String command,
    int id,
    Map<String, dynamic> data,
  ) async {
    if (!_supportedCommands.contains(command)) {
      _writeMsg(socket, {
        'type': 'error',
        'id': id,
        'code': 2,
        'message': 'Unknown command: $command',
      });
      return;
    }

    try {
      final result = await onCommand(
        _commandAliases[command] ?? command,
        _normalizeAliasParams(command, data),
      );
      _writeMsg(socket, {
        'type': 'response',
        'id': id,
        'data': result ?? <String, dynamic>{},
      });
    } on WcpException catch (e) {
      _writeMsg(socket, {
        'type': 'error',
        'id': id,
        'code': e.code ?? 4,
        'message': e.message,
      });
    } on Object catch (e, stack) {
      _log.severe('WCP command "$command" failed', e, stack);
      _writeMsg(socket, {
        'type': 'error',
        'id': id,
        'code': 4,
        'message': 'Internal error: $e',
      });
    }
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  void _writeSpecError(
    Socket socket,
    String error,
    List<String> arguments,
    String message,
  ) {
    _writeMsg(socket, {
      'type': 'error',
      'error': error,
      'arguments': arguments,
      'message': message,
    });
  }

  /// Frames [msg] and writes it to [socket].
  ///
  /// Encoding happens outside the guard on purpose. A handler result that is
  /// not JSON-encodable is a fault in this process, not a departed client:
  /// raised here, it reaches the dispatcher's catch and goes back to the
  /// client as an error frame. Swallowed, it left a spec-envelope client —
  /// which matches replies by order — waiting forever for a reply that was
  /// never sent.
  void _writeMsg(Socket socket, Map<String, dynamic> msg) {
    final frame = _frame(msg);
    try {
      socket.add(frame);
    } on Object {
      // The client has disconnected; there is no one left to answer.
    }
  }

  List<int> _frame(Map<String, dynamic> msg) => [
    ...utf8.encode(jsonEncode(msg)),
    0,
  ];
}
