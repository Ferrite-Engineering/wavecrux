// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/q_format_config.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/shared/widgets/named_enum_table_form.dart'
    show NamedEnumRow;

/// What the Inspector shows: a decoder instance, a decoder being added, or a
/// signal row of the viewer.
///
/// An explicit identity rather than something derived from the selection:
/// the signal selection is a set of full paths (aliased FST names map many
/// rows onto one signal) with no primary, while a display format lives on one
/// viewer row (`SignalEntry.id`) and one path can appear on several rows. The
/// row that was acted on names itself.
@immutable
sealed class WaveCruxInspectable {
  const WaveCruxInspectable();
}

/// An active decoder instance ([ActiveDecoder.id]).
final class InspectedDecoder extends WaveCruxInspectable {
  /// Inspects the decoder [instanceId].
  const InspectedDecoder(this.instanceId);

  /// The decoder instance's id.
  final String instanceId;

  @override
  bool operator ==(Object other) =>
      other is InspectedDecoder && other.instanceId == instanceId;

  @override
  int get hashCode => Object.hash(InspectedDecoder, instanceId);
}

/// A decoder of type [definitionId] being added: a draft until its Add.
final class InspectedNewDecoder extends WaveCruxInspectable {
  /// Inspects a new decoder of type [definitionId].
  const InspectedNewDecoder(this.definitionId);

  /// The decoder definition's id.
  final String definitionId;

  @override
  bool operator ==(Object other) =>
      other is InspectedNewDecoder && other.definitionId == definitionId;

  @override
  int get hashCode => Object.hash(InspectedNewDecoder, definitionId);
}

/// A signal row of the viewer ([SignalEntry.id]).
final class InspectedSignal extends WaveCruxInspectable {
  /// Inspects the viewer row [entryId].
  const InspectedSignal(this.entryId);

  /// The viewer row's id.
  final String entryId;

  @override
  bool operator ==(Object other) =>
      other is InspectedSignal && other.entryId == entryId;

  @override
  int get hashCode => Object.hash(InspectedSignal, entryId);
}

/// The object this tab's Inspector shows, or null for its empty state.
///
/// Per-tab (re-bound in `wavecruxTabOverrides`).
final inspectedObjectProvider =
    NotifierProvider<InspectedObjectNotifier, WaveCruxInspectable?>(
      InspectedObjectNotifier.new,
      name: 'inspectedObjectProvider',
    );

/// Notifier behind [inspectedObjectProvider].
class InspectedObjectNotifier extends Notifier<WaveCruxInspectable?> {
  @override
  WaveCruxInspectable? build() => null;

  /// Shows [target] in the Inspector.
  // ignore: use_setters_to_change_properties
  void select(WaveCruxInspectable? target) => state = target;

  /// Empties the Inspector.
  void clear() => state = null;
}

/// Opens this tab's Inspector with keyboard focus. Every opener calls
/// [CruxInspectorController.open]: a decoder row's and the transaction
/// table's Configure, the decoder picker, and a signal row's Properties,
/// Configure Format and Edit Enum Labels.
///
/// Per-tab: a controller shared by two tabs would let an open in one tab
/// move focus in the other. Revealing shows the on-demand Inspector tab in
/// the right dock and opens the region ([PanelLayoutNotifier.revealInspector],
/// also per-tab).
final inspectorControllerProvider = Provider<CruxInspectorController>(
  buildInspectorController,
  name: 'inspectorControllerProvider',
);

/// The body of [inspectorControllerProvider], shared with its per-tab
/// re-binding.
CruxInspectorController buildInspectorController(Ref ref) {
  final layout = ref.read(panelLayoutProvider.notifier);
  final controller = CruxInspectorController(onReveal: layout.revealInspector);
  ref.onDispose(controller.dispose);
  return controller;
}

