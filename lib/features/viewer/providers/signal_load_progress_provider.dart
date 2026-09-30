// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'signal_load_progress_provider.g.dart';

/// Which pipeline stage a bulk signal operation is in — drives the
/// indicator's tooltip wording ("Adding…" vs "Loading…").
enum SignalLoadPhase {
  /// Signal entries are being constructed and appended to the viewer list
  /// (the "Add All in Scope" entry-building stage).
  adding,

  /// Signal waveform data is being decompressed by the backend.
  loading,
}

/// Snapshot of an in-flight bulk signal operation (e.g. "Add All in Scope"
/// on a wide scope, or scrolling a large file so newly-visible lanes stream
/// in).
///
/// Producers publish progress here so the status bar can surface a
/// determinate indicator (and a cancel affordance) instead of the app looking
/// hung — first while a huge entry list is built ([SignalLoadPhase.adding]),
/// then while signals decompress ([SignalLoadPhase.loading]). When [active]
/// is false the pipeline is idle and the indicator hides.
@immutable
class SignalLoadProgressState {
  const SignalLoadProgressState({
    required this.loaded,
    required this.total,
    required this.active,
    required this.cancelRequested,
    this.phase = SignalLoadPhase.loading,
  });

  /// The idle state — nothing loading, indicator hidden.
  const SignalLoadProgressState.idle()
    : loaded = 0,
      total = 0,
      active = false,
      cancelRequested = false,
      phase = SignalLoadPhase.loading;

  /// Which pipeline stage is running — see [SignalLoadPhase].
  final SignalLoadPhase phase;

  /// Number of signals decompressed so far in the current batch.
  final int loaded;

  /// Total signals the current batch set out to load.
  final int total;

  /// Whether a bulk load is currently in progress.
  final bool active;

  /// Whether the user asked to cancel the current batch. The canvas checks
  /// this between load chunks and stops issuing further loads when set.
  final bool cancelRequested;

  /// Fraction in `[0, 1]`, or `null` when [total] is zero (indeterminate).
  double? get fraction => total <= 0 ? null : (loaded / total).clamp(0.0, 1.0);

  SignalLoadProgressState copyWith({
    int? loaded,
    int? total,
    bool? active,
    bool? cancelRequested,
    SignalLoadPhase? phase,
  }) => SignalLoadProgressState(
    loaded: loaded ?? this.loaded,
    total: total ?? this.total,
    active: active ?? this.active,
    cancelRequested: cancelRequested ?? this.cancelRequested,
    phase: phase ?? this.phase,
  );

  @override
  bool operator ==(Object other) =>
      other is SignalLoadProgressState &&
      other.loaded == loaded &&
      other.total == total &&
      other.active == active &&
      other.cancelRequested == cancelRequested &&
      other.phase == phase;

  @override
  int get hashCode =>
      Object.hash(loaded, total, active, cancelRequested, phase);
}

/// Tracks the progress of the canvas's bulk signal loading.
///
/// `keepAlive` because the canvas may be transiently rebuilt (pane reflow,
/// orientation change) while a load is mid-flight; the progress must survive
/// those rebuilds rather than resetting the indicator to idle.
@Riverpod(keepAlive: true)
class SignalLoadProgress extends _$SignalLoadProgress {
  @override
  SignalLoadProgressState build() => const SignalLoadProgressState.idle();

  /// Starts a new batch of [total] signals. Resets any prior cancel request.
  /// [phase] selects the indicator wording ("Adding…" vs "Loading…").
  void begin(int total, {SignalLoadPhase phase = SignalLoadPhase.loading}) {
    state = SignalLoadProgressState(
      loaded: 0,
      total: math.max(0, total),
      active: total > 0,
      cancelRequested: false,
      phase: phase,
    );
  }

  /// Starts a batch whose size is not known yet: the indicator shows
  /// indeterminate progress with no count until [begin] supplies a total.
  ///
  /// "Add All in Scope" arms this before walking the scope hierarchy, which on
  /// a gate-level netlist is itself long enough to look like a hang. Resets any
  /// prior cancel request, like [begin].
  void beginIndeterminate({SignalLoadPhase phase = SignalLoadPhase.loading}) {
    state = SignalLoadProgressState(
      loaded: 0,
      total: 0,
      active: true,
      cancelRequested: false,
      phase: phase,
    );
  }

  /// Records that [delta] more signals finished loading (clamped to [total]).
  void advance([int delta = 1]) {
    if (!state.active) return;
    state = state.copyWith(
      loaded: math.min(state.loaded + delta, state.total),
    );
  }

  /// Sets the absolute completed count (clamped to [total]). Used by the
  /// chunked entry-building phase, which reports running totals, not deltas.
  void setLoaded(int loaded) {
    if (!state.active) return;
    state = state.copyWith(loaded: loaded.clamp(0, state.total));
  }

  /// Requests cancellation of the in-flight batch. The producer (canvas) is
  /// responsible for observing [SignalLoadProgressState.cancelRequested] and
  /// stopping; this only flips the flag.
  void requestCancel() {
    if (state.active && !state.cancelRequested) {
      state = state.copyWith(cancelRequested: true);
    }
  }

  /// Marks the batch complete (or aborted) and hides the indicator.
  void finish() {
    if (state.active) state = const SignalLoadProgressState.idle();
  }

  /// [finish], but only when the active batch is still in [phase].
  ///
  /// The adding-phase hold and the loading-phase batch overlap around the
  /// frame that materializes a bulk add: the canvas's refresh can begin the
  /// loading batch before the add flow's end-of-frame hold releases, and an
  /// unconditional finish there would hide the loading indicator for the
  /// whole decompression pass. Phase-scoping the finish makes the handoff
  /// race-free regardless of which side completes first.
  void finishPhase(SignalLoadPhase phase) {
    if (state.active && state.phase == phase) {
      state = const SignalLoadProgressState.idle();
    }
  }
}
