// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/annotations/providers/session_annotations_provider.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/lane_geometry_provider.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/annotations/annotation_anchor_resolver.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';

part 'annotation_authoring_provider.g.dart';

/// The annotation currently being typed, if any.
///
/// Creation is deliberately two-phase: the annotation is added to the list
/// immediately (so it draws, and so undo has something to reverse) and this
/// provider names the one whose text field has focus. An empty-bodied callout
/// that is dismissed rather than committed is removed again, so an accidental
/// right-click leaves nothing behind.
/// **keepAlive**, and that is load-bearing rather than tidiness. The canvas
/// writes this the instant it creates a note, at which point nothing is
/// watching it yet — the overlay only starts watching on its next build. An
/// auto-dispose provider throws that write away between the two, and the
/// editor never opens.
@Riverpod(keepAlive: true)
class AnnotationBeingEdited extends _$AnnotationBeingEdited {
  @override
  String? build() => null;

  /// The annotation whose text field currently has focus, if any.
  String? get editing => state;

  set editing(String? id) => state = id;

  void end() => state = null;
}

/// True while a pointer is down on an annotation affordance.
///
/// Exists because `WaveformGestureHandler` wraps the whole canvas *including*
/// the annotation overlay, and it drives cursor placement from a raw
/// [Listener]. A `Listener` is not a gesture recognizer: it fires for every
/// pointer event in its subtree no matter what a descendant `GestureDetector`
/// does with them, so dragging a balloon also dragged the primary cursor.
///
/// Pointer events dispatch deepest-first, so the balloon sets this before the
/// ancestor handler sees the same event, and the handler stands down for the
/// rest of the sequence.
/// **keepAlive** for the same reason as [AnnotationBeingEdited], and here the
/// consequence was the visible bug: the balloon set the claim, nothing was
/// listening, the provider disposed, and the gesture handler's read rebuilt a
/// fresh `false`. So dragging a note kept dragging the cursor even though the
/// hand-off looked correct — and it passed in tests, because the harness held
/// a listener that production does not.
@Riverpod(keepAlive: true)
class AnnotationGestureActive extends _$AnnotationGestureActive {
  @override
  bool build() => false;

  /// Whether an annotation is currently taking a pointer sequence.
  bool get active => state;

  set active(bool value) => state = value;
}

/// The annotation the user is currently working on, if any.
///
/// Selection exists for the keyboard: nudging an anchor needs a subject, and
/// "the one you last touched" is the only answer that does not require a second
/// pointer gesture to establish it. It is deliberately *not* persisted — a
/// selection is a moment in an editing session, not part of the document.
///
/// **keepAlive** for the same reason as [AnnotationBeingEdited]: the canvas
/// writes it on pointer-down, before the overlay's next build subscribes.
@Riverpod(keepAlive: true)
class AnnotationSelected extends _$AnnotationSelected {
  @override
  String? build() => null;

  String? get selected => state;

  set selected(String? id) => state = id;

  void clear() => state = null;
}

/// Whether a new anchor snaps to the nearest transition.
///
/// Per-tab rather than a global setting: it is a property of how you are
/// reading *this* waveform, and a user who turns it off to place a note
/// mid-plateau should not have it off in the next file they open.
@riverpod
class AnnotationSnapEnabled extends _$AnnotationSnapEnabled {
  @override
  bool build() => true;

  /// Whether a new anchor snaps to the nearest transition.
  bool get enabled => state;

  set enabled(bool value) => state = value;

  void toggle() => state = !state;
}

