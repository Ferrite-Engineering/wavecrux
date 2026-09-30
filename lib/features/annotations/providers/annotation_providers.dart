// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_data_revision_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';

part 'annotation_providers.g.dart';

/// Maximum number of annotation-list snapshots retained on the undo stack.
///
/// Matches [kStageWorkspaceUndoHistoryLimit]'s reasoning: bounded memory, and
/// far more history than a session of annotating actually consumes.
const int kAnnotationUndoHistoryLimit = 100;

/// Owns the per-tab annotation list.
///
/// **Undo/redo** follows `StageWorkspaceNotifier` exactly rather than
/// inventing a second mechanism — there is no global undo stack in this app,
/// and two divergent implementations of the same idea is how that starts.
/// Every mutation captures the pre-mutation list; [beginTransaction] /
/// [endTransaction] coalesce a drag's many intermediate positions into one
/// undo step, so dragging a balloon is one press of ⌘Z rather than sixty.
///
/// State is persisted by `SessionService` into `.wavecrux` and restored by
/// `SessionNotifier` — see [restoreFromSession] and [snapshot].
@riverpod
class AnnotationsNotifier extends _$AnnotationsNotifier {
  final List<List<Annotation>> _undoStack = [];
  final List<List<Annotation>> _redoStack = [];

  /// Snapshot captured at [beginTransaction]; non-null while one is open.
  List<Annotation>? _pendingTransactionSnapshot;

  @override
  List<Annotation> build() => const <Annotation>[];

  // ── undo / redo ────────────────────────────────────────────────────────────

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void undo() {
    if (_undoStack.isEmpty) return;
    final target = _undoStack.removeLast();
    _redoStack.add(state);
    state = target;
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final target = _redoStack.removeLast();
    _undoStack.add(state);
    state = target;
  }

  /// Opens a transaction that coalesces every subsequent mutation into a
  /// single undo step. Idempotent.
  void beginTransaction() {
    _pendingTransactionSnapshot ??= state;
  }

  /// Closes the open transaction, recording one undo step for the whole
  /// interaction. No-op when nothing actually changed.
  void endTransaction() {
    final before = _pendingTransactionSnapshot;
    if (before == null) return;
    _pendingTransactionSnapshot = null;
    if (identical(before, state)) return;
    _pushUndo(before);
  }

  /// Discards the open transaction without recording an undo step — for a
  /// drag the user cancels mid-flight.
  void cancelTransaction() {
    _pendingTransactionSnapshot = null;
  }

  void _pushUndo(List<Annotation> before) {
    _undoStack.add(before);
    if (_undoStack.length > kAnnotationUndoHistoryLimit) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _recordChange(void Function() mutate) {
    if (_pendingTransactionSnapshot != null) {
      mutate();
      return;
    }
    final before = state;
    mutate();
    if (identical(before, state)) return;
    _pushUndo(before);
  }

  // ── mutations ──────────────────────────────────────────────────────────────

  /// Appends [annotation]. Ignores a duplicate id rather than creating two
  /// rows the user cannot tell apart — ids arrive from the network under
  /// collaboration, where a full-state rebroadcast re-delivers what we have.
  void add(Annotation annotation) {
    if (state.any((a) => a.id == annotation.id)) return;
    _recordChange(() {
      state = [...state, annotation];
    });
  }

  /// Replaces the annotation with [id] using [update]. No-op when absent.
  void updateById(String id, Annotation Function(Annotation) update) {
    final index = state.indexWhere((a) => a.id == id);
    if (index < 0) return;
    _recordChange(() {
      final next = [...state];
      next[index] = update(next[index]);
      state = next;
    });
  }

  void setText(String id, String text) {
    final capped = text.length > kAnnotationTextMaxLength
        ? text.substring(0, kAnnotationTextMaxLength)
        : text;
    updateById(id, (a) => a.copyWith(text: capped));
  }

  /// Moves the *label*, never the anchor. The distinction is the model's
  /// central invariant — see [Annotation].
  void setLabelOffset(String id, double dx, double dy) {
    updateById(id, (a) => a.copyWith(labelDx: dx, labelDy: dy));
  }

  /// Moves the label by a relative delta, resolved against the **current**
  /// state rather than a caller-held snapshot.
  ///
  /// A drag emits many move events between frames. A caller that computed
  /// `capturedOffset + delta` would resolve every one of them against the same
  /// build-time value, so all but the last would be discarded and the balloon
  /// would travel a fraction of the pointer's distance.
  void nudgeLabel(String id, double dx, double dy) {
    updateById(
      id,
      (a) => a.copyWith(labelDx: a.labelDx + dx, labelDy: a.labelDy + dy),
    );
  }

  /// Moves the *anchor* — the deliberate, separately-afforded gesture.
  void reanchor(String id, AnnotationAnchor anchor) {
    updateById(id, (a) => a.copyWith(anchor: anchor));
  }

  /// Moves one end of a band, leaving the other where it is.
  ///
  /// The ends are **not** normalised: dragging the left edge past the right one
  /// is a legitimate thing to do mid-gesture, and re-ordering them under the
  /// user's finger would make the handle they are holding jump to the other
  /// side. [RangeAnchor.earliest] / [RangeAnchor.latest] already give every
  /// reader a normalised view, so nothing downstream cares.
  void setRangeEnd(String id, {required bool isStart, required int time}) {
    updateById(id, (a) {
      final anchor = a.anchor;
      if (anchor is! RangeAnchor) return a;
      return a.copyWith(
        anchor: RangeAnchor(
          startTime: isStart ? time : anchor.startTime,
          endTime: isStart ? anchor.endTime : time,
          rowId: anchor.rowId,
        ),
      );
    });
  }

  /// Switches a band between spanning one lane and spanning the whole canvas.
  ///
  /// Passing `null` makes it full-height. A band's row is presentation, not
  /// identity — unlike a callout's, where the row *is* what the note is about —
  /// so this is an ordinary edit rather than a re-anchor.
  void setRangeRow(String id, String? rowId) {
    updateById(id, (a) {
      final anchor = a.anchor;
      if (anchor is! RangeAnchor) return a;
      return a.copyWith(
        anchor: RangeAnchor(
          startTime: anchor.startTime,
          endTime: anchor.endTime,
          rowId: rowId,
        ),
      );
    });
  }

  void setCollapsed(String id, {required bool collapsed}) {
    updateById(id, (a) => a.copyWith(collapsed: collapsed));
  }

  void remove(String id) {
    if (!state.any((a) => a.id == id)) return;
    _recordChange(() {
      state = [...state.where((a) => a.id != id)];
    });
  }

  /// Removes every annotation belonging to [layerId] in one undo step — how a
  /// user discards an adopted collaboration layer.
  void removeLayer(String layerId) {
    if (!state.any((a) => a.layerId == layerId)) return;
    _recordChange(() {
      state = [...state.where((a) => a.layerId != layerId)];
    });
  }

  // ── session integration ────────────────────────────────────────────────────

  /// The list as it should be written into a `.wavecrux` document.
  List<Annotation> snapshot() => List.unmodifiable(state);

  /// Replaces the list wholesale on session load, clearing history.
  ///
  /// History is cleared deliberately: undoing across a file load would
  /// resurrect annotations from a different waveform, which is worse than
  /// losing the ability to undo the load.
  void restoreFromSession(List<Annotation> annotations) {
    _undoStack.clear();
    _redoStack.clear();
    _pendingTransactionSnapshot = null;
    state = List.unmodifiable(annotations);
  }
}

/// Whether annotations are drawn on the canvas at all.
///
/// A *view* setting, persisted with the rest of the session: hiding notes to
/// read the raw waveform for a minute should not mean losing them, and the
/// state should still be there when the file is reopened. Export honours it
/// too — what you exported is what you were looking at.
@Riverpod(keepAlive: true)
class AnnotationsVisible extends _$AnnotationsVisible {
  @override
  bool build() => true;

