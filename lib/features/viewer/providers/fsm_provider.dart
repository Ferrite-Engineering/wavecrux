// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/fsm_annotation.dart';
import 'package:wavecrux/domain/models/fsm_layout.dart';
import 'package:wavecrux/domain/models/fsm_model.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/translate_filter_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/collaboration/signal_identity_resolver.dart';
import 'package:wavecrux/services/signal_query/fsm_analysis_service.dart';
import 'package:wavecrux/services/signal_query/fsm_layout_service.dart';

part 'fsm_provider.g.dart';

// ── FsmState (provider state) ─────────────────────────────────────────────────

/// Immutable state held by [FsmNotifier].
@immutable
class FsmViewState {
  const FsmViewState({
    this.signalRef,
    this.model,
    this.layout,
    this.error,
    this.noWaveform = false,
  });

  /// Opaque ref of the signal currently being visualised, or null when no
  /// FSM panel is active.
  final String? signalRef;

  /// Computed FSM model. Null while loading or when [error] is set.
  final FsmModel? model;

  /// Computed layout for [model]. Null when [model] is null.
  final FsmLayout? layout;

  /// Human-readable error message from the last [FsmNotifier.analyzeSignal]
  /// failure, or null on success.
  ///
  /// Carries raw failure text (e.g. a signal-load exception string). The
  /// "no waveform loaded" guidance case is signalled via [noWaveform] so the
  /// panel can render a localized message instead of a hard-coded string.
  final String? error;

  /// True when FSM analysis was attempted with no waveform file loaded. The
  /// panel renders a localized guidance message for this case rather than the
  /// raw [error] string.
  final bool noWaveform;

  /// Whether an FSM analysis is being shown.
  bool get isActive => signalRef != null && model != null;

  FsmViewState copyWith({
    String? signalRef,
    FsmModel? model,
    FsmLayout? layout,
    String? error,
    bool? noWaveform,
    bool clearAll = false,
  }) => clearAll
      ? const FsmViewState()
      : FsmViewState(
          signalRef: signalRef ?? this.signalRef,
          model: model ?? this.model,
          layout: layout ?? this.layout,
          error: error,
          noWaveform: noWaveform ?? this.noWaveform,
        );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsmViewState &&
          runtimeType == other.runtimeType &&
          signalRef == other.signalRef &&
          model == other.model &&
          layout == other.layout &&
          error == other.error &&
          noWaveform == other.noWaveform;

  @override
  int get hashCode => Object.hash(signalRef, model, layout, error, noWaveform);

  @override
  String toString() =>
      'FsmViewState(signal: $signalRef, active: $isActive, error: $error, '
      'noWaveform: $noWaveform)';
}

// ── FsmAnnotationNotifier ─────────────────────────────────────────────────────

/// Manages user-supplied FSM state-name annotations, keyed by signal ref.
///
/// Annotations supplement (and take priority over) GTKWave translate filters
/// when the FSM model is built. This lets users mark any integer-valued
/// signal as an FSM and provide state names directly from the UI.
@Riverpod(keepAlive: true)
class FsmAnnotationNotifier extends _$FsmAnnotationNotifier {
  @override
  Map<String, FsmAnnotation> build() => const {};

  /// Sets an annotation for [signalRef], replacing any prior annotation.
  void setAnnotation(String signalRef, FsmAnnotation annotation) {
    state = Map<String, FsmAnnotation>.unmodifiable({
      ...state,
      signalRef: annotation,
    });
  }

  /// Sets the label for a single state id within [signalRef]'s annotation,
  /// preserving any other labels.
  ///
  /// Removes the entry when [label] is empty.
  void setStateLabel(String signalRef, String stateId, String label) {
    final existing = state[signalRef]?.stateLabels ?? const <String, String>{};
    final updated = Map<String, String>.from(existing);
    if (label.isEmpty) {
      updated.remove(stateId);
    } else {
      updated[stateId] = label;
    }
    if (updated.isEmpty) {
      removeAnnotation(signalRef);
      return;
    }
    setAnnotation(
      signalRef,
      FsmAnnotation(signalRef: signalRef, stateLabels: updated),
    );
  }

  /// Removes [signalRef]'s annotation entirely.
  void removeAnnotation(String signalRef) {
    if (!state.containsKey(signalRef)) return;
    final next = Map<String, FsmAnnotation>.from(state)..remove(signalRef);
    state = Map<String, FsmAnnotation>.unmodifiable(next);
  }

  /// Returns the annotation for [signalRef], or null if none.
  FsmAnnotation? getAnnotation(String signalRef) => state[signalRef];

  /// Removes every annotation; used when a new file is loaded.
  void clearAll() {
    state = const {};
  }

  /// Replaces all annotations with those persisted in a session. Used by
  /// [SessionNotifier] restore so FSM state-name annotations survive a
  /// `.wavecrux` save / re-open. An empty map clears the annotations.
  void restoreFromSession(Map<String, FsmAnnotation> annotations) {
    state = Map<String, FsmAnnotation>.unmodifiable(annotations);
  }
}

// ── FsmNotifier ───────────────────────────────────────────────────────────────

/// Manages the active FSM visualisation: which signal is being shown and the
/// computed model + layout.
///
/// Call [analyzeSignal] to compute and display an FSM for a signal. Call
/// [clearFsm] to dismiss it.
@Riverpod(keepAlive: true)
class FsmNotifier extends _$FsmNotifier {
  static const _analysisService = FsmAnalysisService();
  static const _layoutService = FsmLayoutService();

