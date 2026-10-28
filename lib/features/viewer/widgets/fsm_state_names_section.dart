// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/fsm_annotation.dart';
import 'package:wavecrux/domain/models/fsm_model.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/inspector_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/widgets/signal_format_section.dart'
    show findSignalEntry;
import 'package:wavecrux/l10n/generated/l10n.dart';

/// The Inspector's FSM section for a signal row ([InspectedSignal]): a name
/// field for each state of the row's signal. Null when [target] is not a
/// signal row of [rows], or when [hasStates] says no states of its signal are
/// known: the FSM on show is another signal's, none is named, and "Annotate
/// FSM states…" has not been chosen on it.
Widget? fsmStateNamesInspectorSection(
  BuildContext context,
  WaveCruxInspectable target, {
  required List<SignalEntry> rows,
  required bool Function(String signalRef) hasStates,
}) {
  if (target is! InspectedSignal) return null;
  final signalRef = findSignalEntry(rows, target.entryId)?.signalRef;
  if (signalRef == null || !hasStates(signalRef)) return null;
  return FsmStateNamesSection(entryId: target.entryId);
}

/// The state ids of [signalRef] the FSM section lists: those of [model] (the
/// FSM on show) when it is this signal's, the ids [named], the ids "Annotate
/// FSM states…" [found], and any in [draft]; sorted numerically.
List<String> fsmStateIdsOf(
  String signalRef, {
  required FsmModel? model,
  required Map<String, FsmAnnotation> named,
  required Map<String, List<String>> found,
  FsmStateNamesDraft? draft,
}) => <String>{
  if (model != null && model.signalRef == signalRef)
    for (final s in model.states) s.id,
  ...?named[signalRef]?.stateLabels.keys,
  ...?found[signalRef],
  ...?draft?.labels.keys,
}.toList()..sort(compareFsmStateIds);

/// Orders state ids numerically when both are numbers, else as text.
int compareFsmStateIds(String a, String b) {
  final ai = BigInt.tryParse(a);
  final bi = BigInt.tryParse(b);
  if (ai != null && bi != null) return ai.compareTo(bi);
  return a.compareTo(b);
}

/// See [fsmStateNamesInspectorSection].
///
/// The names apply together on Apply (Enter in a field applies too); a
/// blank name shows the raw value. The draft lives in the tab's
/// [fsmStateNameDraftsProvider]; while it holds unapplied names the
/// Inspector keeps showing this row.
class FsmStateNamesSection extends ConsumerStatefulWidget {
  /// Creates the section for the viewer row [entryId].
  const FsmStateNamesSection({required this.entryId, super.key});

  /// The viewer row's id.
  final String entryId;

  @override
  ConsumerState<FsmStateNamesSection> createState() =>
      _FsmStateNamesSectionState();
}

class _FsmStateNamesSectionState extends ConsumerState<FsmStateNamesSection> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};

  String? get _signalRef => findSignalEntry(
    ref.read(signalGroupsProvider).entries,
    widget.entryId,
  )?.signalRef;

  @override
  void initState() {
    super.initState();
    // A section remounted over a kept draft must hold the row again.
    final signalRef = _signalRef;
    CruxInspector.markDirty(
      context,
      dirty:
          signalRef != null &&
          (ref.read(fsmStateNameDraftsProvider)[signalRef]?.isDirty ?? false),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The field for [id]. With no draft its text follows the names in use
  /// ([text]), set after the frame: a name applied elsewhere, or a session
  /// restored under the open section, shows here too.
  TextEditingController _controllerFor(
    String id,
    String text, {
    required bool drafting,
  }) {
    final controller = _controllers.putIfAbsent(
      id,
      () => TextEditingController(text: text),
    );
    if (!drafting && controller.text != text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.text != text) controller.text = text;
      });
    }
    return controller;
  }

  /// Puts every field back to [labels].
  void _resetFields(Map<String, String> labels) {
    for (final e in _controllers.entries) {
      e.value.text = labels[e.key] ?? '';
    }
  }

  FsmStateNamesDraft _seed(String signalRef, List<String> ids) {
    final named =
        ref.read(fsmAnnotationProvider)[signalRef]?.stateLabels ??
        const <String, String>{};
    final labels = Map<String, String>.unmodifiable(<String, String>{
      for (final id in ids) id: named[id] ?? '',
    });
    return FsmStateNamesDraft(labels: labels, initialLabels: labels);
  }

  Future<void> _apply(String signalRef, FsmStateNamesDraft draft) async {
    final labels = <String, String>{
      for (final e in draft.labels.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
    };
    final notifier = ref.read(fsmAnnotationProvider.notifier);
    if (labels.isEmpty) {
      notifier.removeAnnotation(signalRef);
    } else {
      notifier.setAnnotation(
        signalRef,
        FsmAnnotation(signalRef: signalRef, stateLabels: labels),
      );
    }
    ref.read(fsmStateNameDraftsProvider.notifier).discard(signalRef);
    _resetFields(labels);
    // The FSM diagram of this signal shows the names at once.
    if (ref.read(fsmProvider).signalRef == signalRef) {
      await ref.read(fsmProvider.notifier).refresh();
    }
  }

  void _revert(String signalRef, FsmStateNamesDraft draft) {
    ref.read(fsmStateNameDraftsProvider.notifier).discard(signalRef);
    _resetFields(draft.initialLabels);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final entry = findSignalEntry(
      ref.watch(signalGroupsProvider).entries,
      widget.entryId,
    );
    final signalRef = entry?.signalRef;
    if (signalRef == null) return const SizedBox.shrink();
    ref.listen<FsmStateNamesDraft?>(
      fsmStateNameDraftsProvider.select((d) => d[signalRef]),
      (_, next) =>
          CruxInspector.markDirty(context, dirty: next?.isDirty ?? false),
    );
    final kept = ref.watch(
      fsmStateNameDraftsProvider.select((d) => d[signalRef]),
    );
    final ids = fsmStateIdsOf(
      signalRef,
      model: ref.watch(fsmProvider.select((s) => s.model)),
      named: ref.watch(fsmAnnotationProvider),
      found: ref.watch(fsmKnownStateIdsProvider),
      draft: kept,
    );
    if (ids.isEmpty) return const SizedBox.shrink();
    final seed = _seed(signalRef, ids);
    // A state found after the draft was started gets a blank field.
    final draft = kept == null
        ? seed
        : FsmStateNamesDraft(
            labels: <String, String>{...seed.labels, ...kept.labels},
            initialLabels: <String, String>{
              ...seed.initialLabels,
              ...kept.initialLabels,
            },
          );
    final dirty = draft.isDirty;
    final theme = Theme.of(context);

    return CruxInspectorSection(
      title: l10n.inspectorFsmStateNamesSection,
      onSubmit: dirty ? () => _apply(signalRef, draft) : null,
      footer: CruxInspectorApplyBar(
        applyLabel: l10n.inspectorApply,
        revertLabel: l10n.inspectorRevert,
        onApply: dirty ? () => _apply(signalRef, draft) : null,
        onRevert: dirty ? () => _revert(signalRef, draft) : null,
      ),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.inspectorFsmStateNamesHint,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        CruxFormSection(
          labelWidth: 96,
          children: <Widget>[
            for (final id in ids)
              CruxFormRow(
                label: l10n.fsmAnnotateStateLabel(id),
                child: TextField(
                  controller: _controllerFor(
                    id,
                    draft.labels[id] ?? '',
                    drafting: kept != null,
                  ),
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (text) => ref
                      .read(fsmStateNameDraftsProvider.notifier)
                      .put(signalRef, draft.withLabel(id, text)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
