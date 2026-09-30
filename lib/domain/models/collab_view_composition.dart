// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/custom_translator_def.dart';
import 'package:wavecrux/domain/models/persisted_decoder.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';

/// Declarative **view-composition recipe** broadcast by the presenter and
/// replayed against each follower's own data.
///
/// Collaboration never ships pixels or sample data: the relay is metadata-only
/// and every participant has their own identical copy of the file (the identity
/// hash proves it). So a presenter's *what's-on-screen* — the displayed signal
/// set, decoders, translators, Stage widgets, the FSM viewer target, and which
/// panels are open — replicates as this small, signal-identity-referenced
/// recipe. Each follower reconstructs the view by resolving the recipe's
/// **canonical hierarchical paths** against its own loaded hierarchy.
///
/// Every reference in the recipe is by **stable identity** (scope path + name),
/// never a backend-local `signalRef` and never an index. The serialize seams on
/// the owning providers translate live `signalRef`s to paths; the apply seams
/// translate paths back to the follower's local `signalRef`s. A reference the
/// follower's file lacks degrades to a placeholder (see
/// [CollabCompositionDegradation]) rather than crashing the replay.
///
/// Applied as a **non-destructive overlay** in a transient session scope: the
/// follower's own persisted workspace is captured before the first overlay and
/// restored verbatim on composition-detach or session-leave.
@immutable
class CollabViewComposition {
  const CollabViewComposition({
    this.displayedSignals = const SignalGroup(),
    this.decoders = const [],
    this.translators = const [],
    this.stageWorkspace = const StageWorkspaceState(),
    this.fsmTargetPath,
    this.panelVisibility = const CollabPanelVisibility(),
  });

  /// The ordered displayed-signal list with per-signal radix / height /
  /// grouping. Carried as a [SignalGroup] whose entries are keyed by
  /// [SignalEntry.signalPath]; the backend-local `signalRef` is normalised to
  /// the path on serialize and re-resolved against the follower's hierarchy on
  /// apply.
  final SignalGroup displayedSignals;

  /// Active decoder instances as "decoder D bound to signals [paths] with
  /// config C". Each [PersistedDecoder.config] binding value is a canonical
  /// **path**, not a `signalRef`. The follower runs D on its own data.
  final List<PersistedDecoder> decoders;

  /// The programmable / structured value-translator *library* referenced by the
  /// displayed signals' per-row translator config. Replayed locally so a
  /// follower can decompose a bitfield the presenter authored.
  final List<CustomTranslatorDef> translators;

  /// The Stage panels + per-instance `configuration` maps + signal bindings.
  /// Each [StageSignalBinding.signalRef] holds a canonical **path** in the
  /// recipe; the schema-driven `configuration` map is reused verbatim.
  final StageWorkspaceState stageWorkspace;

  /// Canonical path of the signal the FSM viewer is targeting, or `null` when
  /// the FSM viewer is closed. The presenter's *open state* + *target* — never
  /// the computed model/layout, which the follower recomputes locally.
  final String? fsmTargetPath;

  /// Which panels are open, expressed as **intent** — never pixel geometry.
  final CollabPanelVisibility panelVisibility;

  CollabViewComposition copyWith({
    SignalGroup? displayedSignals,
    List<PersistedDecoder>? decoders,
    List<CustomTranslatorDef>? translators,
    StageWorkspaceState? stageWorkspace,
    String? fsmTargetPath,
    bool clearFsmTargetPath = false,
    CollabPanelVisibility? panelVisibility,
  }) => CollabViewComposition(
    displayedSignals: displayedSignals ?? this.displayedSignals,
    decoders: decoders ?? this.decoders,
    translators: translators ?? this.translators,
    stageWorkspace: stageWorkspace ?? this.stageWorkspace,
    fsmTargetPath: clearFsmTargetPath
        ? null
        : (fsmTargetPath ?? this.fsmTargetPath),
    panelVisibility: panelVisibility ?? this.panelVisibility,
  );

  @override
  bool operator ==(Object other) =>
      other is CollabViewComposition &&
      other.displayedSignals == displayedSignals &&
      _listEq(other.decoders, decoders) &&
      _listEq(other.translators, translators) &&
      other.stageWorkspace == stageWorkspace &&
      other.fsmTargetPath == fsmTargetPath &&
      other.panelVisibility == panelVisibility;

  @override
  int get hashCode => Object.hash(
    displayedSignals,
    Object.hashAll(decoders),
    Object.hashAll(translators),
    stageWorkspace,
    fsmTargetPath,
    panelVisibility,
  );

