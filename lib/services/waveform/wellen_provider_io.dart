// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// WellenProvider — WaveformDataSource backed by the wellen Rust library.
//
// All FFI calls run on a dedicated background isolate. After [openFile]
// completes, the full hierarchy and metadata are cached on the calling isolate.
// After [loadSignal] completes, all value changes for that signal are cached,
// enabling [valueAt], [changesInRange], [nextTransition], and [prevTransition]
// to execute synchronously without further inter-isolate round-trips.

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/native/bindings/wellen_ffi_bindings.dart';
import 'package:wavecrux/native/wellen_ffi_library_io.dart';
import 'package:wavecrux/services/waveform/compact_changes.dart';
import 'package:wavecrux/services/waveform/display_changes.dart';
import 'package:wavecrux/services/waveform/wellen_isolate_orchestrator.dart';

// ── Public implementation ──────────────────────────────────────────────────────

/// [WaveformDataSource] backed by the wellen Rust library via dart:ffi.
///
/// All native calls are dispatched to a long-lived background isolate so the
/// UI thread is never blocked. Hierarchy data and loaded-signal change lists
/// are copied back to the main isolate and cached locally, allowing the
/// synchronous query methods ([valueAt] etc.) to run without crossing the
/// isolate boundary at query time.
class WellenProvider implements WaveformDataSource, CompactChangesSource {
  WellenProvider({Duration? openTimeout, IsolateSpawner? spawner})
    : _openTimeoutOverride = openTimeout,
      _spawner = spawner ?? defaultIsolateSpawner(_wellenWorkerEntry);

  // Watchdog for the open call. Some malformed VCD files cause the wellen
  // Rust library to spin indefinitely; killing and re-spawning the isolate
  // after the deadline lets the UI recover gracefully. The deadline is a
  // hang detector, not a speed expectation — it scales with file size (see
  // [scaledOpenTimeout]) so large-but-valid files (multi-hundred-MB VCDs,
  // million-variable gate-level FSTs) are never killed mid-parse. A fixed
  // 5 s deadline used to reject an 18 MB / 1.3M-variable netlist that loads
  // fine in ~1 s on a fast machine but slower elsewhere.
  @visibleForTesting
  static const defaultOpenTimeout = Duration(seconds: 30);

  /// Deadline cap — even a multi-GB file is declared hung after this.
  @visibleForTesting
  static const maxOpenTimeout = Duration(minutes: 10);

  /// Watchdog deadline for opening a file of [sizeBytes]:
  /// 30 s base + 1 s per MB, capped at [maxOpenTimeout].
  @visibleForTesting
  static Duration scaledOpenTimeout(int sizeBytes) {
    final scaled = defaultOpenTimeout.inSeconds + sizeBytes ~/ (1024 * 1024);
    final capped = scaled > maxOpenTimeout.inSeconds
        ? maxOpenTimeout.inSeconds
        : scaled;
    return Duration(seconds: capped);
  }

  /// Explicit constructor override — used by tests to force a short deadline.
  /// When null, the deadline is size-scaled per [scaledOpenTimeout].
  final Duration? _openTimeoutOverride;
  final IsolateSpawner _spawner;

  /// Size-scaled deadline for [path]. Falls back to [defaultOpenTimeout]
  /// when the size cannot be read (vanished file, permission error) — the
  /// open call itself will then surface the real I/O failure.
  Duration _sizeScaledTimeoutFor(String path) {
    int sizeBytes;
    try {
      sizeBytes = File(path).lengthSync();
    } on Object {
      return defaultOpenTimeout;
    }
    return scaledOpenTimeout(sizeBytes);
  }

  WellenIsolateOrchestrator? _orchestrator;

  // Cached on main isolate after [openFile].
  List<Scope> _rootScopes = const [];
  List<Variable> _allVariables = const [];
  int _endTime = 0;
  Timescale? _timescale;
  String? _date;
  String? _version;
  String _fileFormatCache = 'Unknown';

