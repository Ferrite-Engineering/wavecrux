// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/workspace/providers/recent_workspaces_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Type signature for the OS save-file picker. Tests inject a stub so the
/// flow can be exercised without touching `FilePicker.platform`.
typedef SaveWorkspacePicker =
    Future<String?> Function({
      required String dialogTitle,
      required String fileName,
    });

/// Default picker backed by `FilePicker.saveFile`. Restricts to the
/// `.wavecrux-workspace` extension so the user does not accidentally
/// overwrite a per-tab `.wavecrux` session export with a multi-tab payload.
Future<String?> defaultSaveWorkspacePicker({
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

/// Opens a save dialog and writes the current workspace to the picked path
/// as a named `.wavecrux-workspace` document.
///
/// Unlike [runNewWorkspaceCommand], this command **does not** reset the
/// workspace — the active tabs and panes continue to be the working state.
/// "Save Workspace As…" is the share / version-control flow; the auto-saved
/// `workspace.json` remains the working file.
///
/// Returns `true` on success, `false` for any other outcome (user cancel or
/// save failure). Save failures surface a non-blocking snackbar so the user
/// can retry; the existing workspace remains intact.
Future<bool> runSaveWorkspaceAsCommand({
  required BuildContext context,
  required WidgetRef ref,
  SaveWorkspacePicker picker = defaultSaveWorkspacePicker,
}) async {
  final l10n = L10N.of(context);
  final container = ProviderScope.containerOf(context);

  final path = await picker(
    dialogTitle: l10n.saveWorkspaceAsPickerTitle,
    fileName: 'workspace.wavecrux-workspace',
  );
  if (path == null) return false;

  final saveError = await _saveUsingContainer(container, path);
  if (saveError != null) {
    if (context.mounted) {
      showCruxErrorSnack(context, l10n.saveWorkspaceAsError(saveError));
    }
    return false;
  }
  await container.read(recentWorkspacesProvider.notifier).addWorkspace(path);
  container
      .read(telemetryServiceProvider)
      .record(TelemetryEvent('workspace.named.saved'));
  if (context.mounted) {
    showCruxInfoSnack(context, l10n.saveWorkspaceAsSuccess);
  }
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

/// Test seam: snapshot the current workspace to a named path. Returns the
/// failure reason or `null` on success.
@visibleForTesting
Future<String?> saveWorkspaceAsForContainer(
  ProviderContainer container,
  String path,
) => _saveUsingContainer(container, path);
