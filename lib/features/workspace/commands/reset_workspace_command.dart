// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/session/session_reset.dart';

/// Confirmation prompt for [runResetWorkspaceCommand]. Default uses
/// `showDialog`; tests inject a stub that bypasses the UI surface.
typedef ResetWorkspaceConfirm = Future<bool> Function(BuildContext context);

/// Default confirm: the suite-standard destructive confirm
/// (`confirmCruxDestructiveAction` — Cancel TextButton, error-colored
/// verb-labeled FilledButton), which this dialog previously replicated by
/// hand.
Future<bool> defaultResetWorkspaceConfirm(BuildContext context) {
  final l10n = L10N.of(context);
  return confirmCruxDestructiveAction(
    context,
    title: l10n.resetWorkspaceDialogTitle,
    body: l10n.resetWorkspaceDialogBody,
    confirmLabel: l10n.resetWorkspaceDialogConfirm,
    cancelLabel: l10n.resetWorkspaceDialogCancel,
  );
}

/// Shows the Reset Workspace confirmation prompt and, on confirmation,
/// empties both the live tab list and the persisted workspace.
///
/// Returns `true` when the workspace was reset, `false` when the user
/// cancelled. Auto-save eliminated the user-visible "unsaved
/// changes" concept, so there is no save-vs-discard prompt — the
/// confirmation guards the destructive nature of the operation itself.
Future<bool> runResetWorkspaceCommand({
  required BuildContext context,
  required WidgetRef ref,
  ResetWorkspaceConfirm confirm = defaultResetWorkspaceConfirm,
}) async {
  // Resolve the container before the await so the BuildContext is not used
  // across the gap (we still need it for the confirm prompt itself).
  final container = ProviderScope.containerOf(context);
  if (!await confirm(context)) return false;
  await _resetUsingContainer(container);
  return true;
}

Future<void> _resetUsingContainer(ProviderContainer container) async {
  // Close every live tab first so its per-tab session sidecar is cleaned up,
  // then reset the workspace document to empty (which the derived tab list
  // immediately reflects as the empty-canvas state).
  final wsNotifier = container.wavecruxWorkspace;
  for (final id
      in container
          .read(tabListProvider)
          .map((t) => t.id)
          .toList(growable: false)) {
    await wsNotifier.closeTab(id);
  }

  await wsNotifier.reset();
  await wsNotifier.flushPendingSave();

  // Belt-and-suspenders: also clear the on-disk artifacts directly, so an
  // in-app reset wipes exactly what the `--reset` CLI flag does — the
  // auto-managed workspace.json, any orphaned per-tab sidecars, and the legacy
  // last_session.json manifest. The live reset above already empties the
  // in-memory workspace; this removes the files themselves (a future mutation
  // re-creates workspace.json on demand). No-op on web.
  await resetPersistedSessionData(container.read(workspaceServiceProvider));
}

/// Test seam: pure-Dart equivalent of the command's data path, against a
/// [ProviderContainer] instead of a widget tree.
@visibleForTesting
Future<void> resetWorkspaceStateForContainer(ProviderContainer container) =>
    _resetUsingContainer(container);
