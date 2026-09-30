// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:wavecrux/core/theme/collaborator_palette.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/features/annotations/providers/annotation_layers_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/annotations/providers/session_annotations_provider.dart';

part 'annotation_adoption_provider.g.dart';

/// One annotation offered for adoption when a collaborative session ends,
/// with the colour it wore in the room already resolved.
///
/// **The colour is resolved here and stored as an int, on purpose.** In the
/// session an annotation's colour comes from its author's `colorIndex` — a
/// per-session 0–7 palette slot that means nothing once the session is over,
/// and that next week's session hands to somebody else. Carrying the index
/// into the document would make last week's notes silently recolour and
/// misattribute themselves the moment a new session reassigned the slots. The
/// index is therefore never persisted: it is turned into an RGB value exactly
/// once, at this boundary, which is where the annotation stops being a session
/// artifact and becomes part of a document.
@immutable
class AdoptableAnnotation {
  const AdoptableAnnotation({
    required this.annotation,
    required this.isMine,
    this.colorIndex,
  });

  /// The note itself, in the open-core model.
  final Annotation annotation;

  /// Whether the local user wrote it — the discriminator "Keep only mine"
  /// uses. Decided by the *participant id* in the room rather than by the
  /// display name on the note, because two people called Martin must not
  /// inherit each other's work.
  final bool isMine;

  /// The author's palette slot in the session that is ending, or `null` for an
  /// author the roster no longer knows. A null slot adopts in the theme
  /// colour, which reads as "unattributed" rather than as somebody else's.
  final int? colorIndex;
}

/// The annotations a just-ended session left behind, awaiting the user's
/// decision.
///
/// `null` means there is nothing to ask about — no session has ended, or the
/// one that did produced no notes.
@immutable
class PendingAdoption {
  const PendingAdoption({
    required this.candidates,
    required this.participantCount,
    required this.endedAt,
    this.sessionId,
  });

  final List<AdoptableAnnotation> candidates;

  /// How many people were in the room, for the layer's label. Not
  /// `candidates.length` — three people can leave twelve notes, and the label
  /// says both because both are how somebody recognises the group later.
  final int participantCount;

  /// When the session ended, for the label's date. Passed in rather than read
  /// from the clock at adoption time so the label is stable no matter how long
  /// the prompt sits unanswered.
  final DateTime endedAt;

  final String? sessionId;

  int get count => candidates.length;
  int get mineCount => candidates.where((c) => c.isMine).length;
}

/// Whether a session's annotations are waiting on a *Keep all / Keep only mine
/// / Discard* decision, and which ones.
///
/// Held rather than acted on, because the choice is the user's and the prompt
/// is deliberately non-modal — a dialog thrown up the instant a meeting ends
/// is a dialog dismissed without being read.
///
/// **Per-tab**, like everything else annotations touch: the session mirrors one
/// tab, and the notes it leaves behind belong to that tab's waveform.
///
/// **keepAlive**, and load-bearing rather than tidiness — the same trap
/// `AnnotationBeingEdited` documents. The offer is written by the collaboration
/// bridge at the moment a session ends, when nothing is watching yet: the
/// prompt only starts watching on its next build. An auto-dispose provider
/// throws that write away in between, and the prompt never appears — which
/// would silently make "discard" the outcome of every session, the one branch
/// the design says must never happen by default.
@Riverpod(keepAlive: true)
class AnnotationAdoption extends _$AnnotationAdoption {
  @override
  PendingAdoption? build() => null;

  static const _uuid = Uuid();

  /// Offer [pending] for adoption. A pending set with nothing in it is ignored
  /// rather than shown as an empty prompt.
  void offer(PendingAdoption pending) {
    if (pending.candidates.isEmpty) return;
    state = pending;
  }

  /// Adopt every note the session produced, or only the local user's.
  ///
  /// Both land as ONE named layer. "Keep only mine" is still a layer rather
  /// than loose notes: they were still written in that meeting, and a week
  /// later "which of these came out of the review?" is the same question
  /// whoever wrote them.
  ///
  /// Returns the layer's id, or `null` when nothing was adopted.
  String? keep({required bool onlyMine, required String label}) {
    final pending = state;
    if (pending == null) return null;
    final chosen = onlyMine
        ? pending.candidates.where((c) => c.isMine).toList()
        : pending.candidates;
    state = null;
    if (chosen.isEmpty) return null;

    final layerId = _uuid.v4();
    ref
        .read(annotationLayersProvider.notifier)
        .upsert(
          AnnotationLayer(
            id: layerId,
            label: label,
            sourceSessionId: pending.sessionId,
          ),
        );

    final notifier = ref.read(annotationsProvider.notifier)..beginTransaction();
    for (final candidate in chosen) {
      notifier.add(
        candidate.annotation.copyWith(
          layerId: layerId,
          // The freeze. See [AdoptableAnnotation] — an index would be a
          // borrowed slot, and the loan comes due next session.
          colorRgb: candidate.colorIndex == null
              ? null
              : collaboratorColor(candidate.colorIndex!).toARGB32(),
          clearColor: candidate.colorIndex == null,
        ),
      );
    }
    notifier.endTransaction();
    // The room must not hand these back on the next join — see
    // [AdoptedAnnotationIds]. Recorded for everything the prompt OFFERED, not
    // only what was kept: "keep only mine" is as much a decision about the
    // others as about yours, and a discarded note reappearing would be the same
    // bug wearing different clothes.
    ref
        .read(adoptedAnnotationIdsProvider.notifier)
        .remember(pending.candidates.map((c) => c.annotation.id));
    return layerId;
  }

  /// Throw the session's notes away. One undo step, because "Discard" landing
  /// on the wrong button is exactly the mistake this prompt can cause.
  void discard() => state = null;

  /// Dismiss the prompt **keeping everything**.
  ///
  /// The branch a closed prompt takes, and the reason is worth keeping through
  /// any future refactor of this file: silently discarding destroys the
  /// meeting's output, silently keeping merely surprises somebody, and when
  /// the user simply closes the prompt we take the branch that does not lose
  /// work irreversibly. A kept layer deletes with one control; a discarded one
  /// is gone.
  String? dismiss({required String label}) =>
      keep(onlyMine: false, label: label);
}
