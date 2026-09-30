// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/collaboration/providers/follow_detached_provider.dart';
import 'package:wavecrux/features/viewer/providers/lane_geometry_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';

part 'annotation_walkthrough_provider.g.dart';

/// Default pause between steps when the walkthrough plays itself.
///
/// Long enough to read a short note, short enough that a ten-note tour is not
/// a coffee break. Configurable per session because how long a note takes to
/// read is a property of the note, not of the app.
const Duration kWalkthroughDefaultDwell = Duration(seconds: 4);

/// Where the walkthrough currently is.
@immutable
class WalkthroughState {
  const WalkthroughState({
    this.focusedId,
    this.playing = false,
    this.dwell = kWalkthroughDefaultDwell,
    this.wrapped = false,
  });

  /// The annotation currently being shown, or null before the first step.
  final String? focusedId;

  final bool playing;
  final Duration dwell;

  /// True on the step that came back round to the start.
  ///
  /// Carried in the state rather than announced by the notifier because the
  /// notifier has no `BuildContext` and the indication belongs to whichever
  /// surface is driving — a snackbar from the shortcut handler, something
  /// quieter in the panel. Silence at the wrap is the thing to avoid: a user
  /// pressing `]` who lands back on note 1 with no signal reads it as the key
  /// having done nothing.
  final bool wrapped;

  WalkthroughState copyWith({
    String? focusedId,
    bool clearFocus = false,
    bool? playing,
    Duration? dwell,
    bool? wrapped,
  }) => WalkthroughState(
    focusedId: clearFocus ? null : (focusedId ?? this.focusedId),
    playing: playing ?? this.playing,
    dwell: dwell ?? this.dwell,
    wrapped: wrapped ?? this.wrapped,
  );

  @override
  bool operator ==(Object other) =>
      other is WalkthroughState &&
      other.focusedId == focusedId &&
      other.playing == playing &&
      other.dwell == dwell &&
      other.wrapped == wrapped;

  @override
  int get hashCode => Object.hash(focusedId, playing, dwell, wrapped);
}

/// Steps through the annotation set in time order, one note at a time.
///
/// This is what turns an annotated waveform into a **document someone else can
/// drive**: a reader who did not write the notes gets them in the order they
/// happened, each one centred, expanded and read in place. It is also, almost
/// verbatim, the interaction an EDU pack wants for a guided lab.
///
/// The `dependencies` list is mandatory rather than decorative — every read
/// below is per-tab, and Riverpod refuses the read without it. Same protection
/// the issue-#44 scope-leak guard gives statically.
@Riverpod(
  dependencies: [
    AnnotationsNotifier,
    annotationsInTimeOrder,
    AnnotationSelected,
    TimeMapperNotifier,
    WaveformScrollNotifier,
    laneGeometry,
  ],
)
class AnnotationWalkthrough extends _$AnnotationWalkthrough {
  Timer? _timer;

  /// The lane height the current playback was started with.
  ///
  /// Held rather than re-derived because the ticker has no `BuildContext` to
  /// ask for device metrics, and it only ever affects which row is scrolled
  /// to — never which annotation comes next.
  double _laneHeight = 24;

  @override
  WalkthroughState build() {
    ref.onDispose(() => _timer?.cancel());
    return const WalkthroughState();
  }

  // ── stepping ───────────────────────────────────────────────────────────────

  /// Moves to the next annotation in time order, wrapping past the end.
  bool next({required double minLaneHeight}) =>
      _step(1, minLaneHeight: minLaneHeight);

  /// Moves to the previous annotation, wrapping past the start.
  bool previous({required double minLaneHeight}) =>
      _step(-1, minLaneHeight: minLaneHeight);

  /// Focuses [id] directly — the panel's row tap, in walkthrough terms.
  bool focus(String id, {required double minLaneHeight}) {
    final ordered = ref.read(annotationsInTimeOrderProvider);
    final index = ordered.indexWhere((a) => a.id == id);
    if (index < 0) return false;
    _land(ordered[index], minLaneHeight: minLaneHeight, wrapped: false);
    return true;
  }

