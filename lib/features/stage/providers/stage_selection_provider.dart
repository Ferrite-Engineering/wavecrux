// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';

part 'stage_selection_provider.g.dart';

/// Currently selected stage instance id, or null when nothing is selected.
///
/// Selection is **transient** — it is not persisted to `.wavecrux`
/// session files. The provider listens to [stageWorkspaceProvider]
/// and clears itself automatically when:
///
/// - the active panel changes (selecting an instance on panel A then
///   switching to panel B should not leave the bindings pane open on
///   a no-longer-visible widget)
/// - the selected instance is removed (via the close button or session
///   restore).
@Riverpod(keepAlive: true)
class StageSelectedInstance extends _$StageSelectedInstance {
  @override
  String? build() {
    ref.listen(
      stageWorkspaceProvider,
      (prev, next) {
        if (state == null) return;
        if (prev?.activePanelId != next.activePanelId) {
          state = null;
          return;
        }
        final exists =
            next.activePanel?.instances.any((i) => i.id == state) ?? false;
        if (!exists) state = null;
      },
    );
    return null;
  }

  /// Selects the instance with [id], or clears selection when [id] is
  /// null. A method reads better at the call site than a setter
  /// assignment for this transient UI action.
  // ignore: use_setters_to_change_properties
  void select(String? id) {
    state = id;
  }

  /// Clears the current selection.
  void clear() {
    state = null;
  }
}
