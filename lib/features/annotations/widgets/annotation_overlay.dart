// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:math' as math;

import 'package:crux_ide_layout/crux_ide_layout.dart'
    show kCruxInfoSnackDuration, showCruxInfoSnack;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show kDoubleTapSlop, kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/providers/collaboration_service_provider.dart';
import 'package:wavecrux/core/theme/annotation_colors.dart';
import 'package:wavecrux/core/theme/collaborator_palette.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_layers_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/annotations/providers/session_annotations_provider.dart';
import 'package:wavecrux/features/annotations/widgets/annotations_panel.dart'
    show showUndoSnack;
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/lane_geometry_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Maximum expanded balloons drawn before newcomers render collapsed.
///
/// Ten open text boxes make a waveform unreadable, which defeats the point of
/// drawing on it. Past this count the overlay folds the rest to numbered dots;
/// nothing is hidden — the panel still lists every one.
const int kMaxExpandedBalloons = 6;

/// Width of an expanded callout balloon, in logical pixels.
const double kAnnotationBalloonWidth = 190;

/// Radius of a collapsed annotation's numbered dot.
const double kAnnotationDotRadius = 9;

/// Draws user-authored annotations above the waveform canvas.
///
/// Anchored in **waveform-data coordinates** — `(tick, rowId)` — and
/// re-projected every build through the same [timeMapperProvider] (X) and
/// [laneGeometryProvider] (Y) the canvas itself uses, so a balloon stays glued
/// to the edge it marks through pan, zoom and scroll.
///
/// ### Flat, on purpose
///
/// Every widget here is a direct [Positioned] child of one [Stack], and each
/// interactive one is sized to its own label. An earlier version gave each
/// annotation its own `Stack` holding a canvas-sized leader layer, which made
/// every annotation a canvas-sized child; stacked, they shadowed one another
/// during hit testing and only some balloons could be grabbed. Leaders now
/// paint together in a single non-interactive layer underneath, so nothing
/// overlaps anything it does not visually cover.
///
/// Three behaviours differ from `SharedPointerOverlay`, which this otherwise
/// mirrors:
///
/// * **Orphans draw nothing.** An annotation whose signal is not on screen is
///   surfaced by the panel, not by the canvas. The pointer overlay's `y = 12`
///   fallback is right for an ephemeral ping and wrong here — for persistent
///   annotations it would pile every orphan on the top edge in a heap.
/// * **Drift is styled, not hidden.** A note whose signal no longer reads what
///   it read when written gets a dashed leader and an amber marker.
/// * **Crowding folds automatically** past [kMaxExpandedBalloons].
///
/// [scrollOffset] is the canvas's vertical scroll offset in logical pixels,
/// supplied by the host so content-space row tops map into viewport space.
class AnnotationOverlay extends ConsumerWidget {
  const AnnotationOverlay({required this.scrollOffset, super.key});

