// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/collab_view_composition.dart';

part 'panel_layout_provider.g.dart';

// ── bottom-dock tab ids ───────────────────────────────────────────────────────
// Stable ids for the bottom dock's tabs, shared by the dock widget, the
// shortcut dispatch, and session persistence. Stage tabs are dynamic —
// `'$kBottomDockStagePrefix<stagePanelId>'` — with the bare prefix standing
// for "Stage, whichever panel is active" (the empty-workspace state, and the
// legacy-session derivation that predates per-tab ids).

/// The pinned transaction-table tab.
const String kBottomDockTabTransactions = 'transactions';

/// The cocotb log tab (on-demand).
const String kBottomDockTabCocotb = 'cocotb';

/// The FSM bubble-diagram tab (on-demand).
const String kBottomDockTabFsm = 'fsm';

/// The X-trace tab (on-demand).
const String kBottomDockTabXTrace = 'xtrace';

/// The switching-activity report tab (on-demand).
const String kBottomDockTabActivity = 'activity';

/// Annotations list — the only surface that reaches an annotation the canvas
/// cannot draw (hidden signal, absent signal, or panned out of view).
const String kBottomDockTabAnnotations = 'annotations';

/// The AI Explain Selection result tab (on-demand).
const String kBottomDockTabExplain = 'explain';

/// Prefix for the dynamic per-Stage-panel tabs.
const String kBottomDockStagePrefix = 'stage:';

/// Height the bottom dock opens at until the user drags it or a session
/// restores one ([PanelLayoutState.bottomPaneSize] is null until then).
///
/// Named here rather than left as a literal at the one place that renders the
/// pane, because [PanelLayoutNotifier.growBottomPaneTo] has to reason about
/// the same "not yet chosen" height and the two drifting apart would make the
/// dock grow when it did not need to (or fail to when it did).
const double kDefaultBottomPaneSize = 200;

// ── right-dock tab ids ────────────────────────────────────────────────────────

/// The pinned value-column tab.
const String kRightDockTabValues = 'values';

/// The RTL source-annotation tab (on-demand, desktop only).
const String kRightDockTabRtlSource = 'rtlSource';

/// The docked cross-probe panel tab (on-demand, desktop/tablet).
const String kRightDockTabCrossProbe = 'crossProbe';

// ── left-dock tab ids ─────────────────────────────────────────────────────────

/// The pinned signal-tree tab.
const String kLeftDockTabSignals = 'signals';

/// The waveform-diff summary tab (on-demand while a diff is active).
const String kLeftDockTabDiff = 'diff';

// ── dock regions (drag-between-docks) ─────────────────────────────────────────

/// The bottom dock's region id.
const String kDockRegionBottom = 'bottom';

/// The right dock's region id.
const String kDockRegionRight = 'right';

/// Visibility state for the viewer panels.
@immutable
class PanelLayoutState {
  const PanelLayoutState({
    this.signalTreeVisible = true,
    this.valueColumnVisible = true,
    this.transactionViewVisible = false,
    this.stageViewVisible = false,
    this.rtlSourceVisible = false,
    this.crossProbeVisible = false,
    this.statisticsStripVisible = false,
    this.cocotbLogPanelVisible = false,
    this.annotationsPanelVisible,
    this.bottomDockTab,
    this.bottomDockMaximized = false,
    this.rightDockTab,
    this.leftDockTab,
    this.dockPlacements = const <String, String>{},
    this.leftPaneSize,
    this.rightPaneSize,
    this.bottomPaneSize,
  });

  final bool signalTreeVisible;
  final bool valueColumnVisible;
  final bool transactionViewVisible;
  final bool stageViewVisible;

  /// Width of the left (signal tree) pane in logical pixels, or null to use the
  /// layout default. Updated on drag-to-resize and restored from the session so
  /// a relaunch keeps the user's pane geometry. Mirrors VS Code's persisted
  /// sidebar width.
  final double? leftPaneSize;

  /// Width of the right (value column) pane in logical pixels, or null for the
  /// layout default.
  final double? rightPaneSize;

  /// Height of the bottom (transaction/diagnostic) pane in logical pixels, or
  /// null for the layout default.
  final double? bottomPaneSize;

