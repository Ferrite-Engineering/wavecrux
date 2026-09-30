// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// WellenWasmProvider — WaveformDataSource backed by the wellen Rust library
// compiled to WebAssembly.
//
// On Flutter Web `dart:ffi` is unavailable, so the desktop/mobile FFI bridge
// cannot run. This WASM-backed provider gives the web build the same
// VCD/FST/GHW parsing surface as the native builds.
//
// Single-threaded only — browser WASM threading (SharedArrayBuffer + COOP/COEP
// deployment headers) is deliberately not used. The mainline wellen
// parser is fast enough single-threaded that this is an acceptable trade-off.
//
// The Rust crate lives in `native/wellen_wasm/`; the compiled artefacts
// (`wellen_wasm.js` + `wellen_wasm_bg.wasm`) are emitted into `web/wasm/`
// during the build and shipped as static assets alongside `main.dart.js`.

import 'dart:js_interop';
import 'dart:typed_data';

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
import 'package:wavecrux/services/waveform/compact_changes.dart';
import 'package:wavecrux/services/waveform/display_changes.dart';

// ── JS interop shape ──────────────────────────────────────────────────────────
//
// `web/wasm/wellen_wasm_loader.js` (a hand-written shim) imports the
// wasm-bindgen ES module and exposes the API on `globalThis.waveCruxWellen`
// as a plain object with the methods used below. The shim is necessary
// because Dart's `dart:js_interop` cannot directly import an ES module at
// runtime; the shim wraps the dynamic import and republishes the result.
//
// All numeric values are `double` (JS Number) — simulation times and
// transition counts fit comfortably in 53 bits of precision. The Rust crate
// returns f64 for everything that would otherwise have been a u64.

@JS('waveCruxWellen')
external _WellenLoader? get _waveCruxWellen;

extension type _WellenLoader._(JSObject _) implements JSObject {
  /// Returns a Promise that resolves to `null` on success and to an error
  /// when the wasm module fails to load.
  external JSPromise<JSAny?> ensureReady();

  /// Construct a new handle by parsing `bytes` as a `filename`-format file.
  /// Returns a JSObject (the WellenWasm handle) or throws on parse error.
  external _WellenHandle createWaveform(JSString filename, JSUint8Array bytes);

  /// ABI version exposed by the loaded module. Bumping the constant in the
  /// Rust crate signals a breaking change; the Dart side rejects mismatches.
  external int abiVersion();
}

/// Minimal view of a thrown JS `Error` so we can read its `message` — the
/// parser's reason that `createWaveform` raises on a malformed file (Rust:
/// `simple::read(...).map_err(into_js_err)` → `JsError::new("{e}")`).
extension type _JsThrownError._(JSObject _) implements JSObject {
  external JSString? get message;
}

/// Extracts the parser's reason from the JS error `createWaveform` throws.
/// Reads `message` when the thrown value is a JS error object; otherwise
/// falls back to a string description.
String _jsOpenErrorReason(Object error) {
  try {
    final message = (error as _JsThrownError).message?.toDart;
    if (message != null && message.trim().isNotEmpty) return message;
  } on Object catch (_) {
    // Not a JS error object — fall through to a string description.
  }
  return error.toString();
}

extension type _WellenHandle._(JSObject _) implements JSObject {
  external void free();
  external int fileFormat();
  external double timeEnd();
  external JSString date();
  external JSString version();
  external _TimescaleResult? timescale();
  external int numScopes();
  external int numVars();
  external JSUint32Array rootScopes();
  external JSUint32Array rootVars();
  external JSString scopeName(int scopeIdx);
  external int scopeType(int scopeIdx);
  external JSUint32Array scopeChildScopes(int scopeIdx);
  external JSUint32Array scopeChildVars(int scopeIdx);
  external JSString varName(int varIdx);
  external int varType(int varIdx);
  external int varDirection(int varIdx);
  external int varLength(int varIdx);
  external int varSignalRef(int varIdx);
  external double loadSignal(int signalRef);
  external void unloadSignal(int signalRef);
  external JSString valueAt(int signalRef, double time);
  external _SignalChangesResult? signalChanges(
    int signalRef,
    double start,
    double end,
  );
  external _TransitionResult? nextTransition(int signalRef, double afterTime);
  external _TransitionResult? prevTransition(int signalRef, double beforeTime);
  external double totalTransitionCount();
  external double signalTransitionCount(int signalRef);
  external double memoryUsageBytes();
}