  final double scrollOffset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(annotationsVisibleProvider)) {
      return const SizedBox.shrink();
    }

    // The COMPOSED set — local notes plus any authored in a live session. One
    // renderer, two sources: everything below projects `(tick, rowId)` the
    // same way regardless of where a note came from, and the only difference
    // (a session note wears its author's colour) is already resolved upstream.
    final annotations = ref.watch(visibleAnnotationsInTimeOrderProvider);
    // Who is composing a note right now. Read *before* the empty-set
    // bail-out, because the first note written in a room is authored against a
    // canvas that has none — and that is precisely when somebody else needs to
    // be told it is coming. Empty without a session, so the open-core path
    // still short-circuits on the very next line.
    final writingChips = ref.watch(writingAnnotationChipsProvider);
    if (annotations.isEmpty && writingChips.isEmpty) {
      return const SizedBox.shrink();
    }

    // Which of them were written in the live session, and in whose palette
    // slot. Empty without a session, so the open-core path never pays for it.
    final sessionColors = ref.watch(sessionAnnotationColorIndexProvider);

    final statuses = ref.watch(annotationStatusesProvider);
    final editingId = ref.watch(annotationBeingEditedProvider);
    final timeMapper = ref.watch(timeMapperProvider);
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);
    final geometry = ref.watch(
      laneGeometryProvider(LaneMetrics(minLaneHeight: metrics.minLaneHeight)),
    );
    final scheme = Theme.of(context).colorScheme;
    final l10n = L10N.of(context);
    final notifier = ref.read(annotationsProvider.notifier);
    final selectedId = ref.watch(annotationSelectedProvider);
    final formatter = TimeFormatService(
      timescale: ref.watch(waveformSourceProvider).value?.timescale,
    );

    // Whose words may not be rewritten — adopted layers, and, in a live
    // session, everybody else's notes. The canvas has to consult this for the
    // same reason the panel does: an editor that opens and then discards what
    // you typed is worse than one that never opened.
    final readOnly = ref.watch(readOnlyAnnotationIdsProvider);
    // Somebody else's live-session note: not in the local store, so the local
    // delete is a no-op. The host may still remove it — it is the documented
    // exception to author-only rights — but that has to go over the wire.
    final sessionOnly = ref.watch(sessionOnlyAnnotationIdsProvider);
    final canModerate = ref.watch(canModerateAnnotationsProvider);

    // The lane a full-height band would be confined to: the one signal row the
    // user has selected in the signal list. Null when zero or several are
    // selected — "confine this to a lane" has no answer then, and picking one
    // for them would attach the band to a signal they did not name.
    final confinableRowId = singleSelectedRowId(
      geometry,
      ref.watch(selectedVariablesProvider),
    );

    void select(String id) =>
        ref.read(annotationSelectedProvider.notifier).selected = id;

    final leaders = <Leader>[];
    final bands = <Widget>[];
    final labels = <Widget>[];
    var expandedDrawn = 0;

    for (var i = 0; i < annotations.length; i++) {
      final annotation = annotations[i];
      final status =
          statuses[annotation.id] ?? AnnotationStatus.unanchoredToRow;

      // Orphaned and unresolved annotations have no lane to draw against. The
      // panel owns them; the canvas stays clean.
      if (status == AnnotationStatus.orphaned ||
          status == AnnotationStatus.unresolved) {
        continue;
      }

      final placement = _project(
        annotation: annotation,
        mapper: timeMapper,
        geometry: geometry,
        scrollOffset: scrollOffset,
      );
      if (placement == null) continue;

      final drifted = status == AnnotationStatus.drifted;
      final color = _colorFor(
        annotation,
        scheme,
        drifted: drifted,
        sessionColorIndex: sessionColors[annotation.id],
      );
      final number = i + 1;

      if (annotation.shape == AnnotationShape.band) {
        final range = annotation.anchor as RangeAnchor;
        bands.add(
          _BandMarker(
            key: ValueKey('annotation-band-${annotation.id}'),
            left: placement.left,
            width: placement.width,
            top: placement.laneTop,
            height: placement.laneHeight,
            color: color,
            number: i + 1,
            label: annotation.hasText ? annotation.text : null,
            deltaLabel: formatter.formatDelta(range.startTime, range.endTime),
            selected: annotation.id == selectedId,
            // Bands received neither of these until now. Without `isEditing`
            // a band's text could not be edited **at all** — including at
            // creation, where the delta is pre-filled precisely so the author
            // can replace it with what the measurement means. Without `number`
            // there was no way to tell which canvas band a panel row referred
            // to once two of them overlapped.
            isEditing: editingId == annotation.id,
            onCommit: (text) => _commitText(ref, annotation.id, text),
            onBeginEdit: readOnly.contains(annotation.id)
                ? null
                : () => _beginEdit(ref, annotation.id),
            confinedToLane: range.rowId != null,
            confinableRowId: confinableRowId,
            startTime: range.startTime,
            endTime: range.endTime,
            onSelect: () => select(annotation.id),
            onEdgeDragStart: notifier.beginTransaction,
            // The handle reports its TOTAL travel plus **the tick it started
            // from**, captured once at drag start. Summing rounded per-event
            // tick deltas would lose every sub-tick movement at zooms finer
            // than one tick per pixel; but reading the origin off `range` here
            // is worse, and is what shipped: this closure is rebuilt on every
            // frame of the drag, so `range.startTime` is the *already-moved*
            // start while `totalDx` keeps accumulating. The edge then
            // accelerates away — 48 px of travel landed 390 ticks past where
            // the pointer was. A single-move `tester.dragFrom` cannot see it;
            // only a drag with a rebuild between moves can.
            onEdgeDrag:
                ({required isStart, required originTick, required totalDx}) {
                  final moved =
                      originTick + (totalDx * timeMapper.ticksPerPixel).round();
                  notifier.setRangeEnd(
                    annotation.id,
                    isStart: isStart,
                    time: moved,
                  );
                },
            onEdgeDragEnd: notifier.endTransaction,
            onToggleLane: () => notifier.setRangeRow(
              annotation.id,
              range.rowId == null ? confinableRowId : null,
            ),
          ),
        );
        continue;
      }

      // A point-anchored annotation outside the visible time range is simply
      // not drawn — the panel's "jump to" is the affordance for reaching it,
      // and edge chips for every off-screen note would crowd the ruler.
      if (!placement.anchorVisible) continue;

      // The note being edited is always expanded. A freshly created one has no
      // text yet, so every other rule here would fold it to a dot and the
      // editor would never appear — which makes authoring impossible.
      final isEditing = editingId == annotation.id;
      final collapsed =
          !isEditing &&
          (annotation.collapsed ||
              !annotation.hasText ||
              annotation.shape == AnnotationShape.arrow ||
              expandedDrawn >= kMaxExpandedBalloons);

      if (!collapsed) expandedDrawn++;

      final anchorX = placement.left;
      final anchorY = placement.anchorY;
      final labelX = anchorX + annotation.labelDx;
      // Clamped off the top edge: the default offset places a balloon above
      // its anchor, which for a note on the first lane would put it under the
      // time ruler or off-canvas entirely. The leader still reaches down.
      final labelY = math.max<double>(2, anchorY + annotation.labelDy);

      leaders.add(
        Leader(
          from: Offset(anchorX, anchorY),
          to: Offset(
            labelX + (collapsed ? 0 : kAnnotationBalloonWidth / 2),
            labelY + (collapsed ? 0 : 16),
          ),
          color: color,
          dashed: drifted,
        ),
      );

      labels
        ..add(
          Positioned(
            left: anchorX - 3,
            top: anchorY - 3,
            child: IgnorePointer(
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
            ),
          ),
        )
        ..add(
          collapsed
              ? Positioned(
                  key: ValueKey('annotation-${annotation.id}'),
                  left: labelX - kAnnotationDotRadius,
                  top: labelY - kAnnotationDotRadius,
                  child: _Draggable(
                    onPointerDown: () => select(annotation.id),
                    onDragStart: notifier.beginTransaction,
                    onDragUpdate: (d) =>
                        notifier.nudgeLabel(annotation.id, d.dx, d.dy),
                    onDragEnd: notifier.endTransaction,
                    onTap: () =>
                        notifier.setCollapsed(annotation.id, collapsed: false),
                    child: _NumberDot(
                      number: number,
                      color: color,
                      onColor: scheme.surface,
                      selected: annotation.id == selectedId,
                    ),
                  ),
                )
              : Positioned(
                  key: ValueKey('annotation-${annotation.id}'),
                  left: labelX,
                  top: labelY,
                  width: kAnnotationBalloonWidth,
                  child: _Draggable(
                    onPointerDown: () => select(annotation.id),
                    // While the text field has focus a drag would fight text
                    // selection, so the balloon only moves when not editing.
                    onDragStart: isEditing ? null : notifier.beginTransaction,
                    onDragUpdate: isEditing
                        ? null
                        : (d) => notifier.nudgeLabel(annotation.id, d.dx, d.dy),
                    onDragEnd: isEditing ? null : notifier.endTransaction,
                    child: _Balloon(
                      text: annotation.text,
                      number: number,
                      color: color,
                      selected: annotation.id == selectedId,
                      surface: scheme.surface,
                      onSurface: scheme.onSurface,
                      drifted: drifted,
                      touchTarget: metrics.touchTarget,
                      isEditing: isEditing,
                      // Absent on somebody else's live-session note, for the
                      // same reason the ✕ is: `collapsed` lives on the shared
                      // model, so folding one would need per-viewer state that
                      // does not exist. The panel already hid this; the canvas
                      // did not, and an icon that cannot act is the failure
                      // this pair keeps reproducing.
                      onCollapse: sessionOnly.contains(annotation.id)
                          ? null
                          : () => notifier.setCollapsed(
                              annotation.id,
                              collapsed: true,
                            ),
                      // Absent rather than inert when this viewer may not
                      // remove it. The ✕ did nothing at all on a remote note,
                      // which is the same silent failure the panel's row menu
                      // had — and the panel was fixed first, so the two
                      // surfaces disagreed about what the host could do.
                      onDelete:
                          !sessionOnly.contains(annotation.id) || canModerate
                          ? () => _delete(
                              context,
                              ref,
                              annotation.id,
                              remote: sessionOnly.contains(annotation.id),
                            )
                          : null,
                      onCommit: (text) => _commitText(ref, annotation.id, text),
                      // A locked note explains itself and offers the way
                      // forward, rather than absorbing the gesture in silence.
                      // The refusal is correct — somebody else's words stay
                      // theirs, and a pack can carry them off this machine with
                      // their name attached — but a double-tap that simply does
                      // nothing teaches the user the feature is broken.
                      onBeginEdit: readOnly.contains(annotation.id)
                          ? () => _explainReadOnly(context, ref, annotation.id)
                          : () => _beginEdit(ref, annotation.id),
                    ),
                  ),
                ),
        );
    }

    // "…is writing a note…" — the whole of what replaces streaming keystrokes.
    // Drawn last so a chip is never hidden under a balloon, and only for
    // participants whose anchor projects: the note itself does not exist for
    // anybody else yet, so an unanchored chip would have nothing to point at.
    final chips = <Widget>[];
    for (final chip in writingChips) {
      final placement = _projectAnchor(
        time: chip.time,
        rowId: chip.rowId,
        mapper: timeMapper,
        geometry: geometry,
        scrollOffset: scrollOffset,
      );
      if (placement == null) continue;
      chips.add(
        Positioned(
          key: ValueKey('annotation-writing-${chip.participantId}'),
          left: placement.dx + 6,
          top: math.max(2, placement.dy - 26),
          child: IgnorePointer(
            child: _WritingChip(
              label: l10n.annotationWritingChip(chip.name),
              color: chip.colorIndex == null
                  ? scheme.primary
                  : collaboratorColor(chip.colorIndex!),
              surface: scheme.surface,
            ),
          ),
        ),
      );
    }

    if (bands.isEmpty && labels.isEmpty && chips.isEmpty) {
      return const SizedBox.shrink();
    }

    // Bands, then all leaders in one layer, then the labels. Only the labels
    // take gestures; everything under them is inert, so pan, zoom, cursor
    // placement and Alt-click all still reach WaveformGestureHandler through
    // the gaps.
    return RepaintBoundary(
      child: Stack(
        children: [
          ...bands,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _LeadersPainter(leaders)),
            ),
          ),
          ...labels,
          ...chips,
        ],
      ),
    );
  }

  /// Commits edited text for [id] and closes the editor.
  ///
  /// **Un-collapses on the way out**, which is not tidiness: a note authored
  /// collapsed — or one folded by a walkthrough — renders as a numbered dot,
  /// and `collapsed` survives the edit. So typing a sentence into the balloon
  /// and pressing Enter put the text in the model and in the panel while the
  /// canvas snapped back to a dot, which reads exactly like the text was
  /// thrown away. Somebody who just wrote words wants to see them.
  ///
  /// Empty text is left alone: folding is what an empty note already does, and
  /// an abandoned callout is discarded entirely a line later.
  void _commitText(WidgetRef ref, String id, String text) {
    final notifier = ref.read(annotationsProvider.notifier)..setText(id, text);
    if (text.trim().isNotEmpty) notifier.setCollapsed(id, collapsed: false);
    ref.read(annotationBeingEditedProvider.notifier).end();
    // An empty callout the user walked away from leaves nothing behind.
    ref.read(annotationAuthoringProvider.notifier).discardIfEmpty(id);
  }

  /// Opens an annotation's editor from the canvas.
  ///
  /// Selects as well as edits, so the note the keyboard would act on is the
  /// one whose words are open — the panel's *Edit text* does the same. Without
  /// it, double-tapping one note while another is selected would leave a
  /// subsequent ⌥-arrow nudging something the user is not looking at.
  void _beginEdit(WidgetRef ref, String id) {
    ref.read(annotationSelectedProvider.notifier).selected = id;
    ref.read(annotationBeingEditedProvider.notifier).editing = id;
  }

  /// Says why a note refuses to be edited, and offers to make one that will.
  ///
  /// *Duplicate as mine* is the sanctioned answer to "I want to build on this",
  /// and until now it lived only in the panel's ⋮ — reachable after the
  /// double-tap had already failed with no explanation. Putting it on the
  /// refusal puts it where the user actually is.
  void _explainReadOnly(BuildContext context, WidgetRef ref, String id) {
    final l10n = L10N.of(context);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.annotationReadOnlyAttribution),
          // Pinned to the suite constant rather than left to a framework
          // default they happen to share.
          // ignore: avoid_redundant_argument_values
          duration: kCruxInfoSnackDuration,
          action: SnackBarAction(
            label: l10n.annotationDuplicateAsMine,
            onPressed: () => ref
                .read(annotationAuthoringProvider.notifier)
                .duplicateAsMine(id),
          ),
        ),
      );
  }

  /// Deletes an annotation and offers an undo.
  ///
  /// The snackbar matters more than it looks: a note is typed prose, and the
  /// delete control sits a few pixels from the text the user just wrote.
  void _delete(
    BuildContext context,
    WidgetRef ref,
    String id, {
    bool remote = false,
  }) {
    final l10nEarly = L10N.of(context);
    if (remote) {
      // Moderation goes over the wire; no undo, because the authoritative copy
      // is gone and the note was never ours to restore.
      ref.read(collaborationServiceProvider).removeAnnotation(id);
      showCruxInfoSnack(context, l10nEarly.annotationDeletedToast);
      return;
    }
    final removed = ref.read(annotationAuthoringProvider.notifier).delete(id);
    if (!removed) return;

    final l10n = L10N.of(context);
    // Deferred — see [showUndoSnack]. The canvas ✕ is not itself in a route,
    // but the same note can be deleted from the panel's menu, and one code path
    // for both is what stops the two drifting apart.
    showUndoSnack(
      context,
      message: l10n.annotationDeletedToast,
      undoLabel: l10n.annotationUndo,
      onUndo: ref.read(annotationsProvider.notifier).undo,
    );
  }

  /// Drift beats attribution; attribution beats the note's own colour.
  ///
  /// A session note wears its author's cursor colour so the room can see who
  /// said what at a glance. A local note has no [sessionColorIndex] and keeps
  /// whatever it already had — the theme colour, usually — which is what stops
  /// joining a session from recolouring somebody's week-old private notes into
  /// their participant colour.
  Color _colorFor(
    Annotation annotation,
    ColorScheme scheme, {
    required bool drifted,
    int? sessionColorIndex,
  }) {
    if (drifted) return kAnnotationDriftedColor;
    if (sessionColorIndex != null) return collaboratorColor(sessionColorIndex);
    final rgb = annotation.colorRgb;
    return rgb != null ? Color(rgb) : scheme.primary;
  }

  /// Maps a bare `(time, rowId)` anchor into viewport pixels, or `null` when it
  /// cannot be placed — no anchor at all, no such row on screen, off the
  /// visible time range, or a non-finite coordinate.
  ///
  /// Separate from [_project] because the writing chip has no [Annotation] to
  /// project: the note it announces does not exist for anybody else yet, which
  /// is the entire reason the anchor travels on the wire beside the flag.
  static Offset? _projectAnchor({
    required int? time,
    required String? rowId,
    required TimeMapper mapper,
    required LaneGeometry geometry,
    required double scrollOffset,
  }) {
    if (time == null || rowId == null) return null;
    if (time < mapper.visibleStartTime || time > mapper.visibleEndTime) {
      return null;
    }
    for (final row in geometry.rows) {
      if (row.entry.signalPath != rowId) continue;
      final x = mapper.timeToPixel(time);
      final y = row.top - scrollOffset + row.height / 2;
      // Non-finite coordinates hard-crash the Windows renderer — the same
      // guard every other projection here carries.
      if (!x.isFinite || !y.isFinite) return null;
      return Offset(x, y);
    }
    return null;
  }

  /// Maps an annotation's data anchor into viewport pixels, or `null` when it
  /// cannot be placed (degenerate mapper, or a row absent from the geometry).
  static _Placement? _project({
    required Annotation annotation,
    required TimeMapper mapper,
    required LaneGeometry geometry,
    required double scrollOffset,
  }) {
    final anchor = annotation.anchor;

    double? rowTop;
    double? rowHeight;
    final rowId = annotation.rowId;
    if (rowId != null) {
      for (final row in geometry.rows) {
        if (row.entry.signalPath == rowId) {
          rowTop = row.top - scrollOffset;
          rowHeight = row.height;
          break;
        }
      }
      if (rowTop == null) return null;
    }

    switch (anchor) {
      case PointAnchor(:final time):
        final x = mapper.timeToPixel(time);
        // Non-finite coordinates hard-crash the Windows renderer — the same
        // guard SharedPointerOverlay carries, for the same reason.
        if (!x.isFinite) return null;
        final y = rowTop! + rowHeight! / 2;
        if (!y.isFinite) return null;
        return _Placement(
          left: x,
          width: 0,
          anchorY: y,
          laneTop: rowTop,
          laneHeight: rowHeight,
          anchorVisible:
              time >= mapper.visibleStartTime && time <= mapper.visibleEndTime,
        );

      case RangeAnchor(:final earliest, :final latest):
        final x0 = mapper.timeToPixel(earliest);
        final x1 = mapper.timeToPixel(latest);
        if (!x0.isFinite || !x1.isFinite) return null;
        // A band entirely off-screen contributes nothing; one that straddles
        // an edge is clipped by the Stack rather than dropped.
        if (x1 < 0 || x0 > mapper.viewportWidth) return null;
        return _Placement(
          left: x0,
          width: math.max(1, x1 - x0),
          anchorY: rowTop != null ? rowTop + rowHeight! / 2 : 0,
          laneTop: rowTop ?? 0,
          laneHeight: rowHeight ?? double.infinity,
          anchorVisible: true,
        );
    }
  }
}

