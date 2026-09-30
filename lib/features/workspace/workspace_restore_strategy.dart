// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/workspace.dart';

/// Decision returned by [planWorkspaceRestore] — which tabs should be
/// re-opened in the workspace, and which (if any) should be parked in
/// [otherTabsFromLastSessionProvider] for one-tap reopening from the
/// empty-canvas state.
class WorkspaceRestorePlan {
  const WorkspaceRestorePlan({
    required this.tabsToOpen,
    required this.otherTabs,
  });

  /// Tabs that should be opened immediately as workspace tabs.
  final List<WorkspaceTab> tabsToOpen;

  /// Tabs that should be exposed to the empty-canvas state for one-tap
  /// reopening, surfaced under "Other tabs from your last session".
  final List<WorkspaceTab> otherTabs;
}

/// Computes the restore plan for [surviving] (the tabs whose files still
/// exist on disk) under the given device class and workspace metadata.
///
/// Phone single-tab fallback (ARCHITECTURE.md §3.1.4): on
/// [DeviceClass.phone] / [DeviceClass.phoneLandscape] with more than one
/// surviving tab, returns the most recently active tab as the only
/// [tabsToOpen] entry and parks the rest in [otherTabs]. Tablet and desktop
/// classes restore every surviving tab unconditionally.
///
/// Pure Dart — no Flutter imports, no Riverpod refs. This keeps the
/// device-class branching decision in one easily-unit-testable place; the
/// `_restoreFromWorkspace` glue in `app.dart` is just an adapter that wires
/// providers into this function.
WorkspaceRestorePlan planWorkspaceRestore({
  required DeviceClass deviceClass,
  required List<WorkspaceTab> surviving,
  required TabId? activeTabId,
  required PaneId activePaneId,
}) {
  final isPhone = deviceClass.isPhoneClass;
  if (!isPhone || surviving.length <= 1) {
    return WorkspaceRestorePlan(
      tabsToOpen: List<WorkspaceTab>.unmodifiable(surviving),
      otherTabs: const <WorkspaceTab>[],
    );
  }

  WorkspaceTab? primary;
  if (activeTabId != null) {
    for (final t in surviving) {
      if (t.id == activeTabId) {
        primary = t;
        break;
      }
    }
  }
  primary ??= surviving.first;

  final others = <WorkspaceTab>[];
  for (final t in surviving) {
    if (t.id != primary.id) others.add(t);
  }
  return WorkspaceRestorePlan(
    tabsToOpen: List<WorkspaceTab>.unmodifiable([primary]),
    otherTabs: List<WorkspaceTab>.unmodifiable(others),
  );
}
