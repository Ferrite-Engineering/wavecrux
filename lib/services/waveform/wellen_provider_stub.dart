// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Web / non-`dart:io` no-op implementation of [WellenProvider].
//
// Constructor parameters mirror the desktop implementation so callers
// can instantiate the same way on every platform; on Web they are
// accepted and ignored because `dart:ffi` (and therefore the wellen
// Rust FFI backend) is unavailable.
//
// Per WaveCrux's architecture, web builds use [WellenWasmProvider]
// (the same wellen crate compiled to WebAssembly via wasm-bindgen) for
// every waveform load. Consumers that mention [WellenProvider] gate
// their use behind a `kIsWeb` runtime check and never construct or
// call the stub in production. The stub exists only so that the rest
// of the app can name [WellenProvider] uniformly across all build
// targets without `dart:ffi` import errors on web.
//
// ignore_for_file: avoid_unused_constructor_parameters

import 'package:flutter/foundation.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/waveform/wellen_isolate_orchestrator.dart';

/// Web stub for [WellenProvider]. Every method throws [UnsupportedError]
/// because `dart:ffi` is unavailable on web. Production code never
/// reaches these throws — the architecture mandates [WellenWasmProvider]
/// on web, and consumers gate construction behind `kIsWeb` checks.
class WellenProvider implements WaveformDataSource {
  /// Stub constructor. Accepts the same arguments as the desktop
  /// implementation so callers can instantiate the same way on every
  /// platform; on web every argument is ignored.
  WellenProvider({Duration? openTimeout, IsolateSpawner? spawner});

  static const Duration defaultOpenTimeout = Duration(seconds: 30);

  /// Mirrors the io implementation's deadline cap.
  static const Duration maxOpenTimeout = Duration(minutes: 10);

  /// Mirrors the io implementation's size-scaled open watchdog:
  /// 30 s base + 1 s per MB, capped at [maxOpenTimeout]. Kept in sync so the
  /// analyzer (which resolves the conditional export to this stub) and any
  /// platform-agnostic caller see one behavior.
  static Duration scaledOpenTimeout(int sizeBytes) {
    final scaled = defaultOpenTimeout.inSeconds + sizeBytes ~/ (1024 * 1024);
    final capped = scaled > maxOpenTimeout.inSeconds
        ? maxOpenTimeout.inSeconds
        : scaled;
    return Duration(seconds: capped);
  }

  static Never _unsupported() => throw UnsupportedError(
    'WellenProvider is not available on web. '
    'Use WellenWasmProvider instead.',
  );

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

  /// Mirrors the FFI-only diagnostic accessor on the io implementation.
  /// Returns 'Unknown' on web.
  String get fileFormat => 'Unknown';

  /// Mirrors the FFI-only diagnostic accessor on the io implementation.
  /// Returns 0 on web.
  int get totalTransitions => 0;

  /// Mirrors the FFI-only diagnostic accessor on the io implementation.
  /// Returns 0 on web.
  int signalTransitionCount(String signalRef) => 0;

  /// Mirrors the FFI-only diagnostic accessor on the io implementation.
  /// Returns 0 on web.
  Future<int> memoryUsageBytes() async => 0;

  // ── Testing helpers (mirrored from io implementation) ───────────────────────
  //
  // These exist so the analyzer — which resolves the conditional export to
  // this stub when no platform is specified — recognises the same public
  // testing surface as the io class. They are no-ops here because tests that
  // exercise the wellen path are gated behind `@TestOn('vm')` / runtime
  // platform checks and never run against the stub.

  /// Stub equivalent of the io implementation's testing helper. No-op.
  @visibleForTesting
  void injectLoadedSignal(String signalRef, List<SignalChange> changes) {}

  /// Stub equivalent of the io implementation's testing helper. No-op.
  @visibleForTesting
  void injectHierarchy(List<Scope> scopes) {}
}