  // Cached on main isolate after [loadSignal]: signalRef (int) → compact
  // change-list backed by typed arrays. See [CompactChanges].
  final _loadedSignals = <int, CompactChanges>{};

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  Future<void> openFile(String path) async {
    final orch = await _ensureOrchestrator();
    final timeout = _openTimeoutOverride ?? _sizeScaledTimeoutFor(path);
    final Map<String, dynamic> result;
    try {
      result = await orch.send(
        {'op': 'open', 'path': path},
        timeout: timeout,
      );
    } on TimeoutException {
      // The open call is stuck.  The orchestrator has already killed the
      // isolate; clear our local caches and surface a clear error.
      _resetCachedState();
      throw TimeoutException(
        'Opening "$path" timed out after ${timeout.inSeconds}s. '
        'The file may be malformed or use a format not supported by wellen.',
      );
    }
    if (!(result['ok'] as bool)) {
      // The isolate forwards wellen's own reason in `error`; surface it as a
      // typed exception whose toString() is the bare reason (no "Exception:"
      // prefix) so the viewer's error UI shows it cleanly under the title.
      throw WaveformOpenException(
        result['error'] as String? ?? 'Failed to open file',
      );
    }
    _rootScopes = (result['rootScopes'] as List).cast<Scope>();
    _allVariables = _flattenVariables(_rootScopes);
    _endTime = result['endTime'] as int;
    _timescale = result['timescale'] as Timescale?;
    _date = result['date'] as String?;
    _version = result['version'] as String?;
    _fileFormatCache = result['fileFormat'] as String? ?? 'Unknown';
    _loadedSignals.clear();
  }

  @override
  void close() {
    final orch = _orchestrator;
    if (orch != null && orch.isRunning) {
      // Best-effort: ask the worker to release the native handle before we
      // kill the isolate. In most cases the message will be processed in time.
      orch.sendOneWay({'op': 'close'});
    }
    _teardown();
  }

  // ── Hierarchy ───────────────────────────────────────────────────────────────

  @override
  List<Scope> get rootScopes => _rootScopes;

  @override
  List<Variable> findVariables(SignalFilter filter) {
    if (filter.matchesAll) return List.unmodifiable(_allVariables);
    return _allVariables.where(filter.matches).toList();
  }

  // ── Signal loading ─────────────────────────────────────────────────────────

  @override
  Future<void> loadSignal(String signalRef) async {
    final ref = int.tryParse(signalRef);
    if (ref == null) throw ArgumentError('Invalid signalRef: "$signalRef"');
    if (_loadedSignals.containsKey(ref)) return;

    // No file open yet — fail fast rather than spinning the worker up for a
    // request the worker will reject anyway. Matches the pre-refactor
    // behavior where _workerPort was still null at this point.
    final orch = _orchestrator;
    if (orch == null || !orch.isRunning) {
      throw StateError(
        'WellenProvider.loadSignal called before openFile (no file is open)',
      );
    }
    final result = await orch.send({'op': 'loadSignal', 'ref': ref});
    if (!(result['ok'] as bool)) {
      throw Exception(
        result['error'] as String? ?? 'Failed to load signal $signalRef',
      );
    }
    // Worker hands back three flat typed arrays in a fixed envelope. The
    // legacy `result['changes']` payload (List<SignalChange>) is still
    // accepted as a fallback so the injectLoadedSignal testing helper can
    // round-trip through this code path without a worker.
    final times = result['times'];
    if (times is Uint64List) {
      _loadedSignals[ref] = CompactChanges(
        times: times,
        valueOffsets: result['valueOffsets'] as Uint32List,
        valueBuf: result['valueBuf'] as Uint8List,
        xChangeIndex: result['xChangeIndex'] as Uint32List?,
      );
    } else {
      _loadedSignals[ref] = buildCompactFromList(
        (result['changes'] as List).cast<SignalChange>(),
      );
    }
  }

  @override
  bool isSignalLoaded(String signalRef) {
    final ref = int.tryParse(signalRef);
    if (ref == null) return false;
    return _loadedSignals.containsKey(ref);
  }

  @override
  Future<void> unloadSignal(String signalRef) async {
    final ref = int.tryParse(signalRef);
    if (ref == null) return;
    if (!_loadedSignals.containsKey(ref)) return;
    // Remove from the Dart-side cache first so value queries stop returning
    // data immediately, even if the isolate round-trip takes a moment.
    _loadedSignals.remove(ref);
    final orch = _orchestrator;
    if (orch == null || !orch.isRunning) return;
    // Release the decompressed signal data on the native side.
    await orch.send({'op': 'unloadSignal', 'ref': ref});
  }

  // ── Value queries (synchronous — operate on cached data) ───────────────────

  @override
  String? valueAt(String signalRef, int time) {
    final changes = _changesFor(signalRef);
    if (changes == null || changes.isEmpty) return null;
    final idx = changes.upperBoundLE(time);
    return idx >= 0 ? changes.valueAt(idx) : null;
  }

