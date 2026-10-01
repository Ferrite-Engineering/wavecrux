// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/core/shortcuts/action_context.dart';

/// One atomic precondition an action can require before it becomes enabled.
///
/// ## Why an enum instead of a bare `bool Function(ActionContext)`
///
/// Enablement used to be a single opaque closure per action
/// (`isEnabled: _requiresFileAndCursor`). That answers "is it enabled?" but
/// not "*why* not?", so the keyboard's descriptor-parity guard could only fail
/// silently: pressing Ctrl+D with no file open did nothing at all, where the
/// old hand-rolled handler check used to explain that a waveform file is
/// needed first.
///
/// Decomposing enablement into a *list* of named requirements keeps the
/// enabled/disabled answer identical (an action is enabled iff every
/// requirement is satisfied) while making the unsatisfied one addressable —
/// `ActionDescriptor.unmetRequirement` returns the first requirement that
/// fails, and the UI layer maps that value to a localized hint via
/// `ActionRequirementHint.hint` in `action_requirement_label.dart`.
///
/// A single static reason string per action would be wrong: several actions
/// carry more than one requirement (Explain Selection needs a file AND a
/// selection AND a configured model), and the accurate message depends on
/// which one is missing in the current [ActionContext].
///
/// This file stays pure Dart — no Flutter, no L10N — so the descriptor table
/// and its predicates remain unit-testable without pumping a widget. The
/// localized strings live in the sibling label extension.
enum ActionRequirement {
  /// A waveform file is loaded in the active tab.
  fileLoaded,

  /// A primary cursor is placed in the active tab.
  cursorPresent,

  /// At least one named marker (a–z) exists in the active tab.
  markersPresent,

  /// At least one annotation exists in the active tab. Gates the walkthrough,
  /// which has nothing to step through without one.
  annotationsPresent,

  /// A comparison (diff) file is loaded in the active tab.
  diffActive,

  /// The active tab's pattern search has at least one match.
  patternMatchesPresent,

  /// A cocotb log is loaded in the active tab.
  cocotbLogLoaded,

  /// The active tab's Stage panel is on screen.
  stageViewVisible,

  /// A live streaming VCD session is running in the active tab.
  streamingActive,

  /// The diagnostics surfaces are enabled (debug/profile, or Settings >
  /// Advanced in release).
  diagnosticsEnabled,

  /// At least one signal is selected in the active tab.
  hasSelection,

  /// The active tab's signal list has at least one row (gates Clear Canvas).
  signalsDisplayed,

  /// A usable AI model is configured.
  aiModelConfigured,

  /// No collaborative session is active (gates Share / Join).
  notInSession,

  /// A collaborative session is active.
  inSession,

  /// The local user hosts the active collaborative session.
  isHost,

  /// The local user is a non-host participant in an active session.
  isParticipant,

  /// A session recording exists or is in progress (gates the export).
  recordingAvailable,

  /// Exactly one workspace pane is open (gates Split Pane Right).
  singlePane,

  /// Two or more workspace panes are open (gates Close Pane / Focus Other
  /// Pane / Move Tab to Other Pane).
  multiPane,

  /// The active tab's viewport can still zoom out — it does not already span
  /// the whole trace.
  canZoomOut,

  /// The active tab's viewport can still zoom in — it spans more than the
  /// timescale's one-tick resolution.
  canZoomIn;

  /// Whether this requirement holds under [c].
  ///
  /// Exhaustive `switch`: a new [ActionRequirement] value fails to compile
  /// until its predicate is declared here.
  bool isSatisfiedBy(ActionContext c) => switch (this) {
    ActionRequirement.fileLoaded => c.fileLoaded,
    ActionRequirement.cursorPresent => c.cursorPresent,
    ActionRequirement.markersPresent => c.markersPresent,
    ActionRequirement.annotationsPresent => c.annotationsPresent,
    ActionRequirement.diffActive => c.diffActive,
    ActionRequirement.patternMatchesPresent => c.patternMatchesPresent,
    ActionRequirement.cocotbLogLoaded => c.cocotbLogLoaded,
    ActionRequirement.stageViewVisible => c.stageViewVisible,
    ActionRequirement.streamingActive => c.streamingActive,
    ActionRequirement.diagnosticsEnabled => c.diagnosticsEnabled,
    ActionRequirement.hasSelection => c.hasSelection,
    ActionRequirement.signalsDisplayed => c.signalsDisplayed,
    ActionRequirement.aiModelConfigured => c.aiModelConfigured,
    ActionRequirement.notInSession => !c.inSession,
    ActionRequirement.inSession => c.inSession,
    ActionRequirement.isHost => c.isHost,
    ActionRequirement.isParticipant => c.inSession && !c.isHost,
    ActionRequirement.recordingAvailable => c.inSession || c.isRecording,
    ActionRequirement.singlePane => c.paneCount == 1,
    ActionRequirement.multiPane => c.paneCount >= 2,
    ActionRequirement.canZoomOut => c.canZoomOut,
    ActionRequirement.canZoomIn => c.canZoomIn,
  };
}
