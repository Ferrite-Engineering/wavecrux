// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/core/shortcuts/action_descriptor.dart';
import 'package:wavecrux/core/shortcuts/action_requirement.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/enums/device_class.dart';

/// The single source of truth for where every [ShortcutAction] appears and
/// when it is visible / enabled. Every action-discovery surface (toolbar, menu
/// bar, overflow menu, command palette) reads from this one function instead of
/// maintaining its own visibility set and enablement logic — see
/// [ActionDescriptor] for the per-surface presentation policy.
///
/// ## IMPORTANT — adding a new action
///
/// This is an **exhaustive `switch`** (like `ShortcutAction.category` and
/// `.label`). Adding a value to [ShortcutAction] therefore fails to compile
/// until a case is added here, which is the guardrail that keeps every new
/// action wired into the single source of truth. Never re-introduce a
/// per-surface "hidden actions" set or a per-surface `_isEnabled` copy — declare
/// the behavior here instead.
ActionDescriptor descriptorFor(ShortcutAction action) => switch (action) {
  // ── Everywhere (toolbar + menu + overflow + palette), always enabled ──
  ShortcutAction.openFile ||
  ShortcutAction.openSearch ||
  ShortcutAction.openSettings => const ActionDescriptor(surfaces: _everywhere),

  // ── Save Session As — browsable only, requires a loaded file ────────
  // Deliberately NOT on the toolbar: a Save-As button sitting one pixel from
  // Save is the most mis-clickable pair a strip can offer. It keeps its menu
  // item, its overflow and palette entries, and its Cmd/Ctrl+Shift+S chord.
  //
  // Hidden in the browser, like Save Session: a browser cannot give back a
  // saved session's path, and its Open File does not take `.wavecrux`.
  ShortcutAction.saveSessionAs => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    isVisible: _notWeb,
    requires: [ActionRequirement.fileLoaded],
  ),

  // ── Save Session — everywhere, requires a file, not in the browser ──
  ShortcutAction.saveSession => const ActionDescriptor(
    surfaces: _everywhere,
    isVisible: _notWeb,
    requires: [ActionRequirement.fileLoaded],
  ),

  // ── Share Annotated Waveform — browsable only, requires a loaded file ─
  // Off the toolbar on purpose. It is the one action that sends design data
  // off the machine, it is used occasionally rather than repeatedly, and a
  // button beside Export would invite the mis-click that a disclosure dialog
  // then has to catch.
  ShortcutAction.shareAnnotatedWaveform => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [ActionRequirement.fileLoaded],
  ),

  // ── Walkthrough — browsable, and only while there is a tour to take ─
  // Structurally hidden rather than greyed when the tab has no annotations,
  // the same call `stopStreaming` makes: three permanently-dead rows would be
  // menu noise in every session that never annotates, and the palette has no
  // greyed state to explain them with.
  ShortcutAction.annotationWalkthroughNext ||
  ShortcutAction.annotationWalkthroughPrevious ||
  ShortcutAction.annotationWalkthroughPlay => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    isVisible: _hasAnnotations,
    requires: [
      ActionRequirement.fileLoaded,
      ActionRequirement.annotationsPresent,
    ],
  ),

  // ── Annotation authoring and visibility ─────────────────────────────
  //
  // Three actions, three different visibility rules, and the differences are
  // the point.
  //
  // `addAnnotationAtCursor` needs a cursor and a single selected row, because
  // "at the cursor, on that signal" has no answer otherwise. It is *enabled*
  // on those, not hidden without them: a user hunting for how to add a note
  // must find the row and learn what it wants, which is the discoverability
  // failure this whole group exists to fix.
  ShortcutAction.addAnnotationAtCursor => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [
      ActionRequirement.fileLoaded,
      ActionRequirement.cursorPresent,
      ActionRequirement.hasSelection,
    ],
  ),

  // Enabled on a loaded file rather than gated on "a range exists", because
  // the two sources (drag selection, two cursors) are both invisible to
  // `ActionContext` and a greyed row would leave the user guessing which one
  // it wanted. The handler names the missing half instead.
  ShortcutAction.annotateSelectedRange => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [ActionRequirement.fileLoaded],
  ),

  // Hiding notes is meaningless without notes, so this one follows the
  // walkthrough's structural-hide rule.
  ShortcutAction.toggleAnnotationsVisible => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    isVisible: _hasAnnotations,
    requires: [
      ActionRequirement.fileLoaded,
      ActionRequirement.annotationsPresent,
    ],
  ),

  // The panel toggle deliberately does NOT require annotations. Opening an
  // empty Annotations panel is its most valuable use: the empty state is the
  // only place in the app that names the Option-click gesture, and gating this
  // on `annotationsPresent` is exactly the mistake that made that text
  // unreachable in the first place.
  ShortcutAction.toggleAnnotationsPanel => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [ActionRequirement.fileLoaded],
  ),

  // ── Everywhere, requires a loaded file ──────────────────────────────
  ShortcutAction.closeFile ||
  ShortcutAction.exportWaveform ||
  ShortcutAction.fitAll ||
  ShortcutAction.zoomToSelection ||
  ShortcutAction.addDecoder ||
  ShortcutAction.toggleTransactionTable ||
  ShortcutAction.toggleStagePanel => const ActionDescriptor(
    surfaces: _everywhere,
    requires: [ActionRequirement.fileLoaded],
  ),

  // ── Zoom In / Zoom Out — everywhere, but only while the zoom can move ─
  // The most zoomed-out state is fit-all and the most zoomed-in is one
  // simulation tick across the viewport; past either bound the mapper clamps
  // and the press changes nothing. A toolbar button that lights up, responds
  // and produces no visible effect is worse than a greyed one — it reads as a
  // broken viewer rather than a reached limit — so the bound is declared here
  // and every surface greys together. The keyboard guard turns the same
  // requirement into "the whole trace is already visible" rather than an inert
  // key press.
  ShortcutAction.zoomOut => const ActionDescriptor(
    surfaces: _everywhere,
    requires: [ActionRequirement.fileLoaded, ActionRequirement.canZoomOut],
  ),
  ShortcutAction.zoomIn => const ActionDescriptor(
    surfaces: _everywhere,
    requires: [ActionRequirement.fileLoaded, ActionRequirement.canZoomIn],
  ),

  // ── Stop Streaming — everywhere, but only while a stream is live ────
  // The one action gated by `isVisible` rather than `requires` alone: a
  // permanently-greyed Stop Streaming row is menu noise in the majority of
  // sessions that never stream, and the toolbar has always shown the button
  // conditionally. `requires` still names the precondition so the keyboard
  // guard can explain itself if a binding is ever assigned to it.
  ShortcutAction.stopStreaming => const ActionDescriptor(
    surfaces: _everywhere,
    isVisible: _streaming,
    requires: [ActionRequirement.streamingActive],
  ),

  // ── Everywhere, requires a file AND a cursor ────────────────────────
  // Transition navigation steps the primary cursor to the next/previous edge
  // relative to its current position, so a cursor must exist to anchor the
  // step (the t=0 fallback was removed with the strict-cursor gate).
  ShortcutAction.prevTransition ||
  ShortcutAction.nextTransition => const ActionDescriptor(
    surfaces: _everywhere,
    requires: [ActionRequirement.fileLoaded, ActionRequirement.cursorPresent],
  ),

  // ── Browsable (menu + overflow + palette), always enabled ───────────
  ShortcutAction.quit ||
  ShortcutAction.openAbout ||
  ShortcutAction.issueReporter ||
  ShortcutAction.toggleTheme ||
  ShortcutAction.importGtkwSession ||
  ShortcutAction.toggleSignalTree ||
  ShortcutAction.toggleValueColumn ||
  ShortcutAction.copyDiagnosticsReport ||
  ShortcutAction.loadCocotbLog ||
  ShortcutAction.toggleCocotbLogPanel ||
  ShortcutAction.resetWorkspace ||
  ShortcutAction.openWorkspace ||
  ShortcutAction.closeTab => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
  ),

  // ── Browsable, always enabled, not in the browser ───────────────────
  // Each one writes a file to a path the user picks and then works with that
  // path — a workspace or session document, or a VCD it opens. A browser has
  // no save dialog that hands a path back.
  ShortcutAction.generateTestVcd ||
  ShortcutAction.newWorkspace ||
  ShortcutAction.saveWorkspaceAs ||
  ShortcutAction.exportTabAsSession => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    isVisible: _notWeb,
  ),

  // ── Browsable, requires a loaded file ───────────────────────────────
  ShortcutAction.compareWaveforms ||
  ShortcutAction.analyzeSwitchingActivity ||
  ShortcutAction.patternSearch ||
  ShortcutAction.loadRtlStemsFile => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [ActionRequirement.fileLoaded],
  ),

  // ── Browsable, requires a file AND a cursor ─────────────────────────
  // Per the strict-cursor product decision: Jump to Start/End scroll the
  // viewport to the trace bounds, Set Marker anchors at the cursor, and Clear
  // Cursors is meaningful only with a cursor present — all greyed out until a
  // primary cursor exists.
  ShortcutAction.jumpToStart ||
  ShortcutAction.jumpToEnd ||
  ShortcutAction.setMarker ||
  ShortcutAction.clearCursors => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [ActionRequirement.fileLoaded, ActionRequirement.cursorPresent],
  ),

  // ── Browsable, requires a file AND at least one named marker ────────
  // Jump to / Remove Marker target an existing marker, so they grey out when
  // no marker (a–z) has been set — a cursor is NOT required for either.
  ShortcutAction.jumpToMarker ||
  ShortcutAction.removeMarker => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [ActionRequirement.fileLoaded, ActionRequirement.markersPresent],
  ),

  // ── Browsable, requires a file AND an active diff ───────────────────
  // Divergence navigation steps through the comparison result, so it greys out
  // when no second (comparison) file is loaded.
  ShortcutAction.nextDivergence ||
  ShortcutAction.prevDivergence => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [ActionRequirement.fileLoaded, ActionRequirement.diffActive],
  ),

  // ── Browsable, requires a file AND at least one pattern match ───────
  // Next/Previous Pattern Match step through search results, so they grey out
  // until a pattern search has produced a match.
  ShortcutAction.nextPatternMatch ||
  ShortcutAction.prevPatternMatch => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [
      ActionRequirement.fileLoaded,
      ActionRequirement.patternMatchesPresent,
    ],
  ),

  // ── Clear Cocotb Log — browsable, enabled only with a log loaded ────
  ShortcutAction.clearCocotbLog => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [ActionRequirement.cocotbLogLoaded],
  ),

  // ── Stage edit undo/redo — browsable, enabled only while Stage is open ─
  // Stage history is editable only from the Stage panel, so undo/redo greys
  // out whenever the Stage panel is hidden.
  ShortcutAction.stageUndo ||
  ShortcutAction.stageRedo => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [ActionRequirement.stageViewVisible],
  ),

  // ── Clear Signal Selection — browsable, enabled only with a selection ─
  // Escape clears the selection via the viewer's global key handler; the
  // action stays reachable from the menu / overflow / palette and greys out
  // when nothing is selected.
  ShortcutAction.clearSignalSelection => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [ActionRequirement.hasSelection],
  ),

  // ── Clear Canvas — browsable, enabled while the canvas has rows ─────
  // Greyed rather than hidden on an empty canvas: someone looking for how to
  // start over should find the command and see why it is resting.
  ShortcutAction.clearCanvas => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [
      ActionRequirement.fileLoaded,
      ActionRequirement.signalsDisplayed,
    ],
  ),

  // ── Remove Selected Signals — browsable, enabled with a selection ───
  // The Signals list's Delete / Backspace keys are the fast route; this is
  // the one a keyboard or screen-reader user finds by name.
  ShortcutAction.removeSelectedSignals => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [
      ActionRequirement.fileLoaded,
      ActionRequirement.hasSelection,
    ],
  ),

  // ── Command palette opener — menu + overflow only ──────────────────
  // Self-referential in the palette itself (you can't open the palette
  // from the palette), so it is excluded from the palette surface — but it
  // MUST stay reachable from the menu bar / overflow menu, otherwise
  // unbinding its keyboard shortcut (or losing it to a conflict) would make
  // the command palette permanently inaccessible with no recovery path
  // (issue #38).
  ShortcutAction.openCommandPalette => const ActionDescriptor(
    surfaces: _menuOverflow,
  ),

  // ── Keyboard-only / context-menu-only — hidden from every surface ───
  // WASD + arrow navigation, the per-row setFormat* family (no
  // signal-selection context in a global surface), and the tab cycle /
  // jump shortcuts.
  ShortcutAction.waveformZoomIn ||
  ShortcutAction.waveformZoomOut ||
  ShortcutAction.panLeft ||
  ShortcutAction.panRight ||
  ShortcutAction.panLeftSmall ||
  ShortcutAction.panRightSmall ||
  ShortcutAction.clearSecondaryCursor ||
  ShortcutAction.setFormatBinary ||
  ShortcutAction.setFormatHexadecimal ||
  ShortcutAction.setFormatOctal ||
  ShortcutAction.setFormatUnsignedDecimal ||
  ShortcutAction.setFormatSignedDecimal ||
  ShortcutAction.setFormatAscii ||
  ShortcutAction.setFormatIeee754Single ||
  ShortcutAction.setFormatIeee754Double ||
  ShortcutAction.setFormatFixedPointQ ||
  ShortcutAction.setFormatSignedMagnitude ||
  ShortcutAction.setFormatGrayCode ||
  ShortcutAction.setFormatNamedEnum ||
  ShortcutAction.jumpToTab1 ||
  ShortcutAction.jumpToTab2 ||
  ShortcutAction.jumpToTab3 ||
  ShortcutAction.jumpToTab4 ||
  ShortcutAction.jumpToTab5 ||
  ShortcutAction.jumpToTab6 ||
  ShortcutAction.jumpToTab7 ||
  ShortcutAction.jumpToTab8 ||
  ShortcutAction.jumpToTab9 => const ActionDescriptor(),

  // ── Tab navigation — browsable, needs somewhere to navigate ─────────
  // Next/Previous Tab join the View menu's tab group so tab switching is
  // discoverable without knowing the chord, matching the other three suite
  // products. The direct jump-to-tab-N actions stay accelerator-only above:
  // nine near-identical menu rows would bury the group they sit in.
  ShortcutAction.nextTab ||
  ShortcutAction.previousTab => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    isVisible: _tabletOrDesktop,
    requires: [ActionRequirement.fileLoaded],
  ),

  // ── Diagnostics surfaces (tablet + desktop only) ────────────────────
  // App Diagnostics declares the toolbar surface: the debug-build "Developer
  // Tools" button used to reach `AppDiagnosticsDialog.open` through its own
  // private callback, so the same dialog had two entry points and one of them
  // was invisible to the palette, the menu bar, and the keymap editor. The
  // button now dispatches this action like every other.
  ShortcutAction.openAppDiagnostics => const ActionDescriptor(
    surfaces: _everywhere,
    isVisible: _tabletOrDesktop,
    requires: [ActionRequirement.diagnosticsEnabled],
  ),
  ShortcutAction.openTabDiagnostics => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    isVisible: _tabletOrDesktop,
    requires: [
      ActionRequirement.fileLoaded,
      ActionRequirement.diagnosticsEnabled,
    ],
  ),
  // Pane Render Stats has no per-pane anchor in the menu/overflow, so it is
  // a command-palette-only entry point.
  ShortcutAction.openPaneRenderStats => const ActionDescriptor(
    surfaces: _paletteOnly,
    isVisible: _tabletOrDesktop,
    requires: [ActionRequirement.diagnosticsEnabled],
  ),

  // ── CXP cross-probe panel — hidden on phone ─────────────────────────
  // Declares the toolbar surface: it has had a toolbar button since the D4
  // suite pass, but the descriptor said menu/overflow/palette only. The
  // conformance test checked "every toolbar-surface action has a button", not
  // the reverse, so the mismatch passed silently.
  ShortcutAction.openCrossProbePanel => const ActionDescriptor(
    surfaces: _everywhere,
    isVisible: _tabletOrDesktop,
  ),

  // ── Stage Playback — tablet + desktop, Stage-gated ─────
  // Discoverable everywhere (toolbar + menu + overflow + palette) but
  // enabled only when a file is loaded AND the Stage panel that hosts the
  // transport is visible — so the action greys out (and the Space key is
  // inert) whenever Stage is hidden.
  // Off the toolbar: the visible play/pause lives in the Stage dock tab's
  // strip actions (the one transport surface); menus/palette keep the
  // action so Space stays discoverable.
  ShortcutAction.togglePlayback => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    isVisible: _tabletOrDesktop,
    requires: [
      ActionRequirement.fileLoaded,
      ActionRequirement.stageViewVisible,
    ],
  ),

  // ── Live statistics strip — desktop only ────────────────────────────
  ShortcutAction.toggleStatisticsStrip => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    isVisible: _desktopOnly,
  ),

  // ── RTL source-annotation panel — desktop only, requires a file ─────
  ShortcutAction.toggleRtlSourcePanel => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    isVisible: _desktopOnly,
    requires: [ActionRequirement.fileLoaded],
  ),

  // ── Generate / import RTL stems — desktop only; independent of a loaded
  //    file (you produce the stems from an HDL source tree or a Verilator
  //    AST dump, then load the result).
  //    A desktop-sized browser window is a desktop device class, so the
  //    browser is excluded explicitly: both save their result to a picked path.
  ShortcutAction.generateRtlStems ||
  ShortcutAction.importVerilatorAst => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    isVisible: _desktopApp,
  ),

  // ── Check for Updates — browsable, openCore (NO tier badge) ─────────
  // Manual update check. Always enabled; the activation handler runs
  // updateStatusProvider.checkNow() and surfaces the banner / "already current"
  // confirmation / non-fatal error toast. requiredTier stays openCore (the
  // default) so no tier badge renders on any surface.
  ShortcutAction.checkForUpdates => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
  ),

  // ── Documentation — browsable, openCore, always enabled ─────────────
  // Opens docs.wavecrux.app in the user's browser. Workspace-independent, so
  // it never greys out; the first item in Help across all four products.
  ShortcutAction.openDocumentation => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
  ),

  // ── Debug Advisor / SVA panel (Pro tier) ────────────────────────────
  ShortcutAction.debugAdvisorTogglePanel ||
  ShortcutAction.toggleSvaPanel ||
  ShortcutAction.loadSvaResults ||
  ShortcutAction.clearSvaResults => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requiredTier: LicenseTier.pro,
  ),

  // ── Explain Selection (Experimental AI, open-core) ──────────────────
  // requiredTier stays openCore (no tier badge — it carries the
  // Experimental chip instead). Hidden entirely unless experimental AI is
  // enabled; enabled only with a configured model and a non-empty
  // selection. The "AND a configured model AND a non-empty selection" gate
  // is the enablement predicate, so in the palette (which omits disabled
  // actions) it appears only when usable.
  ShortcutAction.aiExplainSelection => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    isVisible: _aiAvailable,
    requires: [
      ActionRequirement.fileLoaded,
      ActionRequirement.hasSelection,
      ActionRequirement.aiModelConfigured,
    ],
  ),

  // ── AI Waveform Assistant panel (Experimental AI, Pro tier) ─────────
  // requiredTier: pro → surfaces render the PRO badge automatically (the
  // panel header additionally shows the Experimental chip). Hidden unless
  // experimental AI is enabled. No enablement predicate: the panel can be
  // opened to show its model-config / tier-gated state, and activation is
  // routed through FeatureGate by the Pro toggler.
  ShortcutAction.aiAdvisorTogglePanel => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requiredTier: LicenseTier.pro,
    isVisible: _aiAvailable,
  ),

  // ── PCAP→VCD conversion (Enterprise tier) ───────────────────────────
  ShortcutAction.convertPcapToVcd => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requiredTier: LicenseTier.enterprise,
  ),

  // ── Collaborative viewing — gated on session state ───────────────────
  // Hosting a session (Share Session) is the only tier-gated step, and it is
  // the only action here that carries a tier badge. Joining is free in every
  // edition, so everything a guest does once inside (leave, follow, point,
  // ask to present) carries no badge either. Join is visible only where a
  // real collaboration service is bound and the app is a desktop build: the
  // protocol is compiled out of the open-source build, and the web and mobile
  // builds do not offer it.
  ShortcutAction.shareSession => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requiredTier: LicenseTier.enterprise,
    requires: [ActionRequirement.notInSession],
  ),
  ShortcutAction.joinSession => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    isVisible: _collaborationJoinable,
    requires: [ActionRequirement.notInSession],
  ),
  ShortcutAction.stopSharing => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requiredTier: LicenseTier.enterprise,
    requires: [ActionRequirement.isHost],
  ),
  ShortcutAction.leaveSession => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [ActionRequirement.isParticipant],
  ),
  ShortcutAction.exportSessionRecording ||
  ShortcutAction.exportReviewMinutes => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requiredTier: LicenseTier.enterprise,
    requires: [ActionRequirement.recordingAvailable],
  ),

  // ── Presenter Mode — gated on session state, free for every participant ─
  // Handing off, resuming follow, and dropping pointers are meaningful only
  // inside a live session. "Request control" additionally requires being a
  // non-host participant (the host already drives by default), so it reuses
  // the participant predicate. None of them carries a tier: a guest without a
  // licence follows, points and asks to present like anyone else.
  ShortcutAction.handoffPresenter ||
  ShortcutAction.resumeFollowing ||
  ShortcutAction.dropPing ||
  ShortcutAction.dropPin => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [ActionRequirement.inSession],
  ),
  ShortcutAction.requestPresenter => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    requires: [ActionRequirement.isParticipant],
  ),

  // ── Pane management (tablet + desktop only) ─────────────────────────
  // Split additionally needs a window the pane host will split in: below
  // 1000 dp a tablet shows only the active pane.
  ShortcutAction.splitPaneRight => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    isVisible: _splitPaneAllowed,
    requires: [ActionRequirement.singlePane],
  ),
  ShortcutAction.closePane ||
  ShortcutAction.focusOtherPane => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    isVisible: _tabletOrDesktop,
    requires: [ActionRequirement.multiPane],
  ),
  // Move-tab-to-other-pane also has a gesture equivalent (drag-tab-to-pane),
  // but it sits in the View menu's pane group alongside Split / Close / Focus
  // Other Pane — the other three suite products all list it there, and a
  // pane command reachable only from the palette is exactly the kind of
  // cross-product asymmetry the suite's shared menu layout exists to prevent.
  ShortcutAction.moveTabToOtherPane => const ActionDescriptor(
    surfaces: _menuOverflowPalette,
    isVisible: _tabletOrDesktop,
    requires: [ActionRequirement.multiPane],
  ),
};