/// Resolved pixel placement for one annotation.
@immutable
class _Placement {
  const _Placement({
    required this.left,
    required this.width,
    required this.anchorY,
    required this.laneTop,
    required this.laneHeight,
    required this.anchorVisible,
  });

  final double left;
  final double width;
  final double anchorY;
  final double laneTop;
  final double laneHeight;
  final bool anchorVisible;
}

/// Fires [onDoubleTap] without entering the gesture arena.
///
/// **A `GestureDetector` cannot be used here.** Its recognizer would compete
/// with the pan that drags the balloon, and a pan that has to win the arena
/// first emits nothing until it does — the drag silently loses its opening
/// slop-distance of travel and the balloon trails the pointer by 20 px for the
/// rest of the gesture. That is measured, not theoretical: wrapping the
/// balloon's text in a double-tap detector turned a 60 px drag into a 40 px
/// one, which is the same failure the [_Draggable.onPointerDown] comment
/// describes for selection.
///
/// So this recognizes the pair by hand from raw pointer events, exactly as
/// selection does. A [Listener] claims nothing, competes with nothing, and
/// leaves the pan untouched.
///
/// Timing comes from [PointerEvent.timeStamp] rather than the wall clock, so
/// the widget behaves identically under a test's fake clock.
class _DoubleTapRegion extends StatefulWidget {
  const _DoubleTapRegion({
    required this.onDoubleTap,
    required this.child,
    this.behavior = HitTestBehavior.opaque,
    super.key,
  });