  @override
  List<SignalChange> changesInRange(String signalRef, int start, int end) {
    final changes = _changesFor(signalRef);
    if (changes == null || changes.isEmpty) return const [];
    final startIdx = changes.lowerBoundGE(start);
    // lowerBoundGE(end) gives the first index whose time >= end; we want
    // changes strictly before end, so this same value is the exclusive
    // upper bound.
    final endIdx = changes.lowerBoundGE(end);
    return changes.sliceToList(startIdx, endIdx);
  }

  @override
  SignalChange? nextTransition(String signalRef, int afterTime) {
    final changes = _changesFor(signalRef);
    if (changes == null || changes.isEmpty) return null;
    final idx = changes.lowerBoundGT(afterTime);
    if (idx >= changes.length) return null;
    return SignalChange(
      time: changes.timeAt(idx),
      value: changes.valueAt(idx),
    );
  }

  @override
  SignalChange? prevTransition(String signalRef, int beforeTime) {
    final changes = _changesFor(signalRef);
    if (changes == null || changes.isEmpty) return null;
    // upperBoundLE returns the last change with time <= time; we need < .
    // Convert by subtracting 1 from beforeTime.
    final idx = changes.upperBoundLE(beforeTime - 1);
    if (idx < 0) return null;
    return SignalChange(
      time: changes.timeAt(idx),
      value: changes.valueAt(idx),
    );
  }

  // ── Metadata ────────────────────────────────────────────────────────────────

  @override
  int get startTime => 0;

  @override
  int get endTime => _endTime;

  @override
  Timescale? get timescale => _timescale;

  @override
  String? get date => _date;

  @override
  String? get version => _version;

  // ── Diagnostics (FFI-backend–specific) ────────────────────────────────────

  /// File format of the loaded waveform: "VCD", "FST", "GHW", or "Unknown".
  ///
  /// Synchronous — cached during [openFile]. Not part of [WaveformDataSource];
  /// callers check `source is WellenProvider` before accessing this.
  String get fileFormat => _fileFormatCache;

  /// Total value changes across all CURRENTLY LOADED signals.
  ///
  /// Computed lazily by summing the cached per-signal change-list lengths.
  /// Returns 0 when no file is open or no signals have been loaded yet —
  /// File Info handles the 0 case by displaying "not available" so the
  /// counter naturally fills in as the user populates the viewer.
  ///
  /// Earlier builds reported the file-wide count, computed by
  /// load+count+unloading every signal at open time. For a 1500-signal /
  /// 15M-transition file that cost ~400 ms of the open path on a fast Mac;
  /// the trade-off favors instant open + an evolving counter over a "true
  /// total" that costs the user 4× open latency.
  int get totalTransitions {
    if (_loadedSignals.isEmpty) return 0;
    var sum = 0;
    for (final changes in _loadedSignals.values) {
      sum += changes.length;
    }
    return sum;
  }

  /// Number of value changes for [signalRef].
  ///
  /// Uses the locally cached change list — no isolate round-trip. Returns 0
  /// if the signal has not been loaded yet.
  int signalTransitionCount(String signalRef) {
    final ref = int.tryParse(signalRef);
    if (ref == null) return 0;
    return _loadedSignals[ref]?.length ?? 0;
  }

  /// Approximate memory usage of the native wellen handle, in bytes.
  ///
  /// Delegates to the background isolate. Returns an estimate — see the C
  /// header for the formula. Returns 0 if no file is open.
  Future<int> memoryUsageBytes() async {
    final orch = _orchestrator;
    if (orch == null || !orch.isRunning) return 0;
    final result = await orch.send({'op': 'memoryUsage'});
    return result['bytes'] as int? ?? 0;
  }

  // ── Testing helpers ─────────────────────────────────────────────────────────

  /// Injects signal changes directly into the cache without FFI.
  ///
  /// Only for unit testing the synchronous query logic.
  @visibleForTesting
  void injectLoadedSignal(String signalRef, List<SignalChange> changes) {
    final ref = int.tryParse(signalRef);
    if (ref == null) return;
    _loadedSignals[ref] = buildCompactFromList(changes);
  }

  /// Injects a hierarchy directly without FFI.
  ///
  /// Only for unit testing [findVariables].
  @visibleForTesting
  void injectHierarchy(List<Scope> scopes) {
    _rootScopes = scopes;
    _allVariables = _flattenVariables(scopes);
  }

  /// The packed store behind [valueAt] and [changesInRange], so a
  /// column-bounded query can read it in place ([CompactChangesSource]).
  @override
  CompactChanges? compactChangesFor(String signalRef) => _changesFor(signalRef);

  // ── Private helpers ─────────────────────────────────────────────────────────

  CompactChanges? _changesFor(String signalRef) {
    final ref = int.tryParse(signalRef);
    if (ref == null) return null;
    return _loadedSignals[ref];
  }

