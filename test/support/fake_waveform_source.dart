// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

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

/// A hand-crafted in-memory [WaveformDataSource] for AI tests — the §8.9
/// "known-answer fixture" idea without the FFI round-trip, so every assertion
/// has an exact expected value and coordinate.
class FakeWaveformSource implements WaveformDataSource {
  FakeWaveformSource({
    required this.rootScopes,
    required Map<String, List<SignalChange>> changes,
    required this.endTime,
    this.startTime = 0,
    this.timescale,
  }) : _data = changes;

  /// A small reference trace: `top.clk` (1-bit toggling), `top.data` (8-bit),
  /// `top.state` (2-bit, X from tick 5). Range `[0, 40]`.
  factory FakeWaveformSource.reference() => FakeWaveformSource(
    endTime: 40,
    timescale: const Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds),
    rootScopes: [
      Scope(
        name: 'top',
        type: ScopeType.module,
        path: 'top',
        variables: [
          _v('clk', 's_clk', 1),
          _v('data', 's_data', 8),
          _v('state', 's_state', 2),
        ],
      ),
    ],
    changes: {
      's_clk': const [
        SignalChange(time: 0, value: '0'),
        SignalChange(time: 10, value: '1'),
        SignalChange(time: 20, value: '0'),
        SignalChange(time: 30, value: '1'),
      ],
      's_data': const [
        SignalChange(time: 0, value: '00000000'),
        SignalChange(time: 15, value: '10101010'),
      ],
      's_state': const [
        SignalChange(time: 0, value: '00'),
        SignalChange(time: 5, value: 'xx'),
      ],
    },
  );

  static Variable _v(String name, String ref, int width) => Variable(
    name: name,
    varType: VarType.wire,
    direction: VarDirection.input,
    signalRef: ref,
    scopePath: 'top',
    bitWidth: width,
  );

  @override
  final List<Scope> rootScopes;
  final Map<String, List<SignalChange>> _data;
  final Set<String> _loaded = {};

  @override
  final int startTime;
  @override
  final int endTime;
  @override
  final Timescale? timescale;
  @override
  String? get date => null;
  @override
  String? get version => null;

  @override
  List<Variable> findVariables(SignalFilter filter) => [
    for (final s in rootScopes)
      for (final v in s.variables)
        if (filter.matches(v)) v,
  ];

  @override
  Future<void> loadSignal(String signalRef) async => _loaded.add(signalRef);

  @override
  bool isSignalLoaded(String signalRef) => _loaded.contains(signalRef);

  @override
  Future<void> unloadSignal(String signalRef) async =>
      _loaded.remove(signalRef);

  @override
  String? valueAt(String signalRef, int time) {
    if (!_loaded.contains(signalRef)) return null;
    final list = _data[signalRef];
    if (list == null) return null;
    String? v;
    for (final c in list) {
      if (c.time <= time) {
        v = c.value;
      } else {
        break;
      }
    }
    return v;
  }

  @override
  List<SignalChange> changesInRange(String signalRef, int start, int end) {
    if (!_loaded.contains(signalRef)) return const [];
    final list = _data[signalRef];
    if (list == null) return const [];
    return [
      for (final c in list)
        if (c.time >= start && c.time < end) c,
    ];
  }

  @override
  SignalChange? nextTransition(String signalRef, int afterTime) {
    if (!_loaded.contains(signalRef)) return null;
    for (final c in _data[signalRef] ?? const <SignalChange>[]) {
      if (c.time > afterTime) return c;
    }
    return null;
  }

  @override
  SignalChange? prevTransition(String signalRef, int beforeTime) {
    if (!_loaded.contains(signalRef)) return null;
    SignalChange? result;
    for (final c in _data[signalRef] ?? const <SignalChange>[]) {
      if (c.time < beforeTime) {
        result = c;
      } else {
        break;
      }
    }
    return result;
  }

  @override
  Future<void> openFile(String path) async {}
  @override
  void close() {}
}
