// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/wavecrux_tab.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';

part 'tab_providers.g.dart';

// ── Tab model ────────────────────────────────────────────────────────────────
//
// [workspaceProvider] is the single source of truth for the open tabs, their
// order, names, pane assignment, and the active tab. [tabListProvider] and
// [activeTabIdProvider] are now thin **derived views** over that document so
// the many non-widget readers (action context, diagnostics drawer, issue
// reporter, collaboration, remote control, mobile memory guard) keep reading a
// simple `List<WavecruxTab>` / `TabId` without caring that the package's
// `PaneHost` / `ViewerTabBar` widgets render straight from the workspace.
//
// Every tab MUTATION flows through the WaveCrux convenience surface on
// [WaveCruxWorkspaceNotifier] (`openFile`, `openSession`, `newTab`,
// `updateTab`, `markDetached`, `closeTab`, `reorderTabs`, `moveTabToPane`),
// reachable via `ref.wavecruxWorkspace` for the WaveCrux-named ones.

/// Sentinel provider that identifies the owning tab of the nearest
/// [UncontrolledProviderScope].
///
/// This provider has **no default**. Reading it outside a tab-scoped
/// [ProviderContainer] is a programming error and throws [UnimplementedError].
///
/// Every tab container overrides this with the tab's own [TabId]:
/// ```dart
/// ProviderContainer(
///   parent: rootContainer,
///   overrides: [tabIdProvider.overrideWithValue(id)],
/// );
/// ```
@Riverpod(keepAlive: true)
// ignore: avoid_unused_parameters, riverpod_annotation requires a named ref parameter in functional providers
TabId tabId(Ref ref) {
  throw UnimplementedError(
    'tabIdProvider must be overridden in a per-tab ProviderContainer. '
    'Do not read tabIdProvider from the root scope.',
  );
}

/// The [TabId] of the currently focused (active) tab, derived from the
/// workspace's active pane.
///
/// When the workspace has no active tab (cold start with no restored tabs, or
/// after closing the last tab) the notifier holds a single stable synthetic
/// [TabId] that no rendered tab references — [ViewerScreen] checks
/// `tabListProvider.isEmpty` before consuming the active id so the synthetic
/// value is never dispatched against a real tab subtree.
@Riverpod(keepAlive: true)
class ActiveTabIdNotifier extends _$ActiveTabIdNotifier {
  TabId? _emptyFallback;

  @override
  TabId build() {
    final ws = ref.watch(workspaceProvider).value;
    final active = ws?.activePane.activeTabId;
    if (active != null) return active;
    return _emptyFallback ??= TabId.generate();
  }

  /// Activates [id] by focusing it in the workspace. No-op when [id] is not a
  /// real tab. The derived [build] picks up the new active id once the
  /// workspace mutation settles.
  void activate(TabId id) {
    final ws = ref.read(workspaceProvider).value;
    if (ws == null || !ws.tabs.any((t) => t.id == id)) return;
    unawaited(ref.read(workspaceProvider.notifier).setActiveTab(id));
  }
}

/// Ordered list of all open tabs, derived from [workspaceProvider].
///
/// Maps each persisted `WorkspaceTab<WaveCruxTabPayload>` to a [WavecruxTab]
/// view so existing consumers keep their field access (`filePath`,
/// `sessionFilePath`, `isDetached`, `paneId`, `isPlaceholder`). Empty before
/// the workspace hydrates and after the last tab closes — [ViewerScreen] then
/// renders the empty-canvas state.
@Riverpod(keepAlive: true)
List<WavecruxTab> tabList(Ref ref) {
  final ws = ref.watch(workspaceProvider).value;
  if (ws == null) return const [];
  return [
    for (final t in ws.tabs)
      WavecruxTab(
        id: t.id,
        displayName: t.displayName,
        filePath: t.payload.filePath,
        sessionFilePath: t.payload.sessionFilePath,
        isDetached: t.payload.isDetached,
        paneId: t.paneId,
      ),
  ];
}
