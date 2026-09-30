// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/features/annotations/providers/annotation_layers_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/collaboration/providers/collaboration_session_state_provider.dart';

part 'session_annotations_provider.g.dart';

/// Every annotation the canvas should draw: the local ones, plus any authored
/// inside a live collaborative session.
///
/// **One renderer, two sources.** The overlay does not know or care whether a
/// note came from this machine or from the room — it projects `(tick, rowId)`
/// the same way either way. What differs is only what the annotations *look*
/// like, and that difference is resolved here so the drawing code stays one
/// code path.
///
/// ### Colour is decided here, applied in the widget
///
/// This provider says *which* notes wear a participant colour, via
/// [sessionAnnotationColorIndexProvider]; the overlay turns that index into a
/// `Color`. The split is not ceremony — the palette lives in the viewer's
/// widget layer, and a provider under `features/annotations/` reaching across
/// to a sibling feature's widgets is exactly what the import-layering guard
/// exists to stop. It also keeps `dart:ui` out of the state layer, the same
/// rule the `Annotation` model itself follows.
///
/// A participant's **pre-existing local annotations never appear in that map**,
/// and that asymmetry is deliberate rather than an oversight. If joining a
/// session recoloured somebody's week-old private notes into their participant
/// colour, everyone in the room would read them as things said in this
/// meeting. Local notes are yours; session notes are the meeting's.
///
/// ### Open core without a session is unchanged
///
/// With the no-op collaboration service there is no session, the session list
/// is empty, and this returns the local list — the same object, so nothing
/// downstream rebuilds and the open-core build behaves exactly as it did
/// before C4.
/// Local notes plus the live session's, **unfiltered** — the panel's source.
///
/// Separate from [visibleAnnotations] because the two surfaces want different
/// sets, and conflating them cost the panel its whole reason to exist. The
/// canvas hides a hidden layer; the panel must keep listing that layer, because
/// its toggle is the only way to get it back — a layer you cannot see and
/// cannot find again is a layer you have lost.
///
/// Before this existed the panel read the LOCAL-only list, so during a session
/// the canvas drew a colleague's note that the panel did not list at all, and
/// every row action the panel owns — set anchor time, collapse, delete, "show
/// signal" for an orphan — was unreachable for exactly the notes somebody else
/// had just written.
@Riverpod(dependencies: [AnnotationsNotifier, AdoptedAnnotationIds])
List<Annotation> composedAnnotations(Ref ref) {
  final local = ref.watch(annotationsProvider);
  final adopted = ref.watch(adoptedAnnotationIdsProvider);
  final session = ref.watch(collaborationSessionStateProvider).value;
  // Same object when there is no session, so the open-core path rebuilds
  // nothing downstream and behaves exactly as it did before C4.
  if (session == null || session.annotations.isEmpty) return local;

  final merged = <Annotation>[...local];
  final localIds = {for (final a in local) a.id};
  for (final entry in session.annotations) {
    // De-duplicate by id. A participant's own session notes are in both lists:
    // they are local (they wrote them here) and they came back on the host's
    // authoritative snapshot. The local copy wins, because it is the one the
    // author is editing.
    //
    // **This also covers a note you ADOPTED from an earlier session** — the id
    // survives adoption, so rejoining the room does not hand you a second copy
    // of something already in your document. Without that, deleting your own
    // kept note made an identical one reappear from the room, which reads as
    // the delete having failed. The document wins over the room for anything
    // it already holds.
    if (localIds.contains(entry.id)) continue;
    if (adopted.contains(entry.id)) continue;
    merged.add(entry.annotation);
  }
  return List.unmodifiable(merged);
}

/// [composedAnnotations] in walkthrough order — by anchor tick, then creation.
@Riverpod(dependencies: [composedAnnotations])
List<Annotation> composedAnnotationsInTimeOrder(Ref ref) {
  final all = [...ref.watch(composedAnnotationsProvider)]
    ..sort((a, b) {
      final byTime = a.sortTime.compareTo(b.sortTime);
      return byTime != 0 ? byTime : a.createdAt.compareTo(b.createdAt);
    });
  return List.unmodifiable(all);
}

/// What the CANVAS draws: [composedAnnotations] minus any hidden layer.
@Riverpod(dependencies: [composedAnnotations, hiddenAnnotationLayerIds])
List<Annotation> visibleAnnotations(Ref ref) {
  final hidden = ref.watch(hiddenAnnotationLayerIdsProvider);
  final all = ref.watch(composedAnnotationsProvider);
  if (hidden.isEmpty) return all;
  return List.unmodifiable([
    for (final a in all)
      if (a.layerId == null || !hidden.contains(a.layerId)) a,
  ]);
}

/// Ids this document has already settled, and will not take from the room again.
///
/// **Option B, the answer to a note existing in two places.** Adoption keeps a
/// note's id, so rejoining a room hands you the original of something your
/// document already decided about. While your copy exists the composed set
/// prefers it — but delete your copy and the room's version reappears, which
/// reads as the delete having failed, and re-deleting achieves nothing because
/// the room keeps re-offering it.
///
/// Recording the decision fixes both halves: the document wins over the room
/// for anything it has adopted, including the decision to throw it away.
///
/// **In memory, deliberately.** The collision only arises inside one app run —
/// end a session, adopt, rejoin — and persisting a tombstone list would put a
/// growing set of ids into every saved session for a case that does not survive
/// a restart. A restart re-offers an adopted-then-deleted note once. That is a
/// known, bounded gap rather than an oversight.
@Riverpod(keepAlive: true)
class AdoptedAnnotationIds extends _$AdoptedAnnotationIds {
  @override
  Set<String> build() => const {};