/// Creates annotations from the viewer's live state.
///
/// Every entry point — canvas right-click, the keyboard shortcut, the
/// two-cursor range — funnels through here so they cannot drift apart in which
/// anchor they compute or whether they capture a witness.
///
/// The `dependencies` list is mandatory, not decorative: every provider read
/// below is scoped per-tab, and Riverpod refuses the read without it. That
/// refusal is the same protection the issue-#44 scope-leak guard gives
/// statically — a creator that resolved anchors against the root container
/// would compute them from another tab's waveform.
@Riverpod(
  dependencies: [
    laneGeometry,
    TimeMapperNotifier,
    WaveformSourceNotifier,
    CursorStateNotifier,
    NavigationNotifier,
    AnnotationsNotifier,
    AnnotationSnapEnabled,
    annotationAuthorName,
    signalVariablesMap,
    signalVariablesByPath,
  ],
)
class AnnotationAuthoring extends _$AnnotationAuthoring {
  @override
  void build() {}

  static const _uuid = Uuid();
  static const _resolver = AnnotationAnchorResolver();
  static const _witnessService = AnnotationWitnessService();

  /// Creates a callout at a canvas position, returning its id, or `null` when
  /// the position does not land on an annotatable row.
  ///
  /// [snapOverride] forces snapping on or off for this one call — the modifier
  /// held during the gesture — leaving the persisted preference alone.
  String? createAtPosition({
    required double dx,
    required double dy,
    required double scrollOffset,
    required double minLaneHeight,
    AnnotationShape shape = AnnotationShape.callout,
    bool? snapOverride,
  }) {
    final resolved = _resolve(
      dx: dx,
      dy: dy,
      scrollOffset: scrollOffset,
      minLaneHeight: minLaneHeight,
      snapOverride: snapOverride,
    );
    if (resolved == null) return null;
    return _create(
      anchor: resolved.toAnchor(),
      shape: shape,
      signalRef: resolved.signalRef,
      time: resolved.time,
    );
  }

  /// Creates a callout at the primary cursor on [rowId] — the keyboard path.
  ///
  /// Returns `null` when no cursor is placed or the row is not displayed,
  /// which the caller surfaces rather than silently doing nothing.
  String? createAtCursor({
    required String rowId,
    required double minLaneHeight,
    AnnotationShape shape = AnnotationShape.callout,
  }) {
    final time = ref.read(cursorStateProvider).primaryCursorTime;
    if (time == null) return null;

    final geometry = ref.read(
      laneGeometryProvider(LaneMetrics(minLaneHeight: minLaneHeight)),
    );
    String? signalRef;
    for (final row in geometry.rows) {
      if (row.entry.signalPath == rowId) {
        signalRef = row.entry.signalRef;
        break;
      }
    }
    if (signalRef == null) return null;

    return _create(
      anchor: PointAnchor(time: time, rowId: rowId),
      shape: shape,
      signalRef: signalRef,
      time: time,
    );
  }

  /// The tick range a band would span right now, or `null` when there is none.
  ///
  /// **The Shift-drag selection wins over the cursors.** WaveCrux already has a
  /// region gesture — Shift+drag paints a grey zone and feeds
  /// zoom-to-selection — and "annotate this region" is the same question asked
  /// of the same shape. Making the band read from somewhere else would give
  /// the app two different answers to "which range do you mean", one of them
  /// invisible.
  ///
  /// The two cursors remain the fallback, because a range you measured with
  /// cursors is still a range, and the delta readout in the status bar is
  /// where a lot of them come from.
  (int, int)? bandRange() {
    final selection = ref.read(navigationProvider)?.normalized();
    if (selection != null && !selection.isEmpty) {
      return (selection.startTime, selection.endTime);
    }
    final cursor = ref.read(cursorStateProvider);
    final a = cursor.primaryCursorTime;
    final b = cursor.secondaryCursorTime;
    if (a == null || b == null || a == b) return null;
    return (a, b);
  }

