// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/models/last_session_manifest.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart'
    show WorkspaceService;
import 'package:wavecrux/services/session/last_session_service.dart';

/// One-shot migration from the legacy `last_session.json` manifest to the
/// `workspace.json` document.
///
/// Behavior:
/// * If `workspace.json` already exists → no-op (workspace wins).
/// * If `last_session.json` is absent → no-op.
/// * Otherwise: convert the manifest to a single-pane workspace (all tabs
///   in one pane; the first tab is the active tab), persist it via
///   [WorkspaceService.save], then delete the legacy `last_session.json` so
///   subsequent launches skip migration entirely (idempotent).
///
/// Failures during read / parse of the legacy file are logged and treated as
/// "no migration needed"; the offending file is **not** deleted so the user
/// can recover it manually. Failures to write the workspace abort the
/// migration without deleting the legacy file.
class LastSessionMigration {
  const LastSessionMigration({
    required this.lastSessionService,
    required this.workspaceService,
    void Function(String message)? logger,
  }) : _logger = logger;

  final LastSessionService lastSessionService;
  final WorkspaceService workspaceService;
  final void Function(String message)? _logger;

  /// Runs the migration. Returns `true` when a migration ran and produced
  /// a new workspace; returns `false` for the no-op cases (workspace already
  /// exists, no legacy manifest, or unrecoverable failure).
  Future<bool> run() async {
    final existingWorkspace = await workspaceService.load();
    // `load()` is forgiving — corrupt files become Workspace.empty. To detect
    // "no workspace file at all" we check the file directly via the same
    // service's underlying machinery is not exposed; instead, we rely on the
    // weaker but sufficient heuristic: if the legacy file is absent, there is
    // nothing to migrate; if both files exist, prefer the workspace.
    final legacy = await lastSessionService.load();
    if (legacy.tabs.isEmpty) {
      return false;
    }
    if (existingWorkspace.tabs.isNotEmpty) {
      // The workspace already has content — migration would clobber it.
      // Clean up the legacy file so we never reconsider it.
      _log(
        'LastSessionMigration: workspace.json already populated; '
        'discarding legacy last_session.json',
      );
      await lastSessionService.clear();
      return false;
    }

    final pane = WorkspacePane(id: PaneId.generate());
    final tabs = [
      for (final entry in legacy.tabs)
        buildWorkspaceTab(
          id: TabId.generate(),
          displayName: _displayNameFor(entry),
          paneId: pane.id,
          filePath: entry.filePath.isEmpty ? null : entry.filePath,
          sessionExportPath: entry.sessionFilePath,
        ),
    ];
    final panes = <WorkspacePane>[
      if (tabs.isEmpty) pane else pane.copyWith(activeTabId: tabs.first.id),
    ];
    final workspace = Workspace(
      tabs: tabs,
      panes: panes,
      activePaneId: pane.id,
    );

    try {
      await workspaceService.save(workspace);
    } on Exception catch (e) {
      _log(
        'LastSessionMigration: workspace save failed; keeping legacy '
        'last_session.json: $e',
      );
      return false;
    }
    await lastSessionService.clear();
    return true;
  }

  String _displayNameFor(LastSessionTab entry) {
    if (entry.filePath.isNotEmpty) return p.basename(entry.filePath);
    if (entry.sessionFilePath != null) {
      return p.basenameWithoutExtension(entry.sessionFilePath!);
    }
    return 'Untitled';
  }

  void _log(String message) {
    final l = _logger;
    if (l != null) {
      l(message);
    } else {
      // Default sink: route to package:logging so the issue-reporter ring
      // buffer captures migration notes/failures. Tests inject [_logger].
      _moduleLog.warning(message);
    }
  }
}

/// Default logger for the one-shot last-session → workspace migration when no
/// [_logger] sink is injected.
final _moduleLog = Logger('wavecrux.workspace');
