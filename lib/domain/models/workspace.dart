// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// WaveCrux-side adapter for the cross-suite `crux_workspace` package.
///
/// WaveCrux is the
/// reference adopter: the canonical `Workspace`, `WorkspaceTab`,
/// `WorkspacePane`, schema-version constant, and structural exception
/// types live in `package:crux_workspace/crux_workspace.dart`. This file
/// used to define them locally; it is now a thin shim that:
///
/// 1. Re-exports the structural symbols from the package.
/// 2. Defines `Workspace` and `WorkspaceTab` as WaveCrux-specific aliases
///    of the package's generic forms, binding the payload type parameter
///    to [WaveCruxTabPayload].
/// 3. Adds an extension on `WorkspaceTab` exposing convenience getters for
///    the payload fields (`tab.filePath`, `tab.sessionExportPath`) so
///    existing consumer call sites continue compiling without churn.
/// 4. Exposes [buildWorkspaceTab] — a small ergonomic factory that takes
///    `filePath` / `sessionExportPath` as top-level named parameters and
///    builds the `WaveCruxTabPayload` internally, mirroring the
///    WaveCrux-style call sites that predate the migration.
///
/// A follow-on cleanup pass can remove the shim once consumers have moved
/// to construct payloads directly.
library;

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:wavecrux/domain/models/wavecrux_tab_payload.dart';

export 'package:crux_workspace/crux_workspace.dart'
    show
        PaneId,
        TabId,
        WorkspaceInvariantException,
        WorkspacePane,
        WorkspaceRecovery,
        WorkspaceSchemaVersionException,
        kWorkspaceSchemaVersion;

/// WaveCrux-specific [crux.Workspace] alias. Binds the package generic to
/// [WaveCruxTabPayload] so consumers refer to a single concrete type.
typedef Workspace = crux.Workspace<WaveCruxTabPayload>;

/// WaveCrux-specific [crux.WorkspaceTab] alias. The package's generic
/// constructor takes the payload directly; use [buildWorkspaceTab] for an
/// ergonomic constructor that accepts `filePath` and `sessionExportPath`
/// as top-level named parameters.
typedef WorkspaceTab = crux.WorkspaceTab<WaveCruxTabPayload>;

/// Constructs a [WorkspaceTab] from the WaveCrux-flavored field set.
/// Replaces the pre-migration call pattern
/// `WorkspaceTab(id: ..., displayName: ..., paneId: ..., filePath: ...,
/// sessionExportPath: ...)` which referenced WaveCrux's local class.
WorkspaceTab buildWorkspaceTab({
  required crux.TabId id,
  required String displayName,
  required crux.PaneId paneId,
  String? filePath,
  String? sessionFilePath,
  String? sessionExportPath,
  bool isDetached = false,
}) => WorkspaceTab(
  id: id,
  displayName: displayName,
  paneId: paneId,
  payload: WaveCruxTabPayload(
    filePath: filePath,
    sessionFilePath: sessionFilePath,
    sessionExportPath: sessionExportPath,
    isDetached: isDetached,
  ),
);

/// Convenience accessor on a WaveCrux-typed [WorkspaceTab].
///
/// Surfaces the payload's `filePath` as if it were a top-level field of the
/// tab, so consumers read `tab.filePath` rather than `tab.payload.filePath`.
extension WaveCruxWorkspaceTabAccessors on WorkspaceTab {
  /// The absolute path of the waveform file backing the tab. `null` for
  /// tabs not yet bound to a file.
  String? get filePath => payload.filePath;
}