  /// Creates a band over [bandRange], pre-filled with the measured delta so the
  /// common case needs no typing.
  ///
  /// [rowId] confines the band to one lane; `null` spans the whole canvas.
  /// Full-height is the default because the common case — "this whole
  /// transaction is wrong" — is about a window of time rather than about one
  /// signal, and a band that silently attached itself to whichever lane
  /// happened to be selected would be a surprise the user has to undo.
  ///
  /// Returns `null` when there is no range — no drag selection and fewer than
  /// two distinct cursors.
  String? createRangeFromCursors({String? label, String? rowId}) {
    final range = bandRange();
    if (range == null) return null;
    final (a, b) = range;

    final id = _uuid.v4();
    ref
        .read(annotationsProvider.notifier)
        .add(
          Annotation(
            id: id,
            shape: AnnotationShape.band,
            anchor: RangeAnchor(startTime: a, endTime: b, rowId: rowId),
            authorName: _authorName(),
            createdAt: _now(),
            text: label ?? '',
          ),
        );
    return id;
  }

  /// Moves an annotation's anchor by one tick, or onto the adjacent
  /// transition, and re-captures its witness.
  ///
  /// [direction] is -1 for earlier and +1 for later. [toEdge] steps to the next
  /// transition on the annotated signal instead of by a single tick — the
  /// useful granularity at any zoom where one tick is a fraction of a pixel.
  ///
  /// Re-capturing the witness is not optional. The witness records what the
  /// signal read *at the anchored tick*; move the anchor and leave the witness,
  /// and the note reports drift the instant it is nudged — which would make the
  /// drift badge mean "somebody adjusted this" rather than "the design
  /// changed", and that is the whole feature.
  ///
  /// A band translates: both ends move together, because a band's anchor is the
  /// window, not either edge. Dragging an edge is the affordance for changing
  /// the window's width.
  ///
  /// Returns true when something moved.
  bool nudgeAnchor(
    String id, {
    required int direction,
    required bool toEdge,
  }) {
    final notifier = ref.read(annotationsProvider.notifier);
    Annotation? target;
    for (final annotation in notifier.snapshot()) {
      if (annotation.id == id) {
        target = annotation;
        break;
      }
    }
    if (target == null || direction == 0) return false;

    final anchor = target.anchor;
    final rowId = target.rowId;
    final signalRef = rowId == null ? null : _signalRefForRow(rowId);

    switch (anchor) {
      case PointAnchor(:final time, rowId: final anchorRow):
        final next = _stepTime(
          from: time,
          direction: direction,
          toEdge: toEdge,
          signalRef: signalRef,
        );
        if (next == null || next == time) return false;
        notifier.updateById(
          id,
          (a) => a.copyWith(
            anchor: PointAnchor(time: next, rowId: anchorRow),
            witness: signalRef == null
                ? null
                : _captureWitness(signalRef: signalRef, time: next),
            clearWitness: signalRef == null,
          ),
        );
        return true;

      case RangeAnchor(:final startTime, :final endTime, rowId: final bandRow):
        final next = _stepTime(
          from: startTime,
          direction: direction,
          toEdge: toEdge,
          signalRef: signalRef,
        );
        if (next == null || next == startTime) return false;
        final shift = next - startTime;
        notifier.updateById(
          id,
          (a) => a.copyWith(
            anchor: RangeAnchor(
              startTime: startTime + shift,
              endTime: endTime + shift,
              rowId: bandRow,
            ),
          ),
        );
        return true;
    }
  }

