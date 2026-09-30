// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/helpers/workspace_helpers.dart
//
// Shared helpers for the workspace round-trip integration tests
// (`integration_test/workspace/*`). The Flutter framework forbids invoking
// `runApp` more than once in a single test process, so every workspace
// round-trip test approximates "quit and relaunch" by flushing live
// in-memory state through the same code paths the production
// `AppLifecycleState.detached` handler invokes
// (`_WaveCruxAppState._flushWorkspace`) and then re-reading the persisted
// artifacts through fresh service instances. These helpers centralize the
// flush + fixture-path patterns so individual tests stay focused on the
// scenario-specific assertions.
//
// Re-exports [rootContainer] from `app_driver.dart` so existing imports
// of this file continue to expose it; new tests that don't need the
// workspace-specific helpers can import `app_driver.dart` directly.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';

export 'app_driver.dart'
    show
        pumpUntil,
        pumpUntilWaveformReady,
        rootContainer,
        seedFirstLaunchAnswers,
        suppressPlatformSemanticsLeak;

/// Resolves a path under `wavecrux/verification/fixtures/<relativePath>`.
///
/// Mirrors the helper inlined by every integration test in this tree;
/// kept here so workspace tests share a single implementation.
String fixturePath(String relative) => [
  Directory.current.path,
  'verification',
  'fixtures',
  relative,
].join(Platform.pathSeparator);

/// Mirrors the production `_WaveCruxAppState._flushWorkspace` lifecycle
/// hook: snapshots the live tab list (with each tab's own `paneId`
/// preserved — critical for split-pane round-trips) into a fresh
/// [Workspace] and writes it atomically through [WorkspaceService.save].
///
/// This is the only code path that pulls tabs out of [tabListProvider]
/// into the on-disk `workspace.json`: [WorkspaceNotifier.flushPendingSave]
/// writes the notifier's *own* in-memory state, which is not auto-synced
/// from the live tab list. Per-tab session sidecars
/// (`{appSupportDir}/sessions/{tabId}.wavecrux`) carry per-tab state
/// (cursor / zoom / signals / markers) and are flushed separately by
/// reading [sessionAutoSaveProvider] from each tab's container —
/// individual tests do this directly when they assert on per-tab state.
Future<void> flushLiveWorkspace(ProviderContainer root) async {
  final base = root.wavecruxWorkspace.current;
  final liveTabs = root.read(tabListProvider);
  final activeTabId = root.read(activeTabIdProvider);
  final wsTabs = <WorkspaceTab>[
    for (final t in liveTabs)
      if (t.filePath != null)
        buildWorkspaceTab(
          id: t.id,
          displayName: t.displayName,
          paneId: t.paneId,
          filePath: t.filePath,
          sessionExportPath: t.sessionFilePath,
        ),
  ];
  // Recompute per-pane active tab pointers so a pane whose previous
  // active tab is gone gets a sensible replacement instead of dangling
  // at a missing tab id (matches the production reconciliation).
  //
  // Empty siblings are dropped: a pane that holds no live tabs is not
  // written when at least one other pane is populated — persisting it
  // would surface as a phantom pane with no UI to close it on next
  // launch. When no pane holds any tab (canonical empty-canvas state)
  // we keep exactly one pane, preferring the active one.
  final populatedPanes = <WorkspacePane>[
    for (final p in base.panes)
      if (wsTabs.any((wt) => wt.paneId == p.id))
        () {
          final inPane = wsTabs.where((wt) => wt.paneId == p.id).toList();
          final activeForPane = inPane.any((wt) => wt.id == p.activeTabId)
              ? p.activeTabId
              : inPane.first.id;
          return WorkspacePane(id: p.id, activeTabId: activeForPane);
        }(),
  ];
  final List<WorkspacePane> panes;
  if (populatedPanes.isNotEmpty) {
    panes = populatedPanes;
  } else {
    final keepId = base.panes.any((p) => p.id == base.activePaneId)
        ? base.activePaneId
        : base.panes.first.id;
    panes = [WorkspacePane(id: keepId)];
  }
  final activePaneId = panes
      .firstWhere(
        (p) =>
            p.id == base.activePaneId && wsTabs.any((wt) => wt.paneId == p.id),
        orElse: () => panes.firstWhere(
          (p) => wsTabs.any((wt) => wt.paneId == p.id),
          orElse: () => panes.first,
        ),
      )
      .id;
  // The live `activeTabIdProvider` reflects the most-recently-focused tab
  // across the whole workspace, not within the active pane. After a
  // [WorkspaceNotifier.splitPane()] call focus shifts to the new pane
  // before the user moves any tab there, so the live `activeTabId` can
  // point at a tab that lives in a different pane than [activePaneId].
  // Override the active pane's `activeTabId` ONLY when the survivor lives
  // in that pane — otherwise leave whatever per-pane reconciliation in
  // [panes] above produced (the pane's own remembered `activeTabId` if
  // valid, else the first tab in the pane). Otherwise we'd construct a
  // [Workspace] that fails `Workspace._validate`'s "pane.activeTabId is
  // hosted in this pane" invariant and the workspace flush would throw.
  final survivor = wsTabs.any((wt) => wt.id == activeTabId)
      ? wsTabs.firstWhere((wt) => wt.id == activeTabId)
      : null;
  final survivingActiveForPane =
      (survivor != null && survivor.paneId == activePaneId)
      ? survivor.id
      : null;
  final panesWithActive = <WorkspacePane>[
    for (final p in panes)
      if (p.id == activePaneId && survivingActiveForPane != null)
        WorkspacePane(id: p.id, activeTabId: survivingActiveForPane)
      else
        p,
  ];
  await root
      .read(workspaceServiceProvider)
      .save(
        Workspace(
          tabs: wsTabs,
          panes: panesWithActive,
          activePaneId: activePaneId,
        ),
      );
}
