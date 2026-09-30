// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'recent_workspaces_provider.g.dart';

const _kRecentWorkspacesKey = 'recent_workspaces';
const _kMaxRecentWorkspaces = 10;

/// Persists and exposes the list of recently opened named-workspace file paths
/// (`.wavecrux-workspace`).
///
/// Most-recently-opened path is always first. Duplicates collapse by moving
/// the existing entry to the top. The list is capped at
/// [_kMaxRecentWorkspaces] entries and backed by [SharedPreferences].
/// Consumed by the empty-canvas state's "Recent Workspaces" list and updated
/// by both the "Save Workspace As…" and "Open Workspace…" commands.
///
/// Distinct from `recentFilesProvider` (which holds waveform / session
/// files) so the two surfaces do not contaminate each other — opening a
/// `.wavecrux-workspace` should not push a `.fst` out of the recent-files
/// list, and vice versa.
@Riverpod(keepAlive: true)
class RecentWorkspacesNotifier extends _$RecentWorkspacesNotifier {
  @override
  Future<List<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kRecentWorkspacesKey) ?? const <String>[];
  }

  /// Prepends [path] to the list, deduplicating, capping, and persisting.
  Future<void> addWorkspace(String path) async {
    final current = state.value ?? const <String>[];
    final updated = [
      path,
      ...current.where((p) => p != path),
    ].take(_kMaxRecentWorkspaces).toList();
    await _persist(updated);
  }

  /// Removes [path] from the list and persists. No-op when not present.
  Future<void> removeWorkspace(String path) async {
    final current = state.value ?? const <String>[];
    final updated = current.where((p) => p != path).toList();
    if (updated.length == current.length) return;
    await _persist(updated);
  }

  /// Replaces the list with the empty list. Test seam and "Forget all
  /// recent workspaces" hook for a future settings affordance.
  Future<void> clear() async => await _persist(const <String>[]);

  Future<void> _persist(List<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kRecentWorkspacesKey, paths);
    state = AsyncData(paths);
  }
}
