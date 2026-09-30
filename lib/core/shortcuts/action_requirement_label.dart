// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/core/shortcuts/action_requirement.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Localized "why is this disabled, and what do I do about it" hint for each
/// [ActionRequirement].
///
/// Split from [ActionRequirement] itself for the same reason
/// `ActionCategoryLabel` is split from `ActionCategory`: the enum lives in the
/// pure-Dart descriptor layer (unit-testable with no widget pump), and the
/// wavecrux-specific localized strings live in the layer that may reference
/// [L10N].
///
/// Each string is phrased as the *remedy*, not the diagnosis — "Load a
/// waveform file to use this command", not "no file loaded" — because it is
/// shown in response to a key press whose effect the user expected.
extension ActionRequirementHint on ActionRequirement {
  /// The localized hint shown when a keyboard shortcut fires for an action
  /// this requirement is currently blocking.
  ///
  /// Exhaustive `switch`: a new [ActionRequirement] value fails to compile
  /// until its message is declared here, which is the guardrail that keeps a
  /// new requirement from silently reintroducing the inert-key regression.
  String hint(L10N l10n) => switch (this) {
    ActionRequirement.fileLoaded => l10n.actionRequiresFile,
    ActionRequirement.cursorPresent => l10n.actionRequiresCursor,
    ActionRequirement.markersPresent => l10n.actionRequiresMarker,
    ActionRequirement.annotationsPresent => l10n.actionRequiresAnnotation,
    ActionRequirement.diffActive => l10n.actionRequiresDiff,
    ActionRequirement.patternMatchesPresent => l10n.actionRequiresPatternMatch,
    ActionRequirement.cocotbLogLoaded => l10n.actionRequiresCocotbLog,
    ActionRequirement.stageViewVisible => l10n.actionRequiresStagePanel,
    ActionRequirement.streamingActive => l10n.actionRequiresStreaming,
    ActionRequirement.diagnosticsEnabled => l10n.actionRequiresDiagnostics,
    ActionRequirement.hasSelection => l10n.actionRequiresSelection,
    ActionRequirement.aiModelConfigured => l10n.actionRequiresAiModel,
    ActionRequirement.notInSession => l10n.actionRequiresNoSession,
    ActionRequirement.inSession => l10n.actionRequiresSession,
    ActionRequirement.isHost => l10n.actionRequiresHost,
    ActionRequirement.isParticipant => l10n.actionRequiresParticipant,
    ActionRequirement.recordingAvailable => l10n.actionRequiresRecording,
    ActionRequirement.singlePane => l10n.actionRequiresSinglePane,
    ActionRequirement.multiPane => l10n.actionRequiresMultiPane,
    ActionRequirement.canZoomOut => l10n.actionRequiresZoomOutRoom,
    ActionRequirement.canZoomIn => l10n.actionRequiresZoomInRoom,
  };
}