  @override
  String toString() =>
      'CollabViewComposition(signals: ${displayedSignals.entries.length}, '
      'decoders: ${decoders.length}, translators: ${translators.length}, '
      'stagePanels: ${stageWorkspace.panels.length}, fsm: $fsmTargetPath)';

  static bool _listEq<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The open-panel **intent** carried in a [CollabViewComposition].
///
/// Only the composition-relevant panels are synced — which content surfaces the
/// presenter has open, as a declaration of intent. Pixel geometry (split sizes,
/// pane widths) is deliberately excluded: the governing principle syncs
/// *what's on screen*, never the presenter's exact window layout. Diagnostic /
/// ambient surfaces (RTL source, statistics strip, cocotb log) are local and
/// not part of the shared composition.
@immutable
class CollabPanelVisibility {
  const CollabPanelVisibility({
    this.signalTreeVisible = true,
    this.valueColumnVisible = true,
    this.transactionViewVisible = false,
    this.stageViewVisible = false,
  });

  /// Whether the signal hierarchy browser is open.
  final bool signalTreeVisible;

  /// Whether the value column is open.
  final bool valueColumnVisible;

  /// Whether the decoder transaction table is open.
  final bool transactionViewVisible;

  /// Whether the Stage panel is open.
  final bool stageViewVisible;

  CollabPanelVisibility copyWith({
    bool? signalTreeVisible,
    bool? valueColumnVisible,
    bool? transactionViewVisible,
    bool? stageViewVisible,
  }) => CollabPanelVisibility(
    signalTreeVisible: signalTreeVisible ?? this.signalTreeVisible,
    valueColumnVisible: valueColumnVisible ?? this.valueColumnVisible,
    transactionViewVisible:
        transactionViewVisible ?? this.transactionViewVisible,
    stageViewVisible: stageViewVisible ?? this.stageViewVisible,
  );

  @override
  bool operator ==(Object other) =>
      other is CollabPanelVisibility &&
      other.signalTreeVisible == signalTreeVisible &&
      other.valueColumnVisible == valueColumnVisible &&
      other.transactionViewVisible == transactionViewVisible &&
      other.stageViewVisible == stageViewVisible;

  @override
  int get hashCode => Object.hash(
    signalTreeVisible,
    valueColumnVisible,
    transactionViewVisible,
    stageViewVisible,
  );
}

/// References from a presenter's [CollabViewComposition] that the follower's
/// own file could not resolve when replaying it (graceful degradation).
///
/// A signal the follower's waveform lacks, a decoder the follower's build does
/// not have registered (e.g. a Pro decoder on an Open Core viewer), or a Stage
/// widget id absent from the registry each lands here instead of crashing the
/// overlay. The Pro overlay surfaces this through the existing
/// waveform-mismatch banner ("the presenter's view references things your file
/// doesn't have") rather than the replay failing.
@immutable
class CollabCompositionDegradation {
  const CollabCompositionDegradation({
    this.missingSignalPaths = const [],
    this.missingDecoderIds = const [],
    this.missingWidgetIds = const [],
  });

  /// Empty degradation — the overlay replayed with no missing references.
  static const none = CollabCompositionDegradation();

  /// Canonical signal paths in the recipe that no variable in the follower's
  /// hierarchy matched.
  final List<String> missingSignalPaths;

  /// Decoder registry ids in the recipe that the follower's build does not have
  /// registered.
  final List<String> missingDecoderIds;

  /// Stage widget registry ids in the recipe that the follower's build does not
  /// have registered.
  final List<String> missingWidgetIds;

  /// Whether any reference failed to resolve.
  bool get hasMissing =>
      missingSignalPaths.isNotEmpty ||
      missingDecoderIds.isNotEmpty ||
      missingWidgetIds.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is CollabCompositionDegradation &&
      CollabViewComposition._listEq(
        other.missingSignalPaths,
        missingSignalPaths,
      ) &&
      CollabViewComposition._listEq(
        other.missingDecoderIds,
        missingDecoderIds,
      ) &&
      CollabViewComposition._listEq(other.missingWidgetIds, missingWidgetIds);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(missingSignalPaths),
    Object.hashAll(missingDecoderIds),
    Object.hashAll(missingWidgetIds),
  );

  @override
  String toString() =>
      'CollabCompositionDegradation(signals: '
      '${missingSignalPaths.length}, decoders: ${missingDecoderIds.length}, '
      'widgets: ${missingWidgetIds.length})';
}