  /// Null makes the region inert, which is how a read-only note refuses.
  final VoidCallback? onDoubleTap;
  final Widget child;

  /// How much of the region answers a pointer.
  ///
  /// [HitTestBehavior.opaque] for a balloon, so the blank right-hand side of a
  /// short line is still a target — a note whose words are "ack" would
  /// otherwise offer one a few characters wide.
  ///
  /// [HitTestBehavior.deferToChild] for a band, where the layout box spans the
  /// band's full width but only the label chip is painted in it. Opaque there
  /// would swallow pan, zoom and cursor placement along the whole top strip of
  /// a band that may cross the entire viewport.
  final HitTestBehavior behavior;

  @override
  State<_DoubleTapRegion> createState() => _DoubleTapRegionState();
}

class _DoubleTapRegionState extends State<_DoubleTapRegion> {
  Duration? _lastDown;
  Offset? _lastPosition;

  void _onPointerDown(PointerDownEvent event) {
    final last = _lastDown;
    final where = _lastPosition;
    _lastDown = event.timeStamp;
    _lastPosition = event.position;

    if (last == null || where == null) return;
    // Two presses close in both time and space. The distance check is what
    // stops a press, a drag away, and a second press elsewhere from reading as
    // a double-tap.
    if (event.timeStamp - last > kDoubleTapTimeout) return;
    if ((event.position - where).distance > kDoubleTapSlop) return;

    _lastDown = null;
    _lastPosition = null;
    widget.onDoubleTap?.call();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onPointerDown,
    behavior: widget.behavior,
    child: widget.child,
  );
}