  Future<WellenIsolateOrchestrator> _ensureOrchestrator() async {
    final existing = _orchestrator;
    if (existing != null && existing.isRunning) return existing;
    final orch = existing ?? WellenIsolateOrchestrator(spawner: _spawner);
    _orchestrator = orch;
    try {
      await orch.start();
    } on WellenIsolateInitException catch (e) {
      // Surface the same exception type WellenProvider has always thrown.
      throw Exception(e.message);
    }
    return orch;
  }

  void _resetCachedState() {
    _rootScopes = const [];
    _allVariables = const [];
    _loadedSignals.clear();
    _endTime = 0;
    _timescale = null;
    _date = null;
    _version = null;
    _fileFormatCache = 'Unknown';
  }

  void _teardown() {
    _orchestrator?.dispose();
    _orchestrator = null;
    _resetCachedState();
  }
}

// ── Hierarchy flattening (main isolate) ───────────────────────────────────────

List<Variable> _flattenVariables(List<Scope> scopes) {
  final result = <Variable>[];
  void visit(Scope scope) {
    result.addAll(scope.variables);
    scope.childScopes.forEach(visit);
  }

  scopes.forEach(visit);
  return result;
}

// ── Worker isolate ─────────────────────────────────────────────────────────────
//
// Everything below runs exclusively in the background isolate. No Flutter
// imports are used here. The entry point must be a top-level function so
// Isolate.spawn can reference it.

/// Background isolate entry point.
void _wellenWorkerEntry(SendPort mainPort) {
  final WellenFfi wffi;
  try {
    wffi = WellenFfi(_openNativeLibrary());
  } on Object {
    // Cannot load library (ArgumentError from DynamicLibrary.open or similar).
    // Send null to signal failure; _ensureIsolate will completeError.
    mainPort.send(null);
    return;
  }

  final receivePort = ReceivePort();
  mainPort.send(receivePort.sendPort);

  ffi.Pointer<WellenHandle>? handle;
  var currentEndTime = 0;

  receivePort.listen((dynamic raw) {
    final msg = raw as Map<String, dynamic>;
    final id = msg['id'] as int;
    final op = msg['op'] as String;

    try {
      switch (op) {
        case 'open':
          if (handle != null && handle!.address != 0) {
            wffi.wellen_close(handle!);
            handle = null;
          }

          final path = (msg['path'] as String).toNativeUtf8();
          final newHandle = wffi.wellen_open(path.cast<ffi.Char>());
          malloc.free(path);

          if (newHandle.address == 0) {
            // Surface wellen's actual reason (e.g. a malformed-VCD message)
            // rather than a generic failure. The pointer is owned by the
            // native thread-local and valid until the next open — copy it,
            // do not free it. Empty means no detail was captured.
            final reason = wffi
                .wellen_last_open_error()
                .cast<Utf8>()
                .toDartString();
            mainPort.send({
              'id': id,
              'ok': false,
              'error': reason.isNotEmpty ? reason : 'Failed to open file',
            });
            break;
          }

          handle = newHandle;
          currentEndTime = wffi.wellen_time_end(handle!);

          final rootScopes = _buildRootScopes(wffi, handle!);
          final timescale = _readTimescale(wffi, handle!);
          final date = _readCString(wffi.wellen_date(handle!));
          final version = _readCString(wffi.wellen_version(handle!));

          final formatInt = wffi.wellen_file_format(handle!);
          mainPort.send({
            'id': id,
            'ok': true,
            'rootScopes': rootScopes,
            'endTime': currentEndTime,
            'timescale': timescale,
            'date': date,
            'version': version,
            'fileFormat': _formatIntToString(formatInt),
          });

        case 'loadSignal':
          final h = handle;
          if (h == null || h.address == 0) {
            mainPort.send({'id': id, 'ok': false, 'error': 'No file open'});
            break;
          }
          final signalRef = msg['ref'] as int;
          final rc = wffi.wellen_load_signal(h, signalRef);
          if (rc != 0) {
            final errMsg =
                _readCString(wffi.wellen_last_error(h)) ?? 'load failed';
            mainPort.send({'id': id, 'ok': false, 'error': errMsg});
            break;
          }
          final payload = _fetchAllChanges(wffi, h, signalRef, currentEndTime);
          mainPort.send({
            'id': id,
            'ok': true,
            'times': payload.times,
            'valueOffsets': payload.valueOffsets,
            'valueBuf': payload.valueBuf,
            'xChangeIndex': payload.xChangeIndex,
          });

        case 'unloadSignal':
          final h = handle;
          if (h != null && h.address != 0) {
            wffi.wellen_unload_signal(h, msg['ref'] as int);
          }
          mainPort.send({'id': id, 'ok': true});

        case 'totalTransitions':
          final h = handle;
          if (h == null || h.address == 0) {
            mainPort.send({'id': id, 'count': 0});
            break;
          }
          mainPort.send({
            'id': id,
            'count': wffi.wellen_total_transition_count(h),
          });

        case 'memoryUsage':
          final h = handle;
          if (h == null || h.address == 0) {
            mainPort.send({'id': id, 'bytes': 0});
            break;
          }
          mainPort.send({
            'id': id,
            'bytes': wffi.wellen_memory_usage_bytes(h),
          });

        case 'close':
          final h = handle;
          if (h != null && h.address != 0) {
            wffi.wellen_close(h);
            handle = null;
          }
          mainPort.send({'id': id, 'ok': true});
          receivePort.close();

        default:
          mainPort.send({'id': id, 'ok': false, 'error': 'Unknown op: $op'});
      }
    } on Object catch (e) {
      mainPort.send({'id': id, 'ok': false, 'error': e.toString()});
    }
  });
}