// ── derived selectors (the API every surface consumes) ───────────────────────

/// Whether [action] should structurally appear in [surface] under [context]
/// (its descriptor lists the surface and its visibility predicate passes).
/// Independent of enablement — a visible action may still be greyed out.
///
/// One rule applies across the whole table before any per-action predicate:
/// when the build cannot execute tier-gated actions
/// ([ActionContext.tierGatedActionsAvailable] is false — Open Core on a mobile
/// host), every PRO/ENT action is hidden outright. Open Core's handlers for
/// those actions are empty closures, so on an app store they are not an upsell
/// but a feature that visibly does nothing; Apple rejected WaveCrux 0.1.0 (2)
/// under Guideline 2.2 for exactly that.
///
/// Deliberately applied here rather than as a predicate on each PRO/ENT
/// descriptor: this way a *future* Pro or Enterprise action inherits the
/// suppression by setting `requiredTier` alone, and cannot ship a dead mobile
/// menu row by forgetting to add a gate.
bool isActionVisibleIn(
  ShortcutAction action,
  ActionSurface surface,
  ActionContext context,
) {
  final d = descriptorFor(action);
  if (!context.tierGatedActionsAvailable &&
      d.requiredTier != LicenseTier.openCore) {
    return false;
  }
  return d.surfaces.contains(surface) && d.isVisible(context);
}