/// The focus node of this tab's waveform pane, where Escape in the
/// Inspector returns focus. Per-tab; disposed with the tab.
final waveformPaneFocusNodeProvider = Provider<FocusNode>(
  buildWaveformPaneFocusNode,
  name: 'waveformPaneFocusNodeProvider',
);

/// The body of [waveformPaneFocusNodeProvider].
FocusNode buildWaveformPaneFocusNode(Ref ref) {
  final node = FocusNode(debugLabel: 'Waveform pane');
  ref.onDispose(node.dispose);
  return node;
}

// ── decoder drafts ─────────────────────────────────────────────────────────────

/// The draft key of [target]: the instance id, or `new:<definition id>`.
String decoderDraftKey(WaveCruxInspectable target) => switch (target) {
  InspectedDecoder(:final instanceId) => instanceId,
  InspectedNewDecoder(:final definitionId) => 'new:$definitionId',
  InspectedSignal(:final entryId) => 'signal:$entryId',
};

/// A decoder's bindings and parameters being edited in the Inspector, not
/// yet applied.
@immutable
class DecoderDraft {
  /// Creates a draft.
  const DecoderDraft({
    required this.definitionId,
    required this.instanceId,
    required this.bindings,
    required this.bindingPaths,
    required this.params,
    required this.initialBindings,
    required this.initialParams,
    this.offeredPaths,
    this.showValidationError = false,
  });

  /// The decoder definition's id.
  final String definitionId;

  /// The instance edited; null for a decoder being added.
  final String? instanceId;

  /// Logical binding name to signalRef (or null).
  final Map<String, String?> bindings;

  /// Logical binding name to the [Variable.fullPath] it was picked by.
  /// Aliased names share one signalRef, so the bindings alone cannot say
  /// which name the user chose. Display only.
  final Map<String, String?> bindingPaths;

  /// Parameter name to value.
  final Map<String, dynamic> params;

  /// [bindings] as the draft was seeded (after any auto-bind prefill).
  final Map<String, String?> initialBindings;

  /// [params] as the draft was seeded.
  final Map<String, dynamic> initialParams;

  /// The full paths the binding pickers offer, or null for every loaded
  /// signal: "Apply Decoder to Selection" offers only the selection.
  final Set<String>? offeredPaths;

  /// Set when Apply was pressed with a required binding missing.
  final bool showValidationError;

  /// Whether this is a decoder being added.
  bool get isNew => instanceId == null;

  /// Whether Apply would change anything. A new decoder is unapplied from
  /// the moment it is started.
  bool get isDirty =>
      isNew ||
      !mapEquals(bindings, initialBindings) ||
      !mapEquals(params, initialParams);

  /// A copy with the given fields replaced.
  DecoderDraft copyWith({
    Map<String, String?>? bindings,
    Map<String, String?>? bindingPaths,
    Map<String, dynamic>? params,
    bool? showValidationError,
  }) => DecoderDraft(
    definitionId: definitionId,
    instanceId: instanceId,
    bindings: bindings ?? this.bindings,
    bindingPaths: bindingPaths ?? this.bindingPaths,
    params: params ?? this.params,
    initialBindings: initialBindings,
    initialParams: initialParams,
    offeredPaths: offeredPaths,
    showValidationError: showValidationError ?? this.showValidationError,
  );
}

/// The Inspector's unapplied decoder drafts in this tab, keyed by
/// [decoderDraftKey].
///
/// Per-tab, and kept here rather than in the section's widget state: the
/// dock builds only its active tab, so switching to Values and back must not
/// lose an edit.
final decoderDraftsProvider =
    NotifierProvider<DecoderDraftsNotifier, Map<String, DecoderDraft>>(
      DecoderDraftsNotifier.new,
      name: 'decoderDraftsProvider',
    );

/// Notifier behind [decoderDraftsProvider].
class DecoderDraftsNotifier extends Notifier<Map<String, DecoderDraft>> {
  @override
  Map<String, DecoderDraft> build() => const <String, DecoderDraft>{};