  /// Records that this document has taken a position on [ids].
  void remember(Iterable<String> ids) =>
      state = Set.unmodifiable({...state, ...ids});
}

/// Ids that exist ONLY in the live session — notes somebody else wrote.
///
/// Your own session notes are absent: you authored them locally, so they are in
/// both lists and the local copy is the one you edit. What is left is exactly
/// the set the local store cannot mutate, which is what every row action needs
/// to know before offering itself.
///
/// Offering an action that silently fails is worse than not offering it — it is
/// the defect the read-only lock on *Edit text* exists to avoid, and the panel
/// reproduced it four more times the moment it began listing remote notes.
@Riverpod(dependencies: [AnnotationsNotifier])
Set<String> sessionOnlyAnnotationIds(Ref ref) {
  final session = ref.watch(collaborationSessionStateProvider).value;
  if (session == null || session.annotations.isEmpty) {
    return const <String>{};
  }
  final localIds = {for (final a in ref.watch(annotationsProvider)) a.id};
  return Set.unmodifiable({
    for (final entry in session.annotations)
      if (!localIds.contains(entry.id)) entry.id,
  });
}

/// Whether the local participant may remove somebody else's note.
///
/// The host is the sole exception to author-only rights, and the service
/// already enforces exactly this on the wire — `_handleAnnotation`'s remove
/// branch accepts a removal from the author or the host and drops every other.
/// This is the UI asking the same question before showing the control.
@Riverpod(dependencies: [])
bool canModerateAnnotations(Ref ref) =>
    ref.watch(collaborationSessionStateProvider).value?.isLocalHost ?? false;

/// Palette slot for each **session-authored** annotation, by annotation id.
///
/// Only session notes appear here. An id that is absent renders in the theme
/// colour, which is what every local note does and must keep doing.
///
/// An index rather than a colour so the state layer stays free of `dart:ui`,
/// and so the *resolution* happens where the palette lives. The index is a
/// per-session 0–7 slot and is deliberately never persisted — adoption freezes a
/// resolved colour at adoption, precisely because next week's session
/// reassigns these slots.
@riverpod
Map<String, int> sessionAnnotationColorIndex(Ref ref) {
  final session = ref.watch(collaborationSessionStateProvider).value;
  if (session == null || session.annotations.isEmpty) {
    return const <String, int>{};
  }
  final byParticipant = <String, int>{
    for (final p in session.participants) p.id: p.colorIndex,
  };
  return Map.unmodifiable(<String, int>{
    for (final entry in session.annotations)
      entry.id: ?byParticipant[entry.authorId],
  });
}

/// The same set in walkthrough order — by anchor tick, then creation time.
///
/// Mirrors [annotationsInTimeOrderProvider] over the composed set, so a
/// walkthrough during a session steps through the room's notes too rather than
/// only the local ones.
@Riverpod(dependencies: [visibleAnnotations])
List<Annotation> visibleAnnotationsInTimeOrder(Ref ref) {
  final annotations = [...ref.watch(visibleAnnotationsProvider)]
    ..sort((a, b) {
      final byTime = a.sortTime.compareTo(b.sortTime);
      return byTime != 0 ? byTime : a.createdAt.compareTo(b.createdAt);
    });
  return List.unmodifiable(annotations);
}

/// One "…is writing a note…" chip: who, where, and in whose colour.
///
/// A view model rather than the wire type, because the two carry different
/// things: the wire has a participant *id*, and what the canvas needs is the
/// name to print and the palette slot to print it in. Resolving that here
/// keeps the lookup out of the overlay's build loop and keeps `dart:ui` out of
/// the state layer — [colorIndex] is an index for the same reason
/// [sessionAnnotationColorIndexProvider] is.
@immutable
class WritingChip {
  const WritingChip({
    required this.participantId,
    required this.name,
    required this.colorIndex,
    required this.time,
    required this.rowId,
  });

  final String participantId;
  final String name;

  /// The author's per-session palette slot, or `null` if they somehow have
  /// none — the chip then falls back to the theme colour rather than vanishing.
  final int? colorIndex;

  /// Anchor of the note being composed. `null` when it has none, in which case
  /// the canvas draws nothing: an unanchored chip pinned to the top edge would
  /// say "somebody, somewhere", which is not worth the pixels.
  final int? time;
  final String? rowId;

  @override
  bool operator ==(Object other) =>
      other is WritingChip &&
      other.participantId == participantId &&
      other.name == name &&
      other.colorIndex == colorIndex &&
      other.time == time &&
      other.rowId == rowId;

  @override
  int get hashCode => Object.hash(participantId, name, colorIndex, time, rowId);
}

/// Everyone **else** currently composing a note, resolved for display.
///
/// The local participant is filtered out — being told you are typing is not
/// information — and so is anybody the roster does not know, which is the same
/// posture the rest of the session state takes toward unattributable frames.
@riverpod
List<WritingChip> writingAnnotationChips(Ref ref) {
  final session = ref.watch(collaborationSessionStateProvider).value;
  if (session == null || session.writingAnnotation.isEmpty) {
    return const <WritingChip>[];
  }
  final byId = {for (final p in session.participants) p.id: p};
  final chips = <WritingChip>[];
  for (final entry in session.writingAnnotation) {
    if (entry.participantId == session.myParticipantId) continue;
    final participant = byId[entry.participantId];
    if (participant == null) continue;
    chips.add(
      WritingChip(
        participantId: entry.participantId,
        name: participant.displayName,
        colorIndex: participant.colorIndex,
        time: entry.time,
        rowId: entry.rowId,
      ),
    );
  }
  return List.unmodifiable(chips);
}
