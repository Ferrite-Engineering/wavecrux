// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/collaboration/signal_identity_resolver.dart';

SignalIdentityResolver _presenter() => SignalIdentityResolver(
  pathToRef: const {'top.state': 'P1'},
  refToPath: const {'P1': 'top.state'},
);
SignalIdentityResolver _follower() => SignalIdentityResolver(
  pathToRef: const {'top.state': 'L1'},
  refToPath: const {'L1': 'top.state'},
);

ProviderContainer _container() {
  final c = ProviderContainer(
    overrides: [
      waveformSourceProvider.overrideWith(_FakeSourceNotifier.new),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('FsmNotifier view-composition recipe seams', () {
    test('toCompositionRecipe returns null when no FSM is active', () {
      final c = _container();
      expect(
        c.read(fsmProvider.notifier).toCompositionRecipe(_presenter()),
        isNull,
      );
    });

    test('serialize maps the active FSM ref to its canonical path', () async {
      final c = _container();
      // loadSignal throws in the fake, but analyzeSignal still records the
      // target signalRef (error path) — enough to exercise serialization.
      await c.read(fsmProvider.notifier).analyzeSignal('P1');
      expect(c.read(fsmProvider).signalRef, 'P1');
      expect(
        c.read(fsmProvider.notifier).toCompositionRecipe(_presenter()),
        'top.state',
      );
    });

    test('apply(null) clears the FSM viewer', () async {
      final c = _container();
      await c.read(fsmProvider.notifier).analyzeSignal('P1');
      final missing = c
          .read(fsmProvider.notifier)
          .applyCompositionRecipe(null, _follower());
      expect(missing, isEmpty);
      expect(c.read(fsmProvider).signalRef, isNull);
    });

    test('apply resolves the path to a follower-local ref', () async {
      final c = _container();
      final missing = c
          .read(fsmProvider.notifier)
          .applyCompositionRecipe('top.state', _follower());
      expect(missing, isEmpty);
      // analyzeSignal fires for the follower's local ref 'L1'. Let microtasks
      // settle so the (error-path) state lands.
      await Future<void>.delayed(Duration.zero);
      expect(c.read(fsmProvider).signalRef, 'L1');
    });

    test(
      'missing-signal degradation: unresolved path closes FSM + reports',
      () {
        final c = _container();
        final missing = c
            .read(fsmProvider.notifier)
            .applyCompositionRecipe('top.ghost', _follower());
        expect(missing, ['top.ghost']);
        expect(c.read(fsmProvider).signalRef, isNull);
      },
    );
  });
}

/// Source whose [loadSignal] always throws, so [FsmNotifier.analyzeSignal]
/// settles on the error path (which still records the target ref) without
/// needing real signal data.
class _FakeSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_FakeSource());
}

class _FakeSource implements WaveformDataSource {
  @override
  List<Variable> findVariables(SignalFilter filter) => const [];
  @override
  bool isSignalLoaded(String signalRef) => false;
  @override
  Future<void> loadSignal(String signalRef) async =>
      throw StateError('no data in fake');

  @override
  Future<void> openFile(String path) => throw UnimplementedError();
  @override
  void close() => throw UnimplementedError();
  @override
  List<Scope> get rootScopes => throw UnimplementedError();
  @override
  Future<void> unloadSignal(String signalRef) => throw UnimplementedError();
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
  int get startTime => 0;
  @override
  int get endTime => 0;
  @override
  Timescale? get timescale => null;
  @override
  String? get date => null;
  @override
  String? get version => null;
}