  /// Records [draft] under [key]. An edit draft that matches its seed again
  /// is dropped: nothing is left to apply.
  void put(String key, DecoderDraft draft) {
    final next = Map<String, DecoderDraft>.of(state);
    if (!draft.isDirty && !draft.showValidationError) {
      next.remove(key);
    } else {
      next[key] = draft;
    }
    state = Map<String, DecoderDraft>.unmodifiable(next);
  }

  /// Drops the draft under [key] (applied or reverted).
  void discard(String key) {
    if (!state.containsKey(key)) return;
    state = Map<String, DecoderDraft>.unmodifiable(
      Map<String, DecoderDraft>.of(state)..remove(key),
    );
  }
}

// ── signal display-format drafts ───────────────────────────────────────────────

/// A signal row's Q-format or enum labels being edited, not yet applied.
@immutable
class SignalFormatDraft {
  /// Creates a draft; set the half that the row's format uses.
  const SignalFormatDraft({
    this.qFormat,
    this.initialQFormat,
    this.enumRows,
    this.initialEnumRows,
    this.revision = 0,
  });

  /// The Q-format knobs, for a fixed-point row.
  final QFormatConfig? qFormat;

  /// [qFormat] as seeded.
  final QFormatConfig? initialQFormat;

  /// The label table, for a named-enum row.
  final List<NamedEnumRow>? enumRows;

  /// [enumRows] as seeded.
  final List<NamedEnumRow>? initialEnumRows;

  /// Bumped when the rows are replaced wholesale (an import), so the table
  /// rebuilds its fields from the new rows.
  final int revision;

  /// Whether Apply would change anything.
  bool get isDirty =>
      qFormat != initialQFormat || !listEquals(enumRows, initialEnumRows);

  /// A copy with the given fields replaced.
  SignalFormatDraft copyWith({
    QFormatConfig? qFormat,
    List<NamedEnumRow>? enumRows,
    bool bumpRevision = false,
  }) => SignalFormatDraft(
    qFormat: qFormat ?? this.qFormat,
    initialQFormat: initialQFormat,
    enumRows: enumRows ?? this.enumRows,
    initialEnumRows: initialEnumRows,
    revision: bumpRevision ? revision + 1 : revision,
  );
}

/// The Inspector's unapplied display-format drafts in this tab, keyed by
/// [SignalEntry.id]. Per-tab, for the same reason as [decoderDraftsProvider].
final signalFormatDraftsProvider =
    NotifierProvider<
      SignalFormatDraftsNotifier,
      Map<String, SignalFormatDraft>
    >(
      SignalFormatDraftsNotifier.new,
      name: 'signalFormatDraftsProvider',
    );

/// Notifier behind [signalFormatDraftsProvider].
class SignalFormatDraftsNotifier
    extends Notifier<Map<String, SignalFormatDraft>> {
  @override
  Map<String, SignalFormatDraft> build() => const <String, SignalFormatDraft>{};

  /// Records [draft] under [entryId]; a draft equal to its seed is dropped.
  void put(String entryId, SignalFormatDraft draft) {
    final next = Map<String, SignalFormatDraft>.of(state);
    if (draft.isDirty) {
      next[entryId] = draft;
    } else {
      next.remove(entryId);
    }
    state = Map<String, SignalFormatDraft>.unmodifiable(next);
  }

  /// Drops the draft for [entryId] (applied or reverted).
  void discard(String entryId) {
    if (!state.containsKey(entryId)) return;
    state = Map<String, SignalFormatDraft>.unmodifiable(
      Map<String, SignalFormatDraft>.of(state)..remove(entryId),
    );
  }
}

// ── FSM state-name drafts ─────────────────────────────────────────────────────

/// An FSM signal's state names being edited in the Inspector, not yet
/// applied. Keyed by signalRef: the names belong to the signal, so two rows
/// of one signal edit one set.
@immutable
class FsmStateNamesDraft {
  /// Creates a draft of [labels] (state id to name; a blank name falls back
  /// to the raw value) over the names in use, [initialLabels].
  const FsmStateNamesDraft({
    required this.labels,
    required this.initialLabels,
  });

