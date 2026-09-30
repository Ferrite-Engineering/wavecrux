// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/collaboration/signal_identity_resolver.dart';

void main() {
  group('SignalIdentityResolver', () {
    // The same two signals, but with *different* backend-local refs — exactly
    // the cross-machine case view-composition sync must bridge.
    final presenterSource = _FakeSource([
      _v('clk', scope: 'top', ref: '7'),
      _v('data', scope: 'top.cpu', ref: '42'),
    ]);
    final followerSource = _FakeSource([
      _v('clk', scope: 'top', ref: 's!'),
      _v('data', scope: 'top.cpu', ref: 's#'),
    ]);

    test('builds path↔ref maps from the source hierarchy', () {
      final r = SignalIdentityResolver.fromSource(presenterSource);
      expect(r.refForPath('top.clk'), '7');
      expect(r.refForPath('top.cpu.data'), '42');
      expect(r.pathForRef('7'), 'top.clk');
      expect(r.pathForRef('42'), 'top.cpu.data');
    });

    test(
      'a presenter ref serializes to a path that resolves on the follower',
      () {
        final presenter = SignalIdentityResolver.fromSource(presenterSource);
        final follower = SignalIdentityResolver.fromSource(followerSource);

        // Presenter has clk as ref '7'. Serialize → path, then re-resolve on the
        // follower → the follower's *own* ref 's!'.
        final path = presenter.pathForRef('7');
        expect(path, 'top.clk');
        expect(follower.refForPath(path), 's!');
      },
    );

    test('refForPath returns null for a path absent from the hierarchy', () {
      final r = SignalIdentityResolver.fromSource(presenterSource);
      expect(r.refForPath('top.missing'), isNull);
    });

    test('pathForRef returns the ref verbatim when it does not resolve', () {
      final r = SignalIdentityResolver.fromSource(presenterSource);
      expect(r.pathForRef('999'), '999');
    });
  });
}

Variable _v(String name, {required String scope, required String ref}) =>
    Variable(
      name: name,
      varType: VarType.wire,
      direction: VarDirection.unknown,
      signalRef: ref,
      scopePath: scope,
      bitWidth: 1,
    );

/// Minimal source: only [findVariables] is exercised.
class _FakeSource implements WaveformDataSource {
  _FakeSource(this._variables);

  final List<Variable> _variables;

  @override
  List<Variable> findVariables(SignalFilter filter) =>
      _variables.where(filter.matches).toList();

  @override
  Future<void> openFile(String path) => throw UnimplementedError();
  @override
  void close() => throw UnimplementedError();
  @override
  List<Scope> get rootScopes => throw UnimplementedError();
  @override
  Future<void> loadSignal(String signalRef) => throw UnimplementedError();
  @override
  Future<void> unloadSignal(String signalRef) => throw UnimplementedError();
  @override
  bool isSignalLoaded(String signalRef) => throw UnimplementedError();
  @override
  String? valueAt(String signalRef, int time) => throw UnimplementedError();
  @override
  List<SignalChange> changesInRange(String signalRef, int start, int end) =>
      throw UnimplementedError();
  @override
  SignalChange? nextTransition(String signalRef, int afterTime) =>
      throw UnimplementedError();
  @override
  SignalChange? prevTransition(String signalRef, int beforeTime) =>
      throw UnimplementedError();
  @override
  int get startTime => throw UnimplementedError();
  @override
  int get endTime => throw UnimplementedError();
  @override
  Timescale? get timescale => throw UnimplementedError();
  @override
  String? get date => throw UnimplementedError();
  @override
  String? get version => throw UnimplementedError();
}