extension type _TimescaleResult._(JSObject _) implements JSObject {
  external double get factor;
  external double get unitExp;
}

extension type _SignalChangesResult._(JSObject _) implements JSObject {
  external JSFloat64Array get times;
  external JSArray<JSString> get values;
}

extension type _TransitionResult._(JSObject _) implements JSObject {
  external double get time;
  external JSString get value;
}

// ── Public implementation ──────────────────────────────────────────────────────

/// [WaveformDataSource] backed by the wellen Rust library compiled to
/// WebAssembly. Used on Flutter Web where `dart:ffi` is unavailable.
///
/// File contents come as a [Uint8List] (browser File API, drag-and-drop, or
/// `fetch()`). Signal data is decompressed lazily — call [loadSignal] before
/// querying values. Each loaded signal's change list is materialized once on
/// the JS side, copied to Dart-side storage, and queried locally so the hot
/// path never crosses the JS/wasm boundary.
class WellenWasmProvider implements WaveformDataSource, CompactChangesSource {
  WellenWasmProvider();

  /// ABI version we built against. Bumping in the Rust crate must accompany a
  /// bump here; the assertion in [openBytes] catches mismatches loudly.
  @visibleForTesting
  static const int expectedAbiVersion = 1;

  static Future<void>? _initFuture;
  static Object? _loadError;

  _WellenHandle? _handle;

  // Cached on construction; cleared on close.
  List<Scope> _rootScopes = const [];
  List<Variable> _allVariables = const [];
  int _endTime = 0;
  Timescale? _timescale;
  String? _date;
  String? _version;
  String _fileFormatCache = 'Unknown';

  // signalRef (int) → sorted changes in compact typed-array form.
  // Populated by [loadSignal]. See [CompactChanges] for the layout
  // rationale; the wasm side carries the same ~5× memory shrink the
  // FFI side does for the same data.
  final Map<int, CompactChanges> _loadedSignals = {};

  /// Idempotently load the WebAssembly module.
  ///
  /// Safe to call from any code that may run on web before any file open —
  /// the first call kicks off the load, subsequent calls await the same
  /// future. On non-web hosts the stub implementation no-ops.
  static Future<void> ensureInitialized() {
    return _initFuture ??= _doInitialize();
  }

  /// Whether the underlying WebAssembly module has loaded successfully.
  ///
  /// Returns `false` until [ensureInitialized] has completed at least once
  /// and after a load failure. Synchronous so UI code can branch on it
  /// without awaiting; [loadError] records the failure reason.
  static bool get isAvailable {
    final loader = _waveCruxWellen;
    return loader != null && _loadError == null;
  }

  /// Last error from [ensureInitialized], or `null` if the module loaded
  /// successfully (or hasn't been asked to load yet).
  static Object? get loadError => _loadError;

  static Future<void> _doInitialize() async {
    final loader = _waveCruxWellen;
    if (loader == null) {
      final err = StateError(
        'WellenWasm loader (web/wasm/wellen_wasm_loader.js) is not present '
        'on globalThis. The wasm build step did not run, or the loader '
        'script is not included from web/index.html.',
      );
      _loadError = err;
      throw err;
    }
    try {
      final result = await loader.ensureReady().toDart;
      if (result != null) {
        final err = StateError('WellenWasm load returned error: $result');
        _loadError = err;
        throw err;
      }
      // Verify ABI version. Mismatch means the bundled wasm is from a
      // different build than the Dart wrapper — fail fast rather than
      // silently misinterpret return values.
      final actual = loader.abiVersion();
      if (actual != expectedAbiVersion) {
        final err = StateError(
          'WellenWasm ABI version mismatch: expected $expectedAbiVersion, '
          'got $actual. Rebuild the wasm crate with `wasm-pack build` and '
          'redeploy.',
        );
        _loadError = err;
        throw err;
      }
    } on Object catch (e) {
      _loadError = e;
      rethrow;
    }
  }

