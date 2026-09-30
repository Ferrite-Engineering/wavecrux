// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Regression guard for the tab-close race on long-running keepAlive
// notifiers.
//
// Riverpod 3 disposes a notifier eagerly when its container goes away, but an
// in-flight `await` inside one of its methods keeps running. Any `state`
// write or `ref.read` that lands after that point throws
// `UnmountedRefException`, which surfaces as an unhandled async error —
// closing a tab while an analysis, diff, or file load was still running.
//
// Each test here starts a real async method against a source whose
// `loadSignal` never completes until the test releases it, disposes the
// container mid-await, then completes the load and asserts the method returns
// without throwing. Without the `ref.mounted` guards in the notifiers, every
// one of these throws.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/pattern_expression.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/features/viewer/providers/switching_activity_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/providers/x_trace_provider.dart';

// ── a source whose signal loads block until released ──────────────────────────

class _BlockingSource implements WaveformDataSource {
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> loadSignal(String signalRef) => gate.future;

  @override
  bool isSignalLoaded(String signalRef) => false;

  @override
  List<Scope> get rootScopes => const <Scope>[
    Scope(
      name: 'top',
      type: ScopeType.module,
      path: 'top',
      variables: <Variable>[
        Variable(
          name: 'sig',
          varType: VarType.wire,
          direction: VarDirection.unknown,
          signalRef: '!',
          scopePath: 'top',
          bitWidth: 1,
        ),
      ],
    ),
  ];

  @override
  int get startTime => 0;

  @override
  int get endTime => 1000;

  @override
  String? valueAt(String signalRef, int time) => 'x';

  @override
  List<SignalChange> changesInRange(String signalRef, int start, int end) =>
      const <SignalChange>[];

  @override
  void close() {}

  // The notifiers under test touch only the members above. Anything else the
  // interface grows is irrelevant to this race and should not break the build.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

({ProviderContainer container, _BlockingSource source}) _setUp() {
  final source = _BlockingSource();
  final container = ProviderContainer(
    overrides: [
      waveformSourceProvider.overrideWith(() => _FakeSourceNotifier(source)),
    ],
  );
  return (container: container, source: source);
}

/// Runs [start] against a fresh container, disposes the container while the
/// signal load is still pending, then releases the load and returns the
/// future's completion. Fails if disposal mid-await produces an error.
Future<void> _expectSurvivesDisposeMidAwait(
  Future<void> Function(ProviderContainer c) start,
) async {
  final env = _setUp();
  final pending = start(env.container);

  // Let the method reach its `await source.loadSignal(...)`.
  await Future<void>.delayed(Duration.zero);

  // The user closes the tab here.
  env.container.dispose();

  // The load the notifier is still waiting on now completes.
  env.source.gate.complete();

  await expectLater(pending, completes);
}

void main() {
  group('keepAlive notifiers survive container disposal mid-await', () {
    test('XTraceNotifier.traceX', () async {
      await _expectSurvivesDisposeMidAwait(
        (c) => c.read(xTraceProvider.notifier).traceX('!', 500),
      );
    });

    test('PatternSearchNotifier.search', () async {
      await _expectSurvivesDisposeMidAwait(
        (c) => c
            .read(patternSearchProvider.notifier)
            .search(
              const SignalCondition(
                signalPath: 'top.sig',
                operator: ConditionOperator.eq,
                value: '1',
              ),
              0,
              1000,
            ),
      );
    });

    test('SwitchingActivityNotifier.analyze', () async {
      await _expectSurvivesDisposeMidAwait(
        (c) => c
            .read(switchingActivityProvider.notifier)
            .analyze({'!': 'top.sig'}, 0, 1000),
      );
    });
  });
}
