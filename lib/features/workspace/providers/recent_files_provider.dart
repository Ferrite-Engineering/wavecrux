// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/services/platform/security_scoped_bookmark_service.dart';

part 'recent_files_provider.g.dart';

const _kRecentFilesKey = 'recent_files';
const _kMaxRecentFiles = 10;

/// Matches a per-tab session sidecar file at `…/sessions/{tab-uuid}.<ext>`.
/// The tab id is a UUID v4 produced by `crux_workspace`'s `TabId.generate`,
/// so the basename is always exactly 36 hex+dash chars followed by an
/// extension. Issue 29: the workspace restore path passed these internal
/// sidecar paths through [`SessionNotifier.loadFromPath`], which then
/// forwarded them to [`RecentFilesNotifier.addFile`], populating the Welcome
/// screen Recent Files list with UUID-named entries that the user never
/// opened.
///
/// The extension is matched generically (`.<alnum>`) rather than pinned to
/// `.wavecrux`: the auto-save writes the sidecar through the base
/// `crux_workspace` `WorkspaceService`, whose default sidecar extension is
/// `.json` (not the product's `.wavecrux`), so the actual files on disk are
/// `{uuid}.json`. Pinning the pattern to `.wavecrux` (the original Issue 29
/// fix) silently failed to match the real `.json` files and let them leak
/// back into the list — see the regression this guards against.
final RegExp _kSidecarPathPattern = RegExp(
  r'(?:/|\\)sessions(?:/|\\)'
  r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
  r'\.[A-Za-z0-9]+$',
);

// ignore_for_file: unnecessary_raw_strings  // path-separator escapes

/// Returns `true` when [path] looks like a per-tab session sidecar file
/// (`…/sessions/{uuid}.<ext>`, e.g. `{uuid}.json`). Exposed for tests.
@visibleForTesting
bool isInternalSessionSidecarPath(String path) =>
    _kSidecarPathPattern.hasMatch(path);

/// Persists and exposes the list of recently opened waveform file paths.
///
/// Most-recently-opened file is always first. Duplicates are deduplicated by
/// moving the existing entry to the top. The list is capped at
/// [_kMaxRecentFiles] entries and backed by [SharedPreferences]. Consumed by
/// the workspace empty-canvas state and by viewer session-open flows.
///
/// Sidecar guard: [addFile] silently rejects per-tab session sidecar paths
/// (`{appSupportDir}/sessions/{uuid}.<ext>`) so workspace restore — which
/// calls [`SessionNotifier.loadFromPath`] with the sidecar path to rehydrate
/// per-tab state — does not pollute the list with internal storage URLs the
/// user never opened (Issue 29). [build] additionally filters any
/// previously-persisted sidecar paths off the list and rewrites the cleaned
/// list back to disk, so users who already accumulated UUID entries get a
/// one-shot cleanup on next launch.
@Riverpod(keepAlive: true)
class RecentFilesNotifier extends _$RecentFilesNotifier {
  @override
  Future<List<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kRecentFilesKey) ?? const <String>[];
    final cleaned = [
      for (final p in raw)
        if (!isInternalSessionSidecarPath(p)) p,
    ];
    if (cleaned.length != raw.length) {
      await prefs.setStringList(_kRecentFilesKey, cleaned);
    }
    return cleaned;
  }

  /// Prepends [path] to the list, deduplicates, and persists. Silently
  /// no-ops for paths that match the internal per-tab session sidecar
  /// pattern (`…/sessions/{uuid}.<ext>`, Issue 29).
  Future<void> addFile(String path) async {
    if (isInternalSessionSidecarPath(path)) return;
    final current = state.value ?? [];
    final updated = [
      path,
      ...current.where((p) => p != path),
    ].take(_kMaxRecentFiles).toList();
    await _persist(updated);
  }

  /// Removes [path] from the list, its bookmark, and persists.
  Future<void> removeFile(String path) async {
    final current = state.value ?? [];
    final updated = current.where((p) => p != path).toList();
    await SecurityScopedBookmarkService.removeBookmark(path);
    await _persist(updated);
  }

  Future<void> _persist(List<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kRecentFilesKey, paths);
    state = AsyncData(paths);
  }
}