  /// Force-resets internal init state. Test-only.
  @visibleForTesting
  static void resetInitForTests() {
    _initFuture = null;
    _loadError = null;
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Open a waveform from raw [bytes].
  ///
  /// [displayName] is used for extension-based format detection (the path is
  /// never available on web). The byte buffer is copied into WASM linear
  /// memory; the Dart-side wrapper holds the resulting handle.
  Future<void> openBytes(Uint8List bytes, String displayName) async {
    await ensureInitialized();
    final loader = _waveCruxWellen;
    if (loader == null) {
      throw StateError('WellenWasm loader unavailable');
    }
    final _WellenHandle handle;
    try {
      handle = loader.createWaveform(displayName.toJS, bytes.toJS);
    } on Object catch (e) {
      // createWaveform throws a JS Error carrying wellen's reason on a parse
      // failure. Surface it as the same typed exception the FFI path uses so
      // the viewer shows the real reason (e.g. "expected an id for a value
      // change") rather than a generic message.
      throw WaveformOpenException(_jsOpenErrorReason(e));
    }
    _handle = handle;

    _endTime = handle.timeEnd().toInt();
    final dateStr = handle.date().toDart;
    _date = dateStr.isEmpty ? null : dateStr;
    final versionStr = handle.version().toDart;
    _version = versionStr.isEmpty ? null : versionStr;
    _fileFormatCache = _formatIntToString(handle.fileFormat());
    _timescale = _readTimescale(handle);

    _rootScopes = _buildRootScopes(handle);
    _allVariables = _flattenVariables(_rootScopes);
    // The file-wide transition total is derived lazily from
    // _loadedSignals at query time. Earlier builds load+counted+
    // unloaded every signal here so the File Info panel could show a
    // single up-front number; on a 1500-signal file that cost ~400 ms of
    // the open path (the diagnostics call dominated the whole open
    // budget). The File Info UI already handles a "0 → not available"
    // state for an unwarmed session, so deferring is a free win.
  }

  /// File-system path open is not supported on web — call [openBytes] with
  /// the result of a browser file picker or `fetch()` instead.
  @override
  Future<void> openFile(String path) {
    throw UnsupportedError(
      'WellenWasmProvider.openFile is not supported on web; use openBytes '
      'with bytes from the browser file picker or fetch().',
    );
  }

  @override
  void close() {
    _handle?.free();
    _handle = null;
    _rootScopes = const [];
    _allVariables = const [];
    _loadedSignals.clear();
    _endTime = 0;
    _timescale = null;
    _date = null;
    _version = null;
    _fileFormatCache = 'Unknown';
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
    final h = _handle;
    if (h == null) {
      throw StateError('No file open');
    }
    h.loadSignal(ref);
    // Fetch every change for this signal in one round-trip. WASM runs on
    // the same event loop as the caller, so this is a synchronous JS
    // round-trip rather than a SendPort-style copy.
    final queryEnd = _endTime == 0 ? 1.0 : (_endTime + 1).toDouble();
    final raw = h.signalChanges(ref, 0, queryEnd);
    _loadedSignals[ref] = _readCompactChanges(raw);
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
    _loadedSignals.remove(ref);
    _handle?.unloadSignal(ref);
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

  // ── Diagnostics (mirrors WellenProvider) ────────────────────────────────────

  String get fileFormat => _fileFormatCache;

  /// Total value changes across all currently loaded signals — computed
  /// lazily by summing the cached per-signal change-list lengths. See the
  /// matching getter on `WellenProvider` (FFI side) for the rationale: the
  /// eager file-open count cost ~400 ms on a 1500-signal capture, and the
  /// File Info UI already treats 0 as "not available."
  int get totalTransitions {
    if (_loadedSignals.isEmpty) return 0;
    var sum = 0;
    for (final changes in _loadedSignals.values) {
      sum += changes.length;
    }
    return sum;
  }

  int signalTransitionCount(String signalRef) {
    final ref = int.tryParse(signalRef);
    if (ref == null) return 0;
    return _loadedSignals[ref]?.length ?? 0;
  }

  Future<int> memoryUsageBytes() async =>
      _handle?.memoryUsageBytes().toInt() ?? 0;

  // ── Testing helpers ─────────────────────────────────────────────────────────

  @visibleForTesting
  void injectLoadedSignal(String signalRef, List<SignalChange> changes) {
    final ref = int.tryParse(signalRef);
    if (ref == null) return;
    _loadedSignals[ref] = buildCompactFromList(changes);
  }

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

  List<Scope> _buildRootScopes(_WellenHandle h) {
    final totalScopes = h.numScopes();
    final totalVars = h.numVars();
    if (totalScopes == 0) {
      return _buildRootLevelVarScope(h, totalVars);
    }
    final rootIndices = h.rootScopes().toDart;
    return List<Scope>.generate(
      rootIndices.length,
      (i) => _buildScope(h, rootIndices[i], ''),
    );
  }

  List<Scope> _buildRootLevelVarScope(_WellenHandle h, int totalVars) {
    if (totalVars == 0) return const [];
    final indices = h.rootVars().toDart;
    if (indices.isEmpty) return const [];
    final vars = indices.map((idx) => _buildVariable(h, idx, '')).toList();
    return [
      Scope(name: '', type: ScopeType.module, path: '', variables: vars),
    ];
  }

  Scope _buildScope(_WellenHandle h, int idx, String parentPath) {
    final name = h.scopeName(idx).toDart;
    final displayName = name.isEmpty ? '<scope$idx>' : name;
    final typeInt = h.scopeType(idx);
    final path = parentPath.isEmpty ? displayName : '$parentPath.$displayName';
    final childScopeIndices = h.scopeChildScopes(idx).toDart;
    final childVarIndices = h.scopeChildVars(idx).toDart;
    return Scope(
      name: displayName,
      type: _toScopeType(typeInt),
      path: path,
      childScopes: childScopeIndices
          .map((ci) => _buildScope(h, ci, path))
          .toList(),
      variables: childVarIndices
          .map((vi) => _buildVariable(h, vi, path))
          .toList(),
    );
  }

  Variable _buildVariable(_WellenHandle h, int idx, String scopePath) {
    final name = h.varName(idx).toDart;
    final displayName = name.isEmpty ? '<var$idx>' : name;
    final typeInt = h.varType(idx);
    final dirInt = h.varDirection(idx);
    final length = h.varLength(idx);
    final signalRef = h.varSignalRef(idx);
    return Variable(
      name: displayName,
      varType: _toVarType(typeInt),
      direction: _toVarDirection(dirInt),
      signalRef: signalRef.toString(),
      scopePath: scopePath,
      bitWidth: length > 0 ? length : null,
    );
  }

  Timescale? _readTimescale(_WellenHandle h) {
    final ts = h.timescale();
    if (ts == null) return null;
    return Timescale(
      factor: ts.factor.toInt(),
      unit: _expToTimescaleUnit(ts.unitExp.toInt()),
    );
  }

  /// Reads the JS-interop `_SignalChangesResult` into a [CompactChanges].
  ///
  /// The JS side returns two parallel JS arrays — a `Float64Array` of
  /// times and a `JSArray<JSString>` of value strings. We convert times
  /// to a plain `List<int>` (wellen times are integral ticks; the Float64
  /// envelope is just the JS-bridge format — and a `Uint64List` would throw
  /// `UnsupportedError` on the web) and concatenate the value strings into a
  /// flat `Uint8List` with sentinel-terminated offsets, matching the FFI
  /// provider's layout. Value strings are
  /// guaranteed ASCII by wellen for every supported source format, so
  /// the codeUnit copy never produces invalid bytes.
  CompactChanges _readCompactChanges(_SignalChangesResult? raw) {
    if (raw == null) return CompactChanges.empty;
    final timesJs = raw.times.toDart;
    final valuesJs = raw.values.toDart;
    if (timesJs.length != valuesJs.length) {
      throw StateError(
        'WellenWasm signalChanges returned mismatched arrays: '
        'times=${timesJs.length} values=${valuesJs.length}',
      );
    }
    final n = timesJs.length;
    if (n == 0) return CompactChanges.empty;

    // Plain List<int>, NOT Uint64List: 64-bit typed arrays throw
    // `UnsupportedError` on the web (JS has no 64-bit integers). Building a
    // Uint64List here is what left every signal lane empty — the throw was
    // swallowed by the canvas paint's loadSignal call. See CompactChanges.times.
    final times = List<int>.filled(n, 0);
    final offsets = Uint32List(n + 1);
    // First pass: per-entry codeUnit lengths so we can size valueBuf
    // exactly. JSString.toDart is the moment we cross the bridge, so we
    // do it once per entry and keep the Dart string around for the
    // copy pass.
    final dartValues = List<String>.filled(n, '');
    var total = 0;
    for (var i = 0; i < n; i++) {
      final s = valuesJs[i].toDart;
      dartValues[i] = s;
      total += s.length;
    }
    final valueBuf = Uint8List(total);
    var cursor = 0;
    for (var i = 0; i < n; i++) {
      times[i] = timesJs[i].toInt();
      offsets[i] = cursor;
      final s = dartValues[i];
      for (var c = 0; c < s.length; c++) {
        valueBuf[cursor + c] = s.codeUnitAt(c);
      }
      cursor += s.length;
    }
    offsets[n] = cursor;
    return CompactChanges(
      times: times,
      valueOffsets: offsets,
      valueBuf: valueBuf,
    );
  }

  static List<Variable> _flattenVariables(List<Scope> scopes) {
    final result = <Variable>[];
    void visit(Scope scope) {
      result.addAll(scope.variables);
      scope.childScopes.forEach(visit);
    }

    scopes.forEach(visit);
    return result;
  }

  static String _formatIntToString(int fmt) => switch (fmt) {
    1 => 'VCD',
    2 => 'FST',
    3 => 'GHW',
    _ => 'Unknown',
  };
}

// ── Enum converters (mirror the FFI provider's worker-side mapping) ──────────

ScopeType _toScopeType(int v) => switch (v) {
  0 => ScopeType.module,
  1 => ScopeType.task,
  2 => ScopeType.function,
  3 => ScopeType.begin,
  4 => ScopeType.fork,
  5 => ScopeType.generate,
  6 => ScopeType.struct,
  7 => ScopeType.union,
  8 => ScopeType.svClass,
  9 => ScopeType.svInterface,
  10 => ScopeType.svPackage,
  11 => ScopeType.svProgram,
  20 => ScopeType.vhdlArchitecture,
  21 => ScopeType.vhdlProcedure,
  22 => ScopeType.vhdlFunction,
  23 => ScopeType.vhdlRecord,
  24 => ScopeType.vhdlProcess,
  25 => ScopeType.vhdlBlock,
  26 => ScopeType.vhdlForGenerate,
  27 => ScopeType.vhdlIfGenerate,
  28 => ScopeType.vhdlGenerate,
  29 => ScopeType.vhdlPackage,
  30 => ScopeType.ghwGeneric,
  31 => ScopeType.vhdlArray,
  _ => ScopeType.module,
};

VarType _toVarType(int v) => switch (v) {
  0 => VarType.event,
  1 => VarType.integer,
  2 => VarType.parameter,
  3 => VarType.real,
  4 => VarType.reg,
  5 => VarType.supply0,
  6 => VarType.supply1,
  7 => VarType.time,
  8 => VarType.tri,
  9 => VarType.triAnd,
  10 => VarType.triOr,
  11 => VarType.triReg,
  12 => VarType.tri0,
  13 => VarType.tri1,
  14 => VarType.wAnd,
  15 => VarType.wire,
  16 => VarType.wOr,
  17 => VarType.string,
  18 => VarType.port,
  19 => VarType.sparseArray,
  20 => VarType.realTime,
  30 => VarType.bit,
  31 => VarType.logic,
  32 => VarType.svInt,
  33 => VarType.svShortInt,
  34 => VarType.svLongInt,
  35 => VarType.svByte,
  36 => VarType.svEnum,
  37 => VarType.svShortReal,
  40 => VarType.boolean,
  41 => VarType.bitVector,
  42 => VarType.stdLogic,
  43 => VarType.stdLogicVector,
  44 => VarType.stdULogic,
  45 => VarType.stdULogicVector,
  46 => VarType.realParameter,
  47 => VarType.eventParameter,
  _ => VarType.wire,
};

VarDirection _toVarDirection(int v) => switch (v) {
  0 => VarDirection.unknown,
  1 => VarDirection.implicit,
  2 => VarDirection.input,
  3 => VarDirection.output,
  4 => VarDirection.inout,
  5 => VarDirection.buffer,
  6 => VarDirection.linkage,
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
