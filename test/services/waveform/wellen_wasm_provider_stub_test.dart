// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Tests the no-op stub class that backs WellenWasmProvider on every non-web
// host. The web implementation requires `dart:js_interop` and a browser
// runtime; the stub gives non-web build targets a place to import the class
// name without dragging in browser-only types.
//
// Imports the stub directly so the assertions run uniformly on every host
// regardless of how the conditional shim (`wellen_wasm_provider.dart`)
// resolves on the analyzer's current target.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/services/waveform/wellen_wasm_provider_stub.dart';

void main() {
  group('WellenWasmProvider stub (non-web no-op)', () {
    test('openFile throws UnsupportedError', () {
      final provider = WellenWasmProvider();
      expect(
        () => provider.openFile('/any/path.vcd'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('openBytes throws UnsupportedError', () {
      final provider = WellenWasmProvider();
      expect(
        () => provider.openBytes(Uint8List(0), 'dump.vcd'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('loadSignal throws UnsupportedError', () {
      final provider = WellenWasmProvider();
      expect(
        () => provider.loadSignal('0'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('close is a safe no-op', () {
      final provider = WellenWasmProvider();
      expect(provider.close, returnsNormally);
    });

    test('hierarchy returns empty results', () {
      final provider = WellenWasmProvider();
      expect(provider.rootScopes, isEmpty);
      expect(provider.findVariables(const SignalFilter()), isEmpty);
    });

    test('value queries return null/empty without throwing', () {
      final provider = WellenWasmProvider();
      expect(provider.valueAt('0', 0), isNull);
      expect(provider.changesInRange('0', 0, 100), isEmpty);
      expect(provider.nextTransition('0', 0), isNull);
      expect(provider.prevTransition('0', 100), isNull);
      expect(provider.isSignalLoaded('0'), isFalse);
    });

    test('metadata returns null/zero defaults', () {
      final provider = WellenWasmProvider();
      expect(provider.startTime, 0);
      expect(provider.endTime, 0);
      expect(provider.timescale, isNull);
      expect(provider.date, isNull);
      expect(provider.version, isNull);
    });

    test('diagnostic accessors return safe defaults', () async {
      final provider = WellenWasmProvider();
      expect(provider.fileFormat, 'Unknown');
      expect(provider.totalTransitions, 0);
      expect(provider.signalTransitionCount('0'), 0);
      expect(await provider.memoryUsageBytes(), 0);
    });

    test('isAvailable is false off web', () {
      expect(WellenWasmProvider.isAvailable, isFalse);
    });

    test('loadError is null on the stub', () {
      expect(WellenWasmProvider.loadError, isNull);
    });

    test('ensureInitialized completes without throwing on the stub', () async {
      // The stub is a no-op; callers reach it on non-web hosts where the
      // module is genuinely unavailable, so we model this as "completes" — it
      // is the caller's responsibility to check isAvailable afterwards.
      await expectLater(WellenWasmProvider.ensureInitialized(), completes);
    });

    test('testing helpers are no-ops on the stub', () {
      final provider = WellenWasmProvider();
      expect(
        () => provider.injectLoadedSignal('0', const <SignalChange>[]),
        returnsNormally,
      );
      expect(() => provider.injectHierarchy(const <Scope>[]), returnsNormally);
    });
  });
}
