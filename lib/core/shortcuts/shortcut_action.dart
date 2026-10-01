// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter/widgets.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// All keyboard-triggered actions recognized by the shortcut system.
///
/// Implements the cross-suite [CruxAction] interface so generic
/// infrastructure (command palette, menu builders, telemetry sinks)
/// can reason about WaveCrux actions alongside actions from the other
/// future Crux products without depending on
/// this specific enum. Each value's `id` is namespaced with the
/// `wavecrux.` prefix to avoid collisions; the per-value `category`
/// mapping lives in the [ShortcutActionCategory] extension in
/// [action_category.dart](action_category.dart).
enum ShortcutAction implements CruxAction {
  openFile,
  closeFile,
  quit,

  /// Show the About WaveCrux dialog. No default keyboard shortcut; reachable
  /// via the platform menu bar (WaveCrux menu on macOS, Help menu on
  /// Windows/Linux) and the command palette.
  openAbout,

  /// Open the Beta Issue Reporter dialog.
  ///
  /// Collects structured diagnostic data, lets the user opt out of
  /// individual categories, and opens a pre-filled GitHub new-issue page.
  /// Open to all tiers — no badge, no `FeatureGate`. Reachable from the
  /// Help menu / overflow menu, the command palette, and the About box.
  issueReporter,
  // ── zoom ──────────────────────────────────────────────────────────────────
  zoomIn,
  zoomOut,
  fitAll,

  /// Zoom in by one step centred on the viewport (W key — WASD navigation).
  waveformZoomIn,

  /// Zoom out by one step centred on the viewport (S key — WASD navigation).
  waveformZoomOut,

  /// Zoom to the active drag selection (Z key).
  zoomToSelection,
  // ── pan ───────────────────────────────────────────────────────────────────
  panLeft,
  panRight,

  /// Pan left by a small increment (left arrow — fine navigation).
  panLeftSmall,

  /// Pan right by a small increment (right arrow — fine navigation).
  panRightSmall,
  // ── jump ──────────────────────────────────────────────────────────────────
  /// Jump to the simulation start (Home key).
  jumpToStart,

  /// Jump to the simulation end (End key).
  jumpToEnd,
  // ── cursor / marker ───────────────────────────────────────────────────────
  nextTransition,
  prevTransition,
  setMarker,
  jumpToMarker,

  /// Remove a named marker (a–z). Opens a picker of the currently-set
  /// markers; selecting one deletes it. Discoverable via the command
  /// palette and menu bar, and via a right-click on a marker flag in the
  /// time ruler. No default keyboard binding — removal is infrequent and
  /// the set/jump chords (`M` / `⇧M`) own the marker keyboard slots.
  removeMarker,

  /// Remove all cursors (Escape). If the primary cursor is removed the
  /// secondary cursor is also automatically removed.
  clearCursors,

  /// Remove only the secondary (delta) cursor; primary remains.
  clearSecondaryCursor,

  /// Clear the current signal selection — deselect every signal currently
  /// selected via Ctrl/Cmd-click in the Signal Tree or value column
  /// (`selectedVariablesProvider`). Bound to Escape: the viewer's global
  /// Escape handler clears the signal selection alongside the cursors. The
  /// action itself carries no [SingleActivator] (Escape is owned by
  /// [clearCursors] at the binding-table level to keep the no-shadow conflict
  /// guard happy), but it stays discoverable from the menu / overflow menu /
  /// command palette and is enabled only while a selection exists.
  clearSignalSelection,

  /// Clear Canvas: remove every signal from the active tab's canvas in one
  /// step, leaving the file open and the cursors, markers, decoders and zoom
  /// as they are. View menu and command palette; no default chord, because a
  /// one-key wipe of a curated view is a chord that gets hit by accident. An
  /// Undo snackbar follows every clear.
  clearCanvas,

  /// Remove every selected signal from the active tab's canvas. In the
  /// Signals list the Delete and Backspace keys do this directly; this action
  /// is the Edit-menu and palette route to the same removal, so it carries no
  /// global chord of its own (a bare Delete bound app-wide would fire from
  /// panels that have nothing to do with the signal list).
  removeSelectedSignals,
  // ── session ───────────────────────────────────────────────────────────────
  /// Save the current session to its existing path (Ctrl/Cmd+S).
  saveSession,

  /// Save the current session to a new file chosen via a dialog (Ctrl/Cmd+Shift+S).
  saveSessionAs,

  /// Import a GTKWave `.gtkw` session file (Ctrl/Cmd+I).
  importGtkwSession,

  /// Open the export dialog to save VCD / PNG / SVG (Ctrl/Cmd+E).
  exportWaveform,

  /// Step to the next annotation in time order (`]`), centring it.
  ///
  /// Walkthrough navigation is a first-class command rather than a canvas-local
  /// binding, unlike the anchor nudge: it is how a *reader* drives a document
  /// somebody else annotated, so it has to be discoverable in the palette and
  /// rebindable by someone whose keyboard makes `]` awkward.
  annotationWalkthroughNext,

  /// Step to the previous annotation in time order (`[`).
  annotationWalkthroughPrevious,

  /// Start or stop stepping through the annotations automatically.
  annotationWalkthroughPlay,

  /// Create an annotation at the primary cursor on the selected signal row.
  ///
  /// The keyboard path to authoring. Alt/Option-click is the fast one and the
  /// canvas context menu is the discoverable one; this is the one that works
  /// without a pointing device, and the one that puts authoring in a menu at
  /// all.
  addAnnotationAtCursor,

  /// Create a band over the selected time range.
  ///
  /// Reads the Shift+drag selection when there is one and falls back to the
  /// two cursors. Exists as a menu action because the canvas context menu that
  /// used to be its only route is bound to **long-press**, which nobody
  /// performs with a mouse — and right-click is already secondary-cursor
  /// placement, so it cannot host one.
  annotateSelectedRange,

  /// Show or hide every annotation on the canvas.
  ///
  /// The control for the per-session visibility state that shipped in 5.9.1
  /// with persistence and export integration but **no way to set it** — the
  /// export dialog honoured a flag the user could not reach.
  toggleAnnotationsVisible,

