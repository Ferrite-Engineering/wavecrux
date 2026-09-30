// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wavecrux/features/ai/providers/explain_selection_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_adoption_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_layers_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/annotations/providers/annotation_walkthrough_provider.dart';
import 'package:wavecrux/features/annotations/providers/session_annotations_provider.dart';
import 'package:wavecrux/features/annotations/providers/trace_annotation_persistence.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_filter_provider.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_filtered_entries_provider.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_visible_markers_provider.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/cursors/providers/playback_provider.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/providers/transaction_table_provider.dart';
import 'package:wavecrux/features/diagnostics/providers/file_stats_provider.dart';
import 'package:wavecrux/features/diagnostics/providers/memory_stats_provider.dart';
import 'package:wavecrux/features/pack/providers/pack_providers.dart';
import 'package:wavecrux/features/rtl_source/providers/rtl_source_provider.dart';
import 'package:wavecrux/features/search/providers/search_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/stage/providers/riscv_commit_landing_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_selection_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/active_toolbar_height_provider.dart';
import 'package:wavecrux/features/viewer/providers/export_providers.dart';
import 'package:wavecrux/features/viewer/providers/file_watcher_provider.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/features/viewer/providers/process_filter_provider.dart';
import 'package:wavecrux/features/viewer/providers/selected_transaction_provider.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/viewer/providers/streaming_source_provider.dart';
import 'package:wavecrux/features/viewer/providers/switching_activity_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/translate_filter_provider.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_data_revision_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_identity_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/providers/x_trace_provider.dart';