  /// Whether the cocotb log panel takes over the bottom pane.
  ///
  /// When `true`, the bottom pane shows [CocotbLogPanel] instead of the
  /// transaction table or other diagnostic panels. Loading a cocotb log
  /// auto-toggles this to `true`; clearing the log auto-toggles it back.
  final bool cocotbLogPanelVisible;

  /// Whether the Annotations dock panel is shown — `null` meaning "decide
  /// automatically".
  ///
  /// **Tri-state on purpose.** Two booleans' worth of intent live here:
  ///
  /// * `null` — the user has never said. The panel appears exactly when the
  ///   tab has annotations, which is what shipped in 5.9.1 and is right for
  ///   the majority of sessions that never annotate.
  /// * `true` — opened deliberately, and stays open with zero annotations.
  ///   That case is the whole point: the panel's empty state is the only place
  ///   in the app that names the authoring gesture, and while presence was
  ///   derived from `annotations.isNotEmpty` alone that text could never
  ///   render — it appeared only once the user already knew.
  /// * `false` — closed deliberately, and stays closed even as notes are
  ///   added. Without this the close button would be undone by the next note.
  ///
  /// A single boolean cannot express "auto" and "explicitly closed" at once,
  /// and picking either default alone regresses one of the two cases.
  final bool? annotationsPanelVisible;

  /// Whether the RTL source-annotation panel should be visible.
  ///
  /// Desktop only — gated separately on `deviceClassProvider` at the layout
  /// level (the layout simply ignores this flag on phone/tablet).
  final bool rtlSourceVisible;

  /// Whether the shared docked cross-probe panel occupies the right pane. Desktop/tablet only — the layout ignores it
  /// on phone. Toggled by the toolbar button, the View menu, and Cmd/Ctrl+
  /// Shift+X; closed by the panel's own header chevron.
  final bool crossProbeVisible;

  /// Whether the live statistics strip is expanded.
  ///
  /// Desktop only — sits between the IdeLayout and the status bar. Defaults
  /// to collapsed (`false`). The strip widget itself is implemented in a later
  /// phase; this field only tracks the expanded/collapsed state.
  final bool statisticsStripVisible;

  /// The bottom dock's active tab id (one of the `kBottomDockTab*` constants,
  /// a `'$kBottomDockStagePrefix<panelId>'` stage tab, or a Pro-contributed
  /// tab id), or null for a session that never picked one.
  ///
  /// Null triggers [effectiveBottomDockTab]'s legacy derivation, which mirrors
  /// the retired priority chain — so a pre-dock session restores showing the
  /// same panel it saved with.
  final String? bottomDockTab;

  /// Whether the bottom dock is maximized. Presentational and transient:
  /// the dock's layout adapter reports an effectively-infinite height (the
  /// `CruxIdeLayout` fit clamp caps it at the window minus the center floor)
  /// while [bottomPaneSize] keeps the user's real size for restore. A manual
  /// drag-resize clears it.
  final bool bottomDockMaximized;

  /// The bottom-dock tab that is (or would be, when the dock is hidden)
  /// active.
  ///
  /// Validates stage/cocotb ids against their presence flags so a stale
  /// persisted id (Stage toggled off after the tab was active) falls back
  /// rather than pointing at an absent tab; ids whose presence lives in other
  /// providers (FSM, X-trace…) resolve in the dock widget, which sees them.
  String get effectiveBottomDockTab {
    final tab = bottomDockTab;
    if (tab != null) {
      if (tab.startsWith(kBottomDockStagePrefix)) {
        if (stageViewVisible) return tab;
      } else if (tab == kBottomDockTabCocotb) {
        if (cocotbLogPanelVisible) return tab;
      } else {
        return tab;
      }
    }
    // Legacy sessions persisted only the feature flags; mirror the retired
    // priority chain's Stage > cocotb > Transactions so they restore true.
    if (stageViewVisible) return kBottomDockStagePrefix;
    if (cocotbLogPanelVisible) return kBottomDockTabCocotb;
    return kBottomDockTabTransactions;
  }

  /// Whether a Stage tab is on screen — the gate for Stage Playback (the
  /// transport lives inside the Stage panel) and the toolbar's Stage glyph.
  bool get bottomDockShowsStage =>
      transactionViewVisible &&
      stageViewVisible &&
      effectiveBottomDockTab.startsWith(kBottomDockStagePrefix);