  bool _step(int direction, {required double minLaneHeight}) {
    final ordered = ref.read(annotationsInTimeOrderProvider);
    if (ordered.isEmpty) return false;

    final current = ordered.indexWhere((a) => a.id == state.focusedId);
    // No focus yet: `]` starts at the first note and `[` at the last, so
    // either key opens the tour from the end it points away from.
    final target = current < 0
        ? (direction > 0 ? 0 : ordered.length - 1)
        : (current + direction) % ordered.length;
    final wrapped =
        current >= 0 &&
        ((direction > 0 && target <= current) ||
            (direction < 0 && target >= current));

    _land(ordered[target], minLaneHeight: minLaneHeight, wrapped: wrapped);
    return true;
  }

  /// Centres a note, expands it, and folds the one we came from.
  void _land(
    Annotation annotation, {
    required double minLaneHeight,
    required bool wrapped,
  }) {
    final previousId = state.focusedId;
    final foldPrevious = previousId != null && previousId != annotation.id;

    // Collapse bookkeeping runs inside a transaction that is then CANCELLED,
    // so it mutates without recording. A walkthrough is reading, not editing:
    // stepping through ten notes must not leave twenty entries on the undo
    // stack between the user and their last real change.
    final notifier = ref.read(annotationsProvider.notifier)..beginTransaction();
    if (foldPrevious) notifier.setCollapsed(previousId, collapsed: true);
    notifier
      ..setCollapsed(annotation.id, collapsed: false)
      ..cancelTransaction();

    _centre(annotation.sortTime);
    _scrollRowIntoView(annotation.rowId, minLaneHeight: minLaneHeight);

    // Selecting it means the keyboard nudge and the panel agree with the tour
    // about which note is "the" one right now.
    ref.read(annotationSelectedProvider.notifier).selected = annotation.id;
    state = state.copyWith(focusedId: annotation.id, wrapped: wrapped);
  }

  /// Centres [time] at the current zoom — the same recipe the panel's row tap
  /// and `_jumpToPointer` use, so all three ways of reaching a note agree.
  ///
  /// Detaches soft-follow: driving the walkthrough is the local user reading
  /// at their own pace, and a presenter's viewport dragging them off the note
  /// they just stepped to would make the feature unusable mid-session.
  void _centre(int time) {
    final mapper = ref.read(timeMapperProvider);
    final width = mapper.visibleRange;
    if (width <= 0) return;
    final start = time - width ~/ 2;
    ref.read(timeMapperProvider.notifier).zoomToRange(start, start + width);
    ref.read(followDetachedProvider.notifier).detach();
  }

  /// Brings the annotated lane into the vertical viewport.
  ///
  /// A no-op for a full-height band, which belongs to no row, and for a row
  /// that is not displayed — the panel's "Show signal" is the affordance for
  /// that case, and silently scrolling to nothing would be worse than not
  /// scrolling.
  void _scrollRowIntoView(String? rowId, {required double minLaneHeight}) {
    if (rowId == null) return;
    final geometry = ref.read(
      laneGeometryProvider(LaneMetrics(minLaneHeight: minLaneHeight)),
    );
    for (final row in geometry.rows) {
      if (row.entry.signalPath != rowId) continue;
      ref.read(waveformScrollProvider.notifier).setOffset(row.top);
      return;
    }
  }

  // ── playback ───────────────────────────────────────────────────────────────

  /// Starts stepping automatically. Idempotent.
  void play({required double minLaneHeight}) {
    if (state.playing) return;
    _laneHeight = minLaneHeight;
    state = state.copyWith(playing: true);
    // Step immediately, then on the dwell. Waiting the full dwell before the
    // first move makes the control look broken.
    next(minLaneHeight: minLaneHeight);
    _restartTicker();
  }

  void _restartTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(state.dwell, (_) {
      if (!state.playing) return;
      next(minLaneHeight: _laneHeight);
    });
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    if (state.playing) state = state.copyWith(playing: false);
  }

  void toggle({required double minLaneHeight}) {
    if (state.playing) {
      pause();
    } else {
      play(minLaneHeight: minLaneHeight);
    }
  }

  /// Stops and forgets where the tour was.
  void stop() {
    pause();
    state = state.copyWith(clearFocus: true, wrapped: false);
  }

  void setDwell(Duration dwell) {
    if (dwell <= Duration.zero) return;
    state = state.copyWith(dwell: dwell);
    // Restart so a changed dwell takes effect now rather than after the
    // current one elapses.
    if (state.playing) _restartTicker();
  }
}