  /// Show or hide the Annotations dock panel.
  ///
  /// Distinct from [toggleAnnotationsVisible]: that one hides the notes, this
  /// one hides the list of them. Opening the panel with no annotations is the
  /// point rather than an edge case — its empty state is where the authoring
  /// gesture is explained, and until this action existed that empty state
  /// could never render, because the panel only appeared once you already had
  /// an annotation.
  toggleAnnotationsPanel,

  /// Write a `.wavecruxpack` share bundle — the annotated view, the waveform
  /// excerpt it refers to and a preview, in one self-contained file.
  ///
  /// No default binding: it is a deliberate, occasional action that always
  /// passes through a disclosure step, and a chord that sends design data off
  /// the machine is not one worth being able to hit by accident.
  shareAnnotatedWaveform,

  /// End the live streaming VCD session in the active tab.
  ///
  /// Structurally hidden unless a stream is running (`isVisible:
  /// streamingActive`), so it costs nothing in the 99% of sessions that never
  /// stream. It exists as an action rather than a bare toolbar callback so it
  /// is reachable from the menu, the palette and the keymap editor like every
  /// other command — a mouse-only button is exactly the drift the descriptor
  /// table exists to prevent. No default binding: streaming is rare enough not
  /// to be worth a keyboard slot, and the palette reaches it.
  stopStreaming,
  // ── other ─────────────────────────────────────────────────────────────────
  openSearch,

  /// Open the VS Code-style command palette (Ctrl/Cmd+Shift+P).
  openCommandPalette,

  /// Open the protocol decoder picker to add a decoder (Ctrl/Cmd+Shift+D).
  addDecoder,

  /// Toggle the transaction table panel (bottom pane).
  toggleTransactionTable,

  /// Toggle the signal tree panel (left pane).
  toggleSignalTree,

  /// Toggle the value column panel (right pane).
  toggleValueColumn,

  /// Toggle the Stage panel (signal-bound widget dashboard).
  toggleStagePanel,

  /// Start / pause Stage Playback — auto-advance the primary cursor so
  /// signal-bound Stage widgets animate on their own.
  ///
  /// Open Core (no tier badge). The playback *engine* is always-on cursor
  /// infrastructure; this action and the transport UI are gated on Stage panel
  /// visibility (`isEnabled: fileLoaded && stageViewVisible`). Default binding:
  /// Space.
  togglePlayback,

  /// Toggle the live statistics strip (desktop only — ambient performance
  /// monitoring between the IDE layout and the status bar).
  toggleStatisticsStrip,
  toggleTheme,

  /// Open the process-wide App Diagnostics dialog (VERIFICATION_GUIDE §22.10.2).
  ///
  /// Modal dialog with Memory (overall RSS + Dart heap + wellen DB total,
  /// plus a per-tab breakdown table) and Frame Stats (FPS, frame budget
  /// overruns) sections, plus a "Copy Full Diagnostics Report" action that
  /// aggregates app-level data with the active pane's render stats and every
  /// loaded tab's file info and signal health.
  ///
  /// Default binding: Cmd/Ctrl+Shift+M ("Memory"). Replaces the legacy
  /// `openDiagnostics` action; the action was renamed (not deleted) because
  /// the current surface only owns the app-level slice of the old
  /// dialog — per-tab and per-pane data moved to the Tab Diagnostics drawer
  /// and Pane Render Stats popover respectively.
  openAppDiagnostics,

  /// Open the per-tab Tab Diagnostics drawer (VERIFICATION_GUIDE §22.10.1).
  ///
  /// The drawer is non-modal, follows the active tab, and shows four
  /// collapsible sections: File Info, Signal Health, Parser Backend, and
  /// Benchmark This File. Gated by [diagnosticsEnabledProvider] (hidden when
  /// the user has disabled diagnostics) and by `deviceClassProvider`
  /// (rendered on tablet and desktop; hidden on phone).
  ///
  /// Default binding: Cmd/Ctrl+Shift+I ("Inspect tab"). The `D`/`Shift+D`
  /// slot is already taken by [addDecoder]; `I` was previously only used
  /// (unmodified) by [importGtkwSession] (Cmd/Ctrl+I) so the shifted
  /// variant was free.
  openTabDiagnostics,

  /// Open the active pane's Pane Render Stats popover (VERIFICATION_GUIDE §22.10.3).
  ///
  /// Command-palette-only entry point; the popover's natural anchor is the
  /// `i`-icon in each pane's [ViewerTabBar]. Hidden on phone /
  /// phone-landscape and when [diagnosticsEnabledProvider] is false.
  openPaneRenderStats,

  /// Open the CXP cross-probe panel.
  ///
  /// The panel shows currently-connected CXP peers, a rolling buffer of
  /// recent cross-probe events, and a button to send the local selection
  /// to a specific peer. Available on tablet and desktop; hidden on
  /// phone. Default binding: no keystroke; reachable via command palette
  /// and (post-launch) the View menu.
  openCrossProbePanel,

  /// Open the settings screen (Ctrl/Cmd+,).
  openSettings,
  // ── diff / comparison ─────────────────────────────────────────────────────
  /// Open a file picker to compare a second waveform file (Ctrl/Cmd+Shift+C).
  compareWaveforms,

  /// Jump to the next divergence in diff mode (F7).
  nextDivergence,

  /// Jump to the previous divergence in diff mode (Shift+F7).
  prevDivergence,
  // ── switching activity ────────────────────────────────────────────────────
  /// Analyze switching activity for all loaded signals (Ctrl/Cmd+Shift+A).
  analyzeSwitchingActivity,
  // ── pattern search ────────────────────────────────────────────────────────
  /// Open the multi-signal pattern search dialog (Ctrl/Cmd+Shift+F).
  patternSearch,

  /// Jump to the next pattern search match (F3).
  nextPatternMatch,

  /// Jump to the previous pattern search match (Shift+F3).
  prevPatternMatch,
  // ── diagnostics ───────────────────────────────────────────────────────────
  /// Copy all available diagnostics data to the clipboard as plain text.
  copyDiagnosticsReport,
  // ── RTL source annotation ────────────────────────────────────────────────
  /// Load a GTKWave-compatible stems file to enable RTL source annotation.
  loadRtlStemsFile,

