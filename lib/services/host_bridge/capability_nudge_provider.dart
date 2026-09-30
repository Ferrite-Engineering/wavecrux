// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart' show immutable;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/enums/editor_host_capability.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/services/host_bridge/editor_host_provider.dart';
import 'package:wavecrux/services/host_bridge/editor_host_session_provider.dart';

part 'capability_nudge_provider.g.dart';

/// How slow a parse has to be before it is worth explaining.
///
/// **Measured, not guessed.** The trigger reads
/// `WaveformSourceNotifier.lastParseTime`, which is stopwatched around the
/// backend's `openBytes` call and nothing else — not the byte transfer, not
/// the frame that painted the loading state. A file-size threshold was
/// considered and is the wrong answer: it would fire on a 200 MB VCD that
/// parsed in under a second (few signals, few transitions) and stay silent
/// on the 30 MB gate-level FST that took twelve, which is precisely the file
/// whose owner wants to know about the desktop build.
///
/// Three seconds is the point at which a person has stopped waiting and
/// started wondering. Below it the honest answer is that the panel is fine.
const Duration kEditorHostSlowParseThreshold = Duration(seconds: 3);

/// The nudge currently showing, if any.
@immutable
class CapabilityNudge {
  /// Creates a showing nudge.
  const CapabilityNudge({required this.capability, this.parseDuration});

  /// Which boundary it explains.
  final EditorHostCapability capability;

  /// The measured duration that raised it, for
  /// [EditorHostCapability.slowParse]. Null for every other capability —
  /// none of which is raised as a nudge today.
  final Duration? parseDuration;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CapabilityNudge &&
          other.capability == capability &&
          other.parseDuration == parseDuration);

  @override
  int get hashCode => Object.hash(capability, parseDuration);

  @override
  String toString() => 'CapabilityNudge($capability, $parseDuration)';
}

/// Whether an *unsolicited* capability notice may be raised right now.
///
/// Pure, and separated from [CapabilityNudgeNotifier] so the nudge policy's
/// frequency discipline is one readable expression rather than a shape
/// inferred from a notifier's control flow. Every clause is a rule the plan
/// states outright:
///
/// * **Only under an editor host.** These sentences describe an editor
///   panel. A desktop window, a phone, and a plain browser tab have
///   different limitations, or none, and saying otherwise would be false.
/// * **Never on the first file of an installation.** "The first experience
///   must be the product working." [openedFileBefore] comes from the host's
///   `globalState`, which is the only storage in this extension that
///   outlives a window.
/// * **At most one per session.** Not one per capability and not one per
///   file: a second nudge is the point at which a notice becomes nagging,
///   and the first one has already said the thing that mattered.
///
/// Dismissal is deliberately **not** an input here. Dismissing clears the
/// nudge that is showing; it does not need to also suppress future ones,
/// because [alreadyNudgedThisSession] has already done that — a dismissed
/// nudge was, first, a nudge.
bool mayRaiseCapabilityNudge({
  required EditorHostKind hostKind,
  required bool openedFileBefore,
  required bool alreadyNudgedThisSession,
}) {
  if (hostKind == EditorHostKind.none) return false;
  if (!openedFileBefore) return false;
  if (alreadyNudgedThisSession) return false;
  return true;
}

/// The one capability nudge a session is allowed, and its dismissal.
///
/// `keepAlive` and root-scoped on purpose: "once per session" has to mean
/// once per *app run*, and a per-tab notifier would re-arm on every new tab —
/// which is to say once per file, which is the behaviour the policy rules out.
///
/// A "session" ends when this Flutter app does. Inside a VSCode editor that
/// is the webview's lifetime, which `retainContextWhenHidden` preserves
/// across tab switches but not across a window reload or the deliberate
/// context release a document above the retention threshold triggers. Those
/// re-arm the nudge, and that is the honest reading: the app genuinely
/// started again.
@Riverpod(keepAlive: true)
class CapabilityNudgeNotifier extends _$CapabilityNudgeNotifier {
  /// Latched for the process lifetime — never cleared by [dismiss].
  bool _raisedThisSession = false;

  @override
  CapabilityNudge? build() => null;

  /// Whether this session has already spent its one nudge. Inspection seam
  /// for tests, and for a caller that wants to skip computing a message it
  /// would not be allowed to show.
  bool get hasRaisedThisSession => _raisedThisSession;

  /// Offer the slow-parse boundary, having measured [parseDuration].
  ///
  /// Returns whether it was raised. A `false` return is the normal case and
  /// carries no error: the parse was quick, or this is the first file, or the
  /// session already had its nudge.
  ///
  /// Takes the measured [Duration] rather than a "was it slow" bool so the
  /// threshold comparison lives in one place and the same value reaches the
  /// message the user reads.
  bool offerSlowParse(Duration parseDuration) {
    if (parseDuration < kEditorHostSlowParseThreshold) return false;
    if (!mayRaiseCapabilityNudge(
      hostKind: ref.read(editorHostKindProvider),
      openedFileBefore: ref.read(editorHostSessionProvider).openedFileBefore,
      alreadyNudgedThisSession: _raisedThisSession,
    )) {
      return false;
    }
    _raisedThisSession = true;
    state = CapabilityNudge(
      capability: EditorHostCapability.slowParse,
      parseDuration: parseDuration,
    );
    return true;
  }

  /// Dismiss whatever is showing.
  ///
  /// Does **not** un-spend the session's nudge — see [_raisedThisSession].
  /// A dismissal that re-armed the mechanism would turn "at most one per
  /// session" into "one at a time", which is a different and much worse
  /// promise.
  void dismiss() {
    if (state == null) return;
    state = null;
  }
}