/// Wraps a balloon or dot so it can be dragged by its label without moving its
/// anchor — the model's central invariant, expressed as a gesture.
class _Draggable extends ConsumerWidget {
  const _Draggable({
    required this.child,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onTap,
    this.onPointerDown,
    this.cursor,
  });

  final Widget child;
  final VoidCallback? onDragStart;
  final void Function(Offset delta)? onDragUpdate;
  final VoidCallback? onDragEnd;
  final VoidCallback? onTap;

  /// Fired on pointer-down, before any recognizer competes for the sequence.
  ///
  /// Selection rides here rather than on `onTap` deliberately. Adding a tap
  /// recognizer alongside the pan one makes the pan wait to win the arena
  /// before it emits, so a drag silently loses its first slop-distance of
  /// travel — the balloon lags the pointer by 20 px for the rest of the
  /// gesture. A `Listener` callback claims nothing and costs nothing.
  final VoidCallback? onPointerDown;

  /// Pointer cursor over this affordance. Defaults to the move cursor when the
  /// thing is draggable — a band edge overrides it to the resize cursor, which
  /// is the only hint that an edge can be dragged at all.
  final MouseCursor? cursor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void claim({required bool value}) =>
        ref.read(annotationGestureActiveProvider.notifier).active = value;

    // The outer Listener claims the pointer sequence before the ancestor
    // WaveformGestureHandler sees it — see AnnotationGestureActive for why a
    // GestureDetector alone is not enough against a raw Listener ancestor.
    return Listener(
      onPointerDown: (_) {
        claim(value: true);
        onPointerDown?.call();
      },
      // Released on a microtask, NOT synchronously. Pointer events dispatch
      // deepest-first, so this Listener sees the up before the ancestor does.
      // Clearing the claim here would let that handler process the very same
      // event with claim=false and place the cursor at the release point.
      onPointerUp: (_) => scheduleMicrotask(() => claim(value: false)),
      onPointerCancel: (_) => scheduleMicrotask(() => claim(value: false)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onPanStart: onDragStart == null ? null : (_) => onDragStart!(),
        onPanUpdate: onDragUpdate == null
            ? null
            : (d) => onDragUpdate!(d.delta),
        onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
        child: MouseRegion(
          cursor:
              cursor ??
              (onDragUpdate == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.move),
          child: child,
        ),
      ),
    );
  }
}

class _NumberDot extends StatelessWidget {
  const _NumberDot({
    required this.number,
    required this.color,
    required this.onColor,
    this.selected = false,
  });

  final int number;
  final Color color;
  final Color onColor;

