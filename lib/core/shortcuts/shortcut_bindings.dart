// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';

/// The cross-suite [KeymapCodec] configured for WaveCrux's action set and
/// schema id. Used by the persistence store and the keymap Export/Import flow
/// so they share one source of truth for serialization.
final KeymapCodec<ShortcutAction> waveCruxKeymapCodec = KeymapCodec(
  actions: ShortcutAction.values,
  schema: 'wavecrux.keymap',
);

/// Returns platform-aware default key bindings for every [ShortcutAction].
///
/// Uses Cmd (meta) on macOS and iPadOS (where the Magic Keyboard's Command
/// key is the natural modifier) and Ctrl on Linux, Windows, web, and Android.
/// WASD/QE navigation keys have no modifier (NovyWave convention).
/// bare-Q → prevTransition; Cmd/Ctrl+Q → quit (no conflict).
Map<ShortcutAction, ShortcutActivator> defaultBindings() {
  // Treat iOS like macOS for keyboard shortcuts: an iPad with a Magic
  // Keyboard sends Cmd+Shift+P just like a Mac, and the previous binding
  // (which used Ctrl on every non-macOS target) silently failed because
  // iPadOS does not have a Ctrl key on most keyboards.
  final isMac =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  return {
    ShortcutAction.openFile: SingleActivator(
      LogicalKeyboardKey.keyO,
      meta: isMac,
      control: !isMac,
    ),
    // closeFile is never Cmd/Ctrl+W: that belongs to closeTab (universal
    // "close" convention); binding both made closeFile's accelerator
    // permanently dead (closeTab always won the chord) and required a
    // kIntentionalShadows entry just to suppress the resulting conflict
    // warning. (issue #37)
    //
    // On Windows and Linux it is Ctrl+F4, the platform's close-document key,
    // which screen-reader users reach for first and which nothing else in
    // the keymap uses. macOS has no such convention (Cmd+W is the document
    // close there), so it stays unbound on Apple platforms and reachable via
    // the toolbar, menu bar, command palette, or a user-assigned chord.
    if (!isMac)
      ShortcutAction.closeFile: const SingleActivator(
        LogicalKeyboardKey.f4,
        control: true,
      ),
    ShortcutAction.quit: SingleActivator(
      LogicalKeyboardKey.keyQ,
      meta: isMac,
      control: !isMac,
    ),
    // ── zoom (modifier + key) ──────────────────────────────────────────────
    ShortcutAction.zoomIn: SingleActivator(
      LogicalKeyboardKey.equal,
      meta: isMac,
      control: !isMac,
    ),
    ShortcutAction.zoomOut: SingleActivator(
      LogicalKeyboardKey.minus,
      meta: isMac,
      control: !isMac,
    ),
    ShortcutAction.fitAll: SingleActivator(
      LogicalKeyboardKey.digit0,
      meta: isMac,
      control: !isMac,
    ),
    // ── WASD zoom (bare keys — NovyWave convention) ────────────────────────
    ShortcutAction.waveformZoomIn: const SingleActivator(
      LogicalKeyboardKey.keyW,
    ),
    ShortcutAction.waveformZoomOut: const SingleActivator(
      LogicalKeyboardKey.keyS,
    ),
    ShortcutAction.zoomToSelection: const SingleActivator(
      LogicalKeyboardKey.keyZ,
    ),
    // ── pan (WASD + arrows) ───────────────────────────────────────────────
    ShortcutAction.panLeft: const SingleActivator(LogicalKeyboardKey.keyA),
    ShortcutAction.panRight: const SingleActivator(LogicalKeyboardKey.keyD),
    ShortcutAction.panLeftSmall: const SingleActivator(
      LogicalKeyboardKey.arrowLeft,
    ),
    ShortcutAction.panRightSmall: const SingleActivator(
      LogicalKeyboardKey.arrowRight,
    ),
    // ── jump ──────────────────────────────────────────────────────────────
    ShortcutAction.jumpToStart: const SingleActivator(LogicalKeyboardKey.home),
    ShortcutAction.jumpToEnd: const SingleActivator(LogicalKeyboardKey.end),
    // ── cursor / transition navigation ────────────────────────────────────
    ShortcutAction.nextTransition: const SingleActivator(
      LogicalKeyboardKey.keyE,
    ),
    ShortcutAction.prevTransition: const SingleActivator(
      LogicalKeyboardKey.keyQ,
    ),
    // ── annotation walkthrough ────────────────────────────────────────────
    // `]` / `[` — the bracket keys, which no other WaveCrux binding claims and
    // which read as "next / previous item" in every editor a user arrives
    // from. Play has no default chord: starting an automatic tour is a
    // deliberate act, not something worth a keyboard slot.
    ShortcutAction.annotationWalkthroughNext: const SingleActivator(
      LogicalKeyboardKey.bracketRight,
    ),
    ShortcutAction.annotationWalkthroughPrevious: const SingleActivator(
      LogicalKeyboardKey.bracketLeft,
    ),
    // ── named markers (two-key chords) ────────────────────────────────────
    // `M` arms "set marker", `⇧M` arms "jump to marker"; the next a–z key
    // completes the chord (handled by the viewer's marker chord controller,
    // not a SingleActivator, because Flutter activators cannot express a
    // two-key sequence). Bare `M` / `⇧M` are free: Cmd/Ctrl+Shift+M
    // (openAppDiagnostics) carries a primary modifier and does not collide.
    // The command palette advertises these as "Set Marker (M + a–z)" and
    // "Jump to Marker (⇧M + a–z)" — these bindings make that promise real.
    ShortcutAction.setMarker: const SingleActivator(LogicalKeyboardKey.keyM),
    ShortcutAction.jumpToMarker: const SingleActivator(
      LogicalKeyboardKey.keyM,
      shift: true,
    ),
    ShortcutAction.clearCursors: const SingleActivator(
      LogicalKeyboardKey.escape,
    ),
    ShortcutAction.clearSecondaryCursor: const SingleActivator(
      LogicalKeyboardKey.escape,
      shift: true,
    ),
    // ── other ─────────────────────────────────────────────────────────────
    // Cmd/Ctrl+Shift+K — moved off Cmd/Ctrl+Shift+T, which collided with
    // [toggleTransactionTable] (the frequently-toggled bottom dock keeps the
    // ⇧T slot; the rarely-used theme switch takes the free ⇧K slot). The
    // collision left one of the two unreachable by keyboard — see the
    // "no unintended collisions" guard in shortcut_bindings_test.dart.
    ShortcutAction.toggleTheme: SingleActivator(
      LogicalKeyboardKey.keyK,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    ShortcutAction.saveSession: SingleActivator(
      LogicalKeyboardKey.keyS,
      meta: isMac,
      control: !isMac,
    ),
    ShortcutAction.saveSessionAs: SingleActivator(
      LogicalKeyboardKey.keyS,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    ShortcutAction.openSearch: SingleActivator(
      LogicalKeyboardKey.keyF,
      meta: isMac,
      control: !isMac,
    ),
    ShortcutAction.openCommandPalette: SingleActivator(
      LogicalKeyboardKey.keyP,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    ShortcutAction.importGtkwSession: SingleActivator(
      LogicalKeyboardKey.keyI,
      meta: isMac,
      control: !isMac,
    ),
    ShortcutAction.exportWaveform: SingleActivator(
      LogicalKeyboardKey.keyE,
      meta: isMac,
      control: !isMac,
    ),
    ShortcutAction.openSettings: SingleActivator(
      LogicalKeyboardKey.comma,
      meta: isMac,
      control: !isMac,
    ),
    // F1 = About, the suite-wide convention (NetCrux and SimCrux already
    // bind it, and one binding holds in all four apps). F1 was previously unclaimed in
    // WaveCrux — openDocumentation deliberately leaves it to About.
    ShortcutAction.openAbout: const SingleActivator(LogicalKeyboardKey.f1),
    ShortcutAction.addDecoder: SingleActivator(
      LogicalKeyboardKey.keyD,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // Cmd/Ctrl+Shift+T — the transaction-table (bottom dock) toggle owns the
    // ⇧T slot; [toggleTheme] moved to ⇧K to resolve the former collision.
    ShortcutAction.toggleTransactionTable: SingleActivator(
      LogicalKeyboardKey.keyT,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    ShortcutAction.toggleStagePanel: SingleActivator(
      LogicalKeyboardKey.keyG,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // Stage Playback play/pause — bare Space, the universal
    // media-transport key. No modifier and no collision: Space is otherwise
    // unbound across the default keymap. The viewer dispatch no-ops outside
    // Stage, but that check runs after the key is consumed, so on its own it
    // would still take Space from a focused button. `ShortcutManagerWidget`
    // therefore lets a bare Space (and Enter) through to any focused control
    // that accepts activation; Space reaches playback only from surfaces that
    // do not, such as the waveform canvas.
    ShortcutAction.togglePlayback: const SingleActivator(
      LogicalKeyboardKey.space,
    ),
    ShortcutAction.toggleStatisticsStrip: SingleActivator(
      LogicalKeyboardKey.keyY,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // Show/hide annotations. `N` for notes — Cmd/Ctrl+Shift+A is already
    // switching-activity analysis, and Shift+A belongs to authoring one.
    ShortcutAction.toggleAnnotationsVisible: SingleActivator(
      LogicalKeyboardKey.keyN,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // Add an annotation at the cursor. Shift+A as specified in the 5.9.1
    // design; a focused text field consumes the key first, so typing an
    // upper-case A into a note never authors a second one.
    ShortcutAction.addAnnotationAtCursor: const SingleActivator(
      LogicalKeyboardKey.keyA,
      shift: true,
    ),
    ShortcutAction.analyzeSwitchingActivity: SingleActivator(
      LogicalKeyboardKey.keyA,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    ShortcutAction.compareWaveforms: SingleActivator(
      LogicalKeyboardKey.keyC,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    ShortcutAction.nextDivergence: const SingleActivator(LogicalKeyboardKey.f7),
    ShortcutAction.prevDivergence: const SingleActivator(
      LogicalKeyboardKey.f7,
      shift: true,
    ),
    ShortcutAction.patternSearch: SingleActivator(
      LogicalKeyboardKey.keyF,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    ShortcutAction.nextPatternMatch: const SingleActivator(
      LogicalKeyboardKey.f3,
    ),
    ShortcutAction.prevPatternMatch: const SingleActivator(
      LogicalKeyboardKey.f3,
      shift: true,
    ),
    // App Diagnostics dialog. Cmd/Ctrl+Shift+M — "Memory" — the
    // dialog's primary section. Previously Cmd/Ctrl+Shift+D drove the legacy
    // single-dialog `openDiagnostics`; that binding was retired alongside the
    // dialog so the slot is free for future use.
    ShortcutAction.openAppDiagnostics: SingleActivator(
      LogicalKeyboardKey.keyM,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // Tab Diagnostics drawer. Cmd/Ctrl+Shift+I — "Inspect tab".
    // Cmd/Ctrl+I (no shift) is bound to importGtkwSession; the shifted slot
    // was free.
    ShortcutAction.openTabDiagnostics: SingleActivator(
      LogicalKeyboardKey.keyI,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // Pane Render Stats popover is command-palette / icon-anchor
    // only — no default keyboard binding. The popover lives in a pane's tab
    // bar (`i`-icon) and any global shortcut would have to choose one pane
    // arbitrarily; instead we keep activation co-located with the data's
    // owner.
    // Generate Test VCD (moved out of the legacy diagnostics dialog).
    // Cmd/Ctrl+Alt+G ("Generate"). Cmd/Ctrl+Shift+G is taken by
    // [toggleStagePanel]; Alt+G avoids the conflict and reads as
    // "Generate". Discoverable via Tools menu and command palette
    // regardless.
    ShortcutAction.generateTestVcd: SingleActivator(
      LogicalKeyboardKey.keyG,
      meta: isMac,
      control: !isMac,
      alt: true,
    ),
    ShortcutAction.toggleRtlSourcePanel: SingleActivator(
      LogicalKeyboardKey.keyR,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // Cross-Probe panel — Cmd/Ctrl+Shift+X, the suite-wide default chord
    // (one shortcut in all four
    // Crux apps). The shifted X slot was previously unbound in WaveCrux, so
    // there is no collision; the action also stays reachable via the View
    // menu, overflow, and command palette.
    ShortcutAction.openCrossProbePanel: SingleActivator(
      LogicalKeyboardKey.keyX,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // ── stage workspace undo/redo ────────────────────────────────────────
    // Wired globally so Cmd/Ctrl+Z works regardless of which panel has
    // focus. The notifier's `undo` / `redo` are no-ops when the stack
    // is empty — so this binding does nothing unless there's actually
    // a Stage edit to revert. Text fields handle their own Cmd+Z at
    // the gesture-arena level before global shortcuts fire.
    ShortcutAction.stageUndo: SingleActivator(
      LogicalKeyboardKey.keyZ,
      meta: isMac,
      control: !isMac,
    ),
    ShortcutAction.stageRedo: SingleActivator(
      LogicalKeyboardKey.keyZ,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // Debug Advisor toggle. Cmd/Ctrl+Shift+B ("deBug") — Cmd/Ctrl+Shift+D
    // is already bound to addDecoder, so the panel uses B instead. Pro
    // features remain discoverable through the menu bar / overflow menu /
    // command palette regardless of binding choice.
    ShortcutAction.debugAdvisorTogglePanel: SingleActivator(
      LogicalKeyboardKey.keyB,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // SystemVerilog assertion panel toggle. Cmd/Ctrl+Shift+V
    // ("Verification") — Cmd/Ctrl+Shift+A (the originally proposed
    // binding) is already bound to [analyzeSwitchingActivity], so the
    // panel uses V instead. The Pro overlay supplies the toggle body
    // via `svaPanelTogglerProvider`; the open-core default is a no-op
    // so the binding is harmless on Open-Core builds.
    ShortcutAction.toggleSvaPanel: SingleActivator(
      LogicalKeyboardKey.keyV,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // ── tab management ────────────────────────────────────────────────────
    // closeTab: Cmd/Ctrl+W — the sole owner of this chord (closeFile no
    // longer binds it; see the note above).
    ShortcutAction.closeTab: SingleActivator(
      LogicalKeyboardKey.keyW,
      meta: isMac,
      control: !isMac,
    ),
    ShortcutAction.nextTab: const SingleActivator(
      LogicalKeyboardKey.tab,
      control: true,
    ),
    ShortcutAction.previousTab: const SingleActivator(
      LogicalKeyboardKey.tab,
      control: true,
      shift: true,
    ),
    // Cmd/Ctrl+1–9 jump to tab by index. No conflict — fitAll uses Cmd/Ctrl+0.
    ShortcutAction.jumpToTab1: SingleActivator(
      LogicalKeyboardKey.digit1,
      meta: isMac,
      control: !isMac,
    ),
    ShortcutAction.jumpToTab2: SingleActivator(
      LogicalKeyboardKey.digit2,
      meta: isMac,
      control: !isMac,
    ),
    ShortcutAction.jumpToTab3: SingleActivator(
      LogicalKeyboardKey.digit3,
      meta: isMac,
      control: !isMac,
    ),
    ShortcutAction.jumpToTab4: SingleActivator(
      LogicalKeyboardKey.digit4,
      meta: isMac,
      control: !isMac,
    ),
    ShortcutAction.jumpToTab5: SingleActivator(
      LogicalKeyboardKey.digit5,
      meta: isMac,
      control: !isMac,
    ),
    ShortcutAction.jumpToTab6: SingleActivator(
      LogicalKeyboardKey.digit6,
      meta: isMac,
      control: !isMac,
    ),
    ShortcutAction.jumpToTab7: SingleActivator(
      LogicalKeyboardKey.digit7,
      meta: isMac,
      control: !isMac,
    ),
    ShortcutAction.jumpToTab8: SingleActivator(
      LogicalKeyboardKey.digit8,
      meta: isMac,
      control: !isMac,
    ),
    ShortcutAction.jumpToTab9: SingleActivator(
      LogicalKeyboardKey.digit9,
      meta: isMac,
      control: !isMac,
    ),
    // ── pane management (split-pane) ───────────────────────────
    // splitPaneRight: Cmd/Ctrl+\ — matches the VSCode chord. No conflict
    // (backslash is otherwise unbound).
    ShortcutAction.splitPaneRight: SingleActivator(
      LogicalKeyboardKey.backslash,
      meta: isMac,
      control: !isMac,
    ),
    // closePane: Cmd/Ctrl+Shift+W — natural mnemonic ("close more than
    // just a tab"). Distinct from closeTab (Cmd/Ctrl+W) and closeFile
    // (Cmd/Ctrl+W, shadowed at the keyboard layer). The original intent
    // was the VSCode-style chord `Cmd+K W`, but Flutter's
    // [SingleActivator] cannot express chord activators; this is the
    // single-key fallback.
    ShortcutAction.closePane: SingleActivator(
      LogicalKeyboardKey.keyW,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // focusOtherPane, moveTabToOtherPane still have no default keyboard
    // binding — their natural chord activators (`Cmd+K →`, `Cmd+K
    // Shift+→`) are not representable by [SingleActivator] and no
    // obvious single-key slot exists. Both remain discoverable through
    // the menu bar, overflow action menu, and command palette.
  };
}

/// Actions whose keyboard activation is owned by the viewer's global
/// [HardwareKeyboard] handler ([ViewerScreen]'s `_onKeyEvent`) rather than the
/// focus-based [Shortcuts] layer.
///
/// These are the **bare-key** navigation and marker-chord shortcuts. They are
/// deliberately handled outside the focus chain for two reasons:
///
/// 1. **Focus independence.** Bare keys (WASD/QE pan-zoom, marker chords) used
///    to go dead the moment focus left the waveform body (onto toolbar/menu
///    chrome) — the focus `Shortcuts` widget only fires for a focused
///    descendant. The global handler fires regardless of focus.
/// 2. **Marker-chord exclusivity.** While a marker chord is armed (`M`/`⇧M`),
///    the completing key must set the marker even when that key is also a
///    navigation binding (e.g. `q`/`e`/`w`). A `HardwareKeyboard` handler
///    returning `true` does NOT suppress the focus `Shortcuts` dispatch, so if
///    these stayed in the `Shortcuts` map the completion key would *also* fire
///    its navigation action. Routing them through the single global handler —
///    which checks the armed chord first — guarantees one action per keystroke.
///
/// [ShortcutManagerWidget] excludes these from the focus `Shortcuts` map so they
/// never double-fire; their bindings remain in [defaultBindings] so the menu
/// bar / overflow / command palette still display the accelerators.
/// Scope note: this is intentionally limited to the **bare-letter** navigation
/// keys (WASD/QE/Z), the marker chords (M/⇧M) and the two Escape bindings. It
/// deliberately excludes the arrow-key pan (`panLeftSmall`/`panRightSmall`) and
/// Home/End jumps, which stay on the focus `Shortcuts` layer: those keys are
/// also used for widget focus traversal / list navigation, so claiming them
/// globally would hijack them outside the waveform. Letter keys carry that small
/// risk too, but are the keys the marker chord must win over (a–z) and the ones
/// users expect to drive the waveform from anywhere.
///
/// The Escape pair is here for the double-dispatch reason above rather than the
/// focus-independence one, and the symptom it fixes is worth stating because it
/// is not obvious from the mechanism. Both are cleared by step 2 of the viewer's
/// global handler, which runs *before* the focus layer and mutates the very
/// state the action's descriptor requires. Left in the `Shortcuts` map,
/// `clearCursors` was therefore dispatched a second time against a waveform that
/// no longer had a cursor, and `_handleShortcut`'s descriptor-parity guard
/// refused it and hinted "Place a cursor in the waveform to use this command" —
/// on every Escape that had just successfully cleared one.
const Set<ShortcutAction> kGlobalKeyHandledActions = {
  ShortcutAction.setMarker,
  ShortcutAction.jumpToMarker,
  ShortcutAction.waveformZoomIn,
  ShortcutAction.waveformZoomOut,
  ShortcutAction.zoomToSelection,
  ShortcutAction.panLeft,
  ShortcutAction.panRight,
  ShortcutAction.nextTransition,
  ShortcutAction.prevTransition,
  ShortcutAction.clearCursors,
  ShortcutAction.clearSecondaryCursor,
};

/// Resolves the [kGlobalKeyHandledActions] action whose [bindings] activator
/// matches the given key + modifier state, or null if none match.
///
/// Pure (no widget/HardwareKeyboard dependency) so the matching is unit-testable.
/// Pass the live [HardwareKeyboard] modifier flags from the caller. Modifier
/// flags must match exactly (so bare `A` = panLeft does not fire while Shift is
/// held), mirroring [SingleActivator] semantics.
ShortcutAction? globalKeyHandledActionFor(
  Map<ShortcutAction, ShortcutActivator> bindings, {
  required LogicalKeyboardKey logicalKey,
  required bool isControlPressed,
  required bool isShiftPressed,
  required bool isAltPressed,
  required bool isMetaPressed,
}) {
  for (final action in kGlobalKeyHandledActions) {
    final activator = bindings[action];
    if (activator is SingleActivator &&
        activator.trigger == logicalKey &&
        activator.control == isControlPressed &&
        activator.shift == isShiftPressed &&
        activator.alt == isAltPressed &&
        activator.meta == isMetaPressed) {
      return action;
    }
  }
  return null;
}