  /// Generate a GTKWave-compatible stems file from an HDL (Verilog/VHDL) source
  /// tree, so RTL source annotation works without GTKWave's xml2stems/vermin
  /// (desktop only).
  generateRtlStems,

  /// Import a Verilator `--json-only` AST dump as a stems source: the fully
  /// elaborated hierarchy (generate loops unrolled) is converted to a stems
  /// file and loaded, so paths match the waveform hierarchy exactly
  /// (desktop only).
  importVerilatorAst,

  /// Toggle the RTL source-annotation panel (desktop only).
  toggleRtlSourcePanel,
  // ── cocotb log correlation ───────────────────────────────────────────────
  /// Open the standalone Generate Test VCD dialog
  /// (Tools menu). Replaces the legacy diagnostics-dialog
  /// Generator tab. Reachable via the menu bar and command palette;
  /// suggested binding Cmd/Ctrl+Shift+G — currently no default binding
  /// because every shift-letter slot in that range is claimed; the
  /// command remains discoverable through the menu bar and command
  /// palette.
  generateTestVcd,

  /// Open the Convert PCAP to VCD dialog (Tools menu — Enterprise tier).
  ///
  /// Surfaces a Pro-overlay-supplied dialog that reads a libpcap (`.pcap`)
  /// file and synthesizes a VCD waveform of the Ethernet frames at a
  /// user-chosen physical-layer encoding (MII / RMII / GMII / RGMII /
  /// AXIS). The action is registered in open-core so it is discoverable
  /// in the menu bar / overflow menu / command palette regardless of
  /// tier; activation routes through `pcapToVcdDialogOpenerProvider`
  /// which is a no-op default in open-core and overridden by the
  /// Pro overlay to mount the actual conversion dialog.
  /// `FeatureGate.isAvailable(LicenseTier.enterprise, ref)` runs in the
  /// Pro overlay's opener; during `kBetaPeriod` it short-circuits to
  /// allow.
  convertPcapToVcd,

  /// Load a cocotb log file for time-correlated overlay on the waveform.
  loadCocotbLog,

  /// Unload the currently-loaded cocotb log file.
  clearCocotbLog,

  /// Toggle the cocotb log panel.
  toggleCocotbLogPanel,
  // ── stage workspace ──────────────────────────────────────────────────────
  /// Undo the last Stage workspace edit (Ctrl/Cmd+Z).
  ///
  /// Reverts the most recent panel/instance change recorded by
  /// [StageWorkspaceNotifier]'s command stack — adds, removes, layout
  /// changes, binding edits, configuration changes, label edits, and
  /// z-order moves. Drag-to-move and resize gestures are coalesced into
  /// a single undo step. No-op when the stack is empty.
  stageUndo,

  /// Redo the last undone Stage workspace edit
  /// (Ctrl/Cmd+Shift+Z, also Ctrl+Y on non-mac platforms).
  stageRedo,
  // ── set signal format ─────────────────────────────────────────────────────
  setFormatBinary,
  setFormatHexadecimal,
  setFormatOctal,
  setFormatUnsignedDecimal,
  setFormatSignedDecimal,
  setFormatAscii,
  setFormatIeee754Single,
  setFormatIeee754Double,
  setFormatFixedPointQ,
  setFormatSignedMagnitude,
  setFormatGrayCode,
  setFormatNamedEnum,
  // ── debug advisor ────────────────────────────────────────────────────────
  /// Toggle the Debug Advisor suggestions panel (Pro-tier feature surfaced
  /// in open-core via the `debugAdvisorServiceProvider` extension point).
  ///
  /// Default binding is Ctrl/Cmd+Shift+B ("deBug Advisor"). The originally
  /// proposed Ctrl/Cmd+Shift+D conflicts with [addDecoder]; the panel
  /// remains discoverable through the menu bar, the overflow action menu,
  /// and the command palette, so the chosen binding is documentation and
  /// muscle-memory only.
  debugAdvisorTogglePanel,
  // ── SystemVerilog assertion visualization ────────────────────────────────
  /// Toggle the SystemVerilog assertion summary panel (Pro-tier feature
  /// surfaced in open-core via the `svaPanelTogglerProvider` extension
  /// point and the `extraBottomDockTabsProvider` registry).
  ///
  /// Default binding is Ctrl/Cmd+Shift+V ("Verification"). Cmd/Ctrl+Shift+A
  /// (the originally proposed binding) conflicts with
  /// [analyzeSwitchingActivity]; the panel remains discoverable through
  /// the menu bar, the overflow action menu, and the command palette, so
  /// the chosen binding is documentation and muscle-memory only.
  toggleSvaPanel,

  /// Load a SystemVerilog assertion-result log (Verilator / VCS / Questa)
  /// for time-correlated overlay on the waveform. Pro-tier feature surfaced
  /// in open-core via the `svaResultsLoaderProvider` extension point; the
  /// Pro overlay supplies the file-pick + parse implementation and
  /// force-opens the SVA bottom-dock panel on success. No-op in a build
  /// without the Pro overlay installed.
  loadSvaResults,

  /// Unload the currently-loaded SVA result log. Pro-tier; routes through
  /// the clear seam on `svaResultsLoaderProvider` and hides the panel.
  clearSvaResults,
  // ── AI Waveform Assistant (Experimental, open-core) ──────────────────────
  /// Explain the current signal selection with a single, non-agentic AI
  /// model call ("Explain Selection"). Open-core / free, but gated:
  /// it is only visible when experimental AI is enabled
  /// (`aiExperimentalEnabledProvider`) and only enabled when a model is
  /// configured and at least one signal is selected. Carries the Experimental
  /// chip (not a tier badge). No default keyboard binding — palette / menu.
  aiExplainSelection,

