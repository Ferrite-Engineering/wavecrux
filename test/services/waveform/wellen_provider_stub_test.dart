// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Tests the no-op stub class that backs WellenProvider on Flutter Web,
// where `dart:ffi` is unavailable.
//
// This test imports the *stub* file directly so it runs uniformly on every
// host. Code that imports the conditional shim (`wellen_provider.dart`)
// would resolve to the io implementation on the VM and short-circuit these
// assertions; importing the stub explicitly is the only way to verify the
// stub's behavior from a host-target test.

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/services/waveform/wellen_provider_stub.dart';

void main() {
  group('WellenProvider stub (web no-op)', () {
    test('openFile throws UnsupportedError', () {
      final provider = WellenProvider();
      expect(
        () => provider.openFile('/any/path.vcd'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('loadSignal throws UnsupportedError', () {
      final provider = WellenProvider();
      expect(
        () => provider.loadSignal('0'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('close is a safe no-op', () {
      final provider = WellenProvider();
      expect(provider.close, returnsNormally);
    });

    test('hierarchy returns empty results', () {
      final provider = WellenProvider();
      expect(provider.rootScopes, isEmpty);
      expect(provider.findVariables(const SignalFilter()), isEmpty);
    });

    test('value queries return null/empty without throwing', () {
      final provider = WellenProvider();
      expect(provider.valueAt('0', 0), isNull);
      expect(provider.changesInRange('0', 0, 100), isEmpty);
      expect(provider.nextTransition('0', 0), isNull);
      expect(provider.prevTransition('0', 100), isNull);
      expect(provider.isSignalLoaded('0'), isFalse);
    });

    test('metadata returns null/zero defaults', () {
      final provider = WellenProvider();
      expect(provider.startTime, 0);
      expect(provider.endTime, 0);
      expect(provider.timescale, isNull);
      expect(provider.date, isNull);
      expect(provider.version, isNull);
    });

    test('diagnostic accessors return safe defaults', () async {
      final provider = WellenProvider();
      expect(provider.fileFormat, 'Unknown');
      expect(provider.totalTransitions, 0);
      expect(provider.signalTransitionCount('0'), 0);
      expect(await provider.memoryUsageBytes(), 0);
    });

    test('testing helpers are no-ops on the stub', () {
      final provider = WellenProvider();
      expect(
        () => provider.injectLoadedSignal('0', const <SignalChange>[]),
        returnsNormally,
      );
      expect(() => provider.injectHierarchy(const <Scope>[]), returnsNormally);
      // The stub's totalTransitions getter always returns 0; the io impl
      // computes it lazily from cached signal changes (no setter exposed
      // on either side).
      expect(provider.totalTransitions, 0);
    });
  });
}
