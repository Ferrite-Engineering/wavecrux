// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/pane_id.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';

part 'active_pane_id_provider.g.dart';

/// The [PaneId] of the currently focused pane.
///
/// Derived from [workspaceProvider] so that the workspace is the
/// single source of truth for which pane has focus. Until the workspace
/// finishes hydrating (cold start before the first frame), falls back to
/// [PaneId.primary] — matching the implicit pane id every live tab carries
/// before the workspace is loaded. Mutating goes through
/// [WorkspaceNotifier.setActivePane] rather than directly setting state on
/// this provider so the workspace stays consistent.
///
/// Per ARCHITECTURE.md §6.4 (split-pane).
@Riverpod(keepAlive: true)
PaneId activePaneId(Ref ref) {
  final workspace = ref.watch(workspaceProvider).value;
  return workspace?.activePaneId ?? PaneId.primary;
}