  /// Whether this is the annotation the keyboard nudge would move. Shown as a
  /// ring rather than a colour change, so it never collides with the drift
  /// styling — a note can be both selected and drifted, and those two facts
  /// must stay separately legible.
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    width: kAnnotationDotRadius * 2,
    height: kAnnotationDotRadius * 2,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      border: selected ? Border.all(color: onColor, width: 2) : null,
    ),
    child: Text(
      '$number',
      style: TextStyle(
        color: onColor,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _Balloon extends StatelessWidget {
  const _Balloon({
    required this.text,
    required this.number,
    required this.color,
    required this.surface,
    required this.onSurface,
    required this.drifted,
    required this.touchTarget,
    required this.isEditing,
    required this.onCollapse,
    required this.onDelete,
    required this.onCommit,
    required this.onBeginEdit,
    this.selected = false,
  });

  final String text;
  final int number;
  final Color color;
  final Color surface;
  final Color onSurface;
  final bool drifted;
  final double touchTarget;
  final bool isEditing;

  /// Folds this balloon back to its numbered dot.
  ///
  /// Tapping a dot has always expanded it; nothing on the canvas folded one
  /// back, so `collapsed: true` could only ever be set by the walkthrough.
  /// Null when this viewer may not fold the note — see [onDelete].
  final VoidCallback? onCollapse;

  /// Null when this viewer may not remove the note — somebody else's
  /// live-session note, and this is not the host. The ✕ is absent rather than
  /// inert: a control that does nothing is the failure the panel's row menu
  /// already had.
  final VoidCallback? onDelete;
  final void Function(String text) onCommit;

  /// Opens this balloon's editor from the canvas.
  ///
  /// **Double-tap, and scoped to the text alone.** Two constraints meet here:
  ///
  /// * A *single* tap cannot do it. Selection rides pointer-down (see
  ///   [_Draggable.onPointerDown]) and selection is what ⌥-arrow nudges, so
  ///   making one click also open the editor would send every subsequent
  ///   keystroke to a text field and leave the nudge unreachable without an
  ///   Escape first.
  /// * The recognizer must not wrap the whole balloon. A double-tap recognizer
  ///   above the collapse and delete buttons makes each of their taps wait out
  ///   the double-tap timeout — the same ~300 ms lag an ancestor
  ///   `InkWell.onDoubleTap` once put on the panel's ⋮ menu.
  ///
  /// Double-tap is also what the panel's own rows already use to open an
  /// editor, so the canvas and the list ask for the same thing the same way.
  /// Null when this note's words are somebody else's — an adopted layer, or a
  /// live session where rights are author-only.
  final VoidCallback? onBeginEdit;

  /// See [_NumberDot.selected].
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        // High opacity rather than a solid block: the waveform stays faintly
        // legible underneath, which matters when a balloon lands over the very
        // edge it describes.
        color: surface.withValues(alpha: 0.92),
        border: Border.all(color: color, width: selected ? 2.5 : 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _NumberDot(
              number: number,
              color: color,
              onColor: surface,
              selected: selected,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: isEditing
                  ? _InlineEditor(
                      initialText: text,
                      hint: l10n.annotationEditHint,
                      color: onSurface,
                      onCommit: onCommit,
                    )
                  : _DoubleTapRegion(
                      key: const ValueKey('annotation-balloon-text'),
                      onDoubleTap: onBeginEdit,
                      child: Text(
                        text,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.25,
                          color: onSurface,
                          fontStyle: drifted
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                    ),
            ),
            // Fold, then delete. Tapping a dot has always expanded a note;
            // until now nothing on the canvas folded one back, so the only
            // thing that ever set `collapsed` was the walkthrough.
            if (!isEditing)
              if (onCollapse != null)
                Semantics(
                  label: l10n.annotationCollapseTooltip,
                  button: true,
                  child: Tooltip(
                    message: l10n.annotationCollapseTooltip,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onCollapse,
                      child: SizedBox(
                        width: touchTarget * 0.6,
                        height: touchTarget * 0.6,
                        child: Icon(
                          Icons.unfold_less,
                          size: 12,
                          color: onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ),
            if (onDelete != null)
              Semantics(
                label: l10n.annotationDeleteTooltip,
                button: true,
                child: Tooltip(
                  message: l10n.annotationDeleteTooltip,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onDelete,
                    child: SizedBox(
                      width: touchTarget * 0.6,
                      height: touchTarget * 0.6,
                      child: Icon(
                        Icons.close,
                        size: 12,
                        color: onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `<name> is writing a note…`, drawn at the anchor of the note in progress.
///
/// Deliberately does not resemble a balloon: it is not a note, it is somebody
/// about to write one, and a reader who mistakes it for content will wonder why
/// it keeps disappearing. Inert to pointers — there is nothing to interact with,
/// and the canvas underneath still needs to take pan, zoom and cursor gestures
/// through it.
class _WritingChip extends StatelessWidget {
  const _WritingChip({
    required this.label,
    required this.color,
    required this.surface,
  });

  final String label;
  final Color color;
  final Color surface;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: surface.withValues(alpha: 0.92),
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontStyle: FontStyle.italic,
          color: color,
        ),
      ),
    ),
  );
}

/// Commits the inline editor. Its own Intent type rather than a reused one so
/// the Enter binding cannot collide with anything the surrounding app maps.
class _CommitIntent extends Intent {
  const _CommitIntent();
}

/// The in-place text field a new annotation opens with.
///
/// Inline rather than a modal dialog: annotating is something a user does
/// eight times in a row while reading a waveform, and a dialog per note breaks
/// that rhythm completely. Enter commits, Escape cancels, and losing focus
/// commits too — walking away should keep what you typed, not discard it.
class _InlineEditor extends StatefulWidget {
  const _InlineEditor({
    required this.initialText,
    required this.hint,
    required this.color,
    required this.onCommit,
  });

  final String initialText;
  final String hint;
  final Color color;
  final void Function(String text) onCommit;

  @override
  State<_InlineEditor> createState() => _InlineEditorState();
}

class _InlineEditorState extends State<_InlineEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  late final FocusNode _focus = FocusNode();
  bool _committed = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    if (_committed) return;
    _committed = true;
    widget.onCommit(_controller.text.trim());
  }

  void _cancel() {
    if (_committed) return;
    _committed = true;
    // Commits the text the annotation already had, so Escape reverts the edit
    // rather than deleting a note that previously said something.
    widget.onCommit(widget.initialText);
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    // Enter commits; Shift+Enter inserts a line break. A multi-line TextField
    // never fires onSubmitted — Enter just inserts a newline — so binding the
    // key explicitly is the only way to keep "type and press Enter" working
    // while still allowing a two-line note.
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      SingleActivator(LogicalKeyboardKey.enter): _CommitIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter): _CommitIntent(),
    },
    child: Actions(
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            _cancel();
            return null;
          },
        ),
        _CommitIntent: CallbackAction<_CommitIntent>(
          onInvoke: (_) {
            _commit();
            return null;
          },
        ),
      },
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        maxLines: 4,
        minLines: 1,
        maxLength: kAnnotationTextMaxLength,
        style: TextStyle(fontSize: 11, height: 1.25, color: widget.color),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          counterText: '',
          hintText: widget.hint,
          hintStyle: TextStyle(
            fontSize: 11,
            color: widget.color.withValues(alpha: 0.45),
          ),
        ),
        onSubmitted: (_) => _commit(),
      ),
    ),
  );
}

/// The band's own inline text field.
///
/// A thin wrapper over [_InlineEditor] that gives it a legible plate. A band's
/// label sits directly on the shaded region with no balloon behind it, so an
/// unbacked field over a busy waveform is unreadable while you type in it.
class _BandLabelEditor extends StatelessWidget {
  const _BandLabelEditor({
    required this.initialText,
    required this.hint,
    required this.color,
    required this.surface,
    required this.onCommit,
  });

  final String initialText;
  final String hint;
  final Color color;
  final Color surface;
  final void Function(String text) onCommit;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: surface.withValues(alpha: 0.92),
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: _InlineEditor(
        initialText: initialText,
        hint: hint,
        color: Theme.of(context).colorScheme.onSurface,
        onCommit: onCommit,
      ),
    ),
  );
}

/// Width of a band's draggable edge handle, in logical pixels.
///
/// Wider than the 1.5 px border it sits on: the border is the visual, the
/// handle is the target, and a 1.5 px grab region is a border users report as
/// undraggable rather than as thin.
const double kBandHandleWidth = 10;

/// A shaded time span, full canvas height or confined to one lane.
///
/// Both edges are draggable. While an edge is held the band reports its span in
/// the file's timescale, live — the number is the reason somebody drew the band
/// in the first place, and reading it off the ruler mid-drag is not something
/// anyone manages.
class _BandMarker extends StatefulWidget {
  const _BandMarker({
    required this.left,
    required this.width,
    required this.top,
    required this.height,
    required this.color,
    required this.number,
    required this.label,
    required this.deltaLabel,
    required this.selected,
    required this.isEditing,
    required this.onCommit,
    required this.onBeginEdit,
    required this.confinedToLane,
    required this.confinableRowId,
    required this.startTime,
    required this.endTime,
    required this.onSelect,
    required this.onEdgeDragStart,
    required this.onEdgeDrag,
    required this.onEdgeDragEnd,
    required this.onToggleLane,
    super.key,
  });

