// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/custom_translator_def.dart';

part 'custom_translators_provider.g.dart';

/// The library of user-authored [CustomTranslatorDef]s.
///
/// `keepAlive` so authored translators survive navigation and orientation
/// changes within a session. Definitions are referenced by name when bound to a
/// signal; the binding itself is persisted per-signal in the `.wavecrux`
/// session via `SignalEntry.translatorConfig`, so a bound signal keeps its
/// decomposition independently of this in-memory library.
@Riverpod(keepAlive: true)
class CustomTranslators extends _$CustomTranslators {
  @override
  List<CustomTranslatorDef> build() => const [];

  /// Adds [def], or replaces an existing definition with the same name.
  void upsert(CustomTranslatorDef def) {
    final next = [
      for (final d in state)
        if (d.name != def.name) d,
      def,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = next;
  }

  /// Replaces the definition formerly named [oldName] with [def] (supports
  /// renames). When [oldName] is absent this behaves like [upsert].
  void rename(String oldName, CustomTranslatorDef def) {
    final next = [
      for (final d in state)
        if (d.name != oldName && d.name != def.name) d,
      def,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = next;
  }

  /// Removes the definition named [name]. No-op when absent.
  void remove(String name) {
    state = [
      for (final d in state)
        if (d.name != name) d,
    ];
  }

  /// Returns the definition named [name], or null.
  CustomTranslatorDef? byName(String name) {
    for (final d in state) {
      if (d.name == name) return d;
    }
    return null;
  }

  // ── view-composition recipe seams ──────────────────────────────────

  /// Serialize the translator library into a recipe for collaboration
  /// view-composition sync. The definitions are machine-independent (id +
  /// config), so the current library *is* the recipe — a follower replays a
  /// programmable bitfield translator the presenter authored against its own
  /// data.
  List<CustomTranslatorDef> toCompositionRecipe() => state;

  /// Apply a presenter's translator [recipe], replacing the library so that
  /// per-signal translator bindings in the displayed-signal recipe resolve.
  /// The [CollabViewerBridge] has captured the follower's own library for
  /// restore-on-detach.
  void applyCompositionRecipe(List<CustomTranslatorDef> recipe) {
    state = [...recipe]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}
