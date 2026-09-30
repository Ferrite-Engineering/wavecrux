// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Non-web stub for [WellenWasmProvider].
//
// The WASM-backed provider exists only on Flutter Web; on every other host
// the architecture mandates [WellenProvider] (Rust FFI via dart:ffi). This
// stub gives non-web build targets a place to import the class name so the
// conditional export shim resolves cleanly, but every constructor and method
// throws `UnsupportedError`. Production code never instantiates this — the
// `WaveformSourceNotifier` gates its call behind a `kIsWeb` runtime check.
//
// Mirrors the pattern in [wellen_provider_stub.dart].

import 'package:flutter/foundation.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';

/// Non-web stub for [WellenWasmProvider]. Every method throws
/// [UnsupportedError] because WebAssembly + js_interop are unavailable
/// off the web. Production code never reaches these throws — the
/// architecture mandates [WellenProvider] on desktop/mobile.
class WellenWasmProvider implements WaveformDataSource {
  WellenWasmProvider();

  static Never _unsupported() => throw UnsupportedError(
    'WellenWasmProvider is only available on Flutter Web. '
    'Use WellenProvider on desktop and mobile.',
  );

  /// Eagerly initialize the underlying WebAssembly module. No-op on non-web.
  static Future<void> ensureInitialized() async {
    // No-op: on non-web hosts the wasm module is not available.
  }

  /// Whether the WebAssembly module has been loaded and is callable.
  ///
  /// Always `false` off the web — the stub has no underlying module.
  static bool get isAvailable => false;

  /// Last load error, if any. Always `null` on the stub.
  static Object? get loadError => null;

  /// Open a waveform from raw [bytes].
  ///
  /// [displayName] supplies the filename used for format detection.
  Future<void> openBytes(Uint8List bytes, String displayName) => _unsupported();

  @override
  Future<void> openFile(String path) => _unsupported();

  @override
  void close() {}

  @override
  List<Scope> get rootScopes => const [];

  @override
  List<Variable> findVariables(SignalFilter filter) => const [];

  @override
  Future<void> loadSignal(String signalRef) => _unsupported();

  @override
  bool isSignalLoaded(String signalRef) => false;

  @override
  Future<void> unloadSignal(String signalRef) async {}

  @override
  String? valueAt(String signalRef, int time) => null;

  @override
  List<SignalChange> changesInRange(String signalRef, int start, int end) =>
      const [];

  @override
  SignalChange? nextTransition(String signalRef, int afterTime) => null;

  @override
  SignalChange? prevTransition(String signalRef, int beforeTime) => null;

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

  /// Diagnostic accessor mirroring the web implementation.
  String get fileFormat => 'Unknown';

  /// Diagnostic accessor mirroring the web implementation.
  int get totalTransitions => 0;

  /// Diagnostic accessor mirroring the web implementation.
  int signalTransitionCount(String signalRef) => 0;

  /// Diagnostic accessor mirroring the web implementation.
  Future<int> memoryUsageBytes() async => 0;

  // ── Testing helpers (mirrored from the web implementation) ───────────────
  //
  // These exist so the analyzer — which resolves the conditional export to
  // this stub when no `dart.library.js_interop` is available — recognizes the
  // same public testing surface as the web class.

  /// ABI version the wrapper was built against. Mirrors the web constant so
  /// tests referencing it analyze cleanly off the web.
  @visibleForTesting
  static const int expectedAbiVersion = 1;

  /// Force-resets the static init state. No-op on the stub — there is no
  /// module to reload. Mirrors the web helper so the WASM-load-failure web
  /// test (`@TestOn('browser')`) analyzes cleanly on the VM runner.
  @visibleForTesting
  static void resetInitForTests() {}

  @visibleForTesting
  void injectLoadedSignal(String signalRef, List<SignalChange> changes) {}

  @visibleForTesting
  void injectHierarchy(List<Scope> scopes) {}
}