  /// Toggle the agentic **AI Waveform Assistant** panel (Pro tier).
  /// The panel drives the `AiModelClient` + `AiToolRegistry` tool-use loop
  /// (NL navigation/search, explain-region drill-down, "why did this hang at
  /// time X?" anomaly hypotheses). Pro-tier: carries the PRO badge from
  /// `requiredTier`, and the panel header additionally renders the
  /// Experimental chip. Visible only when experimental AI is enabled
  /// (`aiExperimentalEnabledProvider`); dispatched through the open-core
  /// `aiAdvisorPanelTogglerProvider` extension point (Pro overrides it).
  /// No default keyboard binding — palette / menu.
  aiAdvisorTogglePanel,
  // ── collaborative viewing (Enterprise) ───────────────────────────────────
  /// Start a new collaborative session and share a room code or invite link
  /// (Enterprise tier). Routes through `FeatureGate.isAvailable` before
  /// opening the Share Session dialog.
  shareSession,

  /// Join an existing collaborative session using a room code
  /// (Enterprise tier). Routes through `FeatureGate.isAvailable` before
  /// opening the Join Session dialog.
  joinSession,

  /// Stop hosting the current collaborative session and disconnect all
  /// participants (available only while hosting).
  stopSharing,

  /// Leave the collaborative session the user joined as a participant
  /// (available only while connected as a non-host participant).
  leaveSession,

  /// Export the in-memory session event log as JSON or CSV
  /// (available only while a session is active or has been recorded).
  exportSessionRecording,

  /// Export the session's annotations as **review minutes** — Markdown or CSV,
  /// time-ordered, with author, wall clock, signal and tick.
  ///
  /// Distinct from [exportSessionRecording], which is the raw event log: the
  /// recording is audit evidence, the minutes are a document somebody pastes
  /// into a review ticket. They sit in the same menu group because they are
  /// two readings of the same session.
  exportReviewMinutes,
  // ── Presenter Mode (Enterprise) ───────────────────────────────────────────
  /// Hand the presenter role to another participant (Enterprise tier). Opens a
  /// picker of session participants; the current presenter or the host may
  /// transfer the viewport-driving token. Enabled only while in a session.
  handoffPresenter,

  /// Request the presenter role as a non-presenter (Enterprise tier). Surfaces
  /// an approve/deny prompt to the current presenter/host. Enabled only while a
  /// joined participant (the host already controls by default).
  requestPresenter,

  /// Resume following the presenter after locally detaching via a navigation
  /// gesture (Enterprise tier). Snaps the local viewport back to the
  /// presenter's. Enabled only while in a session.
  resumeFollowing,

  /// Drop an ephemeral "ping" pointer at the focused signal/time as a
  /// non-presenter (Enterprise tier) — a transient laser pointer that fades on
  /// its own. Enabled only while in a session.
  dropPing,

  /// Drop a persistent "pin" pointer at the focused signal/time as a
  /// non-presenter (Enterprise tier) — stays until its author deletes it.
  /// Enabled only while in a session.
  dropPin,
  // ── workspace management ──────────────────────────────────────────────────
  /// Empty the current workspace after a single confirmation dialog.
  /// All open tabs are closed and the auto-saved
  /// `workspace.json` is replaced with an empty workspace.
  resetWorkspace,

  /// Save the current workspace under a name (file picker) and then reset
  /// to empty. Cancelling the file picker aborts the reset.
  newWorkspace,

  /// Save the current workspace to a named `.wavecrux-workspace` file
  /// without resetting. The working state continues unchanged;
  /// the named file is a snapshot for sharing or version control.
  saveWorkspaceAs,

  /// Open a named `.wavecrux-workspace` file. Replaces the
  /// active workspace after a single confirmation when there are open tabs.
  openWorkspace,

  /// Export the active tab's state to a `.wavecrux` session file.
  /// Distinct from "Save Workspace As…" — the export captures one tab, not
  /// the multi-tab arrangement.
  exportTabAsSession,
  // ── tab management ────────────────────────────────────────────────────────
  /// Open a new welcome tab (Ctrl/Cmd+T).
  /// Close the active tab (Ctrl/Cmd+W — shadows closeFile at the keyboard
  /// level; closeFile remains accessible from the toolbar and menu bar).
  closeTab,

  /// Activate the next tab in the tab list (Ctrl+Tab).
  nextTab,

  /// Activate the previous tab in the tab list (Ctrl+Shift+Tab).
  previousTab,

  /// Jump to the first tab (Ctrl/Cmd+1). Hidden from menus.
  jumpToTab1,

  /// Jump to the second tab (Ctrl/Cmd+2). Hidden from menus.
  jumpToTab2,

  /// Jump to the third tab (Ctrl/Cmd+3). Hidden from menus.
  jumpToTab3,

  /// Jump to the fourth tab (Ctrl/Cmd+4). Hidden from menus.
  jumpToTab4,

  /// Jump to the fifth tab (Ctrl/Cmd+5). Hidden from menus.
  jumpToTab5,

  /// Jump to the sixth tab (Ctrl/Cmd+6). Hidden from menus.
  jumpToTab6,

  /// Jump to the seventh tab (Ctrl/Cmd+7). Hidden from menus.
  jumpToTab7,

  /// Jump to the eighth tab (Ctrl/Cmd+8). Hidden from menus.
  jumpToTab8,

  /// Jump to the ninth tab (Ctrl/Cmd+9). Hidden from menus.
  jumpToTab9,
  // ── pane management (split-pane) ────────────────────────────────
  /// Split the active pane horizontally, creating a second pane to the right
  /// (Ctrl/Cmd+\). The active tab moves into the new pane, leaving the
  /// original pane with the remaining tabs; if the active pane has only one
  /// tab the new pane opens empty. Hidden on phone / phone-landscape and on
  /// tablets narrower than 1000 dp.
  splitPaneRight,

  /// Close the active pane and merge its tabs into the surviving pane
  /// (Ctrl/Cmd+K W chord). No-op when the workspace already has a single
  /// pane.
  closePane,

  /// Move focus to the other pane (Ctrl/Cmd+K → chord). No-op when the
  /// workspace has a single pane.
  focusOtherPane,

  /// Move the active tab to the other pane (command palette only — the
  /// gesture equivalent is drag-tab-to-pane). No-op when the workspace
  /// has a single pane.
  moveTabToOtherPane,