/// Whether [action] is currently enabled under [context].
bool isActionEnabled(ShortcutAction action, ActionContext context) =>
    descriptorFor(action).isEnabled(context);

/// The first requirement of [action] that [context] does not satisfy, or
/// `null` when the action is enabled.
///
/// This is what turns the keyboard's descriptor-parity guard from a silent
/// early-return into an explanation: the viewer resolves the unmet requirement
/// and shows its localized hint (`ActionRequirementHint.hint`) instead of
/// swallowing the key press. Menu / overflow / toolbar surfaces do not need it
/// — a greyed item next to its label is already self-explanatory — but the
/// keyboard has no such visual anchor.
ActionRequirement? unmetActionRequirement(
  ShortcutAction action,
  ActionContext context,
) => descriptorFor(action).unmetRequirement(context);

/// Actions to render in a browsable [surface] ([ActionSurface.menu] or
/// [ActionSurface.overflow]), grouped by [ActionCategory] in enum declaration
/// order. Every category key is present. Disabled actions are *included* — the
/// menu / overflow grey them out; only structurally-hidden actions are omitted.
Map<ActionCategory, List<ShortcutAction>> groupedActionsFor(
  ActionSurface surface,
  ActionContext context,
) {
  final result = {
    for (final category in ActionCategory.values) category: <ShortcutAction>[],
  };
  for (final action in ShortcutAction.values) {
    if (isActionVisibleIn(action, surface, context)) {
      result[action.category]!.add(action);
    }
  }
  return result;
}