  bool get visible => state;

  set visible(bool value) => state = value;

  void toggle() => state = !state;
}

/// Every displayed signal row's stable path, for the "is this annotation's row
/// on screen?" question.
@riverpod
Set<String> displayedSignalPaths(Ref ref) {
  final group = ref.watch(signalGroupsProvider);
  final paths = <String>{};
  void visit(List<SignalEntry> entries) {
    for (final entry in entries) {
      final path = entry.signalPath;
      if (path != null) paths.add(path);
      if (entry.children.isNotEmpty) visit(entry.children);
    }
  }

  visit(group.entries);
  return Set.unmodifiable(paths);
}

/// Live classification of every annotation against the loaded waveform, keyed
/// by annotation id.
///
/// Recomputed rather than stored, because the entire point is that the answer
/// changes when the design does: reopen a session against a re-simulated dump
/// and the notes that no longer hold report [AnnotationStatus.drifted] without
/// anyone having to ask.
@riverpod
Map<String, AnnotationStatus> annotationStatuses(Ref ref) {
  final annotations = ref.watch(annotationsProvider);
  if (annotations.isEmpty) return const <String, AnnotationStatus>{};

  final displayed = ref.watch(displayedSignalPathsProvider);
  final byPath = ref.watch(signalVariablesByPathProvider);
  final source = ref.watch(waveformSourceProvider).value;

  // Recompute when sample data finishes loading. Nothing else changes at that
  // moment — the source is the same instance and the signal list settled
  // earlier — so without this a status computed while `valueAt` still returned
  // null would be memoized forever. After an in-place reload that meant a
  // stale note kept reporting the previous run's answer.
  ref.watch(waveformDataRevisionProvider);

  // No per-row display format is read here: comparison is on canonical bits,
  // so the answer is independent of the radix each row happens to be showing.
  const witnessService = AnnotationWitnessService();
  final out = <String, AnnotationStatus>{};

  for (final annotation in annotations) {
    final rowId = annotation.rowId;
    if (rowId == null) {
      out[annotation.id] = AnnotationStatus.unanchoredToRow;
      continue;
    }

    final variable = byPath[rowId];
    final isDisplayed = displayed.contains(rowId);

    String? current;
    if (variable != null && isDisplayed && source != null) {
      // A null width means "not a sized bit vector" (a real/analog signal),
      // which ValueFormatService documents as width 0 — pass it through rather
      // than inventing a width and mis-padding the comparison string.
      current = witnessService.currentBits(
        source: source,
        signalRef: variable.signalRef,
        time: annotation.sortTime,
        bitWidth: variable.bitWidth ?? 0,
      );
    }

    out[annotation.id] = AnnotationWitnessService.statusOf(
      annotation,
      isDisplayed: isDisplayed,
      existsInFile: variable != null,
      currentBits: current,
    );
  }
  return Map.unmodifiable(out);
}

/// The annotation set in walkthrough order — by anchor tick, then by creation
/// time so two notes on the same edge keep a stable, authored order.
@riverpod
List<Annotation> annotationsInTimeOrder(Ref ref) {
  final annotations = [...ref.watch(annotationsProvider)]
    ..sort((a, b) {
      final byTime = a.sortTime.compareTo(b.sortTime);
      return byTime != 0 ? byTime : a.createdAt.compareTo(b.createdAt);
    });
  return List.unmodifiable(annotations);
}