  /// Moves an annotation's anchor to an exact tick, re-capturing its witness.
  ///
  /// The precision affordance the ⌥-arrow nudge cannot be: at a zoom where one
  /// tick is a fraction of a pixel, stepping to a known tick by eye is not
  /// something anyone manages, and typing the number is.
  ///
  /// **Re-capturing the witness is the whole trap here**, and it is the same
  /// one [nudgeAnchor] documents: the witness records what the signal read *at
  /// the anchored tick*, so moving the anchor and leaving the witness makes the
  /// note report drift the instant it is adjusted — and the drift badge stops
  /// meaning "the design changed", which is the feature.
  ///
  /// A band translates, keeping its width: a band's anchor is the window, and
  /// dragging an edge is the affordance for changing its width.
  ///
  /// Returns **the tick the anchor now sits at**, already clamped, or `null`
  /// when there is nothing to move.
  ///
  /// Returning the landing tick rather than a bare "did it move" is the point.
  /// The caller's next act is to show the user the result, and the only tick it
  /// otherwise has is the one that was typed — so a value past the end of the
  /// trace clamped the anchor to the last tick and then sent the viewport to
  /// tick 10000, where there is no data and no note. The note had moved
  /// correctly; it had simply been left off-screen, which reads as the note
  /// having been destroyed.
  ///
  /// The tick comes back even when nothing moved, for the same reason: typing a
  /// number and getting no response at all is how a clamp onto the position the
  /// anchor already held presents itself.
  int? setAnchorTime(String id, int time) {
    final notifier = ref.read(annotationsProvider.notifier);
    Annotation? target;
    for (final annotation in notifier.snapshot()) {
      if (annotation.id == id) {
        target = annotation;
        break;
      }
    }
    if (target == null) return null;

    final source = ref.read(waveformSourceProvider).value;
    if (source == null) return null;
    // Clamped rather than refused: a tick past the end of the trace is a typo,
    // and silently doing nothing reads as a broken field.
    final clamped = time.clamp(source.startTime, source.endTime);

    final rowId = target.rowId;
    final signalRef = rowId == null ? null : _signalRefForRow(rowId);

    switch (target.anchor) {
      case PointAnchor(time: final current, rowId: final anchorRow):
        if (clamped == current) return clamped;
        notifier.updateById(
          id,
          (a) => a.copyWith(
            anchor: PointAnchor(time: clamped, rowId: anchorRow),
            witness: signalRef == null
                ? null
                : _captureWitness(signalRef: signalRef, time: clamped),
            clearWitness: signalRef == null,
          ),
        );
        return clamped;

      case RangeAnchor(:final startTime, :final endTime, rowId: final bandRow):
        if (clamped == startTime) return clamped;
        final shift = clamped - startTime;
        notifier.updateById(
          id,
          (a) => a.copyWith(
            anchor: RangeAnchor(
              startTime: startTime + shift,
              endTime: endTime + shift,
              rowId: bandRow,
            ),
          ),
        );
        return clamped;
    }
  }

  /// One tick, or the next transition on [signalRef], clamped to the trace.
  int? _stepTime({
    required int from,
    required int direction,
    required bool toEdge,
    required String? signalRef,
  }) {
    final source = ref.read(waveformSourceProvider).value;
    if (source == null) return null;

    if (toEdge && signalRef != null) {
      final change = direction > 0
          ? source.nextTransition(signalRef, from)
          : source.prevTransition(signalRef, from);
      // No transition that way: hold position rather than silently falling back
      // to a one-tick step, which would look like the key did something
      // different from what it says.
      return change?.time;
    }
    final candidate = from + direction;
    if (candidate < source.startTime || candidate > source.endTime) return null;
    return candidate;
  }

  /// The backend ref for a row's stable path — the same lookup
  /// `annotationStatuses` uses, so a nudge and a drift check can never disagree
  /// about which signal a note is attached to.
  String? _signalRefForRow(String rowId) =>
      ref.read(signalVariablesByPathProvider)[rowId]?.signalRef;

  /// Deletes [id], and reports whether anything was removed so the caller can
  /// decide whether to offer an undo.
  bool delete(String id) {
    final notifier = ref.read(annotationsProvider.notifier);
    final before = notifier.snapshot().length;
    notifier.remove(id);
    return notifier.snapshot().length != before;
  }