  // ── help ──────────────────────────────────────────────────────────────────
  /// Manually check the version manifest for a newer release. Always
  /// available (openCore tier, no badge); surfaces the update banner when one
  /// exists, a confirmation when already current, or a non-fatal error toast on
  /// failure. The automatic launch/periodic checks are governed separately by
  /// the "automatically check for updates" setting.
  checkForUpdates,

  /// Open the online WaveCrux documentation (docs.wavecrux.app) in the user's
  /// browser. Open Core and never tier-gated — documentation is the first
  /// thing a new user reaches for, and every suite Help menu leads with it.
  openDocumentation;

  // ─── CruxAction interface implementation ─────────────────────────────────

  @override
  String get id => 'wavecrux.$name';

  @override
  ActionCategory get category => switch (this) {
    // ── App (macOS app menu / WaveCrux first menu) ────────────────────
    // Per Issue 7, File operations (Open, Save, Close, Export…) live in a
    // separate File menu rather than under "WaveCrux". The host-application
    // category holds only the two items that conventionally belong to the
    // app itself: Settings/Preferences and Quit. DesktopMenuBar renders the
    // `app` category as the macOS application menu (About | Settings | Quit)
    // and folds Settings + Quit into the bottom of the File menu on
    // Windows / Linux, matching VS Code / native desktop convention.
    ShortcutAction.quit => ActionCategory.app,
    ShortcutAction.openSettings => ActionCategory.app,
    // ── File ──────────────────────────────────────────────────────────
    ShortcutAction.openFile => ActionCategory.file,
    ShortcutAction.closeFile => ActionCategory.file,
    ShortcutAction.saveSession => ActionCategory.file,
    ShortcutAction.saveSessionAs => ActionCategory.file,
    ShortcutAction.importGtkwSession => ActionCategory.file,
    ShortcutAction.exportWaveform => ActionCategory.file,
    ShortcutAction.shareAnnotatedWaveform => ActionCategory.file,
    ShortcutAction.annotationWalkthroughNext => ActionCategory.navigate,
    ShortcutAction.annotationWalkthroughPrevious => ActionCategory.navigate,
    ShortcutAction.annotationWalkthroughPlay => ActionCategory.navigate,
    ShortcutAction.addAnnotationAtCursor => ActionCategory.edit,
    ShortcutAction.annotateSelectedRange => ActionCategory.edit,
    ShortcutAction.toggleAnnotationsVisible => ActionCategory.view,
    ShortcutAction.toggleAnnotationsPanel => ActionCategory.view,
    // Streaming is a waveform *source*, so ending it belongs with the other
    // source-lifecycle commands (Open / Close / Save) rather than under View.
    ShortcutAction.stopStreaming => ActionCategory.file,
    // ── View ──────────────────────────────────────────────────────────
    ShortcutAction.zoomIn => ActionCategory.view,
    ShortcutAction.zoomOut => ActionCategory.view,
    ShortcutAction.fitAll => ActionCategory.view,
    ShortcutAction.waveformZoomIn => ActionCategory.view,
    ShortcutAction.waveformZoomOut => ActionCategory.view,
    ShortcutAction.zoomToSelection => ActionCategory.view,
    ShortcutAction.toggleTheme => ActionCategory.view,
    ShortcutAction.toggleTransactionTable => ActionCategory.view,
    ShortcutAction.toggleSignalTree => ActionCategory.view,
    ShortcutAction.toggleValueColumn => ActionCategory.view,
    ShortcutAction.toggleStagePanel => ActionCategory.view,
    ShortcutAction.togglePlayback => ActionCategory.view,
    ShortcutAction.toggleStatisticsStrip => ActionCategory.view,
    ShortcutAction.toggleRtlSourcePanel => ActionCategory.view,
    // ── Navigate ──────────────────────────────────────────────────────
    ShortcutAction.panLeft => ActionCategory.navigate,
    ShortcutAction.panRight => ActionCategory.navigate,
    ShortcutAction.panLeftSmall => ActionCategory.navigate,
    ShortcutAction.panRightSmall => ActionCategory.navigate,
    ShortcutAction.jumpToStart => ActionCategory.navigate,
    ShortcutAction.jumpToEnd => ActionCategory.navigate,
    ShortcutAction.nextTransition => ActionCategory.navigate,
    ShortcutAction.prevTransition => ActionCategory.navigate,
    ShortcutAction.setMarker => ActionCategory.navigate,
    ShortcutAction.jumpToMarker => ActionCategory.navigate,
    ShortcutAction.removeMarker => ActionCategory.navigate,
    ShortcutAction.clearCursors => ActionCategory.navigate,
    ShortcutAction.clearSecondaryCursor => ActionCategory.navigate,
    ShortcutAction.clearSignalSelection => ActionCategory.navigate,
    ShortcutAction.clearCanvas => ActionCategory.view,
    ShortcutAction.removeSelectedSignals => ActionCategory.edit,
    // ── Search ────────────────────────────────────────────────────────
    ShortcutAction.openSearch => ActionCategory.search,
    ShortcutAction.patternSearch => ActionCategory.search,
    ShortcutAction.nextPatternMatch => ActionCategory.search,
    ShortcutAction.prevPatternMatch => ActionCategory.search,
    // ── Tools ─────────────────────────────────────────────────────────
    ShortcutAction.addDecoder => ActionCategory.tools,
    ShortcutAction.compareWaveforms => ActionCategory.tools,
    ShortcutAction.nextDivergence => ActionCategory.tools,
    ShortcutAction.prevDivergence => ActionCategory.tools,
    ShortcutAction.analyzeSwitchingActivity => ActionCategory.tools,
    ShortcutAction.loadRtlStemsFile => ActionCategory.tools,
    ShortcutAction.generateRtlStems => ActionCategory.tools,
    ShortcutAction.importVerilatorAst => ActionCategory.tools,
    ShortcutAction.openAppDiagnostics => ActionCategory.tools,
    ShortcutAction.openTabDiagnostics => ActionCategory.tools,
    ShortcutAction.openPaneRenderStats => ActionCategory.tools,
    ShortcutAction.openCrossProbePanel => ActionCategory.view,
    ShortcutAction.copyDiagnosticsReport => ActionCategory.tools,
    ShortcutAction.generateTestVcd => ActionCategory.tools,
    ShortcutAction.convertPcapToVcd => ActionCategory.tools,
    ShortcutAction.loadCocotbLog => ActionCategory.tools,
    ShortcutAction.clearCocotbLog => ActionCategory.tools,
    ShortcutAction.toggleCocotbLogPanel => ActionCategory.view,
    // ── Stage workspace ───────────────────────────────────────────────
    ShortcutAction.stageUndo => ActionCategory.tools,
    ShortcutAction.stageRedo => ActionCategory.tools,
    // ── Set signal format ─────────────────────────────────────────────
    ShortcutAction.setFormatBinary => ActionCategory.tools,
    ShortcutAction.setFormatHexadecimal => ActionCategory.tools,
    ShortcutAction.setFormatOctal => ActionCategory.tools,
    ShortcutAction.setFormatUnsignedDecimal => ActionCategory.tools,
    ShortcutAction.setFormatSignedDecimal => ActionCategory.tools,
    ShortcutAction.setFormatAscii => ActionCategory.tools,
    ShortcutAction.setFormatIeee754Single => ActionCategory.tools,
    ShortcutAction.setFormatIeee754Double => ActionCategory.tools,
    ShortcutAction.setFormatFixedPointQ => ActionCategory.tools,
    ShortcutAction.setFormatSignedMagnitude => ActionCategory.tools,
    ShortcutAction.setFormatGrayCode => ActionCategory.tools,
    ShortcutAction.setFormatNamedEnum => ActionCategory.tools,
    // ── Debug Advisor (Pro tier) ──────────────────────────────────────
    ShortcutAction.debugAdvisorTogglePanel => ActionCategory.tools,
    ShortcutAction.aiExplainSelection => ActionCategory.tools,
    ShortcutAction.aiAdvisorTogglePanel => ActionCategory.tools,
    // ── SystemVerilog assertion visualization (Pro tier) ──────────────
    ShortcutAction.toggleSvaPanel => ActionCategory.view,
    ShortcutAction.loadSvaResults => ActionCategory.tools,
    ShortcutAction.clearSvaResults => ActionCategory.tools,
    // ── Collaborative viewing (Enterprise tier) ───────────────────────
    ShortcutAction.shareSession => ActionCategory.file,
    ShortcutAction.joinSession => ActionCategory.file,
    ShortcutAction.stopSharing => ActionCategory.file,
    ShortcutAction.leaveSession => ActionCategory.file,
    ShortcutAction.exportSessionRecording => ActionCategory.file,
    ShortcutAction.exportReviewMinutes => ActionCategory.file,
    // ── Presenter Mode (Enterprise) ───────────────────────────────────
    ShortcutAction.handoffPresenter => ActionCategory.file,
    ShortcutAction.requestPresenter => ActionCategory.file,
    ShortcutAction.resumeFollowing => ActionCategory.file,
    ShortcutAction.dropPing => ActionCategory.file,
    ShortcutAction.dropPin => ActionCategory.file,
    // ── Workspace management ──────────────────────────────────────────
    ShortcutAction.resetWorkspace => ActionCategory.file,
    ShortcutAction.newWorkspace => ActionCategory.file,
    ShortcutAction.saveWorkspaceAs => ActionCategory.file,
    ShortcutAction.openWorkspace => ActionCategory.file,
    ShortcutAction.exportTabAsSession => ActionCategory.file,
    // ── Pane management (split-pane) ────────────────────────
    ShortcutAction.splitPaneRight => ActionCategory.view,
    ShortcutAction.closePane => ActionCategory.view,
    ShortcutAction.focusOtherPane => ActionCategory.view,
    ShortcutAction.moveTabToOtherPane => ActionCategory.view,
    // ── Tab management ────────────────────────────────────────────────
    ShortcutAction.closeTab => ActionCategory.file,
    // Tab navigation sits under View across the suite — it changes what is
    // on screen rather than acting on a file. jumpToTabN stay under File
    // with the rest of the tab lifecycle (they are accelerator-only).
    ShortcutAction.nextTab => ActionCategory.view,
    ShortcutAction.previousTab => ActionCategory.view,
    ShortcutAction.jumpToTab1 => ActionCategory.file,
    ShortcutAction.jumpToTab2 => ActionCategory.file,
    ShortcutAction.jumpToTab3 => ActionCategory.file,
    ShortcutAction.jumpToTab4 => ActionCategory.file,
    ShortcutAction.jumpToTab5 => ActionCategory.file,
    ShortcutAction.jumpToTab6 => ActionCategory.file,
    ShortcutAction.jumpToTab7 => ActionCategory.file,
    ShortcutAction.jumpToTab8 => ActionCategory.file,
    ShortcutAction.jumpToTab9 => ActionCategory.file,
    // ── Help ──────────────────────────────────────────────────────────
    ShortcutAction.openAbout => ActionCategory.help,
    ShortcutAction.issueReporter => ActionCategory.help,
    // VS Code lists the palette opener at the top of View, and the suite
    // follows it; every surface (menu, overflow, palette grouping) reads
    // this one category, so they stay in agreement.
    ShortcutAction.openCommandPalette => ActionCategory.view,
    ShortcutAction.checkForUpdates => ActionCategory.help,
    ShortcutAction.openDocumentation => ActionCategory.help,
  };
}