// ── Native library loading ─────────────────────────────────────────────────────

/// Resolves and opens the wellen native library: the bundled library by bare
/// name in a built app, `native/wellen_ffi/target/{release,debug}/` under
/// `flutter test`, and the process image on iOS. The probe order lives in
/// `openWellenFfiLibrary` (`lib/native/wellen_ffi_library_io.dart`), shared
/// with the LXT/LXT2 converter, whose C ABI ships in the same library.
ffi.DynamicLibrary _openNativeLibrary() => openWellenFfiLibrary();

// ── Hierarchy construction (worker) ──────────────────────────────────────────

List<Scope> _buildRootScopes(
  WellenFfi wffi,
  ffi.Pointer<WellenHandle> handle,
) {
  final totalScopes = wffi.wellen_num_scopes(handle);
  final totalVars = wffi.wellen_num_vars(handle);

  if (totalScopes == 0) {
    // No named scopes — check for root-level vars.
    return _buildRootLevelVarScope(wffi, handle, totalVars);
  }

  return using((arena) {
    // One pair of worst-case index buffers shared across the entire walk.
    // Allocating these per scope is quadratic in design size: a gate-level
    // netlist with 142k scopes / 1.3M vars would otherwise calloc (and zero)
    // a totalVars-sized buffer 142k times — ~6.4 s of pure allocator traffic
    // for a file wellen itself parses in under 200 ms. Sharing is safe
    // because every fill is copied into a Dart list before the walk recurses.
    final scopeBuf = arena<ffi.Uint64>(totalScopes);
    final varBuf = arena<ffi.Uint64>(totalVars == 0 ? 1 : totalVars);
    final count = wffi.wellen_root_scopes(handle, scopeBuf, totalScopes);
    if (count <= 0) return const <Scope>[];
    // Copy the root indices out before recursing — _buildScope reuses
    // scopeBuf for its own child queries.
    final rootIndices = List<int>.generate(count, (i) => scopeBuf[i]);
    return [
      for (final idx in rootIndices)
        _buildScope(
          wffi,
          handle,
          idx,
          '',
          scopeBuf,
          totalScopes,
          varBuf,
          totalVars,
        ),
    ];
  });
}

/// Handles the rare case of variables declared at the top level with no scope.
List<Scope> _buildRootLevelVarScope(
  WellenFfi wffi,
  ffi.Pointer<WellenHandle> handle,
  int totalVars,
) {
  if (totalVars == 0) return const [];
  return using((arena) {
    final buf = arena<ffi.Uint64>(totalVars);
    final count = wffi.wellen_root_vars(handle, buf, totalVars);
    if (count <= 0) return const <Scope>[];
    final vars = List.generate(
      count,
      (i) => _buildVariable(wffi, handle, buf[i], ''),
    );
    return [
      Scope(name: '', type: ScopeType.module, path: '', variables: vars),
    ];
  });
}

