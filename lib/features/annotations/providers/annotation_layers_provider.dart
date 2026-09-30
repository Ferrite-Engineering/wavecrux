// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/collaboration/providers/collaboration_session_state_provider.dart';

part 'annotation_layers_provider.g.dart';

/// The tab's registry of adopted annotation layers.
///
/// Holds only the *names*; the annotations themselves stay in
/// [AnnotationsNotifier] carrying a `layerId`. Two lists rather than a nested
/// structure because every existing reader — the canvas, the panel, export,
/// `.wavecrux`, the share bundle — wants a flat annotation list, and nesting
/// would have made all of them walk a tree to get one.
///
/// Per-tab like the annotations it names.
@riverpod
class AnnotationLayers extends _$AnnotationLayers {
  @override
  List<AnnotationLayer> build() => const <AnnotationLayer>[];

  /// Registers [layer], replacing any entry with the same id.
  void upsert(AnnotationLayer layer) {
    final index = state.indexWhere((l) => l.id == layer.id);
    if (index < 0) {
      state = [...state, layer];
      return;
    }
    final next = [...state];
    next[index] = layer;
    state = next;
  }

  /// Shows or hides a layer's annotations on the canvas.
  ///
  /// Hiding is not deleting: the panel keeps listing the group, because a
  /// layer you cannot see and cannot find again is a layer you have lost.
  void setVisible(String id, {required bool visible}) {
    final index = state.indexWhere((l) => l.id == id);
    if (index < 0) return;
    if (state[index].visible == visible) return;
    final next = [...state];
    next[index] = state[index].copyWith(visible: visible);
    state = next;
  }

  /// Drops the registry entry. The annotations are removed separately, by
  /// [AnnotationsNotifier.removeLayer] — deleting a group is one undo step for
  /// the notes and a registry edit for the name, and only the notes are
  /// undoable.
  void remove(String id) {
    if (!state.any((l) => l.id == id)) return;
    state = [...state.where((l) => l.id != id)];
  }

  /// The registry as it should be written into a `.wavecrux` document.
  List<AnnotationLayer> snapshot() => List.unmodifiable(state);

  /// Replaces the registry wholesale on session load.
  void restoreFromSession(List<AnnotationLayer> layers) {
    state = List.unmodifiable(layers);
  }
}

/// Ids of layers currently hidden, for the canvas to skip.
///
/// A set rather than a repeated linear scan: the overlay asks this question
/// once per annotation per build.
@Riverpod(dependencies: [AnnotationLayers])
Set<String> hiddenAnnotationLayerIds(Ref ref) => Set.unmodifiable({
  for (final layer in ref.watch(annotationLayersProvider))
    if (!layer.visible) layer.id,
});

/// Whether the local user may edit an annotation's **text**.
///
/// Adopted notes are read-only by attribution: somebody else's words stay
/// somebody else's, and an editable one would let a reader put a sentence in a
/// named colleague's mouth a week after the meeting. Hiding, deleting and
/// "duplicate as mine" all stay available — what is refused is rewriting the
/// text while the original author's name is on it.
///
/// Notes in the implicit `null` layer are editable, **unless somebody else is
/// writing them right now**.
///
/// The live-session half is the same rule one moment earlier. Rights are
/// author-only on the wire, so an edit to another participant's note is
/// refused by the service — and until this set knew about it, the UI let you
/// open the editor anyway: you typed a sentence, pressed Enter, and watched it
/// vanish as the authoritative state came back. Refusing at the affordance is
/// the difference between "you may not edit this" and "your work was silently
/// discarded".
@Riverpod(dependencies: [AnnotationsNotifier])
Set<String> readOnlyAnnotationIds(Ref ref) {
  final session = ref.watch(collaborationSessionStateProvider).value;
  final theirs = <String>{};
  if (session != null) {
    for (final entry in session.annotations) {
      if (entry.authorId != session.myParticipantId) theirs.add(entry.id);
    }
  }
  return Set.unmodifiable({
    for (final annotation in ref.watch(annotationsProvider))
      if (annotation.layerId != null) annotation.id,
    ...theirs,
  });
}