  /// State id to the name typed so far. Every known id has an entry; an
  /// empty one means "no name".
  final Map<String, String> labels;

  /// [labels] as seeded from the names in use.
  final Map<String, String> initialLabels;

  /// Whether Apply would change anything.
  bool get isDirty => !mapEquals(labels, initialLabels);

  /// A copy with [id] named [label].
  FsmStateNamesDraft withLabel(String id, String label) => FsmStateNamesDraft(
    labels: Map<String, String>.unmodifiable(
      Map<String, String>.of(labels)..[id] = label,
    ),
    initialLabels: initialLabels,
  );
}

/// The Inspector's unapplied FSM state-name drafts in this tab, keyed by
/// signalRef. Per-tab, for the same reason as [decoderDraftsProvider].
final fsmStateNameDraftsProvider =
    NotifierProvider<
      FsmStateNameDraftsNotifier,
      Map<String, FsmStateNamesDraft>
    >(
      FsmStateNameDraftsNotifier.new,
      name: 'fsmStateNameDraftsProvider',
    );

/// Notifier behind [fsmStateNameDraftsProvider].
class FsmStateNameDraftsNotifier
    extends Notifier<Map<String, FsmStateNamesDraft>> {
  @override
  Map<String, FsmStateNamesDraft> build() =>
      const <String, FsmStateNamesDraft>{};

  /// Records [draft] under [signalRef]; a draft equal to its seed is dropped.
  void put(String signalRef, FsmStateNamesDraft draft) {
    final next = Map<String, FsmStateNamesDraft>.of(state);
    if (draft.isDirty) {
      next[signalRef] = draft;
    } else {
      next.remove(signalRef);
    }
    state = Map<String, FsmStateNamesDraft>.unmodifiable(next);
  }

  /// Drops the draft for [signalRef] (applied or reverted).
  void discard(String signalRef) {
    if (!state.containsKey(signalRef)) return;
    state = Map<String, FsmStateNamesDraft>.unmodifiable(
      Map<String, FsmStateNamesDraft>.of(state)..remove(signalRef),
    );
  }

  /// Drops every draft; a new file was loaded.
  void clear() => state = const <String, FsmStateNamesDraft>{};
}

/// The state ids found by "Annotate FSM states…" for a signal whose FSM is
/// not the one on show, keyed by signalRef.
///
/// The Inspector's FSM section lists the ids of the FSM on show (when it is
/// this signal's), the ids already named, and these. Kept apart from
/// `fsmProvider` so naming a signal's states does not replace the FSM
/// diagram on show. Per-tab.
final fsmKnownStateIdsProvider =
    NotifierProvider<FsmKnownStateIdsNotifier, Map<String, List<String>>>(
      FsmKnownStateIdsNotifier.new,
      name: 'fsmKnownStateIdsProvider',
    );

/// Notifier behind [fsmKnownStateIdsProvider].
class FsmKnownStateIdsNotifier extends Notifier<Map<String, List<String>>> {
  @override
  Map<String, List<String>> build() => const <String, List<String>>{};

  /// Records [ids] as the states of [signalRef].
  void put(String signalRef, List<String> ids) {
    state = Map<String, List<String>>.unmodifiable(<String, List<String>>{
      ...state,
      signalRef: List<String>.unmodifiable(ids),
    });
  }

  /// Forgets every signal's ids; a new file was loaded.
  void clear() => state = const <String, List<String>>{};
}

/// The Pro overlay's Inspector sections, after open core's own. Empty in
/// open core; the overlay overrides it in its override list.
final proInspectorSectionsProvider =
    Provider<List<CruxInspectorSectionBuilder<WaveCruxInspectable>>>(
      (_) => const <CruxInspectorSectionBuilder<WaveCruxInspectable>>[],
      name: 'proInspectorSectionsProvider',
    );
