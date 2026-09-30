// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/misc.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';

/// Bundled workspace overrides for widget/unit tests: an in-memory service
/// (no `path_provider`) plus a zero-debounce workspace notifier (so mutations
/// save eagerly and leave no pending `Timer` to trip the widget-test
/// pending-timer check). Spread into a `ProviderContainer` / `ProviderScope`
/// `overrides` list.
List<Override> testWorkspaceOverrides([PaneId? initialPaneId]) => [
  workspaceServiceProvider.overrideWithValue(
    InMemoryWorkspaceService(initialPaneId),
  ),
  workspaceProvider.overrideWith(
    () => WaveCruxWorkspaceNotifier(autoSaveDebounce: Duration.zero),
  ),
];

/// In-memory [WorkspaceService] for widget/unit tests.
///
/// Production [WorkspaceService.load] resolves the app-support directory via
/// `path_provider`, which has no default test implementation — so without an
/// override the workspace `AsyncNotifier` never hydrates and the (now derived)
/// `tabListProvider` stays empty, which means a seeded tab never appears.
///
/// This fake loads/saves entirely in memory: [load] returns a single-pane
/// empty workspace (or the last [save]d document) so tab mutations settle
/// synchronously under `pumpAndSettle`. Methods other than [load]/[save] are
/// routed through [noSuchMethod] (the consolidated mutation paths only call
/// `load`, `save`, and — best-effort, error-swallowed — `deleteSidecar`).
class InMemoryWorkspaceService implements WorkspaceService {
  InMemoryWorkspaceService([this.initialPaneId]);

  /// Pane id the freshly-loaded workspace declares. Defaults to
  /// [PaneId.primary] so a seeded tab (which lands in the active pane) renders.
  final PaneId? initialPaneId;

  Workspace? _saved;

  @override
  Future<Workspace> load() async {
    final saved = _saved;
    if (saved != null) return saved;
    final pane = WorkspacePane(id: initialPaneId ?? PaneId.primary);
    return Workspace(tabs: const [], panes: [pane], activePaneId: pane.id);
  }

  @override
  Future<void> save(Workspace workspace) async {
    _saved = workspace;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
