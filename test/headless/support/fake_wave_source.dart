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
import 'package:wavecrux/headless/wave_file_cache.dart';

/// A one-signal source (`top.clk`, 1 bit, 1 ns ticks, 0 to 40) whose
/// [loadSignal] throws [loadError] when one is given; no data otherwise.
class FakeWaveSource implements WaveformDataSource {
  /// A source whose loads fail with [loadError], when given.
  FakeWaveSource({this.loadError});

  /// What every load throws.
  final Object? loadError;

  static const Variable _clk = Variable(
    name: 'clk',
    varType: VarType.wire,
    direction: VarDirection.unknown,
    signalRef: '0',
    scopePath: 'top',
    bitWidth: 1,
  );

  @override
  List<Scope> get rootScopes => const <Scope>[
    Scope(
      name: 'top',
      type: ScopeType.module,
      path: 'top',
      variables: <Variable>[_clk],
    ),
  ];

  @override
  Future<void> loadSignal(String signalRef) async {
    final error = loadError;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
  }

  @override
  Future<void> openFile(String path) async {}

  @override
  void close() {}

  @override
  List<Variable> findVariables(SignalFilter filter) => const <Variable>[_clk];

  @override
  bool isSignalLoaded(String signalRef) => loadError == null;

  @override
  Future<void> unloadSignal(String signalRef) async {}

  @override
  String? valueAt(String signalRef, int time) => null;

  @override
  List<SignalChange> changesInRange(String signalRef, int start, int end) =>
      const <SignalChange>[];

  @override
  SignalChange? nextTransition(String signalRef, int afterTime) => null;

  @override
  SignalChange? prevTransition(String signalRef, int beforeTime) => null;

  @override
  int get startTime => 0;

  @override
  int get endTime => 40;

  @override
  Timescale? get timescale =>
      const Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);

  @override
  String? get date => null;

  @override
  String? get version => null;
}

/// A [WaveFile] over a [FakeWaveSource], calling [onClose] when closed.
WaveFile fakeWaveFile({Object? loadError, void Function()? onClose}) =>
    WaveFile(
      source: FakeWaveSource(loadError: loadError),
      format: 'VCD',
      close: () async => onClose?.call(),
    );