  final double left;
  final double width;
  final double top;
  final double height;
  final Color color;

  /// The band's row number in the panel — drawn as a badge so a canvas band
  /// and a list row can be matched by eye. Callouts have carried one since
  /// 5.9.1; bands did not, so two overlapping ones were indistinguishable.
  final int number;

  final String? label;

  /// Whether this band's text field currently has focus.
  final bool isEditing;

  /// Commits edited text.
  final void Function(String text) onCommit;

  /// Opens this band's editor from the canvas. See [_Balloon.onBeginEdit] for
  /// why it is a double-tap, why only the label chip carries it, and why it is
  /// nullable.
  final VoidCallback? onBeginEdit;

  /// The span, formatted in the file's timescale. Recomputed by the parent on
  /// every rebuild, so it tracks an in-flight edge drag without this widget
  /// having to know anything about ticks.
  final String deltaLabel;

  final bool selected;
  final bool confinedToLane;

  /// The lane a full-height band would be confined to, or null when the user
  /// has not singled one out. Null disables the confine direction of the
  /// toggle rather than hiding it, so the control does not appear and vanish
  /// as the signal selection changes.
  final String? confinableRowId;

  /// The band's current ends, in ticks. Held so the state can snapshot the one
  /// being dragged at gesture start — see [onEdgeDrag].
  final int startTime;
  final int endTime;

  final VoidCallback onSelect;
  final VoidCallback onEdgeDragStart;

  /// Reports the handle's **total** travel in pixels since the drag began,
  /// together with [originTick] — the tick that end sat at when the gesture
  /// started.
  ///
  /// Both halves are required to place the edge correctly. Travel alone forces
  /// the caller to find an origin, and the only one in scope there is the
  /// live (already-moved) anchor, which compounds.
  final void Function({
    required bool isStart,
    required int originTick,
    required double totalDx,
  })
  onEdgeDrag;
  final VoidCallback onEdgeDragEnd;
  final VoidCallback onToggleLane;

  @override
  State<_BandMarker> createState() => _BandMarkerState();
}

class _BandMarkerState extends State<_BandMarker> {
  bool _dragging = false;

  /// The dragged end's tick at gesture start, snapshotted so the placement is
  /// computed from where the edge *was* rather than from where it has already
  /// been moved to this frame.
  int _originTick = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final fullHeight = !widget.height.isFinite;
    final color = widget.color;
    final scheme = Theme.of(context).colorScheme;
    final canToggle = widget.confinedToLane || widget.confinableRowId != null;

