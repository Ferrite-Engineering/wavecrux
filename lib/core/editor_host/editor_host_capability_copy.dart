// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart' show immutable;
import 'package:wavecrux/domain/enums/editor_host_capability.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// The words for one [EditorHostCapability] boundary.
///
/// A pair rather than a single string because every surface that shows one
/// renders the title differently from the body — a banner emphasises the
/// title, a panel empty state centres both — and a single blob would force
/// each of them to re-split it.
@immutable
class EditorHostCapabilityCopy {
  /// Creates the pair.
  const EditorHostCapabilityCopy({required this.title, required this.message});

  /// One short line naming the boundary.
  final String title;

  /// What the limitation is, why it exists, and what to do about it —
  /// `fsdbWebUnsupportedMessage`'s three-part shape, which every string
  /// resolved here follows.
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EditorHostCapabilityCopy &&
          other.title == title &&
          other.message == message);

  @override
  int get hashCode => Object.hash(title, message);

  @override
  String toString() => 'EditorHostCapabilityCopy($title)';
}

/// The localized copy for [capability].
///
/// The one place the four boundaries' words are resolved. Four surfaces show
/// them (the slow-parse banner, the Stage empty state, the RTL Source empty
/// state, the empty canvas), and routing all four through one function is
/// what keeps a later edit to any one of them from making it the odd voice
/// out. It is also the seam the widget tests assert against, so a boundary
/// that stops being reachable fails a test rather than going quiet.
///
/// [parseDuration] is required by, and used only by,
/// [EditorHostCapability.slowParse] — the measured wall-clock duration of
/// the parse that raised it. Passing `null` for that capability is a
/// programming error, and the assertion says so rather than rendering the
/// literal `null` into a user-facing sentence.
EditorHostCapabilityCopy editorHostCapabilityCopy(
  L10N l10n,
  EditorHostCapability capability, {
  Duration? parseDuration,
}) {
  switch (capability) {
    case EditorHostCapability.slowParse:
      assert(
        parseDuration != null,
        'slowParse copy needs the measured duration that raised it',
      );
      return EditorHostCapabilityCopy(
        title: l10n.editorHostSlowParseTitle(
          formatEditorHostParseDuration(parseDuration ?? Duration.zero),
        ),
        message: l10n.editorHostSlowParseMessage,
      );
    case EditorHostCapability.stage:
      return EditorHostCapabilityCopy(
        title: l10n.editorHostStageTitle,
        message: l10n.editorHostStageMessage,
      );
    case EditorHostCapability.interactiveVcd:
      return EditorHostCapabilityCopy(
        title: l10n.editorHostInteractiveVcdTitle,
        message: l10n.editorHostInteractiveVcdMessage,
      );
    case EditorHostCapability.rtlAnnotation:
      return EditorHostCapabilityCopy(
        title: l10n.editorHostRtlAnnotationTitle,
        message: l10n.editorHostRtlAnnotationMessage,
      );
  }
}

/// Renders [duration] the way the Diagnostics → File Info panel already
/// renders a parse time: `1.2 s` above a second, `450 ms` below it.
///
/// Deliberately the same shape as `FileInfoPanel._formatParseTime`, and
/// deliberately not locale-formatted: the panel this mirrors is not either,
/// and a notice that said `12,4 s` while the diagnostics pane beside it said
/// `12.4 s` would read as two different measurements of the same parse.
String formatEditorHostParseDuration(Duration duration) {
  final ms = duration.inMicroseconds / 1000.0;
  if (ms < 1000) return '${ms.toStringAsFixed(0)} ms';
  return '${(ms / 1000).toStringAsFixed(1)} s';
}
