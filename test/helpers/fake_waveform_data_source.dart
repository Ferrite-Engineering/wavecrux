// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';

/// Tiny in-memory [WaveformDataSource] for unit tests.
///
/// Each signal is described by a list of `(time, value)` change records and
/// a bit width. The fake responds to `valueAt`, `changesInRange`,
/// `nextTransition`, and `prevTransition` against that data without ever
/// touching the file system or FFI.
class FakeWaveformDataSource implements WaveformDataSource {
  FakeWaveformDataSource({
    List<Scope>? scopes,
    Map<String, List<SignalChange>>? signals,
    int startTime = 0,
    int endTime = 1000,
    Timescale? timescale,
  }) : _scopes = scopes ?? const <Scope>[],
       _signals = signals ?? <String, List<SignalChange>>{},
       _startTime = startTime,
       _endTime = endTime,
       _timescale = timescale,
       _loaded = (signals ?? <String, List<SignalChange>>{}).keys.toSet();

  final List<Scope> _scopes;
  final Map<String, List<SignalChange>> _signals;
  final Set<String> _loaded;
  final int _startTime;
  final int _endTime;
  final Timescale? _timescale;

  @override
  Future<void> openFile(String path) async {}

  @override
  void close() {}

  @override
  List<Scope> get rootScopes => _scopes;

  @override
  List<Variable> findVariables(SignalFilter filter) {
    final out = <Variable>[];
    void walk(Scope s) {
      out.addAll(s.variables);
      s.childScopes.forEach(walk);
    }

    _scopes.forEach(walk);
    return out;
  }

  @override
  Future<void> loadSignal(String signalRef) async {
    _loaded.add(signalRef);
  }

  @override
  bool isSignalLoaded(String signalRef) => _loaded.contains(signalRef);

  @override
  Future<void> unloadSignal(String signalRef) async {
    _loaded.remove(signalRef);
  }

  @override
  String? valueAt(String signalRef, int time) {
    final changes = _signals[signalRef];
    if (changes == null || changes.isEmpty) return null;
    String? value;
    for (final c in changes) {
      if (c.time > time) break;
      value = c.value;
    }
    return value;
  }

  @override
  List<SignalChange> changesInRange(String signalRef, int start, int end) {
    final changes = _signals[signalRef];
    if (changes == null) return const [];
    return changes
        .where((c) => c.time >= start && c.time < end)
        .toList(growable: false);
  }

  @override
  SignalChange? nextTransition(String signalRef, int afterTime) {
    final changes = _signals[signalRef];
    if (changes == null) return null;
    for (final c in changes) {
      if (c.time > afterTime) return c;
    }
    return null;
  }

  @override
  SignalChange? prevTransition(String signalRef, int beforeTime) {
    final changes = _signals[signalRef];
    if (changes == null) return null;
    SignalChange? result;
    for (final c in changes) {
      if (c.time >= beforeTime) break;
      result = c;
    }
    return result;
  }

  @override
  int get startTime => _startTime;

  @override
  int get endTime => _endTime;

  @override
  Timescale? get timescale => _timescale;

  @override
  String? get date => null;

  @override
  String? get version => null;
}

/// Convenience [Variable] constructor for tests.
Variable testVariable(
  String name,
  String ref,
  String scopePath, {
  int? bitWidth = 1,
  VarType varType = VarType.wire,
}) => Variable(
  name: name,
  varType: varType,
  direction: VarDirection.unknown,
  signalRef: ref,
  scopePath: scopePath,
  bitWidth: bitWidth,
);

/// Convenience [Scope] constructor for tests.
Scope testScope(
  String name,
  String path,
  List<Variable> variables, {
  List<Scope> children = const [],
  ScopeType type = ScopeType.module,
}) => Scope(
  name: name,
  type: type,
  path: path,
  childScopes: children,
  variables: variables,
);
