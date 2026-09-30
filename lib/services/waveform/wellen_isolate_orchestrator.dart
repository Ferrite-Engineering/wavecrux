// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// WellenIsolateOrchestrator — request-routing + lifecycle for the worker.
//
// Owns the long-lived background isolate that hosts the wellen FFI worker.
// Extracted out of [WellenProvider] so the failure / recovery / cancellation
// surface can be exercised in a unit test without spawning a real isolate
// and without loading the native library.
//
// The provider keeps the cached hierarchy / per-signal change lists and all
// FFI-call argument marshalling. The orchestrator only knows:
//
//   * how to spawn (and re-spawn) the worker isolate via an injectable
//     [IsolateSpawner] factory,
//   * how to assign request ids and route responses back to the right
//     completer,
//   * how to apply an optional per-request timeout that kills + respawns
//     the worker on hang,
//   * how to honor a cancel token so superseded in-flight responses are
//     silently dropped,
//   * how to dispose: kill the isolate, close the receive port, error
//     every still-pending completer.
//
// Tests pass a fake [IsolateSpawner] that talks to a controlled
// [ReceivePort]; production passes [defaultIsolateSpawner], which wraps
// [Isolate.spawn].

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

/// Signature for spawning the worker isolate.
///
/// Receives [mainPort], which is the SendPort the worker should:
///
///   1. Send its own worker [SendPort] back on (success), or
///   2. Send `null` on (failure to load the native library).
///
/// And [debugName], which is the optional isolate debug name.
///
/// Returns a handle the orchestrator can later [Isolate.kill] on. In tests,
/// the handle is a stand-in that records the kill call.
typedef IsolateSpawner =
    Future<IsolateHandle> Function(
      SendPort mainPort, {
      String? debugName,
    });

/// Handle for an isolate-like resource. A real [Isolate] kill closure backs
/// the production implementation; tests substitute a closure that records
/// the kill call instead of touching `dart:isolate`.
///
/// Implementations must be idempotent — [kill] may be called more than
/// once if the orchestrator is disposed after an earlier kill-and-respawn.
@immutable
class IsolateHandle {
  const IsolateHandle(this._kill);

  /// Wraps a real [Isolate]. Used in production by [defaultIsolateSpawner].
  IsolateHandle.real(Isolate isolate)
    : _kill = (() => isolate.kill(priority: Isolate.immediate));

  final void Function() _kill;

  /// Terminates the underlying isolate (or releases the test fake).
  void kill() => _kill();
}

/// Production spawner: wraps [Isolate.spawn] with the worker entry point
/// supplied by the caller.
///
/// The caller passes the top-level [entryPoint] function. This indirection
/// keeps `dart:isolate` knowledge in this file while letting the worker body
/// stay in `wellen_provider_io.dart`.
IsolateSpawner defaultIsolateSpawner(
  void Function(SendPort) entryPoint,
) {
  return (SendPort mainPort, {String? debugName}) async {
    final isolate = await Isolate.spawn<SendPort>(
      entryPoint,
      mainPort,
      errorsAreFatal: false,
      debugName: debugName,
    );
    return IsolateHandle.real(isolate);
  };
}

/// Error thrown when the worker isolate cannot be initialized (native
/// library missing, spawn failed, etc.).
class WellenIsolateInitException implements Exception {
  WellenIsolateInitException(this.message);
  final String message;
  @override
  String toString() => 'WellenIsolateInitException: $message';
}

/// Manages the lifecycle of the wellen worker isolate and routes requests
/// to it.
///
/// See the file-level comment for the seam description.
class WellenIsolateOrchestrator {
  WellenIsolateOrchestrator({
    required IsolateSpawner spawner,
    String? debugName,
  }) : _spawner = spawner,
       _debugName = debugName ?? 'wellen_worker';

  final IsolateSpawner _spawner;
  final String _debugName;

  IsolateHandle? _isolate;
  SendPort? _workerPort;
  ReceivePort? _receivePort;

  int _nextRequestId = 0;
  final _pending = <int, _PendingRequest>{};

  /// Monotonically increasing cancel token. Responses that arrive for a
  /// request whose token differs from the current value are dropped.
  int _loadToken = 0;
  int get currentLoadToken => _loadToken;

  bool _disposed = false;
  bool get isDisposed => _disposed;

  /// Whether the worker isolate is currently running.
  bool get isRunning => _workerPort != null;

  /// Spawn the worker isolate (idempotent — second call while running is a
  /// no-op). Returns the SendPort the worker reports back, or throws
  /// [WellenIsolateInitException] if the worker cannot come up.
  Future<void> start() async {
    if (_disposed) {
      throw StateError('WellenIsolateOrchestrator: already disposed');
    }
    if (_workerPort != null) return;

    final receivePort = ReceivePort();
    _receivePort = receivePort;

    final initCompleter = Completer<SendPort>();

    receivePort.listen((dynamic raw) {
      if (!initCompleter.isCompleted) {
        if (raw == null) {
          initCompleter.completeError(
            WellenIsolateInitException(
              'wellen native library could not be loaded',
            ),
          );
        } else {
          initCompleter.complete(raw as SendPort);
        }
        return;
      }
      _routeResponse(raw);
    });

    try {
      _isolate = await _spawner(receivePort.sendPort, debugName: _debugName);
    } on Object catch (e) {
      // Spawn threw before sending anything: surface a graceful init error
      // and clean up the receive port so we don't leak a dangling listener.
      receivePort.close();
      _receivePort = null;
      throw WellenIsolateInitException('spawn failed: $e');
    }

    try {
      _workerPort = await initCompleter.future;
    } on Object {
      // Worker reported a failure before sending a SendPort (e.g. native
      // library missing). Tear down so a subsequent caller can retry.
      _isolate?.kill();
      _isolate = null;
      _receivePort?.close();
      _receivePort = null;
      rethrow;
    }
  }

