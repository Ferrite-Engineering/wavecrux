// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crux_io/crux_io.dart' show SpawnHost;
import 'package:flutter/foundation.dart';

/// Manages a single external translate-filter process.
///
/// GTKWave process filter protocol:
/// - The process is launched once and kept running (long-lived).
/// - To translate a value, write it as a hex string + newline to stdin.
/// - Read the translated label back as one line from stdout.
/// - An empty or whitespace-only response means "no translation" — fall back
///   to the raw value.
///
/// Error handling:
/// - Process crash → pending and future requests return `null`.
/// - Request timeout (500 ms default) → returns `null`.
/// - [kIsWeb] platform → all methods are no-ops returning `null`.
///
/// Callers must call [dispose] when the service is no longer needed.
class ProcessFilterService {
  /// [spawnHost] is the host the executable is resolved against, defaulting
  /// to the live process. Tests pass a Windows host with a synthetic PATH.
  ProcessFilterService({SpawnHost? spawnHost}) : _spawnHost = spawnHost;

  final SpawnHost? _spawnHost;
  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  final Queue<Completer<String?>> _pending = Queue();
  bool _disposed = false;

  // Serializes stdin writes so that flush() is never called concurrently on
  // the same IOSink (concurrent flush() calls throw "StreamSink is bound").
  Future<void> _writeChain = Future.value();

  /// Launches [executablePath] with optional [arguments].
  ///
  /// Throws [ProcessException] if the process cannot be started (e.g., file
  /// not found, permission denied). Safe to call only once per service
  /// instance; call [dispose] before re-starting.
  ///
  /// A bare name is resolved against PATH first. On Windows, `CreateProcess`
  /// would otherwise search WaveCrux's current directory — the shell it was
  /// launched from — ahead of PATH, so a same-named binary in that directory
  /// would run in place of the user's filter. A bare name nothing on PATH
  /// answers to throws the same [ProcessException] with nothing spawned.
  ///
  /// On [kIsWeb] this is a no-op.
  Future<void> startProcess(
    String executablePath, [
    List<String> arguments = const [],
  ]) async {
    if (kIsWeb) return;
    final executable = (_spawnHost ?? SpawnHost.current()).requireExecutable(
      executablePath,
    );
    _process = await Process.start(executable, arguments);

    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (_pending.isNotEmpty) {
              final completer = _pending.removeFirst();
              final trimmed = line.trim();
              completer.complete(trimmed.isEmpty ? null : trimmed);
            }
          },
          onDone: _onProcessExited,
          onError: (_) => _onProcessExited(),
          cancelOnError: false,
        );

    _stderrSub = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (kDebugMode) debugPrint('ProcessFilterService stderr: $line');
          },
          cancelOnError: false,
        );

    // Detect unexpected process exit.
    unawaited(
      _process!.exitCode.then((_) => _onProcessExited()),
    );
  }

  void _onProcessExited() {
    if (_disposed) return;
    if (kDebugMode) debugPrint('ProcessFilterService: process exited');
    _drainPending();
    _process = null;
  }

  void _drainPending() {
    for (final c in _pending) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
  }

  /// Sends [hexValue] to the process stdin and returns the translated label.
  ///
  /// [hexValue] should be the hex representation of the signal value (e.g.,
  /// `"ff"` for an 8-bit signal with all bits high). For indeterminate (x/z)
  /// values pass `"x"`.
  ///
  /// Returns `null` on:
  /// - Web platform
  /// - Process not running
  /// - Empty / whitespace-only response (no translation available)
  /// - Timeout (default 500 ms)
  /// - Any I/O error
  Future<String?> translate(
    String hexValue, {
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    if (kIsWeb || _disposed || _process == null) return null;
    try {
      final completer = Completer<String?>();
      _pending.add(completer);

      // Chain writes so flush() is never called concurrently on the same IOSink
      // (concurrent flush() calls throw "StreamSink is bound to a stream").
      // The timeout starts only after the write is flushed, so it measures only
      // the round-trip time to the filter process.
      final process = _process!;
      _writeChain = _writeChain.whenComplete(() async {
        if (!_disposed && _process != null) {
          process.stdin.writeln(hexValue);
          await process.stdin.flush();
        }
      });
      // Await the write before starting the response timeout so that slow
      // event-loop drains (e.g. heavy test environments) don't consume budget.
      await _writeChain;

      if (_disposed || _process == null) {
        _pending.remove(completer);
        return null;
      }

      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          _pending.remove(completer);
          if (!completer.isCompleted) completer.complete(null);
          return null;
        },
      );
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('ProcessFilterService.translate error: $e');
      return null;
    }
  }

  /// Whether the underlying process is currently running.
  bool get isRunning => !_disposed && _process != null;

  /// Kills the process and releases all resources.
  ///
  /// Safe to call multiple times. After dispose, [translate] always
  /// returns `null`.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _drainPending();
    unawaited(_stdoutSub?.cancel());
    unawaited(_stderrSub?.cancel());
    _process?.kill();
    _process = null;
  }
}
