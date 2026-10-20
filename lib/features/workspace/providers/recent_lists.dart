// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:wavecrux/services/platform/security_scoped_bookmark_service.dart';

/// Matches a per-tab session sidecar file at `…/sessions/{tab-uuid}.<ext>`.
/// The tab id is a UUID v4 produced by `crux_workspace`'s `TabId.generate`,
/// so the basename is always exactly 36 hex+dash chars followed by an
/// extension. The workspace restore path passes these internal sidecar paths
/// through the session loader, which would otherwise record them as opened and
/// fill the Welcome screen's Recent Files list with UUID-named entries the
/// user never opened.
///
/// The extension is matched generically (`.<alnum>`) rather than pinned to
/// `.wavecrux`: the auto-save writes the sidecar through the base
/// `crux_workspace` `WorkspaceService`, whose default sidecar extension is
/// `.json` (not the product's `.wavecrux`), so the actual files on disk are
/// `{uuid}.json`. Pinning the pattern to `.wavecrux` silently failed to match
/// the real `.json` files and let them leak back into the list.
final RegExp _kSidecarPathPattern = RegExp(
  r'(?:/|\\)sessions(?:/|\\)'
  r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
  r'\.[A-Za-z0-9]+$',
);

// ignore_for_file: unnecessary_raw_strings  // path-separator escapes

/// Returns `true` when [path] looks like a per-tab session sidecar file
/// (`…/sessions/{uuid}.<ext>`, e.g. `{uuid}.json`).
bool isInternalSessionSidecarPath(String path) =>
    _kSidecarPathPattern.hasMatch(path);

/// The waveform and session files the user recently opened, most recent first.
///
/// Stored under the `recent_files` preference key WaveCrux has always used, so
/// a saved list survives. A per-tab session sidecar is never recorded, and one
/// found in a stored list is cleaned out of it. Removing an entry also drops
/// its security-scoped bookmark.
final CruxRecentList recentFiles = CruxRecentList(
  name: 'recentFiles',
  store: (_) => const CruxPrefsRecentStore('recent_files'),
  accepts: (path) => !isInternalSessionSidecarPath(path),
  onRemoved: SecurityScopedBookmarkService.removeBookmark,
);

/// The named workspaces (`.wavecrux-workspace`) the user recently opened or
/// saved, most recent first.
///
/// Distinct from [recentFiles] so the two surfaces do not contaminate each
/// other: opening a `.wavecrux-workspace` does not push a `.fst` out of the
/// recent-files list, and vice versa.
final CruxRecentList recentWorkspaces = CruxRecentList(
  name: 'recentWorkspaces',
  store: (_) => const CruxPrefsRecentStore('recent_workspaces'),
);
