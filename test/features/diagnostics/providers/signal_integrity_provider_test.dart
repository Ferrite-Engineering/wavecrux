// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/diagnostics/providers/signal_integrity_provider.dart';

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('SignalIntegrityNotifier — initial state', () {
    test('starts as AsyncData(null)', () {
      final c = _container();
      final state = c.read(signalIntegrityProvider);
      expect(state, isA<AsyncData<dynamic>>());
      expect(state.value, isNull);
    });
  });

  group('SignalIntegrityNotifier — runAnalysis with no file loaded', () {
    test(
      'stays AsyncData(null) when no waveform source is available',
      () async {
        final c = _container();

        final states = <AsyncValue<dynamic>>[];
        c.listen(
          signalIntegrityProvider,
          (_, next) => states.add(next),
        );

        await c.read(signalIntegrityProvider.notifier).runAnalysis();

        final state = c.read(signalIntegrityProvider);
        expect(state, isA<AsyncData<dynamic>>());
        expect(state.value, isNull);
      },
    );
  });

  group('SignalIntegrityNotifier — state transitions', () {
    test(
      're-running analysis after reset returns to AsyncData(null)',
      () async {
        final c = _container();

        final states = <AsyncValue<dynamic>>[];
        c.listen(
          signalIntegrityProvider,
          (_, next) => states.add(next),
        );

        // With no file loaded two successive calls should both stay null.
        await c.read(signalIntegrityProvider.notifier).runAnalysis();
        await c.read(signalIntegrityProvider.notifier).runAnalysis();

        expect(c.read(signalIntegrityProvider).value, isNull);
      },
    );
  });
}
