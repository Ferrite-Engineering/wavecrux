// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/device_class.dart';

/// Immutable snapshot of the app state that decides whether each
/// [ShortcutAction] is visible and enabled in a given surface.
///
/// This is the single input to [ActionDescriptor.isVisible] /
/// [ActionDescriptor.isEnabled]. It is pure Dart (no Flutter imports) so the
/// descriptor table and its predicates are unit-testable without pumping a
/// widget. Each action-discovery surface (toolbar, menu bar, overflow menu,
/// command palette) builds one [ActionContext] from the Riverpod providers it
/// already watches and passes it to the descriptor.
///
/// Note: *whether a surface renders at all* (e.g. the native menu bar only
/// exists on a desktop OS) is a surface-level decision that stays in the
/// surface widget — it is deliberately not modeled here, which is per-action
/// state only.
@immutable
class ActionContext {
  const ActionContext({
    required this.fileLoaded,
    required this.deviceClass,
    this.diagnosticsEnabled = false,
    this.paneCount = 1,
    this.inSession = false,
    this.isHost = false,
    this.isRecording = false,
    this.stageViewVisible = false,
    this.crossProbeVisible = false,
    this.aiAvailable = false,
    this.aiModelConfigured = false,
    this.hasSelection = false,
    this.cursorPresent = false,
    this.markersPresent = false,
    this.annotationsPresent = false,
    this.signalsDisplayed = false,
    this.diffActive = false,
    this.cocotbLogLoaded = false,
    this.patternMatchesPresent = false,
    this.streamingActive = false,
    this.playbackActive = false,
    this.canZoomOut = true,
    this.canZoomIn = true,
    this.tierGatedActionsAvailable = true,
    this.isWeb = false,
    this.splitPaneAllowed = true,
  });

  /// Whether the active tab has a waveform file loaded.
  final bool fileLoaded;

  /// Logical device class derived from the display dimensions.
  final DeviceClass deviceClass;

  /// Whether the active tab's Stage panel is currently visible. Gates the
  /// `togglePlayback` action (Stage Playback) — playback is only meaningful
  /// while the Stage panel that hosts the transport is on screen.
  final bool stageViewVisible;

  /// Whether the active tab's shared cross-probe panel is currently visible.
  /// Drives the toolbar toggle button's filled/outlined state.
  final bool crossProbeVisible;

  /// Whether the diagnostics surfaces are enabled (always on in debug/profile,
  /// toggled via Settings > Advanced in release).
  final bool diagnosticsEnabled;

  /// Number of workspace panes (1 = single pane; ≥ 2 = split).
  final int paneCount;

  /// Whether a collaborative session is currently active.
  final bool inSession;

  /// Whether the local user is hosting the active collaborative session.
  final bool isHost;

  /// Whether the active collaborative session is being recorded.
  final bool isRecording;

  /// Whether experimental AI features are enabled for this build + user
  /// (`aiExperimentalEnabledProvider`). Gates the *visibility* of every AI
  /// action — when false the AI surfaces are hidden entirely.
  final bool aiAvailable;

  /// Whether a usable AI model is configured (`AiModelClient.isConfigured`).
  /// Open Core's no-op client reports `false`; a configured BYO-key client
  /// reports `true`. Gates the *enablement* of AI actions.
  final bool aiModelConfigured;

  /// Whether the active tab has at least one signal selected. Gates AI actions
  /// (e.g. Explain Selection) that operate on the current selection.
  final bool hasSelection;

  /// Whether the active tab has a primary cursor placed. Gates actions that
  /// operate relative to the cursor — Set Marker (anchors there), the
  /// transition navigation (next/prev edge), Jump to Start/End (cursor-relative
  /// navigation), and Clear Cursors.
  final bool cursorPresent;

  /// Whether the active tab has at least one named marker (a–z) set. Gates Jump
  /// to Marker and Remove Marker — both meaningless with no markers to target.
  final bool markersPresent;

  /// Whether the active tab has at least one annotation. Gates the walkthrough
  /// actions, which are *structurally hidden* rather than greyed when false:
  /// three dead rows in every session that never annotates is menu noise.
  final bool annotationsPresent;

  /// Whether the active tab's signal list has at least one row. Gates Clear
  /// Canvas, which has nothing to clear on an empty canvas.
  final bool signalsDisplayed;

  /// Whether the active tab has a comparison (diff) file loaded. Gates the
  /// Next/Previous Divergence navigation — there is nothing to step through
  /// until a second file is being compared.
  final bool diffActive;

  /// Whether the active tab has a cocotb log loaded. Gates Clear Cocotb Log —
  /// a no-op when no log is loaded.
  final bool cocotbLogLoaded;

  /// Whether the active tab's pattern search has at least one match. Gates
  /// Next/Previous Pattern Match — nothing to step through with zero matches.
  final bool patternMatchesPresent;

