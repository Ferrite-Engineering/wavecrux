// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/services/translate/process_filter_service.dart';

part 'process_filter_provider.g.dart';

/// Captures external translate-filter process launch failures into the
/// issue-reporter buffer (release-visible, unlike the old debug-only prints).
final _log = Logger('wavecrux.translate');

/// Manages active GTKWave process-filter programs per signal.
///
/// State is a [Map<String, String?>] keyed by signal ref, where the value is
/// the **cached translated label** from the most recent successful
/// [translateValue] call (`null` when no cached result is available yet).
///
/// The actual [ProcessFilterService] instances (running processes) are stored
/// internally. Call [executablePaths] to get the signalRef→path map for
/// session persistence.
///
/// Process filter translation is asynchronous: callers typically fire-and-
/// forget via `unawaited(notifier.translateValue(...))` so that the value
/// column updates reactively when the result arrives.
///
/// ## macOS App Sandbox Limitation
///
/// Process filters spawn arbitrary user scripts via [Process.start], which is
/// blocked by the macOS App Sandbox. On a sandboxed macOS build,
/// [setProcessFilter] will return an error message rather than silently
/// failing. Users who need process filters on macOS have these options:
///   (a) Run WaveCrux without the sandbox (unsigned or dev builds).
///   (b) Distribute the app outside the App Store without sandbox.
///   (c) Use the static translate filter file alternative instead — assign a
///       GTKWave-compatible `.txt` value→label file via "Assign Translate
///       Filter…". Static filters read a file at load time and require no
///       process spawning, so they work within the sandbox.
@Riverpod(keepAlive: true)
class ProcessFilterNotifier extends _$ProcessFilterNotifier {
  // signalRef → running ProcessFilterService
  final Map<String, ProcessFilterService> _services = {};

  // signalRef → absolute executable path (for session snapshot / UI display)
  final Map<String, String> _executablePaths = {};

  @override
  Map<String, String?> build() {
    ref.onDispose(_disposeAll);
    return const {};
  }

  void _disposeAll() {
    for (final svc in _services.values) {
      svc.dispose();
    }
    _services.clear();
  }

  /// Starts a new process-filter program at [executablePath] (with optional
  /// [arguments]) and assigns it to [signalRef].
  ///
  /// Any previously running process for the same signal is disposed first.
  /// Returns `null` on success. Returns a user-facing error message string when
  /// the process cannot be started — the caller should display it to the user.
  ///
  /// On [kIsWeb] this is a no-op and returns `null`.
  ///
  /// If the OS denies process creation (e.g., macOS app sandbox), returns a
  /// message explaining the sandbox limitation and suggesting the static
  /// translate filter alternative. Other launch failures are logged and return
  /// `null` (silent failure — typically a bad path or missing executable).
  Future<String?> setProcessFilter(
    String signalRef,
    String executablePath, [
    List<String> arguments = const [],
  ]) async {
    if (kIsWeb) {
      if (kDebugMode) {
        debugPrint(
          'ProcessFilterNotifier: process filters not supported on web',
        );
      }
      return null;
    }
    // Dispose any existing process for this signal.
    _services[signalRef]?.dispose();
    _services.remove(signalRef);

    final service = ProcessFilterService();
    try {
      await service.startProcess(executablePath, arguments);
    } on ProcessException catch (e) {
      service.dispose();
      if (e.message.contains('Operation not permitted')) {
        return _kSandboxError;
      }
      _log.warning('Failed to start process filter "$executablePath": $e');
      return null;
    } on Exception catch (e) {
      _log.warning('Failed to start process filter "$executablePath": $e');
      service.dispose();
      return null;
    }

    _services[signalRef] = service;
    _executablePaths[signalRef] = executablePath;
    // Add to state with null cache (no translation yet for this cursor time).
    state = Map<String, String?>.unmodifiable({...state, signalRef: null});
    return null;
  }

  static const _kSandboxError =
      'Process filters are not available in the sandboxed macOS build. '
      'Use "Assign Translate Filter…" with a .txt file instead — '
      'static filters work within the sandbox.';

  /// Removes the process filter for [signalRef] and kills its process.
  ///
  /// No-op when no process filter is assigned to [signalRef].
  void removeProcessFilter(String signalRef) {
    if (!state.containsKey(signalRef)) return;
    _services[signalRef]?.dispose();
    _services.remove(signalRef);
    _executablePaths.remove(signalRef);
    state = Map<String, String?>.unmodifiable(
      Map<String, String?>.from(state)..remove(signalRef),
    );
  }

  /// Disposes all running filter processes and resets state to empty.
  ///
  /// Called by [WaveformSourceNotifier] when a new file is opened or the
  /// current file is closed, so that stale filters from a previous file are
  /// not applied to signals in the new file that happen to share the same ref.
  void clearAll() {
    _disposeAll();
    _executablePaths.clear();
    state = const {};
  }

  /// Sends [rawValue] (the raw VCD bit-string, e.g. `"b11001010"` or `"1"`)
  /// to the process filter assigned to [signalRef].
  ///
  /// Converts [rawValue] to its hex representation before sending (GTKWave
  /// protocol). Returns the translated label, or `null` if no filter is
  /// assigned, the process timed out, or no translation is available.
  ///
  /// When the result differs from the cached value, state is updated so that
  /// watchers of this provider rebuild with the new label.
  Future<String?> translateValue(
    String signalRef,
    String rawValue, {
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    final service = _services[signalRef];
    if (service == null) return null;

    final hexValue = _rawBitsToHex(rawValue);
    final translated = await service.translate(hexValue, timeout: timeout);

    // Only mutate state when the result actually changed to avoid
    // triggering unnecessary rebuilds.
    if (state[signalRef] != translated) {
      state = Map<String, String?>.unmodifiable({
        ...state,
        signalRef: translated,
      });
    }
    return translated;
  }

  /// Whether [signalRef] currently has a process filter assigned.
  bool hasProcessFilter(String signalRef) => state.containsKey(signalRef);

  /// Current signalRef → executable-path assignments for session persistence.
  Map<String, String> get executablePaths => Map.unmodifiable(_executablePaths);

  /// Restores process filters from a saved session.
  ///
  /// Disposes all current filters, then starts a new process for each path in
  /// [paths]. Entries whose executable cannot be started are silently skipped.
  Future<void> restoreFromSession(Map<String, String> paths) async {
    _disposeAll();
    _executablePaths.clear();
    state = const {};

    for (final entry in paths.entries) {
      await setProcessFilter(entry.key, entry.value);
    }
  }

  // ── helpers ─────────────────────────────────────────────────────────────────

  /// Converts a raw VCD bit-string to its hex representation for the process
  /// filter protocol.
  ///
  /// - Strips the leading `b`/`B` prefix used by multi-bit VCD values.
  /// - Values containing `x` or `z` bits are sent as `"x"`.
  /// - Pure binary values are converted to lowercase hex.
  static String _rawBitsToHex(String rawValue) {
    var bits = rawValue.toLowerCase();
    if (bits.startsWith('b')) bits = bits.substring(1);
    if (bits.contains('x') || bits.contains('z')) return 'x';
    final value = BigInt.tryParse(bits, radix: 2);
    if (value == null) return bits;
    return value.toRadixString(16);
  }
}
