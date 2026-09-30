// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/workspace.dart';

part 'other_tabs_from_last_session_provider.g.dart';

/// Tabs from the previous session that were **not** auto-restored on launch.
///
/// On phone (`DeviceClass.phone` / `phoneLandscape`) WaveCrux honors the
/// workspace's auto-save but forces a single-tab layout — the most recent
/// active tab is the only one re-opened (see ARCHITECTURE.md §3.1.4). Any
/// additional tabs that lived in the workspace at quit are surfaced here so
/// the empty-canvas state can offer them under "Other tabs from your last
/// session" for one-tap opening.
///
/// On tablet and desktop this list stays empty — those device classes
/// restore every surviving tab directly.
///
/// Root-scope and keep-alive: populated once during the post-launch workspace
/// restore handshake in [WaveCruxApp._restoreFromWorkspace] and consumed by
/// [EmptyCanvasState]. Cleared when the user opens any of the entries (so it
/// stays one-shot per cold start).
@Riverpod(keepAlive: true)
class OtherTabsFromLastSession extends _$OtherTabsFromLastSession {
  @override
  List<WorkspaceTab> build() => const <WorkspaceTab>[];

  /// Replaces the list with [tabs]. Empty input clears the list.
  void set(List<WorkspaceTab> tabs) {
    state = List<WorkspaceTab>.unmodifiable(tabs);
  }

  /// Removes [tab] from the list, e.g. after the user taps the row and the
  /// tab is opened in the workspace.
  void remove(WorkspaceTab tab) {
    if (state.isEmpty) return;
    state = List<WorkspaceTab>.unmodifiable(
      state.where((t) => t.id != tab.id),
    );
  }

  /// Clears the list outright.
  void clear() {
    if (state.isEmpty) return;
    state = const <WorkspaceTab>[];
  }
}