  /// Whether the transaction table is on screen — the toolbar's
  /// transaction-table glyph.
  bool get bottomDockShowsTransactions =>
      transactionViewVisible &&
      effectiveBottomDockTab == kBottomDockTabTransactions;

  /// The right dock's active tab id, or null for a session that never picked
  /// one.
  ///
  /// Null resolves through [effectiveRightDockTab]'s legacy derivation, which
  /// mirrors the retired right-region priority chain (Cross-Probe > RTL
  /// Source > Values).
  final String? rightDockTab;

  /// The left dock's active tab id (signals / diff). In-memory only — a diff
  /// does not survive a relaunch, so there is nothing meaningful to persist.
  final String? leftDockTab;

  /// Where the user dragged a movable tab, keyed by tab id → region
  /// (`kDockRegionBottom` / `kDockRegionRight`). Absent means the tab's
  /// native region. Persisted in the session sidecar so an arrangement
  /// survives a relaunch. Movable tabs: the on-demand analyses (FSM,
  /// X-Trace, Activity, Explain, Cocotb) and Cross-Probe.
  final Map<String, String> dockPlacements;

  /// The region [id] currently lives in, honouring a drag override.
  String dockRegionOf(String id, String nativeRegion) =>
      dockPlacements[id] ?? nativeRegion;

  /// The right-dock tab that is (or would be) active. Same validation and
  /// legacy-derivation contract as [effectiveBottomDockTab].
  String get effectiveRightDockTab {
    final tab = rightDockTab;
    if (tab != null) {
      if (tab == kRightDockTabCrossProbe) {
        if (crossProbeVisible) return tab;
      } else if (tab == kRightDockTabRtlSource) {
        if (rtlSourceVisible) return tab;
      } else {
        return tab;
      }
    }
    if (crossProbeVisible) return kRightDockTabCrossProbe;
    if (rtlSourceVisible) return kRightDockTabRtlSource;
    return kRightDockTabValues;
  }

  /// Whether the docked cross-probe panel is on screen — the toolbar's
  /// cross-probe glyph. Dock- AND placement-aware: the CXP feature being on
  /// *behind* another tab does not light the glyph, and a CXP tab dragged to
  /// the bottom dock is tracked there.
  bool get rightDockShowsCrossProbe {
    if (!crossProbeVisible) return false;
    if (dockRegionOf(kRightDockTabCrossProbe, kDockRegionRight) ==
        kDockRegionBottom) {
      return transactionViewVisible &&
          effectiveBottomDockTab == kRightDockTabCrossProbe;
    }
    return valueColumnVisible &&
        effectiveRightDockTab == kRightDockTabCrossProbe;
  }