/// Builds one [Scope] subtree. [scopeBuf] / [varBuf] are the walk-wide
/// scratch index buffers allocated once in [_buildRootScopes] — each fill
/// below is copied into a Dart list before recursing, so reuse is safe.
Scope _buildScope(
  WellenFfi wffi,
  ffi.Pointer<WellenHandle> handle,
  int idx,
  String parentPath,
  ffi.Pointer<ffi.Uint64> scopeBuf,
  int totalScopes,
  ffi.Pointer<ffi.Uint64> varBuf,
  int totalVars,
) {
  final namePtr = wffi.wellen_scope_name(handle, idx);
  final name = namePtr.address != 0
      ? namePtr.cast<Utf8>().toDartString()
      : '<scope$idx>';
  final scopeTypeInt = wffi.wellen_scope_type(handle, idx);
  final path = parentPath.isEmpty ? name : '$parentPath.$name';

  final scopeCount = wffi.wellen_scope_child_scopes(
    handle,
    idx,
    scopeBuf,
    totalScopes,
  );
  final childScopeIndices = scopeCount <= 0
      ? const <int>[]
      : List<int>.generate(scopeCount, (i) => scopeBuf[i]);

  final varCount = totalVars == 0
      ? 0
      : wffi.wellen_scope_child_vars(handle, idx, varBuf, totalVars);
  final childVarIndices = varCount <= 0
      ? const <int>[]
      : List<int>.generate(varCount, (i) => varBuf[i]);

  return Scope(
    name: name,
    type: _toScopeType(scopeTypeInt),
    path: path,
    childScopes: [
      for (final ci in childScopeIndices)
        _buildScope(
          wffi,
          handle,
          ci,
          path,
          scopeBuf,
          totalScopes,
          varBuf,
          totalVars,
        ),
    ],
    variables: [
      for (final vi in childVarIndices) _buildVariable(wffi, handle, vi, path),
    ],
  );
}

Variable _buildVariable(
  WellenFfi wffi,
  ffi.Pointer<WellenHandle> handle,
  int idx,
  String scopePath,
) {
  final namePtr = wffi.wellen_var_name(handle, idx);
  final name = namePtr.address != 0
      ? namePtr.cast<Utf8>().toDartString()
      : '<var$idx>';
  final varTypeInt = wffi.wellen_var_type(handle, idx);
  final dirInt = wffi.wellen_var_direction(handle, idx);
  final length = wffi.wellen_var_length(handle, idx);
  final signalRef = wffi.wellen_var_signal_ref(handle, idx);

  return Variable(
    name: name,
    varType: _toVarType(varTypeInt),
    direction: _toVarDirection(dirInt),
    // Signal refs from wellen are opaque u32 values; stringify for the interface.
    signalRef: signalRef.toString(),
    scopePath: scopePath,
    bitWidth: length > 0 ? length : null,
  );
}

// ── Signal data fetching (worker) ─────────────────────────────────────────────

/// Three flat typed arrays describing a signal's change list, plus the index
/// of its changes that carry an unknown bit. Built in the worker isolate,
/// copied over [SendPort], and wrapped in [CompactChanges] on the main
/// isolate. Building the `x` index here keeps that O(bytes) scan off the UI
/// isolate; see [CompactChanges.xChangeIndex].
class CompactChangesPayload {
  CompactChangesPayload({
    required this.times,
    required this.valueOffsets,
    required this.valueBuf,
    required this.xChangeIndex,
  });
  final Uint64List times;
  final Uint32List valueOffsets;
  final Uint8List valueBuf;
  final Uint32List xChangeIndex;
}

