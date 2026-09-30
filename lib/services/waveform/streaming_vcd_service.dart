// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// StreamingVcdService — WaveformDataSource backed by an incremental VCD
// byte-stream.
//
// This is the engine for interactive / streaming VCD mode (Section 4.3.1),
// equivalent to GTKWave's `--interactive` mode with `shmidcat`. Feed any
// `Stream<List<int>>` — stdin, a named pipe, or a file opened progressively —
// and the hierarchy becomes available after `$enddefinitions`, with value
// changes accumulating in memory as the stream continues.
//
// Parsing is token-based (whitespace-separated), driven incrementally.
// Chunk boundaries in the middle of a token are handled by buffering the
// partial token until the next chunk.

import 'dart:async';
import 'dart:io';

import 'package:crux_async/crux_async.dart';
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

// Default debounce interval between onDataUpdated notifications.
const Duration _kDefaultUpdateInterval = Duration(milliseconds: 100);

/// [WaveformDataSource] that parses VCD data incrementally from a byte stream.
///
/// **Usage:**
/// ```dart
/// final service = StreamingVcdService();
/// service.startFromStream(stdin);            // attach stream
/// await service.headerParsedFuture;          // wait for hierarchy
/// // subscribe to live updates
/// service.onDataUpdated.listen((_) => ...);
/// ```
///
/// All [WaveformDataSource] query methods operate on the data accumulated at
/// the time of the call. Because streaming is concurrent, results may change
/// between successive calls as new value changes arrive.
class StreamingVcdService implements WaveformDataSource {
  /// Creates a streaming VCD service.
  ///
  /// [updateInterval] controls the debounce between [onDataUpdated] events.
  /// Pass [Duration.zero] in tests to receive updates synchronously.
  StreamingVcdService({
    Duration updateInterval = _kDefaultUpdateInterval,
  }) : _updateInterval = updateInterval,
       _updateDebounce = Debouncer(duration: updateInterval);

  final Duration _updateInterval;
  final Debouncer _updateDebounce;

  // ── accumulated waveform state ────────────────────────────────────────────

  List<Scope> _rootScopes = const [];
  List<Variable> _allVariables = const [];
  final Map<String, List<SignalChange>> _allChanges = {};
  final Set<String> _loadedSignals = {};
  int _endTime = 0;
  Timescale? _timescale;
  String? _date;
  String? _version;

  // ── streaming infrastructure ──────────────────────────────────────────────

  StreamSubscription<List<int>>? _streamSub;
  final StreamController<void> _updateController =
      StreamController<void>.broadcast();
  final StreamController<void> _doneController =
      StreamController<void>.broadcast();
  bool _closed = false;

  // ── incremental parser state ──────────────────────────────────────────────

  /// Partial token carried over from the previous chunk boundary.
  String _partialToken = '';

  bool _headerParsed = false;
  final Completer<void> _headerCompleter = Completer<void>();
  final Completer<void> _streamEndedCompleter = Completer<void>();

  // Header-phase directive state machine.
  _DirectiveKind _activeDirective = _DirectiveKind.none;
  final List<String> _directiveTokens = [];

  // Scope construction stack.
  final List<_StreamScopeBuilder> _scopeStack = [];
  final List<Scope> _rootScopesList = [];

  // Current simulation timestamp (value section).
  int _currentTime = 0;

  // Pending bits/real for two-token vector/real value-change syntax.
  // Holds the value half of `b<bits> <idcode>` until the idcode token arrives.
  String? _pendingValueBits;

  // Whether we are currently inside a $comment block in the value section.
  bool _inValueComment = false;

  // ── public API ────────────────────────────────────────────────────────────

  /// Fires (debounced by [updateInterval]) after each batch of new value-change
  /// data is appended to the in-memory store.
  Stream<void> get onDataUpdated => _updateController.stream;

  /// Fires once when the byte stream reaches EOF (either naturally or via [stop]).
  Stream<void> get onStreamEnded => _doneController.stream;

  /// Whether `$enddefinitions` has been seen — the hierarchy is ready.
  bool get isHeaderParsed => _headerParsed;

  /// The latest simulation timestamp received so far.
  int get currentEndTime => _endTime;

  /// Resolves when [isHeaderParsed] becomes true (i.e. `$enddefinitions $end`
  /// has been parsed and [rootScopes] is populated).
  Future<void> get headerParsedFuture => _headerCompleter.future;

