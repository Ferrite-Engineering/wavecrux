// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart' show immutable;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'editor_host_session_provider.g.dart';

/// What the extension host has told this build about the installation it is
/// running inside.
///
/// Exactly one fact today, and it is the one the Dart half structurally
/// cannot work out for itself.
@immutable
class EditorHostSession {
  /// Creates the facts.
  const EditorHostSession({required this.openedFileBefore});

  /// The conservative default: assume this is the first file.
  ///
  /// Conservative in the direction that matters — the nudge policy forbids a nudge
  /// on the first file a user opens, so a host that never sent the frame (an
  /// older extension, a dropped message, a plain browser tab with no host at
  /// all) produces *silence*, not a nudge on the worst possible occasion.
  static const EditorHostSession unknown = EditorHostSession(
    openedFileBefore: false,
  );

  /// Whether this **installation** had opened a waveform before the one
  /// currently on screen.
  ///
  /// Sourced from `ExtensionContext.globalState` on the host side — see
  /// `crux-vscode/packages/wavecrux/src/webview/host-session.ts` for why the
  /// durable half of this lives there and the per-session half lives here.
  /// The Dart build has no storage that survives a webview reload, so a
  /// second first-open flag invented on this side would drift from the one
  /// `file.first_opened` already uses.
  final bool openedFileBefore;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EditorHostSession &&
          other.openedFileBefore == openedFileBefore);

  @override
  int get hashCode => openedFileBefore.hashCode;

  @override
  String toString() => 'EditorHostSession(openedFileBefore: $openedFileBefore)';
}

/// The host-supplied session facts, or [EditorHostSession.unknown].
///
/// `keepAlive` and root-scoped, like `editorHostKindProvider`: the frame
/// arrives once, early, on the bridge, and a per-tab copy would be `unknown`
/// for every tab but the one that happened to be mounted when it landed.
@Riverpod(keepAlive: true)
class EditorHostSessionNotifier extends _$EditorHostSessionNotifier {
  @override
  EditorHostSession build() => EditorHostSession.unknown;

  /// Records what the host said. Idempotent.
  ///
  /// The host re-posts the frame after a context release (a >64 MiB document
  /// whose webview VSCode tore down and rebuilt), so this can legitimately be
  /// called more than once per installation — with the same value, since the
  /// host samples it before it marks the installation as having opened a file.
  void set(EditorHostSession session) {
    if (state == session) return;
    state = session;
  }
}