  PanelLayoutState copyWith({
    bool? signalTreeVisible,
    bool? valueColumnVisible,
    bool? transactionViewVisible,
    bool? stageViewVisible,
    bool? rtlSourceVisible,
    bool? crossProbeVisible,
    bool? statisticsStripVisible,
    bool? cocotbLogPanelVisible,
    bool? annotationsPanelVisible,
    bool clearAnnotationsPanelVisible = false,
    String? bottomDockTab,
    bool? bottomDockMaximized,
    String? rightDockTab,
    String? leftDockTab,
    Map<String, String>? dockPlacements,
    double? leftPaneSize,
    double? rightPaneSize,
    double? bottomPaneSize,
  }) {
    return PanelLayoutState(
      signalTreeVisible: signalTreeVisible ?? this.signalTreeVisible,
      valueColumnVisible: valueColumnVisible ?? this.valueColumnVisible,
      transactionViewVisible:
          transactionViewVisible ?? this.transactionViewVisible,
      stageViewVisible: stageViewVisible ?? this.stageViewVisible,
      rtlSourceVisible: rtlSourceVisible ?? this.rtlSourceVisible,
      crossProbeVisible: crossProbeVisible ?? this.crossProbeVisible,
      statisticsStripVisible:
          statisticsStripVisible ?? this.statisticsStripVisible,
      cocotbLogPanelVisible:
          cocotbLogPanelVisible ?? this.cocotbLogPanelVisible,
      annotationsPanelVisible: clearAnnotationsPanelVisible
          ? null
          : (annotationsPanelVisible ?? this.annotationsPanelVisible),
      bottomDockTab: bottomDockTab ?? this.bottomDockTab,
      bottomDockMaximized: bottomDockMaximized ?? this.bottomDockMaximized,
      rightDockTab: rightDockTab ?? this.rightDockTab,
      leftDockTab: leftDockTab ?? this.leftDockTab,
      dockPlacements: dockPlacements ?? this.dockPlacements,
      leftPaneSize: leftPaneSize ?? this.leftPaneSize,
      rightPaneSize: rightPaneSize ?? this.rightPaneSize,
      bottomPaneSize: bottomPaneSize ?? this.bottomPaneSize,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PanelLayoutState &&
        other.signalTreeVisible == signalTreeVisible &&
        other.valueColumnVisible == valueColumnVisible &&
        other.transactionViewVisible == transactionViewVisible &&
        other.stageViewVisible == stageViewVisible &&
        other.rtlSourceVisible == rtlSourceVisible &&
        other.crossProbeVisible == crossProbeVisible &&
        other.statisticsStripVisible == statisticsStripVisible &&
        other.cocotbLogPanelVisible == cocotbLogPanelVisible &&
        other.annotationsPanelVisible == annotationsPanelVisible &&
        other.bottomDockTab == bottomDockTab &&
        other.bottomDockMaximized == bottomDockMaximized &&
        other.rightDockTab == rightDockTab &&
        other.leftDockTab == leftDockTab &&
        _placementsEqual(other.dockPlacements, dockPlacements) &&
        other.leftPaneSize == leftPaneSize &&
        other.rightPaneSize == rightPaneSize &&
        other.bottomPaneSize == bottomPaneSize;
  }

  @override
  int get hashCode => Object.hash(
    signalTreeVisible,
    valueColumnVisible,
    transactionViewVisible,
    stageViewVisible,
    rtlSourceVisible,
    crossProbeVisible,
    statisticsStripVisible,
    cocotbLogPanelVisible,
    annotationsPanelVisible,
    bottomDockTab,
    bottomDockMaximized,
    rightDockTab,
    leftDockTab,
    Object.hashAllUnordered(
      dockPlacements.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    leftPaneSize,
    rightPaneSize,
    bottomPaneSize,
  );

  static bool _placementsEqual(Map<String, String> a, Map<String, String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}

/// Manages panel visibility state for the viewer screen.
///
/// This is a **per-tab** provider (overridden in `wavecruxTabOverrides`): each
/// tab keeps its own panel arrangement and the per-tab session sidecar
/// persists it. `keepAlive` because the state must survive moments when no
/// widget is watching it — e.g. it is read during `ViewerScreen.initState`
/// (to seed the tab's [IdeController]) before the StatusBar/IdeLayout that
/// watch it are built; an autoDispose provider would schedule a disposal there
/// and lose the seeded/restored layout (and leak a dispose timer in tests).
///
/// External callers (toolbar, menu, keyboard shortcuts) use the toggle/set
/// methods. [ViewerScreen] syncs [IdeController] bidirectionally:
/// - drag-to-resize fires [setSignalTreeVisible] etc. via [IdeLayout.onPaneStateChanged]
/// - programmatic toggles are applied to [IdeController] via [ref.listen]
@Riverpod(keepAlive: true)
class PanelLayoutNotifier extends _$PanelLayoutNotifier {
  @override
  PanelLayoutState build() => const PanelLayoutState();

  void toggleSignalTree() =>
      state = state.copyWith(signalTreeVisible: !state.signalTreeVisible);

  void toggleValueColumn() =>
      state = state.copyWith(valueColumnVisible: !state.valueColumnVisible);

  void toggleTransactionView() => state = state.copyWith(
    transactionViewVisible: !state.transactionViewVisible,
  );

  void toggleStageView() =>
      state = state.copyWith(stageViewVisible: !state.stageViewVisible);

  void setSignalTreeVisible({required bool visible}) =>
      state = state.copyWith(signalTreeVisible: visible);

  void setValueColumnVisible({required bool visible}) =>
      state = state.copyWith(valueColumnVisible: visible);

  void setTransactionViewVisible({required bool visible}) =>
      state = state.copyWith(transactionViewVisible: visible);

  void setStageViewVisible({required bool visible}) =>
      state = state.copyWith(stageViewVisible: visible);

  void toggleRtlSource() =>
      state = state.copyWith(rtlSourceVisible: !state.rtlSourceVisible);

  void setRtlSourceVisible({required bool visible}) =>
      state = state.copyWith(rtlSourceVisible: visible);

  void toggleCrossProbe() =>
      state = state.copyWith(crossProbeVisible: !state.crossProbeVisible);

  void setCrossProbeVisible({required bool visible}) =>
      state = state.copyWith(crossProbeVisible: visible);

  /// Flips the live-statistics strip.
  ///
  /// The `tool.opened` counter lives on this method — not on
  /// [setStatisticsStripVisible], which is also how a restored session
  /// reinstates the strip — and fires only on the off→on edge, because a
  /// toggle that closes the strip is not an open.
  void toggleStatisticsStrip() {
    final opening = !state.statisticsStripVisible;
    state = state.copyWith(statisticsStripVisible: opening);
    if (opening) {
      ref
          .read(telemetryServiceProvider)
          .record(
            TelemetryEvent(
              'tool.opened',
              properties: const <String, Object?>{'tool': 'statistics'},
            ),
          );
    }
  }

  void setStatisticsStripVisible({required bool visible}) =>
      state = state.copyWith(statisticsStripVisible: visible);

  /// Show or hide the Annotations dock panel, resolving "auto" to the concrete
  /// opposite of what is on screen right now.
  ///
  /// [annotationsPresent] is the caller's view of whether the tab has any
  /// notes — the auto rule. Passing it in rather than reading it keeps the
  /// panel-layout notifier free of a dependency on the annotation list.
  void toggleAnnotationsPanel({required bool annotationsPresent}) {
    final showing = state.annotationsPanelVisible ?? annotationsPresent;
    state = state.copyWith(annotationsPanelVisible: !showing);
  }

  /// Set the panel's visibility explicitly, or pass `null` to hand it back to
  /// the automatic rule.
  void setAnnotationsPanelVisible({required bool? visible}) =>
      state = state.copyWith(
        annotationsPanelVisible: visible,
        clearAnnotationsPanelVisible: visible == null,
      );

  void toggleCocotbLogPanel() => state = state.copyWith(
    cocotbLogPanelVisible: !state.cocotbLogPanelVisible,
  );

  void setCocotbLogPanelVisible({required bool visible}) =>
      state = state.copyWith(cocotbLogPanelVisible: visible);

  // ── bottom dock ──────────────────────────────────────────────────────────────

  /// Records [id] as the bottom dock's active tab without touching the
  /// region's visibility (a strip tap on an already-open dock).
  void setBottomDockTab(String id) => state = state.copyWith(bottomDockTab: id);

  /// VSCode's "reveal": activates [id] AND opens the bottom region, so asking
  /// for any one tab shows the whole strip.
  void revealBottomDockTab(String id) => state = state.copyWith(
    bottomDockTab: id,
    transactionViewVisible: true,
  );

  /// Toggles the bottom dock between maximized and the user's stored size.
  /// Maximize never overwrites [PanelLayoutState.bottomPaneSize] — restoring
  /// is just clearing the flag.
  void toggleBottomDockMaximized() => state = state.copyWith(
    bottomDockMaximized: !state.bottomDockMaximized,
  );

  // ── right dock ───────────────────────────────────────────────────────────────

  /// Records [id] as the right dock's active tab without touching the
  /// region's visibility.
  void setRightDockTab(String id) => state = state.copyWith(rightDockTab: id);

  /// VSCode's "reveal" for the right dock: activates [id] AND opens the
  /// right region.
  void revealRightDockTab(String id) => state = state.copyWith(
    rightDockTab: id,
    valueColumnVisible: true,
  );

  // ── left dock ────────────────────────────────────────────────────────────────

  /// Records [id] as the left dock's active tab.
  void setLeftDockTab(String id) => state = state.copyWith(leftDockTab: id);

  /// VSCode's "reveal" for the left dock: activates [id] AND opens the left
  /// region.
  void revealLeftDockTab(String id) => state = state.copyWith(
    leftDockTab: id,
    signalTreeVisible: true,
  );

  // ── drag-between-docks ───────────────────────────────────────────────────────

  /// Re-homes a movable tab into [region] and reveals it there — the drop
  /// handler for the bottom/right docks' `onTabMovedIn`.
  void moveDockTab(String id, String region) {
    state = state.copyWith(
      dockPlacements: {...state.dockPlacements, id: region},
    );
    if (region == kDockRegionBottom) {
      revealBottomDockTab(id);
    } else {
      revealRightDockTab(id);
    }
  }

  /// Restores a session's placement overrides wholesale (session restore
  /// only — user moves go through [moveDockTab]).
  void restoreDockPlacements(Map<String, String> placements) =>
      state = state.copyWith(dockPlacements: placements);

  /// Placement-aware reveal: opens [id] in whichever region it currently
  /// lives in ([nativeRegion] unless dragged elsewhere). The activation
  /// call sites (loading a cocotb log, an analysis completing, the CXP
  /// toggle) use this so a moved tab reveals where the user put it.
  void revealDockTabPlaced(String id, String nativeRegion) {
    if (state.dockRegionOf(id, nativeRegion) == kDockRegionBottom) {
      revealBottomDockTab(id);
    } else {
      revealRightDockTab(id);
    }
  }

  // ── pane geometry ────────────────────────────────────────────────────────────
  // Updated by the drag-to-resize sink (`_WaveCruxIdePanelLayoutSink`) and on
  // session restore. Persisted in the session sidecar so a relaunch keeps the
  // user's pane geometry. (`PaneSize` pixels.)

  void setLeftPaneSize(double pixels) =>
      state = state.copyWith(leftPaneSize: pixels);

  void setRightPaneSize(double pixels) =>
      state = state.copyWith(rightPaneSize: pixels);

  // A manual drag while maximized is the user choosing a real size again, so
  // the resize clears the maximized flag.
  void setBottomPaneSize(double pixels) => state = state.copyWith(
    bottomPaneSize: pixels,
    bottomDockMaximized: false,
  );

  /// Raises the bottom dock to at least [pixels] — never lowers it.
  ///
  /// For the one situation where a feature *put something in the dock* and the
  /// dock is too short to show it: the default 200 px is fine for a log table
  /// and useless for a Stage panel carrying a widget three times that tall,
  /// which is then revealed as a strip of its own chrome. Raise-only because
  /// the dock's height is the user's setting everywhere else, and a reveal has
  /// no business shrinking a dock the user deliberately made big.
  ///
  /// Deliberately does not touch [PanelLayoutState.bottomDockMaximized]: while
  /// maximized the stored size is only the restore target, and a maximized
  /// dock already shows more than this would ask for.
  void growBottomPaneTo(double pixels) {
    if ((state.bottomPaneSize ?? kDefaultBottomPaneSize) >= pixels) return;
    state = state.copyWith(bottomPaneSize: pixels);
  }

  // ── view-composition recipe seams ──────────────────────────────────

  /// Serialize the composition-relevant panel *intent* (signal tree, value
  /// column, transaction view, Stage) for collaboration sync. Diagnostic /
  /// ambient surfaces (RTL source, statistics strip, cocotb log) and all pixel
  /// geometry are deliberately excluded — only "what's on screen" intent syncs.
  CollabPanelVisibility toCompositionRecipe() => CollabPanelVisibility(
    signalTreeVisible: state.signalTreeVisible,
    valueColumnVisible: state.valueColumnVisible,
    transactionViewVisible: state.transactionViewVisible,
    stageViewVisible: state.stageViewVisible,
  );

  /// Apply a presenter's panel [recipe], setting the four composition-relevant
  /// intent flags and leaving the follower's local diagnostic-panel state
  /// untouched.
  void applyCompositionRecipe(CollabPanelVisibility recipe) {
    state = state.copyWith(
      signalTreeVisible: recipe.signalTreeVisible,
      valueColumnVisible: recipe.valueColumnVisible,
      transactionViewVisible: recipe.transactionViewVisible,
      stageViewVisible: recipe.stageViewVisible,
    );
  }
}
