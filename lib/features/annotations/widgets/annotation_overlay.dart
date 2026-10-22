// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:crux_annotations/crux_annotations.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart'
    show CruxToastAction, showCruxInfoSnack;
import 'package:flutter/material.dart';
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
/// nothing is hidden — the panel still lists every one. The suite's shared
/// crowding limit.
const int kMaxExpandedBalloons = kCruxCalloutMaxExpanded;

/// Width of an expanded callout balloon, in logical pixels.
const double kAnnotationBalloonWidth = kCruxCalloutBalloonWidth;

/// Radius of a collapsed annotation's numbered dot.
const double kAnnotationDotRadius = kCruxCalloutDotRadius;

/// Draws user-authored annotations above the waveform canvas.
///
/// Draws with the suite's shared callout layer (`crux_annotations`): the
/// balloon, numbered dot, leaders, draggable and fold rule are the ones
/// NetCrux draws on its schematic. What is WaveCrux's here is the projection,
/// the bands, the arrows' dot-only rule and every string.
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

    final leaders = <CruxCalloutLeader>[];
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
      // An arrow is a leader and a dot by definition, so it never opens.
      final collapsed = CruxCalloutGeometry.isCollapsed(
        isEditing: isEditing,
        collapsed: annotation.collapsed,
        hasText: annotation.hasText,
        alwaysDot: annotation.shape == AnnotationShape.arrow,
        expandedSoFar: expandedDrawn,
      );

      if (!collapsed) expandedDrawn++;

      final anchorX = placement.left;
      final anchorY = placement.anchorY;
      final anchorPoint = Offset(anchorX, anchorY);
      // Clamped off the top edge: the default offset places a balloon above
      // its anchor, which for a note on the first lane would put it under the
      // time ruler or off-canvas entirely. The leader still reaches down.
      final labelOrigin = CruxCalloutGeometry.labelOrigin(
        anchorPoint,
        labelDx: annotation.labelDx,
        labelDy: annotation.labelDy,
      );
      final labelX = labelOrigin.dx;
      final labelY = labelOrigin.dy;

      leaders.add(
        CruxCalloutLeader(
          from: anchorPoint,
          to: CruxCalloutGeometry.leaderEnd(labelOrigin, collapsed: collapsed),
          color: color,
          dashed: drifted,
        ),
      );

      labels
        ..add(
          Positioned(
            left: anchorX - CruxCalloutAnchorDot.size / 2,
            top: anchorY - CruxCalloutAnchorDot.size / 2,
            child: CruxCalloutAnchorDot(color: color),
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
                    child: CruxCalloutNumberDot(
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
                    child: CruxCalloutBalloon(
                      collapseTooltip: l10n.annotationCollapseTooltip,
                      deleteTooltip: l10n.annotationDeleteTooltip,
                      editHint: l10n.annotationEditHint,
                      maxLength: kAnnotationTextMaxLength,
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
              child: CustomPaint(painter: CruxCalloutLeadersPainter(leaders)),
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
    showCruxInfoSnack(
      context,
      l10n.annotationReadOnlyAttribution,
      action: CruxToastAction(
        label: l10n.annotationDuplicateAsMine,
        onPressed: () =>
            ref.read(annotationAuthoringProvider.notifier).duplicateAsMine(id),
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

/// Wraps a balloon or dot so it can be dragged by its label without moving its
/// anchor — the model's central invariant, expressed as a gesture.
///
/// The shared [CruxCalloutDraggable], bound to WaveCrux's
/// [annotationGestureActiveProvider] so the claim reaches the
/// WaveformGestureHandler underneath.
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

  // The shared draggable's Listener claims the pointer sequence before the
  // ancestor WaveformGestureHandler sees it — see AnnotationGestureActive for
  // why a GestureDetector alone is not enough against a raw Listener ancestor
  // — and releases it on a microtask, after that handler has seen the up.
  @override
  Widget build(BuildContext context, WidgetRef ref) => CruxCalloutDraggable(
    onClaim: (value) =>
        ref.read(annotationGestureActiveProvider.notifier).active = value,
    onPointerDown: onPointerDown,
    onDragStart: onDragStart,
    onDragUpdate: onDragUpdate,
    onDragEnd: onDragEnd,
    onTap: onTap,
    cursor: cursor,
    child: child,
  );
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

/// The band's own inline text field.
///
/// A thin wrapper over the shared [CruxCalloutInlineEditor] that gives it a
/// legible plate. A band's
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
      child: CruxCalloutInlineEditor(
        initialText: initialText,
        hint: hint,
        color: Theme.of(context).colorScheme.onSurface,
        onCommit: onCommit,
        maxLength: kAnnotationTextMaxLength,
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

  /// Opens this band's editor from the canvas. See [CruxCalloutBalloon.onBeginEdit] for
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
            child: CruxCalloutNumberDot(
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
              : CruxCalloutDoubleTapRegion(
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