/// Produces the WaveCrux-specific per-tab Riverpod override list applied on
/// top of the package's [`tabIdProvider`] for a freshly-created tab
/// `ProviderContainer`.
///
/// This is the body that previously lived inline inside
/// [`TabContainerManager._createContainer`]; lifting it to a standalone
/// function lets the WaveCrux-flavored [`TabContainerManager`] delegate
/// container creation to the [`crux_workspace`] package's generic
/// [`crux.TabContainerManager`] while keeping the WaveCrux-specific
/// per-tab providers intact.
///
/// The returned list overrides the WaveCrux-side [`tabIdProvider`] (the
/// Riverpod-annotated sentinel in `lib/features/tabs/providers/tab_providers.dart`)
/// with [tabId] so that local widget code reading the local `tabIdProvider`
/// resolves to the correct per-tab identity. The package's
/// [`crux.TabContainerManager`] additionally prepends an override for its own
/// [`crux.tabIdProvider`] (a separate provider with the same conceptual role);
/// the two coexist without conflict because they are distinct Riverpod
/// `Provider` instances.
List<Override> wavecruxTabOverrides(crux.TabId tabId) {
  return <Override>[
    // WaveCrux-local `tabIdProvider` override — distinct from
    // `crux.tabIdProvider` which the package's TabContainerManager prepends
    // automatically.
    tabIdProvider.overrideWithValue(tabId),

    // Waveform source and streaming.
    waveformSourceProvider.overrideWith(WaveformSourceNotifier.new),
    streamingSourceProvider.overrideWith(StreamingSourceNotifier.new),
    fileWatcherProvider.overrideWith(FileWatcherNotifier.new),
    // The content-hash identity is published by the per-tab WaveformSourceNotifier
    // and read by the collaboration bridge for the *active tab*, so it must be
    // per-tab too (otherwise every tab would clobber a single root identity).
    waveformIdentityProvider.overrideWith(WaveformIdentity.new),
    // Bumped by this tab's canvas when its lanes finish loading, and read by
    // per-tab consumers that derive values from the source. Root-scoped, one
    // tab's loads would invalidate every other tab's derivations.
    waveformDataRevisionProvider.overrideWith(WaveformDataRevision.new),

    // Derived providers that read waveformSourceProvider must be scoped to
    // this container so Riverpod can resolve them against the per-tab source
    // override rather than the root scope default.
    waveformIsLoadedProvider.overrideWith(waveformIsLoaded),
    currentTimescaleProvider.overrideWith(currentTimescale),
    visibleTimeRangeProvider.overrideWith(visibleTimeRange),
    // Derived from `currentTimescaleProvider` + `timeMapperProvider` (both
    // per-tab). Scoped here so the ruler reads the focused tab's timescale and
    // visible window rather than the empty root scope. No production consumer
    // reads it today, but scoping it keeps the per-tab-seed invariant intact
    // and makes it correct the moment a widget binds to it. (Scope-leak class
    // of issue #44.)
    timeRulerDataProvider.overrideWith(timeRulerData),
    hierarchyProvider.overrideWith(hierarchy),
    signalVariablesMapProvider.overrideWith(signalVariablesMap),
    // Path-keyed sibling of the ref-keyed map above; same per-tab rationale
    // (derives from the per-tab hierarchy).
    signalVariablesByPathProvider.overrideWith(signalVariablesByPath),
    filteredTransactionsProvider.overrideWith(filteredTransactions),
    activeToolbarHeightProvider.overrideWith(activeToolbarHeight),
    cursorDeltaProvider.overrideWith(cursorDelta),
    // cocotb log, filter, and derived filtered/visible entries are all
    // per-tab: each tab loads its own cocotb log against its own waveform's
    // timescale, and the filter chip state is independent per tab. Before
    // this, the log + filter lived at root scope and bled across every tab
    // (one log shared by all tabs), and `cocotbFilteredEntriesProvider` /
    // `cocotbVisibleMarkersProvider` hoisted to root and read that single
    // global log — so the timeline overlay in tab B showed tab A's markers.
    // The log loader writes through the active tab's container (see
    // `_loadCocotbLog` in viewer_screen.dart) and the per-tab session sidecar
    // captures/restores `cocotbLogProvider` via the per-tab SessionNotifier.
    cocotbLogProvider.overrideWith(CocotbLog.new),
    cocotbFilterProvider.overrideWith(CocotbFilter.new),
    cocotbFilteredEntriesProvider.overrideWith(cocotbFilteredEntries),
    cocotbVisibleMarkersProvider.overrideWith(cocotbVisibleMarkers),
    exportSignalMapProvider.overrideWith(exportSignalMap),
    // Issue 17: the export notifier's internal `ref` reads
    // `waveformSourceProvider`, `signalGroupsProvider`,
    // `signalVariablesMapProvider`, and `timeMapperProvider` — all
    // per-tab. Without this per-tab override the notifier would live at
    // the root scope (it is `@Riverpod(keepAlive: true)`) and resolve
    // those reads against the empty root-scope state, surfacing the
    // "no waveform loaded" snackbar even when the focused tab has a
    // file open.
    exportProvider.overrideWith(ExportNotifier.new),
    // The share-pack notifier reads exactly the same per-tab state as the
    // export notifier — source, signal list, time mapper, annotations,
    // session snapshot — and is `keepAlive` for the same reason, so it needs
    // the same per-tab override. Without it, "Share Annotated Waveform…" from
    // a tab with a file open would report no waveform loaded.
    sharePackProvider.overrideWith(SharePackNotifier.new),
    fileStatsProvider.overrideWith(fileStats),
    // Issue 20: per-tab memory polling. The notifier reads
    // `waveformSourceProvider` (per-tab) inside its 2 s timer; without a
    // per-tab override it resolves to the empty root-scope source and
    // emits a null `MemoryStats` forever, leaving the App Diagnostics
    // dialog's RSS / wellen-DB totals and the per-tab breakdown table
    // permanently showing "—" / "0 B" even when tabs have files
    // loaded. Each tab now owns its own poller that reads the tab's
    // own loaded source.
    memoryStatsProvider.overrideWith(MemoryStatsNotifier.new),
    searchResultsProvider.overrideWith(searchResults),
    signalValuesAtCursorProvider.overrideWith(signalValuesAtCursor),

    // Signal arrangement and tree selection.
    signalGroupsProvider.overrideWith(SignalGroupsNotifier.new),
    selectedVariablesProvider.overrideWith(SelectedVariablesNotifier.new),
    // Signal hierarchy expand/collapse — per-tab, NOT global, so expanding a
    // scope in tab A's signal tree does not also expand an identically-pathed
    // scope in tab B's tree (which used to happen because the provider lived
    // at root scope and held a Set<String> of scope paths shared across every
    // tab).
    expandedScopesProvider.overrideWith(ExpandedScopesNotifier.new),
    // Signal tree vertical scroll offset — per-tab, mirrored from the panel's
    // ScrollController and persisted in the session sidecar (same rationale as
    // the expand/collapse set above: each tab scrolls independently).
    signalTreeScrollProvider.overrideWith(SignalTreeScrollNotifier.new),
    // Cross-probe "reveal signal" request — per-tab so an inbound CXP highlight
    // scrolls the tab it targeted into view rather than a root-scope singleton
    // shared across every tab.
    revealSignalRequestProvider.overrideWith(RevealSignalRequestNotifier.new),

    // Cursor, markers, and navigation.
    cursorStateProvider.overrideWith(CursorStateNotifier.new),
    markerStateProvider.overrideWith(MarkerStateNotifier.new),
    // Waveform annotations — per-tab like markers, and for the same reason:
    // a note is anchored to a signal path in *this* tab's waveform, so a
    // root-scope singleton would draw one tab's annotations over another's.
    annotationsProvider.overrideWith(AnnotationsNotifier.new),
    // The three derived annotation providers read per-tab state
    // (`annotationsProvider`, `signalGroupsProvider`, `waveformSourceProvider`)
    // and must be scoped here too. Without these the overlay watches the
    // ROOT-scope time-ordered list — permanently empty — and draws nothing at
    // all, which is precisely how this shipped broken until the issue-#44
    // scope-leak guard named all three. (Scope-leak class of issue #44.)
    annotationsInTimeOrderProvider.overrideWith(annotationsInTimeOrder),
    // Adopted layers are per-tab like the annotations they name:
    // a layer registry at root scope would hide one tab's notes when another
    // tab's group was toggled off, and would persist into every tab's sidecar.
    annotationLayersProvider.overrideWith(AnnotationLayers.new),
    hiddenAnnotationLayerIdsProvider.overrideWith(hiddenAnnotationLayerIds),
    readOnlyAnnotationIdsProvider.overrideWith(readOnlyAnnotationIds),
    // The pending "keep these notes?" decision belongs to the tab whose
    // waveform the session mirrored.
    annotationAdoptionProvider.overrideWith(AnnotationAdoption.new),
    // The composed local+session set the canvas actually draws.
    // Per-tab because its local half is: root-scoped it would compose one
    // tab's session notes over an empty local list and draw them everywhere.
    // Per-tab: the decisions are this document's, and at the root one tab's
    // adoption would suppress another tab's room.
    adoptedAnnotationIdsProvider.overrideWith(AdoptedAnnotationIds.new),
    composedAnnotationsProvider.overrideWith(composedAnnotations),
    // Per-tab because its local half is: it subtracts THIS tab's local notes
    // from the room's, and at the root it would subtract nothing and call every
    // session note remote.
    sessionOnlyAnnotationIdsProvider.overrideWith(sessionOnlyAnnotationIds),
    composedAnnotationsInTimeOrderProvider.overrideWith(
      composedAnnotationsInTimeOrder,
    ),
    visibleAnnotationsProvider.overrideWith(visibleAnnotations),
    visibleAnnotationsInTimeOrderProvider.overrideWith(
      visibleAnnotationsInTimeOrder,
    ),
    displayedSignalPathsProvider.overrideWith(displayedSignalPaths),
    annotationStatusesProvider.overrideWith(annotationStatuses),
    // Authoring state and the creator that reads this tab's cursor, geometry
    // and source. Root-scoped, a right-click in one tab would resolve its
    // anchor against another tab's waveform.
    annotationBeingEditedProvider.overrideWith(AnnotationBeingEdited.new),
    // Which note the keyboard nudge moves. Per-tab because the annotations are
    // — a root-scoped selection would let ⌥→ in one tab move a note in
    // another, which is the same defect class the rest of this list exists for.
    annotationSelectedProvider.overrideWith(AnnotationSelected.new),
    annotationSnapEnabledProvider.overrideWith(AnnotationSnapEnabled.new),
    annotationGestureActiveProvider.overrideWith(AnnotationGestureActive.new),
    annotationAuthoringProvider.overrideWith(AnnotationAuthoring.new),
    // The walkthrough drives per-tab state — the ordered annotation list, the
    // time mapper, the vertical scroll — and holds a timer. Root-scoped, `]`
    // would step a tour through an empty list while the tab with the notes sat
    // still, and one tab's playback would keep ticking over another's view.
    annotationWalkthroughProvider.overrideWith(AnnotationWalkthrough.new),
    annotationAuthorNameProvider.overrideWith(annotationAuthorName),
    timeMapperProvider.overrideWith(TimeMapperNotifier.new),
    navigationProvider.overrideWith(NavigationNotifier.new),
    waveformScrollProvider.overrideWith(WaveformScrollNotifier.new),
    // Canvas viewport height — published per-tab by [WaveformViewCenter] so the
    // (full-height, right-pane) value column can size its scroll region to the
    // (bottom-shortened, center-pane) canvas and keep one shared maxScrollExtent.
    canvasViewportHeightProvider.overrideWith(CanvasViewportHeightNotifier.new),
    // Stage Playback engine. Reads `cursorStateProvider`, `timeMapperProvider`,
    // `navigationProvider`, and `currentTimescaleProvider` (all per-tab) to
    // auto-advance the focused tab's primary cursor; without this override it
    // would hoist to the root scope and drive the empty root cursor.
    playbackProvider.overrideWith(PlaybackNotifier.new),

    // Panel visibility (signal tree, value column, bottom/transaction, Stage,
    // statistics strip, RTL source, cocotb log) is **per-tab**: each tab keeps
    // its own panel arrangement, and toggling a chevron in one tab never moves
    // another tab's panels — even two tabs docked in the same pane. The
    // per-tab IdeController (the `panes` split geometry) is the 1:1 geometric
    // mirror of this state. Because per-tab containers host the StatusBar,
    // IdeLayout, and the session snapshot/restore notifiers, overriding here is
    // what makes those surfaces resolve THIS tab's panel state — and it is also
    // what makes the per-tab session sidecar round-trip panel visibility (the
    // snapshot reads `panelLayoutProvider`; before this override it read the
    // never-updated root singleton, so panel state never persisted). New tabs
    // start at the `PanelLayoutState()` defaults (clean slate); a restored tab
    // is rehydrated from its sidecar by `SessionNotifier`.
    panelLayoutProvider.overrideWith(PanelLayoutNotifier.new),

    // Session.
    sessionProvider.overrideWith(SessionNotifier.new),
    // Per-tab incremental sidecar autosave (debounced; writes
    // `{appSupportDir}/sessions/{tabId}.wavecrux` continuously while the user
    // works). Without this override, the autosave would resolve against the
    // root container — where `tabIdProvider` is unset and none of the per-tab
    // state providers exist — so it would never run. The owning
    // [`TabContainerManager`] eagerly reads this provider after container
    // creation so the notifier instantiates immediately and arms its
    // `ref.listen` chain.
    sessionAutoSaveProvider.overrideWith(SessionAutoSaveNotifier.new),
    // Per-tab because the notes it persists are: it reads this tab's
    // annotations and this tab's loaded trace. Root-scoped it would write one
    // tab's notes under another tab's file.
    traceAnnotationPersistenceProvider.overrideWith(
      TraceAnnotationPersistence.new,
    ),

    // Protocol decoders and transaction view.
    activeDecodersProvider.overrideWith(ActiveDecodersNotifier.new),
    transactionTableFilterProvider.overrideWith(
      TransactionTableFilterNotifier.new,
    ),
    selectedTransactionProvider.overrideWith(SelectedTransactionNotifier.new),

    // Analysis tools.
    // Explain Selection AI controller. Its notifier runs the AI tool handlers
    // (`getSelectionContext`, `listDecodedTransactions`, …) against `ref`, and
    // those tools read per-tab state (waveformSource, cursorState, markerState,
    // activeDecoders). Every caller already routes per-tab — the shortcut
    // dispatch reads `explainSelectionProvider.notifier` off the active tab
    // container and the result-panel priority check runs on the per-tab
    // Consumer `ref` — but without this override the provider hoisted to the
    // root container, so the tools read the empty root-scope state and the AI
    // received no waveform context in any tab. Same scope-leak class as issue
    // #44; surfaced by the per-tab scope-leak guardrail.
    explainSelectionProvider.overrideWith(ExplainSelection.new),
    xTraceProvider.overrideWith(XTraceNotifier.new),
    diffProvider.overrideWith(DiffNotifier.new),
    patternSearchProvider.overrideWith(PatternSearchNotifier.new),
    switchingActivityProvider.overrideWith(SwitchingActivityNotifier.new),
    processFilterProvider.overrideWith(ProcessFilterNotifier.new),
    translateFilterProvider.overrideWith(TranslateFilterNotifier.new),
    fsmProvider.overrideWith(FsmNotifier.new),
    fsmAnnotationProvider.overrideWith(FsmAnnotationNotifier.new),
    // The two FSM derived providers below read `fsmProvider`,
    // `cursorStateProvider`, and `waveformSourceProvider` (all per-tab) inside
    // their bodies but are plain `@riverpod` functions with no declared
    // `dependencies`, so without a per-tab override they hoist to the root
    // container — where `fsmProvider` is never analyzed — and always return
    // null. The FSM bubble diagram in `fsm_panel.dart` then never highlights
    // the current state or the most recent transition. Same scope-leak class
    // as issue #44 (Stage signal binding); surfaced by the per-tab scope-leak
    // guardrail test.
    fsmCurrentStateIdProvider.overrideWith(fsmCurrentStateId),
    fsmRecentTransitionProvider.overrideWith(fsmRecentTransition),
    diffSignalStatusProvider.overrideWith(diffSignalStatus),
    diffXorTracesProvider.overrideWith(diffXorTraces),

    // RTL source annotation. The notifier holds the parsed stems file, the
    // currently-displayed source file, and the highlight line — all per-tab,
    // so loading a stems file in one tab does not annotate another tab's
    // signals. `rtlStemsLoadedProvider` is a bare `@riverpod` that watches
    // `rtlSourceProvider`; without a per-tab override it would hoist to the
    // root container and always read the empty root stems state (always
    // returning false), so the bidirectional source-nav in
    // `_onSelectedVariablesChanged` would never fire. Both are
    // `@Riverpod(keepAlive: true)` / `@riverpod`; the writers and the per-tab
    // session sidecar (stemsPath capture/restore) route through the active
    // tab's container.
    rtlSourceProvider.overrideWith(RtlSourceNotifier.new),
    rtlStemsLoadedProvider.overrideWith(rtlStemsLoaded),

    // Stage panel.
    stageLoadedSignalsProvider.overrideWith(StageLoadedSignals.new),
    stageWorkspaceProvider.overrideWith(StageWorkspaceNotifier.new),
    stageSelectedInstanceProvider.overrideWith(StageSelectedInstance.new),
    // The Stage signal-snapshot family reads `waveformSourceProvider`,
    // `cursorStateProvider`, and `signalVariablesMapProvider` inside its body
    // — all per-tab. Without a per-tab override the family resolves at the
    // root container, whose `waveformSourceProvider` never has a file loaded
    // (files are always per-tab), so every binding returned
    // `StageSignalSnapshot.noFile()` and every Stage widget rendered "–"
    // (inactive) regardless of cursor position. See GitHub issue #44.
    stageBoundSignalProvider.overrideWith(stageBoundSignal),
    // Where an inbound CXP stream coordinate landed — per-tab, because
    // the cross-probe opens the trace in its own tab and a root-scope
    // singleton would caption every other tab's Commit Inspector with a
    // proof that has nothing to do with the file it is showing.
    riscvCommitLandingProvider.overrideWith(RiscvCommitLandingNotifier.new),
  ];
}
