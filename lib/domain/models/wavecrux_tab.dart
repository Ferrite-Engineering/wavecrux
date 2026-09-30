// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/pane_id.dart';
import 'package:wavecrux/domain/models/tab_id.dart';

/// Represents a single open tab in the WaveCrux multi-tab workspace.
///
/// Each tab encapsulates the in-memory state of one waveform viewing
/// session. There is no `kind: welcome` tab variant — emptiness is a
/// workspace state, not a tab kind. The [paneId] field records which
/// split pane hosts every live tab.
///
/// Pure Dart — no Flutter imports.
@immutable
class WavecruxTab {
  const WavecruxTab({
    required this.id,
    required this.displayName,
    this.filePath,
    this.sessionFilePath,
    this.isDetached = false,
    this.paneId = PaneId.primary,
  });

  /// Creates a placeholder tab with no file loaded yet and a generated
  /// [TabId]. Retained for transitional compatibility with the previous
  /// `WavecruxTab.welcome()` factory; new code should prefer rendering the
  /// empty-canvas state via an empty workspace.
  factory WavecruxTab.placeholder({
    String displayName = 'Welcome',
    PaneId paneId = PaneId.primary,
  }) => WavecruxTab(
    id: TabId.generate(),
    displayName: displayName,
    paneId: paneId,
  );

  final TabId id;
  final String displayName;
  final String? filePath;
  final String? sessionFilePath;
  final bool isDetached;

  /// Identifies the pane hosting this tab (split-pane). With a
  /// single pane the value is the workspace's primary pane id; with split-
  /// pane every tab belongs to exactly one pane.
  final PaneId paneId;

  /// `true` when the tab has neither a loaded waveform file nor a session
  /// reference — the successor to the retired `kind == TabKind.welcome`.
  bool get isPlaceholder => filePath == null && sessionFilePath == null;

  WavecruxTab copyWith({
    TabId? id,
    String? displayName,
    String? filePath,
    String? sessionFilePath,
    bool? isDetached,
    PaneId? paneId,
  }) {
    return WavecruxTab(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      filePath: filePath ?? this.filePath,
      sessionFilePath: sessionFilePath ?? this.sessionFilePath,
      isDetached: isDetached ?? this.isDetached,
      paneId: paneId ?? this.paneId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WavecruxTab &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          displayName == other.displayName &&
          filePath == other.filePath &&
          sessionFilePath == other.sessionFilePath &&
          isDetached == other.isDetached &&
          paneId == other.paneId;

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    filePath,
    sessionFilePath,
    isDetached,
    paneId,
  );

  @override
  String toString() =>
      'WavecruxTab(id: $id, displayName: $displayName, '
      'filePath: $filePath, paneId: $paneId, isDetached: $isDetached)';
}