/// [Intent] that carries a [ShortcutAction] through Flutter's Actions/Shortcuts tree.
class ShortcutActionIntent extends Intent {
  const ShortcutActionIntent(this.action);

  final ShortcutAction action;

  @override
  bool operator ==(Object other) =>
      other is ShortcutActionIntent && other.action == action;

  @override
  int get hashCode => action.hashCode;
}

/// Provides localized human-readable labels for display in settings UI.
extension ShortcutActionLabel on ShortcutAction {
  String label(L10N l10n) => switch (this) {
    ShortcutAction.openFile => l10n.shortcutActionOpenFile,
    ShortcutAction.closeFile => l10n.shortcutActionCloseFile,
    ShortcutAction.quit => l10n.shortcutActionQuit,
    ShortcutAction.openAbout => l10n.shortcutActionOpenAbout,
    // The menu label, NOT issueReporterTitle: that string is the dialog's
    // own heading, and a heading must not carry the ellipsis a menu item
    // needs to say "this opens something".
    ShortcutAction.issueReporter => l10n.shortcutActionSubmitIssue,
    ShortcutAction.zoomIn => l10n.shortcutActionZoomIn,
    ShortcutAction.zoomOut => l10n.shortcutActionZoomOut,
    ShortcutAction.fitAll => l10n.shortcutActionFitAll,
    ShortcutAction.waveformZoomIn => l10n.shortcutActionWaveformZoomIn,
    ShortcutAction.waveformZoomOut => l10n.shortcutActionWaveformZoomOut,
    ShortcutAction.zoomToSelection => l10n.shortcutActionZoomToSelection,
    ShortcutAction.panLeft => l10n.shortcutActionPanLeft,
    ShortcutAction.panRight => l10n.shortcutActionPanRight,
    ShortcutAction.panLeftSmall => l10n.shortcutActionPanLeftSmall,
    ShortcutAction.panRightSmall => l10n.shortcutActionPanRightSmall,
    ShortcutAction.jumpToStart => l10n.shortcutActionJumpToStart,
    ShortcutAction.jumpToEnd => l10n.shortcutActionJumpToEnd,
    ShortcutAction.nextTransition => l10n.shortcutActionNextTransition,
    ShortcutAction.prevTransition => l10n.shortcutActionPrevTransition,
    ShortcutAction.toggleTheme => l10n.shortcutActionToggleTheme,
    ShortcutAction.openAppDiagnostics => l10n.shortcutActionOpenAppDiagnostics,
    ShortcutAction.openTabDiagnostics => l10n.shortcutActionOpenTabDiagnostics,
    ShortcutAction.openPaneRenderStats =>
      l10n.shortcutActionOpenPaneRenderStats,
    ShortcutAction.openCrossProbePanel => l10n.crossProbeMenuItem,
    ShortcutAction.setMarker => l10n.shortcutActionSetMarker,
    ShortcutAction.jumpToMarker => l10n.shortcutActionJumpToMarker,
    ShortcutAction.removeMarker => l10n.shortcutActionRemoveMarker,
    ShortcutAction.openSearch => l10n.shortcutActionOpenSearch,
    ShortcutAction.openCommandPalette => l10n.shortcutActionOpenCommandPalette,
    ShortcutAction.saveSession => l10n.shortcutActionSaveSession,
    ShortcutAction.saveSessionAs => l10n.shortcutActionSaveSessionAs,
    ShortcutAction.importGtkwSession => l10n.shortcutActionImportGtkwSession,
    ShortcutAction.exportWaveform => l10n.shortcutActionExportWaveform,
    ShortcutAction.shareAnnotatedWaveform =>
      l10n.shortcutActionShareAnnotatedWaveform,
    ShortcutAction.annotationWalkthroughNext =>
      l10n.shortcutActionAnnotationWalkthroughNext,
    ShortcutAction.annotationWalkthroughPrevious =>
      l10n.shortcutActionAnnotationWalkthroughPrevious,
    ShortcutAction.annotationWalkthroughPlay =>
      l10n.shortcutActionAnnotationWalkthroughPlay,
    ShortcutAction.addAnnotationAtCursor =>
      l10n.shortcutActionAddAnnotationAtCursor,
    ShortcutAction.annotateSelectedRange =>
      l10n.shortcutActionAnnotateSelectedRange,
    ShortcutAction.toggleAnnotationsVisible =>
      l10n.shortcutActionToggleAnnotationsVisible,
    ShortcutAction.toggleAnnotationsPanel =>
      l10n.shortcutActionToggleAnnotationsPanel,
    ShortcutAction.stopStreaming => l10n.shortcutActionStopStreaming,
    ShortcutAction.openSettings => l10n.shortcutActionOpenSettings,
    ShortcutAction.clearCursors => l10n.shortcutActionClearCursors,
    ShortcutAction.clearSecondaryCursor =>
      l10n.shortcutActionClearSecondaryCursor,
    ShortcutAction.clearSignalSelection =>
      l10n.shortcutActionClearSignalSelection,
    ShortcutAction.clearCanvas => l10n.shortcutActionClearCanvas,
    ShortcutAction.removeSelectedSignals =>
      l10n.shortcutActionRemoveSelectedSignals,
    ShortcutAction.addDecoder => l10n.shortcutActionAddDecoder,
    ShortcutAction.toggleTransactionTable =>
      l10n.shortcutActionToggleTransactionTable,
    ShortcutAction.toggleSignalTree => l10n.shortcutActionToggleSignalTree,
    ShortcutAction.toggleValueColumn => l10n.shortcutActionToggleValueColumn,
    ShortcutAction.toggleStagePanel => l10n.shortcutActionToggleStagePanel,
    ShortcutAction.togglePlayback => l10n.shortcutActionTogglePlayback,
    ShortcutAction.toggleStatisticsStrip =>
      l10n.shortcutActionToggleStatisticsStrip,
    ShortcutAction.compareWaveforms => l10n.shortcutActionCompareWaveforms,
    ShortcutAction.nextDivergence => l10n.shortcutActionNextDivergence,
    ShortcutAction.prevDivergence => l10n.shortcutActionPrevDivergence,
    ShortcutAction.analyzeSwitchingActivity =>
      l10n.shortcutActionAnalyzeSwitchingActivity,
    ShortcutAction.patternSearch => l10n.shortcutActionPatternSearch,
    ShortcutAction.nextPatternMatch => l10n.shortcutActionNextPatternMatch,
    ShortcutAction.prevPatternMatch => l10n.shortcutActionPrevPatternMatch,
    ShortcutAction.copyDiagnosticsReport =>
      l10n.shortcutActionCopyDiagnosticsReport,
    ShortcutAction.loadRtlStemsFile => l10n.shortcutActionLoadRtlStemsFile,
    ShortcutAction.generateRtlStems => l10n.shortcutActionGenerateRtlStems,
    ShortcutAction.importVerilatorAst => l10n.shortcutActionImportVerilatorAst,
    ShortcutAction.toggleRtlSourcePanel =>
      l10n.shortcutActionToggleRtlSourcePanel,
    ShortcutAction.generateTestVcd => l10n.shortcutActionGenerateTestVcd,
    ShortcutAction.convertPcapToVcd => l10n.shortcutActionConvertPcapToVcd,
    ShortcutAction.loadCocotbLog => l10n.shortcutActionLoadCocotbLog,
    ShortcutAction.clearCocotbLog => l10n.shortcutActionClearCocotbLog,
    ShortcutAction.toggleCocotbLogPanel =>
      l10n.shortcutActionToggleCocotbLogPanel,
    ShortcutAction.stageUndo => l10n.shortcutActionStageUndo,
    ShortcutAction.stageRedo => l10n.shortcutActionStageRedo,
    ShortcutAction.debugAdvisorTogglePanel =>
      l10n.shortcutActionDebugAdvisorTogglePanel,
    ShortcutAction.toggleSvaPanel => l10n.shortcutActionToggleSvaPanel,
    ShortcutAction.loadSvaResults => l10n.shortcutActionLoadSvaResults,
    ShortcutAction.clearSvaResults => l10n.shortcutActionClearSvaResults,
    ShortcutAction.aiExplainSelection => l10n.shortcutActionAiExplainSelection,
    ShortcutAction.aiAdvisorTogglePanel =>
      l10n.shortcutActionAiAdvisorTogglePanel,
    ShortcutAction.setFormatBinary => l10n.shortcutActionSetFormatBinary,
    ShortcutAction.setFormatHexadecimal =>
      l10n.shortcutActionSetFormatHexadecimal,
    ShortcutAction.setFormatOctal => l10n.shortcutActionSetFormatOctal,
    ShortcutAction.setFormatUnsignedDecimal =>
      l10n.shortcutActionSetFormatUnsignedDecimal,
    ShortcutAction.setFormatSignedDecimal =>
      l10n.shortcutActionSetFormatSignedDecimal,
    ShortcutAction.setFormatAscii => l10n.shortcutActionSetFormatAscii,
    ShortcutAction.setFormatIeee754Single =>
      l10n.shortcutActionSetFormatIeee754Single,
    ShortcutAction.setFormatIeee754Double =>
      l10n.shortcutActionSetFormatIeee754Double,
    ShortcutAction.setFormatFixedPointQ =>
      l10n.shortcutActionSetFormatFixedPointQ,
    ShortcutAction.setFormatSignedMagnitude =>
      l10n.shortcutActionSetFormatSignedMagnitude,
    ShortcutAction.setFormatGrayCode => l10n.shortcutActionSetFormatGrayCode,
    ShortcutAction.setFormatNamedEnum => l10n.shortcutActionSetFormatNamedEnum,
    ShortcutAction.shareSession => l10n.shortcutActionShareSession,
    ShortcutAction.joinSession => l10n.shortcutActionJoinSession,
    ShortcutAction.stopSharing => l10n.shortcutActionStopSharing,
    ShortcutAction.leaveSession => l10n.shortcutActionLeaveSession,
    ShortcutAction.exportSessionRecording =>
      l10n.shortcutActionExportSessionRecording,
    ShortcutAction.exportReviewMinutes =>
      l10n.shortcutActionExportReviewMinutes,
    ShortcutAction.handoffPresenter => l10n.shortcutActionHandoffPresenter,
    ShortcutAction.requestPresenter => l10n.shortcutActionRequestPresenter,
    ShortcutAction.resumeFollowing => l10n.shortcutActionResumeFollowing,
    ShortcutAction.dropPing => l10n.shortcutActionDropPing,
    ShortcutAction.dropPin => l10n.shortcutActionDropPin,
    ShortcutAction.resetWorkspace => l10n.shortcutActionResetWorkspace,
    ShortcutAction.newWorkspace => l10n.shortcutActionNewWorkspace,
    ShortcutAction.saveWorkspaceAs => l10n.shortcutActionSaveWorkspaceAs,
    ShortcutAction.openWorkspace => l10n.shortcutActionOpenWorkspace,
    ShortcutAction.exportTabAsSession => l10n.shortcutActionExportTabAsSession,
    ShortcutAction.closeTab => l10n.shortcutActionCloseTab,
    ShortcutAction.nextTab => l10n.shortcutActionNextTab,
    ShortcutAction.previousTab => l10n.shortcutActionPreviousTab,
    ShortcutAction.jumpToTab1 => l10n.shortcutActionJumpToTab(1),
    ShortcutAction.jumpToTab2 => l10n.shortcutActionJumpToTab(2),
    ShortcutAction.jumpToTab3 => l10n.shortcutActionJumpToTab(3),
    ShortcutAction.jumpToTab4 => l10n.shortcutActionJumpToTab(4),
    ShortcutAction.jumpToTab5 => l10n.shortcutActionJumpToTab(5),
    ShortcutAction.jumpToTab6 => l10n.shortcutActionJumpToTab(6),
    ShortcutAction.jumpToTab7 => l10n.shortcutActionJumpToTab(7),
    ShortcutAction.jumpToTab8 => l10n.shortcutActionJumpToTab(8),
    ShortcutAction.jumpToTab9 => l10n.shortcutActionJumpToTab(9),
    ShortcutAction.splitPaneRight => l10n.shortcutActionSplitPaneRight,
    ShortcutAction.closePane => l10n.shortcutActionClosePane,
    ShortcutAction.focusOtherPane => l10n.shortcutActionFocusOtherPane,
    ShortcutAction.moveTabToOtherPane => l10n.shortcutActionMoveTabToOtherPane,
    ShortcutAction.checkForUpdates => l10n.shortcutActionCheckForUpdates,
    ShortcutAction.openDocumentation => l10n.shortcutActionOpenDocumentation,
  };
}