/// Actions to list in the command palette under [context] — visible **and**
/// enabled, in enum declaration order. The palette has no greyed state, so a
/// disabled action is omitted rather than shown inert.
List<ShortcutAction> paletteActionsFor(ActionContext context) => ShortcutAction
    .values
    .where(
      (a) =>
          isActionVisibleIn(a, ActionSurface.palette, context) &&
          isActionEnabled(a, context),
    )
    .toList();

// ── surface sets ─────────────────────────────────────────────────────────────

const Set<ActionSurface> _everywhere = {
  ActionSurface.toolbar,
  ActionSurface.menu,
  ActionSurface.overflow,
  ActionSurface.palette,
};

const Set<ActionSurface> _menuOverflowPalette = {
  ActionSurface.menu,
  ActionSurface.overflow,
  ActionSurface.palette,
};

const Set<ActionSurface> _paletteOnly = {ActionSurface.palette};

const Set<ActionSurface> _menuOverflow = {
  ActionSurface.menu,
  ActionSurface.overflow,
};

// ── enablement / visibility predicates (top-level for const tear-off) ─────────

bool _tabletOrDesktop(ActionContext c) => !c.deviceClass.isPhoneClass;
bool _desktopOnly(ActionContext c) => c.deviceClass == DeviceClass.desktop;
bool _desktopApp(ActionContext c) => _desktopOnly(c) && !c.isWeb;
bool _notWeb(ActionContext c) => !c.isWeb;
bool _collaborationJoinable(ActionContext c) => c.collaborationAvailable;
bool _splitPaneAllowed(ActionContext c) =>
    _tabletOrDesktop(c) && c.splitPaneAllowed;
bool _aiAvailable(ActionContext c) => c.aiAvailable;
bool _streaming(ActionContext c) => c.streamingActive;
bool _hasAnnotations(ActionContext c) => c.annotationsPresent;
