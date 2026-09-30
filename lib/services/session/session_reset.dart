// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/features/workspace/providers/workspace_provider.dart'
    show WorkspaceService;
import 'package:wavecrux/services/session/last_session_service.dart';

/// Clears **all** persisted session/workspace restore state from disk:
///
/// 1. the auto-managed `workspace.json` document (and its `.tmp` sibling),
/// 2. every per-tab session sidecar under `{appSupportDir}/sessions/`, and
/// 3. the legacy `last_session.json` manifest.
///
/// This is the single data path behind both the `--reset` CLI flag (called
/// from `bootstrap()` before the widget tree exists) and the in-app "Reset
/// workspace & sessions" action (Settings → Advanced and the startup recovery
/// banner). Keeping one helper guarantees the CLI and UI resets clear exactly
/// the same artifacts.
///
/// Deliberately does **not** touch app settings, the keymap, recent-files /
/// recent-workspaces history, or any waveform file the user opened — `--reset`
/// recovers from a wedged *session*, it is not a factory reset.
///
/// Every step is best-effort and non-fatal (each underlying service swallows
/// and logs its own I/O errors); a no-op on web, where none of these files
/// exist. Pass [lastSessionService] to override the manifest service in tests.
Future<void> resetPersistedSessionData(
  WorkspaceService workspaceService, {
  LastSessionService lastSessionService = const LastSessionService(),
}) async {
  await workspaceService.clear();
  await workspaceService.clearAllSidecars();
  await lastSessionService.clear();
}
