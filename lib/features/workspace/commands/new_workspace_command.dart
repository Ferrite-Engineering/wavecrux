// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Type signature for the OS save-file picker. Tests inject a stub instead
/// of touching `FilePicker.platform`.
typedef SaveAsPicker =
    Future<String?> Function({
      required String dialogTitle,
      required String fileName,
    });

/// Default [SaveAsPicker] backed by `FilePicker.saveFile`. Restricts
/// to the `.wavecrux-workspace` extension so the user does not accidentally
/// overwrite a per-tab `.wavecrux` session export with a multi-tab payload.
Future<String?> defaultSaveAsPicker({
  required String dialogTitle,
  required String fileName,
}) => FilePicker.saveFile(
  // file_picker 12 requires bytes & writes the file; pass empty so it
  // only returns the chosen path and we write via our own service below.
  bytes: Uint8List(0),
  dialogTitle: dialogTitle,
  fileName: fileName,
  allowedExtensions: const ['wavecrux-workspace'],
  type: FileType.custom,
);

/// Opens a save dialog, writes the current workspace to the picked path as a
/// named `.wavecrux-workspace` document, then empties the live tab list and
/// the auto-managed workspace. Cancelling the save dialog aborts without
/// resetting.
///
/// Returns `true` when both the save and reset succeed, `false` for any
/// other outcome (user cancel, save failure). Save failures surface a
/// non-blocking snackbar so the user can retry; the existing workspace
/// remains intact.
Future<bool> runNewWorkspaceCommand({
  required BuildContext context,
  required WidgetRef ref,
  SaveAsPicker picker = defaultSaveAsPicker,
}) async {
  final l10n = L10N.of(context);
  // Resolve container before the picker await so the BuildContext is not
  // used across the gap.
  final container = ProviderScope.containerOf(context);

  final path = await picker(
    dialogTitle: l10n.newWorkspaceSavePickerTitle,
    fileName: 'workspace.wavecrux-workspace',
  );
  if (path == null) return false;

  final saveError = await _saveUsingContainer(container, path);
  if (saveError != null) {
    if (context.mounted) {
      showCruxErrorSnack(context, l10n.newWorkspaceSaveError(saveError));
    }
    return false;
  }
  final telemetry = container.read(telemetryServiceProvider)
    ..record(TelemetryEvent('workspace.named.saved'));
  await _resetUsingContainer(container);
  // "New Workspace" semantically creates a fresh blank workspace after
  // archiving the prior one. workspace.reset is emitted by the underlying
  // notifier; workspace.created marks the user-visible new-workspace flow
  // distinct from a destructive reset.
  telemetry.record(TelemetryEvent('workspace.created'));
  return true;
}

Future<String?> _saveUsingContainer(
  ProviderContainer container,
  String path,
) async {
  final notifier = container.wavecruxWorkspace;
  final service = container.read(workspaceServiceProvider);
  try {
    await notifier.flushPendingSave();
    await service.saveToPath(path, notifier.current);
    return null;
  } on Object catch (e) {
    return e.toString();
  }
}

Future<void> _resetUsingContainer(ProviderContainer container) async {
  final notifier = container.wavecruxWorkspace;
  // Close each tab first so its per-tab session sidecar is cleaned up, then
  // reset the (now empty) workspace document.
  for (final id
      in container
          .read(tabListProvider)
          .map((t) => t.id)
          .toList(growable: false)) {
    await notifier.closeTab(id);
  }
  await notifier.reset();
  await notifier.flushPendingSave();
}

/// Test seam: snapshot the current workspace to a named path. Returns the
/// failure reason or `null` on success.
@visibleForTesting
Future<String?> saveCurrentWorkspaceToPathForContainer(
  ProviderContainer container,
  String path,
) => _saveUsingContainer(container, path);

/// Test seam: data-path reset for the new-workspace flow.
@visibleForTesting
Future<void> resetWorkspaceForNewWorkspaceContainer(
  ProviderContainer container,
) => _resetUsingContainer(container);