  @override
  FsmViewState build() => const FsmViewState();

  /// Builds the FSM model for [signalRef] over the full simulation range,
  /// applies any active translate filter and user annotation, and stores
  /// the result in state.
  Future<void> analyzeSignal(String signalRef) async {
    final source = ref.read(waveformSourceProvider).value;
    if (source == null) {
      state = const FsmViewState(noWaveform: true);
      return;
    }

    final variablesMap = ref.read(signalVariablesMapProvider);
    final variable = variablesMap[signalRef];
    final signalPath = variable?.fullPath ?? signalRef;

    if (!source.isSignalLoaded(signalRef)) {
      try {
        await source.loadSignal(signalRef);
      } on Object catch (e) {
        if (!ref.mounted) return;
        state = FsmViewState(
          signalRef: signalRef,
          error: e.toString(),
        );
        return;
      }
    }

    // `loadSignal` above is async and can span a tab close; Riverpod 3
    // disposes the notifier eagerly, so a later `state` write would throw
    // `UnmountedRefException`.
    if (!ref.mounted) return;

    final translateFilter = ref.read(translateFilterProvider)[signalRef];
    final annotation = ref.read(fsmAnnotationProvider)[signalRef];

    final model = _analysisService.buildModel(
      signalRef: signalRef,
      signalPath: signalPath,
      source: source,
      startTime: source.startTime,
      endTime: source.endTime,
      annotation: annotation,
      translateFilter: translateFilter,
    );

    final layout = _layoutService.compute(model);

    state = FsmViewState(
      signalRef: signalRef,
      model: model,
      layout: layout,
    );
  }

  /// Re-runs analysis for the currently selected signal, picking up any
  /// changed annotations or filters.
  Future<void> refresh() async {
    final ref = state.signalRef;
    if (ref == null) return;
    await analyzeSignal(ref);
  }

  /// Dismisses the active FSM and resets to idle.
  void clearFsm() {
    state = const FsmViewState();
  }

  // ── view-composition recipe seams ──────────────────────────────────

  /// Serialize the FSM viewer target into a **signal-identity-based** recipe:
  /// the canonical path of the analysed signal, or `null` when the FSM viewer
  /// is closed. The computed model/layout never travel — the follower
  /// recomputes them locally from its own data.
  String? toCompositionRecipe(SignalIdentityResolver resolver) {
    final ref = state.signalRef;
    if (ref == null) return null;
    return resolver.pathForRef(ref);
  }

  /// Apply a presenter's FSM [targetPath]: re-resolve it to the follower's
  /// local `signalRef` via [resolver] and analyse it, or [clearFsm] when the
  /// presenter has no FSM open. Returns `[targetPath]` when the path matches no
  /// local variable (missing-reference degradation), in which case the FSM
  /// viewer is closed rather than analysing a stale ref.
  List<String> applyCompositionRecipe(
    String? targetPath,
    SignalIdentityResolver resolver,
  ) {
    if (targetPath == null) {
      clearFsm();
      return const [];
    }
    final ref = resolver.refForPath(targetPath);
    if (ref == null) {
      clearFsm();
      return [targetPath];
    }
    unawaited(analyzeSignal(ref));
    return const [];
  }

  /// Moves the primary cursor to the first time [stateId] was entered.
  ///
  /// Returns true on success; false if the state has no recorded entry
  /// time (e.g. it appears only as the initial value at t=0 with no
  /// transition into it during the analysis range).
  bool jumpToFirstOccurrence(String stateId) {
    final model = state.model;
    if (model == null) return false;
    final fsmState = model.stateById(stateId);
    final time = fsmState?.firstEntryTime;
    if (time == null) return false;
    ref.read(cursorStateProvider.notifier).placePrimary(time);
    ref.read(navigationProvider.notifier).jumpToTime(time);
    return true;
  }
}

// ── derived providers ─────────────────────────────────────────────────────────

/// The state id currently active at the primary cursor position, or null
/// when no cursor is set, no FSM is active, or the signal is x/z at that
/// time.
///
/// Used by the bubble diagram widget to highlight the current state.
@riverpod
String? fsmCurrentStateId(Ref ref) {
  final fsm = ref.watch(fsmProvider);
  if (!fsm.isActive) return null;
  final cursor = ref.watch(cursorStateProvider).primaryCursorTime;
  if (cursor == null) return null;
  final source = ref.watch(waveformSourceProvider).value;
  if (source == null) return null;
  return const FsmAnalysisService().stateIdAt(
    signalRef: fsm.signalRef!,
    source: source,
    time: cursor,
  );
}

/// The most recent transition (from-id, to-id) that occurred at or before
/// the primary cursor, or null when no recent transition can be identified.
///
/// Used by the bubble diagram widget to briefly highlight the active edge.
@riverpod
({String fromId, String toId})? fsmRecentTransition(
  Ref ref,
) {
  final fsm = ref.watch(fsmProvider);
  final model = fsm.model;
  if (model == null) return null;
  final cursor = ref.watch(cursorStateProvider).primaryCursorTime;
  if (cursor == null) return null;

  // Find the latest transition whose time is ≤ cursor.
  String? fromId;
  String? toId;
  var bestTime = -1;
  for (final t in model.transitions) {
    for (final time in t.times) {
      if (time > cursor) break; // times are sorted ascending
      if (time >= bestTime) {
        bestTime = time;
        fromId = t.fromId;
        toId = t.toId;
      }
    }
  }
  if (fromId == null || toId == null) return null;
  return (fromId: fromId, toId: toId);
}