  /// Whether the active tab has a live streaming VCD session (starting or
  /// active). Gates Stop Streaming, which is *structurally hidden* rather than
  /// greyed when false: a permanently-disabled Stop Streaming row would be
  /// menu noise for the majority of sessions that never stream.
  ///
  /// Deliberately a bool and not the streaming state itself — the elapsed time
  /// ticks once a second, and putting it here would rebuild every action
  /// surface on every tick.
  final bool streamingActive;

  /// Whether the active tab's Stage Playback is currently playing. Purely
  /// presentational: `togglePlayback` is enabled either way, but the toolbar
  /// button shows a pause glyph while playing instead of an inert play icon.
  final bool playbackActive;

  /// Whether the active tab's viewport can still zoom out — false once it
  /// already spans the whole trace, which is the most zoomed-out state there
  /// is. Greys out Zoom Out in every action surface rather than letting the
  /// press land on a clamp and change nothing: a control that responds and
  /// does nothing is its own small lie.
  ///
  /// Defaults to true so every existing [ActionContext] literal — and the
  /// no-file case, where the requirement is unreachable behind
  /// [ActionRequirement.fileLoaded] anyway — behaves as before.
  final bool canZoomOut;

  /// Whether the active tab's viewport can still zoom in — false once it spans
  /// the timescale's one-tick resolution, below which the trace carries no
  /// detail to reveal. The mirror of [canZoomOut], and greyed the same way.
  final bool canZoomIn;

  /// Whether this build can actually execute PRO/ENT-tier actions
  /// (`tierGatedActionsAvailableProvider`).
  ///
  /// When false, every action whose `requiredTier` is not `openCore` is
  /// hidden from all surfaces rather than badged-and-dead. Open Core on a
  /// mobile host is the false case: its handlers for those actions are empty
  /// closures, and an app store offers no upgrade path that would make an
  /// enabled-but-inert menu row anything other than a broken feature. See the
  /// provider's doc-comment for the App Store rejection that motivated it.
  ///
  /// Defaults to true so desktop behavior — and every existing test that
  /// builds an [ActionContext] — is unchanged.
  final bool tierGatedActionsAvailable;

  /// Whether this is the browser build.
  ///
  /// Hides the actions whose result is a file on disk the browser cannot give
  /// back: saving a session or a workspace, generating a test VCD, producing
  /// RTL stems. Exports that end as a download stay visible.
  final bool isWeb;

  /// Whether the window can show split panes (`splitPaneAllowedProvider`):
  /// false on phones and on tablets narrower than 1000 dp, where the pane host
  /// renders only the active pane. Hides Split Pane Right there — a split made
  /// then would put the tabs left behind in a pane nobody can see.
  final bool splitPaneAllowed;

  /// Convenience: a phone-sized display (phone or phone-landscape).
  bool get isPhoneClass => deviceClass.isPhoneClass;

  @override
  bool operator ==(Object other) =>
      other is ActionContext &&
      other.fileLoaded == fileLoaded &&
      other.deviceClass == deviceClass &&
      other.diagnosticsEnabled == diagnosticsEnabled &&
      other.paneCount == paneCount &&
      other.inSession == inSession &&
      other.isHost == isHost &&
      other.isRecording == isRecording &&
      other.stageViewVisible == stageViewVisible &&
      other.crossProbeVisible == crossProbeVisible &&
      other.aiAvailable == aiAvailable &&
      other.aiModelConfigured == aiModelConfigured &&
      other.hasSelection == hasSelection &&
      other.cursorPresent == cursorPresent &&
      other.markersPresent == markersPresent &&
      other.signalsDisplayed == signalsDisplayed &&
      other.diffActive == diffActive &&
      other.cocotbLogLoaded == cocotbLogLoaded &&
      other.patternMatchesPresent == patternMatchesPresent &&
      other.streamingActive == streamingActive &&
      other.playbackActive == playbackActive &&
      other.canZoomOut == canZoomOut &&
      other.canZoomIn == canZoomIn &&
      other.tierGatedActionsAvailable == tierGatedActionsAvailable &&
      other.isWeb == isWeb &&
      other.splitPaneAllowed == splitPaneAllowed;

  @override
  int get hashCode => Object.hash(
    fileLoaded,
    deviceClass,
    diagnosticsEnabled,
    paneCount,
    inSession,
    isHost,
    isRecording,
    stageViewVisible,
    crossProbeVisible,
    aiAvailable,
    aiModelConfigured,
    hasSelection,
    Object.hash(
      cursorPresent,
      markersPresent,
      diffActive,
      cocotbLogLoaded,
      patternMatchesPresent,
      streamingActive,
      playbackActive,
      tierGatedActionsAvailable,
      Object.hash(
        canZoomOut,
        canZoomIn,
        isWeb,
        splitPaneAllowed,
        signalsDisplayed,
      ),
    ),
  );
}
