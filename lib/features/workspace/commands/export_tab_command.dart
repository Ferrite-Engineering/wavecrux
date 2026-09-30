// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/session/session_service.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

/// Type signature for the OS save-file picker. Tests inject a stub.
typedef ExportTabPicker =
    Future<String?> Function({
      required String dialogTitle,
      required String fileName,
    });

/// Default picker backed by `FilePicker.saveFile`. Filters to the
/// `.wavecrux` extension so per-tab session exports cannot collide with the
/// named-workspace `.wavecrux-workspace` extension.
Future<String?> defaultExportTabPicker({
  required String dialogTitle,
  required String fileName,
}) => FilePicker.saveFile(
  // file_picker 12 requires bytes & writes the file; pass empty so it
  // only returns the chosen path and we write via our own service below.
  bytes: Uint8List(0),
  dialogTitle: dialogTitle,
  fileName: fileName,
  allowedExtensions: const ['wavecrux'],
  type: FileType.custom,
);

/// Opens a save dialog and writes the active tab's full viewer state to the
/// picked path as a `.wavecrux` session-export file.
///
/// Distinct from "Save Workspace As…" (which captures the multi-tab arrangement
/// as a `.wavecrux-workspace` document): "Export Tab as Session…" produces a
/// single-tab document for sharing one debug session with a colleague.
///
/// On success, updates the active tab's `sessionFilePath` so subsequent
/// exports can default to the same destination, and surfaces a non-blocking
/// success snackbar. On failure the existing tab state is left untouched.
///
/// Returns `true` on success, `false` for user cancel or save failure.
Future<bool> runExportTabCommand({
  required BuildContext context,
  required WidgetRef ref,
  TabId? tabId,
  ExportTabPicker picker = defaultExportTabPicker,
}) async {
  final l10n = L10N.of(context);
  final container = ProviderScope.containerOf(context);

  // The explicit `TabId` annotation narrows `TabId? ?? TabId` from the
  // analyzer's `TabId?` inference back to `TabId` so the callee accepts it.
  // ignore: omit_local_variable_types
  final TabId targetTabId = tabId ?? container.read(activeTabIdProvider);
  final tabs = container.read(tabListProvider);
  if (!tabs.any((t) => t.id == targetTabId)) return false;

  final path = await picker(
    dialogTitle: l10n.exportTabAsSessionPickerTitle,
    fileName: 'session.wavecrux',
  );
  if (path == null) return false;

  final error = await exportTabForContainer(container, targetTabId, path);
  if (error != null) {
    if (context.mounted) {
      showCruxErrorSnack(context, l10n.sessionSaveError(error));
    }
    return false;
  }
  container
      .read(telemetryServiceProvider)
      .record(TelemetryEvent('tab.exported'));
  if (context.mounted) {
    showCruxInfoSnack(context, l10n.sessionSaveSuccess);
  }
  return true;
}

/// Test seam (and shared implementation): exports the tab identified by
/// [tabId] to [path] using the tab's own [ProviderContainer] for the
/// snapshot. Returns the failure reason or `null` on success.
///
/// Per-tab containers (ARCHITECTURE.md §6.4) own every provider whose state
/// needs to be captured — signals, cursors, markers, zoom, panel layout,
/// stage workspace, translate filters. The export pipes through the same
/// [SessionService.saveSession] path the in-tab "Save Session As…" affordance
/// uses; only the entry point differs (the workspace pivot renames the
/// surface, not the underlying serializer).
@visibleForTesting
Future<String?> exportTabForContainer(
  ProviderContainer container,
  TabId tabId,
  String path,
) async {
  final tcm = container.read(tabContainerManagerProvider);
  final tabContainer = tcm.containerFor(tabId);
  try {
    await tabContainer.read(sessionProvider.notifier).saveToPath(path);
  } on SessionSaveException catch (e) {
    return e.reason;
  } on Object catch (e) {
    return e.toString();
  }

  // Stamp the tab's sessionFilePath so subsequent exports default to the same
  // path (the field the derived WavecruxTab view surfaces).
  await container.wavecruxWorkspace.updateTab(
    tabId,
    sessionFilePath: path,
  );
  return null;
}