  /// Copies an adopted annotation into the user's own notes, editable and
  /// signed by them.
  ///
  /// The escape hatch that makes read-only attribution tolerable. Somebody
  /// else's words stay theirs — but "I agree with this and want to build on it"
  /// is a real thing to want, and the honest way to allow it is a *new* note
  /// with a new author rather than an edit under the original name.
  ///
  /// The copy leaves the layer (`clearLayer`) and drops the frozen session
  /// colour, so it renders as what it now is: one of yours.
  ///
  /// Returns the new id, or `null` when [id] names nothing.
  String? duplicateAsMine(String id) {
    final notifier = ref.read(annotationsProvider.notifier);
    // Local first, then the room — and the room is consulted only if the local
    // search missed. Duplicating is the escape hatch for a note you may not
    // edit, and in a live session those are precisely the notes that are NOT
    // local, so searching only the local store made the action fail exactly
    // where it was needed. An adopted note IS local, so it resolves without
    // reaching for session state at all.
    Iterable<Annotation> candidates() sync* {
      yield* notifier.snapshot();
      yield* ref.read(composedAnnotationsProvider);
    }

    for (final annotation in candidates()) {
      if (annotation.id != id) continue;
      final copy = annotation.copyWith(
        id: _uuid.v4(),
        authorName: _authorName(),
        createdAt: _now(),
        clearLayer: true,
        clearColor: true,
      );
      notifier.add(copy);
      return copy.id;
    }
    return null;
  }

  /// Removes an annotation abandoned without text — an accidental right-click
  /// must not leave an empty balloon on the canvas.
  ///
  /// Only callouts are dropped: an arrow legitimately carries no text.
  void discardIfEmpty(String id) {
    final notifier = ref.read(annotationsProvider.notifier);
    for (final annotation in notifier.snapshot()) {
      if (annotation.id != id) continue;
      if (annotation.shape != AnnotationShape.arrow && !annotation.hasText) {
        notifier.remove(id);
      }
      return;
    }
  }

  ResolvedAnchor? _resolve({
    required double dx,
    required double dy,
    required double scrollOffset,
    required double minLaneHeight,
    bool? snapOverride,
  }) {
    final geometry = ref.read(
      laneGeometryProvider(LaneMetrics(minLaneHeight: minLaneHeight)),
    );
    return _resolver.resolve(
      position: Offsetish(dx, dy),
      mapper: ref.read(timeMapperProvider),
      geometry: geometry,
      scrollOffset: scrollOffset,
      source: ref.read(waveformSourceProvider).value,
      snapToEdges: snapOverride ?? ref.read(annotationSnapEnabledProvider),
    );
  }

  String _create({
    required AnnotationAnchor anchor,
    required AnnotationShape shape,
    required String signalRef,
    required int time,
  }) {
    final id = _uuid.v4();
    ref
        .read(annotationsProvider.notifier)
        .add(
          Annotation(
            id: id,
            shape: shape,
            anchor: anchor,
            authorName: _authorName(),
            createdAt: _now(),
            witness: _captureWitness(signalRef: signalRef, time: time),
          ),
        );
    return id;
  }

  /// Reads what the signal is doing right now, so the note can later tell its
  /// reader whether that is still true.
  AnnotationWitness? _captureWitness({
    required String signalRef,
    required int time,
  }) {
    final source = ref.read(waveformSourceProvider).value;
    if (source == null) return null;

    // Width comes from the hierarchy rather than the row, because a row can be
    // displayed before its metadata resolves and a wrong width would pad the
    // canonical bits incorrectly — which reads as drift forever after.
    final variable = ref
        .read(signalVariablesMapProvider)
        .values
        .where((v) => v.signalRef == signalRef)
        .firstOrNull;

    return _witnessService.capture(
      source: source,
      signalRef: signalRef,
      time: time,
      bitWidth: variable?.bitWidth ?? 0,
    );
  }

  /// Author attribution. Local display name only — nothing is fetched, and
  /// nothing about the author leaves the machine until the user explicitly
  /// shares a bundle, which discloses these names at share time.
  String _authorName() => ref.read(annotationAuthorNameProvider);

  DateTime _now() => DateTime.now();
}

/// The name stamped on annotations this user writes.
///
/// Overridden by the Pro overlay with the collaboration display name so a
/// user's notes carry one identity everywhere. Open core defaults to empty,
/// which renders as unattributed rather than as a fabricated name.
@riverpod
String annotationAuthorName(Ref ref) => '';