/// Fetches all value changes for [signalRef] by calling [wellen_signal_changes]
/// with growing buffers until the output fits. Returns the change-list in
/// the compact typed-array layout expected by [CompactChanges].
///
/// The wellen FFI emits values back-to-back into a byte buffer with a null
/// terminator per entry, and an offsets array pointing at each value's start.
/// The compact layout drops the null terminators and stores an `n+1`-long
/// offsets array (sentinel = total bytes), making valueAt(idx) a simple
/// range read against the buffer.
CompactChangesPayload _fetchAllChanges(
  WellenFfi wffi,
  ffi.Pointer<WellenHandle> handle,
  int signalRef,
  int endTime,
) {
  // Use endTime + 1 so we include any change at exactly endTime.
  final queryEnd = endTime == 0 ? 1 : endTime + 1;

  var maxCount = 1024;
  var valueBufLen = maxCount * 20; // ~20 bytes per value string is generous

  while (true) {
    final result = using<CompactChangesPayload?>((arena) {
      final timesBuf = arena<ffi.Uint64>(maxCount);
      final valueBuf = arena<ffi.Uint8>(valueBufLen);
      final offsetsBuf = arena<ffi.Uint32>(maxCount);

      final count = wffi.wellen_signal_changes(
        handle,
        signalRef,
        0,
        queryEnd,
        timesBuf,
        valueBuf,
        valueBufLen,
        offsetsBuf,
        maxCount,
      );

      if (count == -2) return null; // Buffers too small — retry.
      if (count <= 0) {
        return CompactChangesPayload(
          times: Uint64List(0),
          valueOffsets: Uint32List(1),
          valueBuf: Uint8List(0),
          xChangeIndex: Uint32List(0),
        );
      }

      // Bulk-copy the times from the native buffer to a Dart-owned
      // Uint64List. asTypedList() returns a view; the explicit Uint64List
      // copy is necessary because the native arena is freed by `using`.
      final timesView = timesBuf.cast<ffi.Uint64>().asTypedList(count);
      final times = Uint64List(count)..setRange(0, count, timesView);

      // Walk the native offsets + value buffer to (a) compute per-entry
      // lengths (using the null-terminator), and (b) build a compact
      // sentinel-terminated offsets array. The null terminators are
      // dropped from the compact payload.
      final nativeOffsets = offsetsBuf.cast<ffi.Uint32>().asTypedList(count);
      final nativeValueBuf = valueBuf.cast<ffi.Uint8>().asTypedList(
        valueBufLen,
      );
      final lengths = Uint32List(count);
      var totalBytes = 0;
      for (var i = 0; i < count; i++) {
        final start = nativeOffsets[i];
        var p = start;
        while (p < valueBufLen && nativeValueBuf[p] != 0) {
          p++;
        }
        lengths[i] = p - start;
        totalBytes += p - start;
      }

      final compactOffsets = Uint32List(count + 1);
      final compactValueBuf = Uint8List(totalBytes);
      var dst = 0;
      for (var i = 0; i < count; i++) {
        compactOffsets[i] = dst;
        final start = nativeOffsets[i];
        final len = lengths[i];
        if (len > 0) {
          compactValueBuf.setRange(dst, dst + len, nativeValueBuf, start);
        }
        dst += len;
      }
      compactOffsets[count] = dst;

      return CompactChangesPayload(
        times: times,
        valueOffsets: compactOffsets,
        valueBuf: compactValueBuf,
        xChangeIndex: buildXChangeIndex(compactOffsets, compactValueBuf),
      );
    });

    if (result != null) return result;
    // Double both buffers and retry.
    maxCount *= 2;
    valueBufLen *= 2;
  }
}

String _formatIntToString(int fmt) => switch (fmt) {
  WELLEN_FORMAT_VCD => 'VCD',
  WELLEN_FORMAT_FST => 'FST',
  WELLEN_FORMAT_GHW => 'GHW',
  _ => 'Unknown',
};

// ── Metadata helpers (worker) ─────────────────────────────────────────────────

Timescale? _readTimescale(
  WellenFfi wffi,
  ffi.Pointer<WellenHandle> handle,
) {
  return using((arena) {
    final factorPtr = arena<ffi.Uint32>();
    final expPtr = arena<ffi.Int32>();
    final present = wffi.wellen_get_timescale(handle, factorPtr, expPtr);
    if (present == 0) return null;
    return Timescale(
      factor: factorPtr.value,
      unit: _expToTimescaleUnit(expPtr.value),
    );
  });
}

String? _readCString(ffi.Pointer<ffi.Char> ptr) {
  if (ptr.address == 0) return null;
  final s = ptr.cast<Utf8>().toDartString();
  return s.isEmpty ? null : s;
}

// ── Enum converters (worker) ──────────────────────────────────────────────────

ScopeType _toScopeType(int v) => switch (v) {
  WELLEN_SCOPE_MODULE => ScopeType.module,
  WELLEN_SCOPE_TASK => ScopeType.task,
  WELLEN_SCOPE_FUNCTION => ScopeType.function,
  WELLEN_SCOPE_BEGIN => ScopeType.begin,
  WELLEN_SCOPE_FORK => ScopeType.fork,
  WELLEN_SCOPE_GENERATE => ScopeType.generate,
  WELLEN_SCOPE_STRUCT => ScopeType.struct,
  WELLEN_SCOPE_UNION => ScopeType.union,
  WELLEN_SCOPE_CLASS => ScopeType.svClass,
  WELLEN_SCOPE_INTERFACE => ScopeType.svInterface,
  WELLEN_SCOPE_PACKAGE => ScopeType.svPackage,
  WELLEN_SCOPE_PROGRAM => ScopeType.svProgram,
  WELLEN_SCOPE_VHDL_ARCH => ScopeType.vhdlArchitecture,
  WELLEN_SCOPE_VHDL_PROC => ScopeType.vhdlProcedure,
  WELLEN_SCOPE_VHDL_FUNC => ScopeType.vhdlFunction,
  WELLEN_SCOPE_VHDL_RECORD => ScopeType.vhdlRecord,
  WELLEN_SCOPE_VHDL_PROCESS => ScopeType.vhdlProcess,
  WELLEN_SCOPE_VHDL_BLOCK => ScopeType.vhdlBlock,
  WELLEN_SCOPE_VHDL_FOR_GEN => ScopeType.vhdlForGenerate,
  WELLEN_SCOPE_VHDL_IF_GEN => ScopeType.vhdlIfGenerate,
  WELLEN_SCOPE_VHDL_GEN => ScopeType.vhdlGenerate,
  WELLEN_SCOPE_VHDL_PKG => ScopeType.vhdlPackage,
  WELLEN_SCOPE_GHW_GENERIC => ScopeType.ghwGeneric,
  WELLEN_SCOPE_VHDL_ARRAY => ScopeType.vhdlArray,
  _ => ScopeType.module,
};