    final band = Stack(
      children: [
        // The shaded body. Inert: pan, zoom and cursor placement must still
        // reach the canvas through a band that may span the whole viewport.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                border: Border(
                  left: BorderSide(
                    color: color,
                    width: widget.selected ? 2.5 : 1.5,
                  ),
                  right: BorderSide(
                    color: color,
                    width: widget.selected ? 2.5 : 1.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        // The badge, inset past the left edge handle so it does not sit on a
        // drag target. Inert — it identifies the band, it is not a control.
        Positioned(
          left: kBandHandleWidth + 2,
          top: 2,
          child: IgnorePointer(
            child: _NumberDot(
              number: widget.number,
              color: color,
              onColor: Theme.of(context).colorScheme.surface,
              selected: widget.selected,
            ),
          ),
        ),
        Positioned(
          left: kBandHandleWidth * 2 + 6,
          right: kBandHandleWidth + 2,
          top: 2,
          // NOT inside the IgnorePointer while editing: the text field has to
          // take the pointer. A band whose label was permanently inert is why
          // band text could never be edited, including the pre-filled delta
          // the author is meant to replace.
          child: widget.isEditing
              ? _BandLabelEditor(
                  initialText: widget.label ?? '',
                  hint: l10n.annotationEditHint,
                  color: color,
                  surface: Theme.of(context).colorScheme.surface,
                  onCommit: widget.onCommit,
                )
              : _DoubleTapRegion(
                  // Double-tap to edit, matching the balloon and the panel's
                  // rows. The same arena-free recognizer the balloon uses:
                  // there is no pan to lose here, but a band spans lanes the
                  // user still needs to pan and zoom, and a recognizer over it
                  // would be one more thing competing for those.
                  onDoubleTap: widget.onBeginEdit,
                  behavior: HitTestBehavior.deferToChild,
                  // Backed, not bare. The label used to be 10px of `color`
                  // painted straight onto the lanes, and a band's colour is
                  // the theme primary — so on any trace drawn in that same
                  // hue the words were green-on-green and effectively
                  // invisible. This is the balloon's own decoration at band
                  // scale: a near-opaque surface so the text has a ground of
                  // its own, the annotation colour carried by the border and
                  // the number dot rather than by the glyphs.
                  //
                  // [Align] rather than filling the Positioned: it hands the
                  // chip loose constraints so it hugs its text, instead of a
                  // header bar spanning the whole band.
                  child: Align(
                    alignment: Alignment.topCenter,
                    // Nothing to say, nothing to draw. An untexted band that is
                    // not being dragged would otherwise render the chrome of a
                    // chip around no text — a small empty box sitting on the
                    // waveform, which reads as a rendering fault rather than as
                    // a band awaiting words.
                    child: (widget.label == null && !_dragging)
                        ? const SizedBox.shrink()
                        : DecoratedBox(
                            key: const ValueKey('annotation-band-label-chip'),
                            decoration: BoxDecoration(
                              color: scheme.surface.withValues(alpha: 0.92),
                              border: Border.all(
                                color: color,
                                width: widget.selected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.label != null)
                                    Text(
                                      widget.label!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: scheme.onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  if (_dragging)
                                    Text(
                                      widget.deltaLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: scheme.onSurface,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                  ),
                ),
        ),
        _BandEdgeHandle(
          alignStart: true,
          onSelect: widget.onSelect,
          onStart: () {
            setState(() {
              _dragging = true;
              _originTick = widget.startTime;
            });
            widget.onEdgeDragStart();
          },
          onUpdate: (dx) => widget.onEdgeDrag(
            isStart: true,
            originTick: _originTick,
            totalDx: dx,
          ),
          onEnd: () {
            setState(() => _dragging = false);
            widget.onEdgeDragEnd();
          },
        ),
        _BandEdgeHandle(
          alignStart: false,
          onSelect: widget.onSelect,
          onStart: () {
            setState(() {
              _dragging = true;
              _originTick = widget.endTime;
            });
            widget.onEdgeDragStart();
          },
          onUpdate: (dx) => widget.onEdgeDrag(
            isStart: false,
            originTick: _originTick,
            totalDx: dx,
          ),
          onEnd: () {
            setState(() => _dragging = false);
            widget.onEdgeDragEnd();
          },
        ),
        // LAST in the Stack and inset past the right handle. Both matter: the
        // edge handles span the band's full height, so a toggle drawn earlier
        // would be under one of them, and one sharing the handle's column
        // would compete with it for the same pixels.
        if (canToggle)
          Positioned(
            right: kBandHandleWidth + 2,
            bottom: 0,
            child: _BandLaneToggle(
              color: color,
              confined: widget.confinedToLane,
              tooltip: widget.confinedToLane
                  ? l10n.annotationBandSpanAllLanes
                  : l10n.annotationBandConfineToLane,
              onPressed: () {
                widget.onSelect();
                widget.onToggleLane();
              },
            ),
          ),
      ],
    );

    return fullHeight
        ? Positioned(
            left: widget.left,
            width: widget.width,
            top: 0,
            bottom: 0,
            child: band,
          )
        : Positioned(
            left: widget.left,
            width: widget.width,
            top: widget.top,
            height: widget.height,
            child: band,
          );
  }
}

/// One draggable band edge.
///
/// Holds its own accumulated travel so the parent can compute an absolute new
/// tick from the edge's pre-drag position, which is what keeps a slow drag at
/// sub-tick-per-pixel zoom from losing ground to rounding.
class _BandEdgeHandle extends ConsumerStatefulWidget {
  const _BandEdgeHandle({
    required this.alignStart,
    required this.onSelect,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final bool alignStart;
  final VoidCallback onSelect;
  final VoidCallback onStart;
  final void Function(double totalDx) onUpdate;
  final VoidCallback onEnd;

  @override
  ConsumerState<_BandEdgeHandle> createState() => _BandEdgeHandleState();
}

class _BandEdgeHandleState extends ConsumerState<_BandEdgeHandle> {
  double _travelled = 0;

  @override
  Widget build(BuildContext context) => Positioned(
    // Wholly INSIDE the band, not straddling its border. The band's Stack
    // clips hit testing to its own bounds, so a handle centred on the edge
    // would have half its target dead — and the dead half is the outer one,
    // which is exactly where a user aiming at a border puts the pointer.
    left: widget.alignStart ? 0 : null,
    right: widget.alignStart ? null : 0,
    top: 0,
    bottom: 0,
    width: kBandHandleWidth,
    child: _Draggable(
      onPointerDown: widget.onSelect,
      onDragStart: () {
        _travelled = 0;
        widget.onStart();
      },
      onDragUpdate: (d) {
        _travelled += d.dx;
        widget.onUpdate(_travelled);
      },
      onDragEnd: widget.onEnd,
      cursor: SystemMouseCursors.resizeLeftRight,
      child: const SizedBox.expand(),
    ),
  );
}

/// Switches a band between one lane and the whole canvas.
class _BandLaneToggle extends StatelessWidget {
  const _BandLaneToggle({
    required this.color,
    required this.confined,
    required this.tooltip,
    required this.onPressed,
  });

  final Color color;
  final bool confined;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: tooltip,
    button: true,
    child: Tooltip(
      message: tooltip,
      child: _Draggable(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            confined ? Icons.unfold_more : Icons.unfold_less,
            size: 14,
            color: color,
          ),
        ),
      ),
    ),
  );
}

/// Draws the leader line from an anchor to its label.
/// One leader, in overlay coordinates.
@immutable
class Leader {
  const Leader({
    required this.from,
    required this.to,
    required this.color,
    required this.dashed,
  });

  final Offset from;
  final Offset to;
  final Color color;
  final bool dashed;

  // Value equality so `_LeadersPainter.shouldRepaint` can ask whether the
  // geometry actually moved. Leaders are rebuilt from scratch on every layout
  // pass, so identity comparison would always say "different" and the painter
  // would repaint on every scroll and zoom frame — which is exactly what it
  // used to do.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Leader &&
          other.from == from &&
          other.to == to &&
          other.color == color &&
          other.dashed == dashed;

  @override
  int get hashCode => Object.hash(from, to, color, dashed);
}

/// Paints every leader in a single full-canvas layer beneath the labels.
///
/// One painter rather than one per annotation, because a leader spans the gap
/// between an anchor and a label that may sit anywhere on the canvas — so a
/// per-annotation layer would have to be canvas-sized, and N canvas-sized
/// layers stacked on top of each other shadow one another during hit testing.
/// Leaders are decoration, never affordances, so they belong at the bottom in
/// one non-interactive layer.
class _LeadersPainter extends CustomPainter {
  const _LeadersPainter(this.leaders);

  final List<Leader> leaders;

  @override
  void paint(Canvas canvas, Size size) {
    for (final leader in leaders) {
      final paint = Paint()
        ..color = leader.color
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;

      if (!leader.dashed) {
        canvas.drawLine(leader.from, leader.to, paint);
        continue;
      }

      // A dashed leader marks a drifted annotation — the visual cue that the
      // claim was true of a different run of this design.
      const dash = 4.0;
      const gap = 3.0;
      final delta = leader.to - leader.from;
      final length = delta.distance;
      if (length <= 0) continue;
      final step = delta / length;
      var travelled = 0.0;
      while (travelled < length) {
        final segment = math.min(dash, length - travelled);
        canvas.drawLine(
          leader.from + step * travelled,
          leader.from + step * (travelled + segment),
          paint,
        );
        travelled += dash + gap;
      }
    }
  }

  @override
  // The painter's whole output is a function of [leaders], so comparing them
  // is the complete answer. This returned an unconditional `true` for a long
  // time — on the one canvas that relayouts on every scroll and zoom frame,
  // where a leader set that has not moved is the overwhelmingly common case.
  bool shouldRepaint(_LeadersPainter old) => !listEquals(old.leaders, leaders);
}
