// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_menu_bar/crux_menu_bar.dart';
import 'package:wavecrux/core/shortcuts/action_category.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';

/// Declarative ordering and grouping of WaveCrux's menu-bar actions, in the
/// suite-wide canonical group order (see the shared `crux_menu_bar` README).
///
/// `action_descriptors.dart` is the single source of truth for *which* actions
/// appear in the menu surface and *when* they are visible/enabled. This table
/// is the single source of truth for the *order* those actions appear in and
/// *where the logical separators fall*: each category maps to an ordered list
/// of groups, and the shared menu bar draws a divider between consecutive
/// non-empty groups (empty groups — e.g. an Enterprise collaboration block on
/// an open-core build — collapse away with no dangling separator).
///
/// ## Canonical group order
///
/// The same skeleton is used by all four products, so a user moving between
/// them finds each command in the same place:
///
/// - **File** — New | Open/Import | Save | Export | Close | Reset | *(collab)*
/// - **View** — Command Palette | Zoom | Panels | Panes | Tabs | Appearance
/// - **Navigate** — Ends | Step | Markers | Clear
/// - **Search** — Find | Match navigation
/// - **Tools** — Analyses… | Diagnostics (last)
/// - **Help** — Documentation | Report Issue | Check for Updates | About
///
/// ## Not in this table on purpose
///
/// `openSettings` and `quit` are **deliberately absent**: their placement is
/// platform-specific in a way the table cannot express (macOS application menu
/// vs. the bottom of the Windows/Linux File menu), so `CruxDesktopMenuBar`
/// places them from [kAppMenuActions]. `openAbout` and `checkForUpdates` *are*
/// listed here, under Help — their Windows/Linux home — and the macOS renderer
/// hoists them into the application menu.
///
/// `ActionCategory.edit` renders a menu because annotation
/// authoring is WaveCrux's first genuine editing action — it creates a thing
/// the user then owns, edits and deletes. It is deliberately not filed under
/// View (which would put a create action in a menu of visibility toggles) nor
/// under Navigate (whose annotation group is the walkthrough, a reading
/// activity). Undo/redo for annotations already exists in
/// `AnnotationsNotifier` without a menu surface and is the obvious next
/// occupant.
///
/// ## Drift guard
///
/// `desktop_menu_bar_test.dart` asserts that `cruxMenuLayoutActions(this)`
/// unioned with `kAppMenuActions.desktopFolded` equals exactly the set of
/// actions whose descriptor lists `ActionSurface.menu`. A newly menu-visible
/// action therefore fails the test until it is placed in a group here — the
/// same "single source of truth, enforced" discipline as the exhaustive
/// `descriptorFor` switch.
const CruxMenuLayout<ShortcutAction> kMenuLayout = {
  // ── Edit ──────────────────────────────────────────────────────────────────
  // Annotation authoring.
  ActionCategory.edit: [
    [
      ShortcutAction.addAnnotationAtCursor,
      ShortcutAction.annotateSelectedRange,
    ],
    // Signal removal: the Signals list's Delete key, reachable by name.
    [
      ShortcutAction.removeSelectedSignals,
    ],
  ],

  // ── File ──────────────────────────────────────────────────────────────────
  // New | Open/Import | Save | Export | Close | Reset | Collaboration (ENT).
  ActionCategory.file: [
    [
      ShortcutAction.newWorkspace,
    ],
    [
      ShortcutAction.openFile,
      ShortcutAction.openWorkspace,
      ShortcutAction.importGtkwSession,
    ],
    [
      ShortcutAction.saveSession,
      ShortcutAction.saveSessionAs,
      ShortcutAction.saveWorkspaceAs,
    ],
    [
      ShortcutAction.exportTabAsSession,
      ShortcutAction.exportWaveform,
      ShortcutAction.shareAnnotatedWaveform,
    ],
    [
      ShortcutAction.closeTab,
      ShortcutAction.closeFile,
      // Present only while a stream is live (`isVisible: streamingActive`), so
      // the group is Close/Close/Stop mid-stream and Close/Close otherwise.
      ShortcutAction.stopStreaming,
    ],
    [
      ShortcutAction.resetWorkspace,
    ],
    [
      ShortcutAction.shareSession,
      ShortcutAction.joinSession,
      ShortcutAction.stopSharing,
      ShortcutAction.leaveSession,
      ShortcutAction.exportSessionRecording,
      ShortcutAction.exportReviewMinutes,
    ],
    // Presenter Mode (Enterprise).
    [
      ShortcutAction.handoffPresenter,
      ShortcutAction.requestPresenter,
      ShortcutAction.resumeFollowing,
      ShortcutAction.dropPing,
      ShortcutAction.dropPin,
    ],
  ],

  // ── View ──────────────────────────────────────────────────────────────────
  // Command Palette | Zoom | Panels | Panes | Tabs | Appearance.
  //
  // The palette opener leads the View menu, matching VS Code. It is reachable
  // from the menu so the palette can always be reopened even if its keyboard
  // shortcut is unbound (issue #38), and is excluded from the palette surface
  // itself (self-referential).
  ActionCategory.view: [
    [
      ShortcutAction.openCommandPalette,
    ],
    [
      ShortcutAction.zoomIn,
      ShortcutAction.zoomOut,
      ShortcutAction.zoomToSelection,
      ShortcutAction.fitAll,
    ],
    // What is on the canvas: Clear Canvas sits beside the zoom group because
    // both act on the view of the open file, not on a panel.
    [
      ShortcutAction.clearCanvas,
    ],
    [
      ShortcutAction.toggleSignalTree,
      ShortcutAction.toggleValueColumn,
      ShortcutAction.toggleTransactionTable,
      ShortcutAction.toggleStagePanel,
      ShortcutAction.togglePlayback,
      ShortcutAction.toggleCocotbLogPanel,
      ShortcutAction.toggleRtlSourcePanel,
      ShortcutAction.toggleSvaPanel,
      ShortcutAction.openCrossProbePanel,
      ShortcutAction.toggleStatisticsStrip,
    ],
    // Annotations: the notes themselves, then the list of them. Two toggles
    // rather than one because hiding your notes and hiding the panel that
    // lists them are different intentions — and the panel one is what makes
    // an empty Annotations panel reachable at all.
    [
      ShortcutAction.toggleAnnotationsVisible,
      ShortcutAction.toggleAnnotationsPanel,
    ],
    [
      ShortcutAction.splitPaneRight,
      ShortcutAction.closePane,
      ShortcutAction.focusOtherPane,
      ShortcutAction.moveTabToOtherPane,
    ],
    [
      ShortcutAction.nextTab,
      ShortcutAction.previousTab,
    ],
    [
      ShortcutAction.toggleTheme,
    ],
  ],

  // ── Navigate ──────────────────────────────────────────────────────────────
  // Jump-to-ends | Transitions | Markers | Clear.
  ActionCategory.navigate: [
    [
      ShortcutAction.jumpToStart,
      ShortcutAction.jumpToEnd,
    ],
    [
      ShortcutAction.prevTransition,
      ShortcutAction.nextTransition,
    ],
    [
      ShortcutAction.setMarker,
      ShortcutAction.jumpToMarker,
      ShortcutAction.removeMarker,
    ],
    [
      ShortcutAction.annotationWalkthroughPrevious,
      ShortcutAction.annotationWalkthroughNext,
      ShortcutAction.annotationWalkthroughPlay,
    ],
    [
      ShortcutAction.clearCursors,
      ShortcutAction.clearSignalSelection,
    ],
  ],

  // ── Search ────────────────────────────────────────────────────────────────
  // Find | Pattern match navigation.
  ActionCategory.search: [
    [
      ShortcutAction.openSearch,
      ShortcutAction.patternSearch,
    ],
    [
      ShortcutAction.prevPatternMatch,
      ShortcutAction.nextPatternMatch,
    ],
  ],

  // ── Tools ─────────────────────────────────────────────────────────────────
  // Decoders | Compare | Analyze | Advisor (PRO) | AI | cocotb | SVA |
  // Stage edit | Generate/Convert | Diagnostics (last, per the suite order).
  ActionCategory.tools: [
    [
      ShortcutAction.addDecoder,
    ],
    [
      ShortcutAction.compareWaveforms,
      ShortcutAction.prevDivergence,
      ShortcutAction.nextDivergence,
    ],
    [
      ShortcutAction.analyzeSwitchingActivity,
      ShortcutAction.generateRtlStems,
      ShortcutAction.importVerilatorAst,
      ShortcutAction.loadRtlStemsFile,
    ],
    [
      ShortcutAction.debugAdvisorTogglePanel,
    ],
    [
      ShortcutAction.aiExplainSelection,
      ShortcutAction.aiAdvisorTogglePanel,
    ],
    [
      ShortcutAction.loadCocotbLog,
      ShortcutAction.clearCocotbLog,
    ],
    [
      ShortcutAction.loadSvaResults,
      ShortcutAction.clearSvaResults,
    ],
    [
      ShortcutAction.stageUndo,
      ShortcutAction.stageRedo,
    ],
    [
      ShortcutAction.generateTestVcd,
      ShortcutAction.convertPcapToVcd,
    ],
    [
      ShortcutAction.openTabDiagnostics,
      ShortcutAction.openAppDiagnostics,
      ShortcutAction.copyDiagnosticsReport,
    ],
  ],

  // ── Help ──────────────────────────────────────────────────────────────────
  // Documentation | Report Issue | Check for Updates | About.
  // About and Check for Updates are hoisted into the macOS application menu.
  ActionCategory.help: [
    [
      ShortcutAction.openDocumentation,
    ],
    [
      ShortcutAction.issueReporter,
    ],
    [
      ShortcutAction.checkForUpdates,
    ],
    [
      ShortcutAction.openAbout,
    ],
  ],
};

/// The four actions whose menu placement the host platform decides.
///
/// On macOS all render in the system application menu; on Windows/Linux
/// [CruxAppMenuActions.settings] and [CruxAppMenuActions.quit] fold into the
/// bottom of File while About and Check for Updates stay in Help.
const CruxAppMenuActions<ShortcutAction> kAppMenuActions = CruxAppMenuActions(
  about: ShortcutAction.openAbout,
  checkForUpdates: ShortcutAction.checkForUpdates,
  settings: ShortcutAction.openSettings,
  quit: ShortcutAction.quit,
);