  /// Resolves when the underlying byte stream reaches EOF.
  Future<void> get streamEndedFuture => _streamEndedCompleter.future;

  /// Attaches [stream] and starts consuming data in the background.
  ///
  /// Returns immediately. Await [headerParsedFuture] if you need the hierarchy
  /// before querying. Listen to [onDataUpdated] for incremental value-change
  /// notifications.
  void startFromStream(Stream<List<int>> stream) {
    unawaited(_streamSub?.cancel());
    _streamSub = stream.listen(
      _onChunk,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  /// Attaches [stream] and waits until the VCD header is fully parsed.
  ///
  /// Resolves once `$enddefinitions $end` is seen; value changes continue to
  /// accumulate in the background.
  Future<void> startAndWaitForHeader(Stream<List<int>> stream) async {
    startFromStream(stream);
    await _headerCompleter.future;
  }

  /// Cancels the stream subscription and stops processing data.
  ///
  /// Accumulated data remains queryable. Call [close] to also release all
  /// resources.
  void stop() {
    unawaited(_streamSub?.cancel());
    _streamSub = null;
    _updateDebounce.cancel();
    if (!_updateController.isClosed) _updateController.add(null);
    if (!_streamEndedCompleter.isCompleted) _streamEndedCompleter.complete();
    if (!_doneController.isClosed) {
      _doneController.add(null);
    }
  }

  // ── WaveformDataSource ────────────────────────────────────────────────────

  /// Opens a file (or named pipe) at [path] as a byte stream and waits for the
  /// VCD header to be fully parsed before returning.
  ///
  /// Throws [UnsupportedError] on Flutter Web (dart:ffi / dart:io not
  /// available).
  @override
  Future<void> openFile(String path) async {
    if (kIsWeb) {
      throw UnsupportedError('Streaming VCD is not supported on Flutter Web.');
    }
    await startAndWaitForHeader(File(path).openRead());
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(_streamSub?.cancel());
    _streamSub = null;
    _updateDebounce.dispose();
    unawaited(_updateController.close());
    unawaited(_doneController.close());
    if (!_headerCompleter.isCompleted) {
      _headerCompleter.completeError(StateError('StreamingVcdService closed'));
    }
    if (!_streamEndedCompleter.isCompleted) {
      _streamEndedCompleter.complete();
    }
    _rootScopes = const [];
    _allVariables = const [];
    _allChanges.clear();
    _loadedSignals.clear();
    _endTime = 0;
  }

  @override
  List<Scope> get rootScopes => _rootScopes;

  @override
  List<Variable> findVariables(SignalFilter filter) {
    if (filter.matchesAll) return List.unmodifiable(_allVariables);
    return _allVariables.where(filter.matches).toList();
  }

  @override
  Future<void> loadSignal(String signalRef) async {
    _loadedSignals.add(signalRef);
  }

  @override
  bool isSignalLoaded(String signalRef) => _loadedSignals.contains(signalRef);

  @override
  Future<void> unloadSignal(String signalRef) async {
    _loadedSignals.remove(signalRef);
  }

  @override
  String? valueAt(String signalRef, int time) {
    final changes = _changesFor(signalRef);
    if (changes == null || changes.isEmpty) return null;
    var lo = 0;
    var hi = changes.length - 1;
    int? found;
    while (lo <= hi) {
      final mid = (lo + hi) >>> 1;
      if (changes[mid].time <= time) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found != null ? changes[found].value : null;
  }

  @override
  List<SignalChange> changesInRange(String signalRef, int start, int end) {
    final changes = _changesFor(signalRef);
    if (changes == null || changes.isEmpty) return const [];
    var lo = 0;
    var hi = changes.length;
    while (lo < hi) {
      final mid = (lo + hi) >>> 1;
      if (changes[mid].time < start) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final result = <SignalChange>[];
    for (var i = lo; i < changes.length && changes[i].time < end; i++) {
      result.add(changes[i]);
    }
    return result;
  }

  @override
  SignalChange? nextTransition(String signalRef, int afterTime) {
    final changes = _changesFor(signalRef);
    if (changes == null || changes.isEmpty) return null;
    var lo = 0;
    var hi = changes.length;
    while (lo < hi) {
      final mid = (lo + hi) >>> 1;
      if (changes[mid].time <= afterTime) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < changes.length ? changes[lo] : null;
  }

  @override
  SignalChange? prevTransition(String signalRef, int beforeTime) {
    final changes = _changesFor(signalRef);
    if (changes == null || changes.isEmpty) return null;
    var lo = 0;
    var hi = changes.length - 1;
    int? found;
    while (lo <= hi) {
      final mid = (lo + hi) >>> 1;
      if (changes[mid].time < beforeTime) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found != null ? changes[found] : null;
  }

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

  // ── stream callbacks ──────────────────────────────────────────────────────

  void _onChunk(List<int> bytes) {
    if (_closed) return;
    _processText(String.fromCharCodes(bytes));
  }

  void _onDone() {
    if (_closed) return;
    // Flush any partial token remaining from the last chunk.
    if (_partialToken.isNotEmpty) {
      _dispatchToken(_partialToken);
      _partialToken = '';
    }
    // If the stream ended without $enddefinitions, finalize now so the caller
    // is not left waiting on headerParsedFuture.
    if (!_headerParsed) _finalizeHeader();
    // Cancel debounce and fire a final update.
    _updateDebounce.cancel();
    if (!_updateController.isClosed) _updateController.add(null);
    if (!_streamEndedCompleter.isCompleted) _streamEndedCompleter.complete();
    if (!_doneController.isClosed) _doneController.add(null);
  }

  // ── tokenizer ─────────────────────────────────────────────────────────────

  void _processText(String text) {
    final combined = _partialToken + text;
    _partialToken = '';

    var inToken = false;
    var start = 0;
    var hadTokensPostHeader = false;

    for (var i = 0; i < combined.length; i++) {
      final c = combined[i];
      final isWs = c == ' ' || c == '\n' || c == '\r' || c == '\t';
      if (isWs) {
        if (inToken) {
          final wasHeader = !_headerParsed;
          _dispatchToken(combined.substring(start, i));
          // Schedule an update for any token that arrives once the header is
          // parsed (covers both the token that triggers _finalizeHeader and all
          // subsequent value-change tokens).
          if (!wasHeader || _headerParsed) hadTokensPostHeader = true;
          inToken = false;
        }
      } else {
        if (!inToken) {
          start = i;
          inToken = true;
        }
      }
    }

    // Save incomplete terminal token for the next chunk.
    if (inToken) {
      _partialToken = combined.substring(start);
    }

    if (hadTokensPostHeader) _scheduleUpdate();
  }

  void _dispatchToken(String token) {
    if (!_headerParsed) {
      _processHeaderToken(token);
    } else {
      _processValueToken(token);
    }
  }

  // ── header parser (state machine) ─────────────────────────────────────────

  void _processHeaderToken(String token) {
    switch (_activeDirective) {
      case _DirectiveKind.none:
        switch (token) {
          case r'$enddefinitions':
            _activeDirective = _DirectiveKind.enddefinitions;
          case r'$timescale':
            _activeDirective = _DirectiveKind.timescale;
            _directiveTokens.clear();
          case r'$date':
            _activeDirective = _DirectiveKind.date;
            _directiveTokens.clear();
          case r'$version':
            _activeDirective = _DirectiveKind.version;
            _directiveTokens.clear();
          case r'$comment':
            _activeDirective = _DirectiveKind.comment;
          case r'$scope':
            _activeDirective = _DirectiveKind.scope;
            _directiveTokens.clear();
          case r'$upscope':
            _activeDirective = _DirectiveKind.upscope;
          case r'$var':
            _activeDirective = _DirectiveKind.varDecl;
            _directiveTokens.clear();
        }

      case _DirectiveKind.enddefinitions:
        if (token == r'$end') _finalizeHeader();

      case _DirectiveKind.timescale:
        if (token == r'$end') {
          _timescale = _parseTimescale(_directiveTokens.join());
          _activeDirective = _DirectiveKind.none;
          _directiveTokens.clear();
        } else {
          _directiveTokens.add(token);
        }

      case _DirectiveKind.date:
        if (token == r'$end') {
          final raw = _directiveTokens.join(' ').trim();
          _date = raw.isEmpty ? null : raw;
          _activeDirective = _DirectiveKind.none;
          _directiveTokens.clear();
        } else {
          _directiveTokens.add(token);
        }

      case _DirectiveKind.version:
        if (token == r'$end') {
          final raw = _directiveTokens.join(' ').trim();
          _version = raw.isEmpty ? null : raw;
          _activeDirective = _DirectiveKind.none;
          _directiveTokens.clear();
        } else {
          _directiveTokens.add(token);
        }

      case _DirectiveKind.comment:
        if (token == r'$end') _activeDirective = _DirectiveKind.none;

      case _DirectiveKind.scope:
        if (token == r'$end') {
          _processScopeDirective();
          _activeDirective = _DirectiveKind.none;
          _directiveTokens.clear();
        } else {
          _directiveTokens.add(token);
        }

      case _DirectiveKind.upscope:
        if (token == r'$end') {
          _popScope();
          _activeDirective = _DirectiveKind.none;
        }

      case _DirectiveKind.varDecl:
        if (token == r'$end') {
          _processVarDirective();
          _activeDirective = _DirectiveKind.none;
          _directiveTokens.clear();
        } else {
          _directiveTokens.add(token);
        }
    }
  }

  void _processScopeDirective() {
    // Tokens: [type, name]  (e.g. ['module', 'top'])
    if (_directiveTokens.length < 2) return;
    final typeStr = _directiveTokens[0];
    final name = _directiveTokens[1];
    final parentPath = _scopeStack.isEmpty ? '' : _scopeStack.last.path;
    final path = parentPath.isEmpty ? name : '$parentPath.$name';
    _scopeStack.add(
      _StreamScopeBuilder(
        name: name,
        type: _parseScopeType(typeStr),
        path: path,
      ),
    );
  }

  void _popScope() {
    if (_scopeStack.isEmpty) return;
    final builder = _scopeStack.removeLast();
    final scope = builder.build();
    if (_scopeStack.isEmpty) {
      _rootScopesList.add(scope);
    } else {
      _scopeStack.last.childScopes.add(scope);
    }
  }

  void _processVarDirective() {
    // Tokens: [type, bitWidth, idcode, name, ...]
    if (_directiveTokens.length < 4) return;
    final varType = _parseVarType(_directiveTokens[0]);
    final bitWidth = int.tryParse(_directiveTokens[1]);
    final idcode = _directiveTokens[2];
    final name = _directiveTokens[3];
    final scopePath = _scopeStack.isEmpty ? '' : _scopeStack.last.path;

    final isReal =
        varType == VarType.real ||
        varType == VarType.realTime ||
        varType == VarType.svShortReal;

    final variable = Variable(
      name: name,
      varType: varType,
      direction: VarDirection.unknown,
      signalRef: idcode,
      scopePath: scopePath,
      bitWidth: isReal ? null : bitWidth,
    );

    if (_scopeStack.isNotEmpty) {
      _scopeStack.last.variables.add(variable);
    }
    _allChanges.putIfAbsent(idcode, () => []);
  }

  void _finalizeHeader() {
    // Gracefully close any open scope builders (malformed-VCD resilience).
    while (_scopeStack.isNotEmpty) {
      _popScope();
    }
    _rootScopes = List.unmodifiable(_rootScopesList);
    _allVariables = _flattenVariables(_rootScopes);
    _headerParsed = true;
    _activeDirective = _DirectiveKind.none;
    if (!_headerCompleter.isCompleted) _headerCompleter.complete();
  }

  // ── value parser ──────────────────────────────────────────────────────────

  void _processValueToken(String token) {
    if (token.isEmpty) return;

    // Skip tokens inside a $comment block.
    if (_inValueComment) {
      if (token == r'$end') _inValueComment = false;
      return;
    }

    // If we have a pending vector/real value, this token is the idcode.
    if (_pendingValueBits != null) {
      _recordChange(token, _pendingValueBits!);
      _pendingValueBits = null;
      return;
    }

    final first = token[0];

    // VCD directive tokens in the value section.
    if (first == r'$') {
      if (token == r'$comment') _inValueComment = true;
      // $dumpvars / $dumpall / $dumpoff / $dumpon / $end — skip.
      return;
    }

    // Timestamp: #<ticks>
    if (first == '#') {
      final time = int.tryParse(token.substring(1));
      if (time != null) {
        _currentTime = time;
        if (time > _endTime) _endTime = time;
      }
      return;
    }

    // Vector change: b<bits> <idcode>  or  B<bits> <idcode>
    if (first == 'b' || first == 'B') {
      _pendingValueBits = token.substring(1);
      return;
    }

    // Real change: r<value> <idcode>  or  R<value> <idcode>
    if (first == 'r' || first == 'R') {
      _pendingValueBits = token.substring(1);
      return;
    }

    // Scalar change: <0|1|x|z><idcode>
    if (token.length >= 2) {
      final valueChar = first.toLowerCase();
      if (valueChar == '0' ||
          valueChar == '1' ||
          valueChar == 'x' ||
          valueChar == 'z') {
        _recordChange(token.substring(1), valueChar);
      }
    }
  }

  void _recordChange(String idcode, String value) {
    _allChanges
        .putIfAbsent(idcode, () => [])
        .add(
          SignalChange(time: _currentTime, value: value),
        );
  }

  // ── debounce ──────────────────────────────────────────────────────────────

  void _scheduleUpdate() {
    if (_updateController.isClosed) return;
    if (_updateInterval == Duration.zero) {
      _updateController.add(null);
      return;
    }
    _updateDebounce.run(() {
      if (!_updateController.isClosed) _updateController.add(null);
    });
  }

  // ── query helper ──────────────────────────────────────────────────────────

  List<SignalChange>? _changesFor(String signalRef) {
    if (!_loadedSignals.contains(signalRef)) return null;
    return _allChanges[signalRef];
  }

  // ── static parse helpers ─────────────────────────────────────────────────

  static List<Variable> _flattenVariables(List<Scope> scopes) {
    final result = <Variable>[];
    void visit(Scope scope) {
      result.addAll(scope.variables);
      scope.childScopes.forEach(visit);
    }

    scopes.forEach(visit);
    return result;
  }

  static Timescale? _parseTimescale(String raw) {
    final normalized = raw.replaceAll(' ', '').toLowerCase();
    final match = RegExp(r'^(\d+)([a-z]+)$').firstMatch(normalized);
    if (match == null) return null;
    final factor = int.tryParse(match.group(1)!) ?? 1;
    final unit = switch (match.group(2)!) {
      'fs' => TimescaleUnit.femtoSeconds,
      'ps' => TimescaleUnit.picoSeconds,
      'ns' => TimescaleUnit.nanoSeconds,
      'us' || 'μs' => TimescaleUnit.microSeconds,
      'ms' => TimescaleUnit.milliSeconds,
      's' => TimescaleUnit.seconds,
      _ => TimescaleUnit.unknown,
    };
    return Timescale(factor: factor, unit: unit);
  }

  static ScopeType _parseScopeType(String type) => switch (type) {
    'module' => ScopeType.module,
    'task' => ScopeType.task,
    'function' => ScopeType.function,
    'begin' => ScopeType.begin,
    'fork' => ScopeType.fork,
    _ => ScopeType.module,
  };

  static VarType _parseVarType(String type) => switch (type) {
    'event' => VarType.event,
    'integer' => VarType.integer,
    'parameter' => VarType.parameter,
    'real' => VarType.real,
    'realtime' => VarType.realTime,
    'reg' => VarType.reg,
    'supply0' => VarType.supply0,
    'supply1' => VarType.supply1,
    'time' => VarType.time,
    'tri' => VarType.tri,
    'triand' => VarType.triAnd,
    'trior' => VarType.triOr,
    'trireg' => VarType.triReg,
    'tri0' => VarType.tri0,
    'tri1' => VarType.tri1,
    'wand' => VarType.wAnd,
    'wire' => VarType.wire,
    'wor' => VarType.wOr,
    'string' => VarType.string,
    'port' => VarType.port,
    _ => VarType.wire,
  };
}

// ── header directive state machine ────────────────────────────────────────────

enum _DirectiveKind {
  none,
  enddefinitions,
  timescale,
  date,
  version,
  comment,
  scope,
  upscope,
  varDecl,
}

// ── scope builder ─────────────────────────────────────────────────────────────

class _StreamScopeBuilder {
  _StreamScopeBuilder({
    required this.name,
    required this.type,
    required this.path,
  });

  final String name;
  final ScopeType type;
  final String path;
  final List<Scope> childScopes = [];
  final List<Variable> variables = [];

  Scope build() => Scope(
    name: name,
    type: type,
    path: path,
    childScopes: List.unmodifiable(childScopes),
    variables: List.unmodifiable(variables),
  );
}
