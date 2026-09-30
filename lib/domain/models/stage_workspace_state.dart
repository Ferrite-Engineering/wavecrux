// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';

/// The complete Stage workspace: ordered list of panels plus the
/// currently-selected panel id.
///
/// One Stage workspace per session. Persisted as part of
/// `SessionState.stageWorkspace` in `.wavecrux` files.
///
/// Pure Dart — no Flutter imports.
@immutable
class StageWorkspaceState {
  const StageWorkspaceState({
    this.panels = const [],
    this.activePanelId,
  });

  /// Ordered list of Stage panels (tabs).
  final List<StagePanelConfig> panels;

  /// [StagePanelConfig.id] of the currently-selected panel, or null
  /// when [panels] is empty.
  final String? activePanelId;

  /// True when the workspace has at least one panel.
  bool get hasPanels => panels.isNotEmpty;

  /// Returns the active panel, or null when [panels] is empty or
  /// [activePanelId] doesn't match any panel.
  StagePanelConfig? get activePanel {
    final id = activePanelId;
    if (id == null) return null;
    for (final p in panels) {
      if (p.id == id) return p;
    }
    return null;
  }

  StageWorkspaceState copyWith({
    List<StagePanelConfig>? panels,
    Object? activePanelId = _unset,
  }) => StageWorkspaceState(
    panels: panels ?? this.panels,
    activePanelId: activePanelId == _unset
        ? this.activePanelId
        : activePanelId as String?,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StageWorkspaceState) return false;
    if (activePanelId != other.activePanelId) return false;
    if (panels.length != other.panels.length) return false;
    for (var i = 0; i < panels.length; i++) {
      if (panels[i] != other.panels[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(activePanelId, Object.hashAll(panels));

  @override
  String toString() =>
      'StageWorkspaceState(panels: ${panels.length}, '
      'active: $activePanelId)';
}

const _unset = Object();
