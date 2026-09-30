// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/plugins/translator_registry.dart';

part 'translator_expansion_provider.g.dart';

/// Which translator-bound signal rows are currently expanded into child rows.
///
/// Keyed by [SignalEntry.id]. Expansion state lives here — in a `keepAlive`
/// Riverpod provider — rather than in widget `State` so it survives list
/// rebuilds, scrolling, and orientation changes (the open-core
/// orientation-resilience rule). Toggling re-derives [signalChildRowCounts],
/// which the three columns and [LaneGeometry] read to reserve identical child
/// space so subfields never drift from their wave.
@Riverpod(keepAlive: true)
class ExpandedTranslatorRows extends _$ExpandedTranslatorRows {
  @override
  Set<String> build() => const {};

  /// Expands [entryId] if collapsed, collapses it if expanded.
  void toggle(String entryId) {
    final next = Set<String>.of(state);
    if (!next.remove(entryId)) next.add(entryId);
    state = next;
  }

  /// True when [entryId] is currently expanded.
  bool isExpanded(String entryId) => state.contains(entryId);

  /// Collapses every row (e.g. on session reset).
  void collapseAll() => state = const {};
}

/// The number of child rows every expanded, bitfield-bound signal contributes,
/// keyed by [SignalEntry.id].
///
/// This is the single source the value column ([LaneGeometry]), the waveform
/// canvas, and the signal-names list all read to reserve identical vertical
/// child-row space — so the columns cannot drift out of alignment. The count is
/// static per signal (the number of declared field specs), independent of the
/// cursor value, which is what makes geometry reservation possible.
@Riverpod(dependencies: [SignalGroupsNotifier, ExpandedTranslatorRows])
Map<String, int> signalChildRowCounts(Ref ref) {
  final group = ref.watch(signalGroupsProvider);
  final expanded = ref.watch(expandedTranslatorRowsProvider);
  if (expanded.isEmpty) return const {};

  // Resolve each expanded row's translator from the registry (so Pro-pack
  // translators contributed through `extraTranslatorsProvider` participate)
  // and ask it for its static child-row count. Translators that don't
  // implement [ChildRowTranslator] (the built-in flat formatter, RISC-V
  // disassembly) reserve no rows and render inline.
  final registry = ref.watch(translatorRegistryProvider);

  final counts = <String, int>{};
  void visit(List<SignalEntry> entries) {
    for (final entry in entries) {
      switch (entry.kind) {
        case SignalEntryKind.signal:
          if (expanded.contains(entry.id)) {
            final n = translatorChildRowCount(registry, entry.translatorConfig);
            if (n > 0) counts[entry.id] = n;
          }
        case SignalEntryKind.group:
          visit(entry.children);
        case SignalEntryKind.separator:
        case SignalEntryKind.comment:
          break;
      }
    }
  }

  visit(group.entries);
  return counts;
}

/// The static child-row count for [config], resolved through [registry]: looks
/// up the bound translator by its [kTranslatorIdConfigKey] id and asks it when
/// it is a [ChildRowTranslator]. Returns `0` when unbound, unknown, or flat.
///
/// This is the single source of truth for "how many expandable child rows does
/// this binding reserve" — read by [signalChildRowCounts] (to inflate geometry
/// for *expanded* rows) and by the value-column row (to decide whether to show
/// the expand chevron at all: a flat or inline-only translator like RISC-V
/// disassembly reserves `0`, so it gets no chevron).
int translatorChildRowCount(
  TranslatorRegistry registry,
  Map<String, Object?>? config,
) {
  final id = config?[kTranslatorIdConfigKey] as String?;
  if (id == null) return 0;
  final translator = registry.get(id);
  if (translator is! ChildRowTranslator) return 0;
  return translator.childRowCount(config);
}
