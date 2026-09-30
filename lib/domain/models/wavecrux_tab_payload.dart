// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Per-tab payload type carried by `WorkspaceTab<WaveCruxTabPayload>`.
///
/// Captures the slice of per-tab state that lives directly in the persisted
/// `workspace.json` document. Heavyweight per-tab state (cursor time, zoom
/// state, signal groups, markers, decoder config, Stage instance config)
/// remains scoped to its per-tab Riverpod providers and is exported into
/// a separate `.wavecrux` sidecar; what lives here is the framework-visible
/// summary needed to re-bind the file and reach the sidecar after restart.
///
/// Pure Dart — no Flutter imports. Immutable with manual `==` / `hashCode` /
/// `copyWith` / JSON round-trip per the WaveCrux domain-model conventions.
@immutable
class WaveCruxTabPayload {
  /// Creates a payload.
  const WaveCruxTabPayload({
    this.filePath,
    this.sessionFilePath,
    this.sessionExportPath,
    this.isDetached = false,
  });

  /// Absolute path of the waveform file backing the tab. `null` for tabs
  /// that have not yet been bound to a file (e.g. a freshly-created tab
  /// awaiting File→Open). The corresponding live `WaveformDataSource` lives
  /// in the per-tab Riverpod scope and is reconstructed from this path on
  /// workspace restoration.
  final String? filePath;

  /// Absolute path of the `.wavecrux` session the tab was opened *from*
  /// (File→Open Session). Distinct from [sessionExportPath]; `null` when the
  /// tab was not opened from a session file.
  final String? sessionFilePath;

  /// Absolute path of the `.wavecrux` session file last exported (or
  /// imported) for this tab. Used to hint the destination on subsequent
  /// "Export Tab as Session…" invocations. `null` when the tab has no
  /// associated export file.
  final String? sessionExportPath;

  /// Whether the tab is currently detached into a secondary window.
  /// `false` for in-place tabs.
  final bool isDetached;

  /// Returns a copy with the supplied fields replaced.
  ///
  /// Note: nullable fields cannot be cleared via `copyWith` — callers that
  /// want to clear a field construct a new payload directly. This mirrors
  /// the convention used elsewhere in the WaveCrux domain models.
  WaveCruxTabPayload copyWith({
    String? filePath,
    String? sessionFilePath,
    String? sessionExportPath,
    bool? isDetached,
  }) => WaveCruxTabPayload(
    filePath: filePath ?? this.filePath,
    sessionFilePath: sessionFilePath ?? this.sessionFilePath,
    sessionExportPath: sessionExportPath ?? this.sessionExportPath,
    isDetached: isDetached ?? this.isDetached,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaveCruxTabPayload &&
          runtimeType == other.runtimeType &&
          filePath == other.filePath &&
          sessionFilePath == other.sessionFilePath &&
          sessionExportPath == other.sessionExportPath &&
          isDetached == other.isDetached;

  @override
  int get hashCode =>
      Object.hash(filePath, sessionFilePath, sessionExportPath, isDetached);

  @override
  String toString() =>
      'WaveCruxTabPayload(filePath: $filePath, '
      'sessionFilePath: $sessionFilePath, '
      'sessionExportPath: $sessionExportPath, isDetached: $isDetached)';
}