VarType _toVarType(int v) => switch (v) {
  WELLEN_VAR_EVENT => VarType.event,
  WELLEN_VAR_INTEGER => VarType.integer,
  WELLEN_VAR_PARAMETER => VarType.parameter,
  WELLEN_VAR_REAL => VarType.real,
  WELLEN_VAR_REG => VarType.reg,
  WELLEN_VAR_SUPPLY0 => VarType.supply0,
  WELLEN_VAR_SUPPLY1 => VarType.supply1,
  WELLEN_VAR_TIME => VarType.time,
  WELLEN_VAR_TRI => VarType.tri,
  WELLEN_VAR_TRIAND => VarType.triAnd,
  WELLEN_VAR_TRIOR => VarType.triOr,
  WELLEN_VAR_TRIREG => VarType.triReg,
  WELLEN_VAR_TRI0 => VarType.tri0,
  WELLEN_VAR_TRI1 => VarType.tri1,
  WELLEN_VAR_WAND => VarType.wAnd,
  WELLEN_VAR_WIRE => VarType.wire,
  WELLEN_VAR_WOR => VarType.wOr,
  WELLEN_VAR_STRING => VarType.string,
  WELLEN_VAR_PORT => VarType.port,
  WELLEN_VAR_SPARSE_ARRAY => VarType.sparseArray,
  WELLEN_VAR_REAL_TIME => VarType.realTime,
  WELLEN_VAR_BIT => VarType.bit,
  WELLEN_VAR_LOGIC => VarType.logic,
  WELLEN_VAR_INT => VarType.svInt,
  WELLEN_VAR_SHORT_INT => VarType.svShortInt,
  WELLEN_VAR_LONG_INT => VarType.svLongInt,
  WELLEN_VAR_BYTE => VarType.svByte,
  WELLEN_VAR_ENUM => VarType.svEnum,
  WELLEN_VAR_SHORT_REAL => VarType.svShortReal,
  WELLEN_VAR_BOOLEAN => VarType.boolean,
  WELLEN_VAR_BIT_VECTOR => VarType.bitVector,
  WELLEN_VAR_STD_LOGIC => VarType.stdLogic,
  WELLEN_VAR_STD_LOGIC_VEC => VarType.stdLogicVector,
  WELLEN_VAR_STD_ULOGIC => VarType.stdULogic,
  WELLEN_VAR_STD_ULOGIC_VEC => VarType.stdULogicVector,
  WELLEN_VAR_REAL_PARAMETER => VarType.realParameter,
  WELLEN_VAR_EVENT_PARAMETER => VarType.eventParameter,
  _ => VarType.wire,
};

VarDirection _toVarDirection(int v) => switch (v) {
  WELLEN_DIR_UNKNOWN => VarDirection.unknown,
  WELLEN_DIR_IMPLICIT => VarDirection.implicit,
  WELLEN_DIR_INPUT => VarDirection.input,
  WELLEN_DIR_OUTPUT => VarDirection.output,
  WELLEN_DIR_INOUT => VarDirection.inout,
  WELLEN_DIR_BUFFER => VarDirection.buffer,
  WELLEN_DIR_LINKAGE => VarDirection.linkage,
  _ => VarDirection.unknown,
};

TimescaleUnit _expToTimescaleUnit(int exp) => switch (exp) {
  -15 => TimescaleUnit.femtoSeconds,
  -12 => TimescaleUnit.picoSeconds,
  -9 => TimescaleUnit.nanoSeconds,
  -6 => TimescaleUnit.microSeconds,
  -3 => TimescaleUnit.milliSeconds,
  0 => TimescaleUnit.seconds,
  _ => TimescaleUnit.unknown,
};