  void _routeResponse(dynamic raw) {
    if (raw is! Map) return;
    final id = raw['id'];
    if (id is! int) return;
    final pending = _pending.remove(id);
    if (pending == null) return;
    // Honor cancel token: if the request opted in to load-token tracking
    // AND the token snapshot differs from the current token, silently drop
    // the response. Untagged requests (loadToken == null) always complete.
    if (pending.loadToken != null && pending.loadToken != _loadToken) {
      return;
    }
    if (!pending.completer.isCompleted) {
      pending.completer.complete(raw.cast<String, dynamic>());
    }
  }

  /// Send [payload] to the worker. The map will be sent verbatim with an
  /// `id` field added so the response can be routed back.
  ///
  /// If [timeout] is provided and the worker doesn't respond within it,
  /// the isolate is killed and respawned on the next [start] call, and the
  /// future completes with a [TimeoutException].
  ///
  /// If [tagWithLoadToken] is true, the request is associated with the
  /// current [currentLoadToken]; a subsequent [bumpLoadToken] call will
  /// cause any late response to be dropped.
  Future<Map<String, dynamic>> send(
    Map<String, dynamic> payload, {
    Duration? timeout,
    bool tagWithLoadToken = false,
  }) {
    if (_disposed) {
      return Future.error(
        StateError('WellenIsolateOrchestrator: disposed'),
      );
    }
    final port = _workerPort;
    if (port == null) {
      return Future.error(
        StateError('WellenIsolateOrchestrator: not started'),
      );
    }
    final id = _nextRequestId++;
    final completer = Completer<Map<String, dynamic>>();
    final loadToken = tagWithLoadToken ? _loadToken : null;
    _pending[id] = _PendingRequest(completer, loadToken);
    port.send({'id': id, ...payload});

    if (timeout == null) {
      return completer.future;
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        // Drop the pending entry so any late response is ignored, then kill
        // the worker so it doesn't continue chewing on whatever caused the
        // hang. The caller decides whether to call start() again.
        _pending.remove(id);
        _killAndDrainPending(
          TimeoutException(
            'WellenIsolateOrchestrator: request "${payload['op']}" '
            'timed out after ${timeout.inMilliseconds}ms',
          ),
        );
        throw TimeoutException(
          'WellenIsolateOrchestrator: request "${payload['op']}" '
          'timed out after ${timeout.inMilliseconds}ms',
        );
      },
    );
  }

  /// Send [payload] without waiting for a response. Useful for fire-and-
  /// forget cleanup messages just before [dispose].
  ///
  /// Returns the assigned request id (caller may ignore it). Throws
  /// [StateError] if the orchestrator is disposed or not started.
  int sendOneWay(Map<String, dynamic> payload) {
    if (_disposed) {
      throw StateError('WellenIsolateOrchestrator: disposed');
    }
    final port = _workerPort;
    if (port == null) {
      throw StateError('WellenIsolateOrchestrator: not started');
    }
    final id = _nextRequestId++;
    port.send({'id': id, ...payload});
    return id;
  }

  /// Increment the load token, causing any in-flight responses tagged with
  /// the previous token to be dropped when they arrive.
  ///
  /// Pending completers are NOT errored — they're simply orphaned. Callers
  /// holding their futures must arrange their own cancellation semantics
  /// (typically by attaching `.then(...)` callbacks that no-op when the
  /// caller is gone).
  void bumpLoadToken() {
    _loadToken++;
  }

  /// Kill the worker and error every pending request, but keep the
  /// orchestrator usable (a subsequent [start] respawns the worker).
  ///
  /// Used by the timeout path and for explicit recovery.
  void _killAndDrainPending(Object error) {
    _isolate?.kill();
    _isolate = null;
    _workerPort = null;
    _receivePort?.close();
    _receivePort = null;
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final p in pending) {
      if (!p.completer.isCompleted) {
        p.completer.completeError(error);
      }
    }
  }

  /// Permanently dispose this orchestrator. After [dispose], [send] and
  /// [start] will throw [StateError]. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _killAndDrainPending(StateError('WellenIsolateOrchestrator: disposed'));
  }

  /// Visible for testing: snapshot of pending request ids. Empty in normal
  /// steady-state.
  @visibleForTesting
  Iterable<int> get debugPendingIds => _pending.keys;
}

/// One in-flight request awaiting a response from the worker.
@immutable
class _PendingRequest {
  const _PendingRequest(this.completer, this.loadToken);
  final Completer<Map<String, dynamic>> completer;

  /// Snapshot of the orchestrator's load token at the moment the request
  /// was sent, or `null` if the request opted out of load-token tracking.
  final int? loadToken;
}
