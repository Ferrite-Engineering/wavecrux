// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/recent_workspaces_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

/// Type signature for the OS open-file picker. Tests inject a stub.
typedef OpenWorkspacePicker =
    Future<String?> Function({
      required String dialogTitle,
    });

/// Type signature for the "Open Workspace…" confirmation prompt. Tests
/// inject a stub that bypasses the UI surface.
typedef OpenWorkspaceConfirm = Future<bool> Function(BuildContext context);

/// Default picker backed by `FilePicker.pickFiles`. Filters to
/// `.wavecrux-workspace` so the user can't accidentally route a per-tab
/// `.wavecrux` session export through the workspace-open path.
Future<String?> defaultOpenWorkspacePicker({
  required String dialogTitle,
}) async {
  final picked = await FilePicker.pickFiles(
    dialogTitle: dialogTitle,
    allowedExtensions: const ['wavecrux-workspace'],
    type: FileType.custom,
  );
  return picked?.files.firstOrNull?.path;
}

/// Default confirm prompt for [runOpenWorkspaceCommand]. Shown only when the
/// current workspace has open tabs — loading a named workspace replaces all
/// of them, which is destructive enough to warrant a single confirmation.
Future<bool> defaultOpenWorkspaceConfirm(BuildContext context) async {
  final l10n = L10N.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.openWorkspaceDialogTitle),
      content: Text(l10n.openWorkspaceDialogBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.openWorkspaceDialogCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.openWorkspaceDialogConfirm),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Opens a `.wavecrux-workspace` file via [picker], optionally confirms with
/// the user when the current workspace has open tabs, and replaces the
/// active workspace with the loaded one.
///
/// Returns `true` when the workspace was replaced; `false` for user cancel,
/// invalid schema, or load failure. Load failures surface a non-blocking
/// snackbar; the existing workspace is left untouched.
Future<bool> runOpenWorkspaceCommand({
  required BuildContext context,
  required WidgetRef ref,
  OpenWorkspacePicker picker = defaultOpenWorkspacePicker,
  OpenWorkspaceConfirm confirm = defaultOpenWorkspaceConfirm,
}) async {
  final l10n = L10N.of(context);
  final container = ProviderScope.containerOf(context);

  final path = await picker(dialogTitle: l10n.openWorkspaceDialogTitle);
  if (path == null) return false;

  // Single confirmation when the current workspace is non-empty: loading
  // replaces the current workspace, after exactly one confirmation.
  final liveTabs = container.read(tabListProvider);
  if (liveTabs.isNotEmpty) {
    if (!context.mounted) return false;
    if (!await confirm(context)) return false;
  }

  final loadError = await openWorkspaceFromPathForContainer(container, path);
  if (loadError != null) {
    if (context.mounted) {
      showCruxErrorSnack(context, l10n.openWorkspaceError(loadError));
    }
    return false;
  }

  await container.read(recentWorkspacesProvider.notifier).addWorkspace(path);
  return true;
}

/// Shared implementation: replaces the workspace with the document at [path].
/// Returns the failure reason or `null` on success.
///
/// Steps:
/// 1. Read the file and decode JSON via [Workspace.fromJson] (which validates
///    the schema version and invariants).
/// 2. Close every live tab so the in-memory state matches the freshly-loaded
///    workspace.
/// 3. Replace the workspace via `replaceFromNamed` and flush so the next
///    auto-managed `workspace.json` write captures the new arrangement.
///
/// Public so the empty-canvas state's recent-workspaces row can short-circuit
/// the file-picker and confirmation dialog and jump straight to the load.
Future<String?> openWorkspaceFromPathForContainer(
  ProviderContainer container,
  String path,
) async {
  final Workspace next;
  try {
    final raw = await File(path).readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      return 'Workspace document root is not a JSON object';
    }
    next = Workspace.fromJson(decoded, const WaveCruxWorkspaceCodec());
  } on WorkspaceSchemaVersionException catch (e) {
    return e.toString();
  } on WorkspaceInvariantException catch (e) {
    return e.toString();
  } on FormatException catch (e) {
    return e.toString();
  } on FileSystemException catch (e) {
    return e.toString();
  } on Object catch (e) {
    return e.toString();
  }

  // Close every prior tab first so its per-tab session sidecar is cleaned up.
  // The tab list now derives from the workspace document, so [replaceFromNamed]
  // alone swaps the visible tabs — this loop only handles sidecar cleanup.
  final wsNotifier = container.wavecruxWorkspace;
  for (final id
      in container
          .read(tabListProvider)
          .map((t) => t.id)
          .toList(growable: false)) {
    await wsNotifier.closeTab(id);
  }

  await wsNotifier.replaceFromNamed(next);
  await wsNotifier.flushPendingSave();
  return null;
}
