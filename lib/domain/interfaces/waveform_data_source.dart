// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';

/// The central abstraction over a loaded waveform file.
///
/// Two concrete implementations exist:
/// - `WellenProvider` — wraps the wellen Rust library via FFI (desktop/mobile).
/// - `WellenWasmProvider` — wraps the same wellen Rust library compiled to
///   WebAssembly via wasm-bindgen (Flutter Web).
///
/// All time values are in simulation **ticks**; the physical duration of a
/// tick is given by [timescale]. Callers convert ticks ↔ real time using the
/// [Timescale] from the loaded file.
abstract class WaveformDataSource {
  // ── lifecycle ──────────────────────────────────────────────────────────────

  /// Open and parse a waveform file at [path].
  ///
  /// The hierarchy is fully available after this completes. Signal data is
  /// **not** loaded; call [loadSignal] to bring individual signals into memory.
  ///
  /// Throws if the file cannot be read or its format is unrecognised.
  Future<void> openFile(String path);

  /// Release all resources associated with the currently loaded file.
  void close();

  // ── hierarchy ──────────────────────────────────────────────────────────────

  /// The top-level scopes in the design hierarchy.
  ///
  /// Each [Scope] contains its direct [Scope.childScopes] and [Scope.variables];
  /// traverse recursively to walk the full tree.
  List<Scope> get rootScopes;

  /// Return all variables in the hierarchy that satisfy [filter].
  ///
  /// Searches across every scope. Pass [SignalFilter] with all-null fields
  /// (or `SignalFilter()`) to return every variable.
  List<Variable> findVariables(SignalFilter filter);

  // ── signal data (lazy loading) ─────────────────────────────────────────────

  /// Load the waveform data for [signalRef] into memory so that value queries
  /// can be answered.
  ///
  /// [signalRef] is [Variable.signalRef] obtained from the hierarchy.
  /// Calling this on an already-loaded signal is a no-op.
  Future<void> loadSignal(String signalRef);

  /// Returns `true` if the waveform data for [signalRef] is currently in
  /// memory (i.e. [loadSignal] has been called and not yet unloaded).
  bool isSignalLoaded(String signalRef);

  /// Unloads waveform data for [signalRef] from memory.
  ///
  /// After calling this, [isSignalLoaded] returns `false` and value queries
  /// return `null` until [loadSignal] is called again.  Calling on an already-
  /// unloaded signal is a no-op.  Implementations that cannot release memory
  /// (e.g. the pure-Dart web parser where all data lives in a shared map) may
  /// treat this as a no-op.
  Future<void> unloadSignal(String signalRef) async {}

  // ── value queries ──────────────────────────────────────────────────────────

  /// The raw value of [signalRef] at (or immediately before) simulation tick
  /// [time], returned as a bit-string (e.g. `"0"`, `"1"`, `"10xz"`, `"3.14"`).
  ///
  /// Returns `null` if the signal has no recorded value at or before [time]
  /// (i.e. [time] is before the first recorded transition), or if the signal
  /// is not loaded.
  String? valueAt(String signalRef, int time);

  /// All value changes for [signalRef] in the half-open interval
  /// `[start, end)`, ordered by ascending time.
  ///
  /// Returns an empty list if the signal is not loaded or has no changes in
  /// the range.
  List<SignalChange> changesInRange(String signalRef, int start, int end);

  /// The first value change for [signalRef] that occurs **strictly after**
  /// [afterTime].
  ///
  /// Returns `null` if there is no later transition or the signal is not
  /// loaded.
  SignalChange? nextTransition(String signalRef, int afterTime);

  /// The last value change for [signalRef] that occurs **strictly before**
  /// [beforeTime].
  ///
  /// Returns `null` if there is no earlier transition or the signal is not
  /// loaded.
  SignalChange? prevTransition(String signalRef, int beforeTime);

  // ── metadata ───────────────────────────────────────────────────────────────

  /// The earliest time in the waveform (typically 0).
  int get startTime;

  /// The latest time recorded in the waveform.
  int get endTime;

  /// The simulation timescale, or `null` if the file does not declare one.
  Timescale? get timescale;

  /// The `$date` declaration from the file header, or `null` if absent.
  String? get date;

  /// The `$version` declaration from the file header, or `null` if absent.
  String? get version;
}

/// Thrown by a [WaveformDataSource] when it fails to open a file.
///
/// [reason] is the underlying parser's own message — e.g. for a malformed
/// VCD, "expected an id for a value change". It is **not localized** (it
/// comes from the wellen engine in English); the viewer surfaces it
/// verbatim beneath a localized "couldn't load" title so the user can see
/// *why* the file was rejected. [toString] returns the bare reason (no
/// `Exception:` prefix) so an error UI that renders `error.toString()`
/// shows it cleanly.
class WaveformOpenException implements Exception {
  const WaveformOpenException(this.reason);

  /// The parser's human-readable reason for the open failure.
  final String reason;

  @override
  String toString() => reason;
}
