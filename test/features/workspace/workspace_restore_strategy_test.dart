// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/workspace/workspace_restore_strategy.dart';

WorkspaceTab _tab(
  PaneId paneId, {
  required String name,
  required String path,
  TabId? id,
}) => buildWorkspaceTab(
  id: id ?? TabId.generate(),
  displayName: name,
  paneId: paneId,
  filePath: path,
);

void main() {
  final paneId = PaneId.fromString('00000000-0000-0000-0000-000000000001');

  group('planWorkspaceRestore — desktop/tablet', () {
    test('restores every surviving tab on desktop with three tabs', () {
      final a = _tab(paneId, name: 'a.vcd', path: '/tmp/a.vcd');
      final b = _tab(paneId, name: 'b.vcd', path: '/tmp/b.vcd');
      final c = _tab(paneId, name: 'c.vcd', path: '/tmp/c.vcd');
      final plan = planWorkspaceRestore(
        deviceClass: DeviceClass.desktop,
        surviving: [a, b, c],
        activeTabId: c.id,
        activePaneId: paneId,
      );
      expect(plan.tabsToOpen, [a, b, c]);
      expect(plan.otherTabs, isEmpty);
    });

    test('restores every surviving tab on tablet with three tabs', () {
      final a = _tab(paneId, name: 'a.vcd', path: '/tmp/a.vcd');
      final b = _tab(paneId, name: 'b.vcd', path: '/tmp/b.vcd');
      final c = _tab(paneId, name: 'c.vcd', path: '/tmp/c.vcd');
      final plan = planWorkspaceRestore(
        deviceClass: DeviceClass.tablet,
        surviving: [a, b, c],
        activeTabId: a.id,
        activePaneId: paneId,
      );
      expect(plan.tabsToOpen, [a, b, c]);
      expect(plan.otherTabs, isEmpty);
    });
  });

  group('planWorkspaceRestore — phone single-tab fallback', () {
    test('phone with three tabs restores the most recent active tab as the '
        'only visible tab and exposes the rest as otherTabs', () {
      final a = _tab(paneId, name: 'a.vcd', path: '/tmp/a.vcd');
      final b = _tab(paneId, name: 'b.vcd', path: '/tmp/b.vcd');
      final c = _tab(paneId, name: 'c.vcd', path: '/tmp/c.vcd');
      final plan = planWorkspaceRestore(
        deviceClass: DeviceClass.phone,
        surviving: [a, b, c],
        activeTabId: b.id,
        activePaneId: paneId,
      );
      expect(plan.tabsToOpen, [b]);
      expect(plan.otherTabs, [a, c]);
    });

    test('phone with three tabs and no recorded active tab falls back to the '
        'first survivor as primary', () {
      final a = _tab(paneId, name: 'a.vcd', path: '/tmp/a.vcd');
      final b = _tab(paneId, name: 'b.vcd', path: '/tmp/b.vcd');
      final c = _tab(paneId, name: 'c.vcd', path: '/tmp/c.vcd');
      final plan = planWorkspaceRestore(
        deviceClass: DeviceClass.phone,
        surviving: [a, b, c],
        activeTabId: null,
        activePaneId: paneId,
      );
      expect(plan.tabsToOpen, [a]);
      expect(plan.otherTabs, [b, c]);
    });

    test('phone with a single surviving tab opens it without otherTabs', () {
      final a = _tab(paneId, name: 'a.vcd', path: '/tmp/a.vcd');
      final plan = planWorkspaceRestore(
        deviceClass: DeviceClass.phone,
        surviving: [a],
        activeTabId: a.id,
        activePaneId: paneId,
      );
      expect(plan.tabsToOpen, [a]);
      expect(plan.otherTabs, isEmpty);
    });

    test('phoneLandscape obeys the same single-tab rule as phone', () {
      final a = _tab(paneId, name: 'a.vcd', path: '/tmp/a.vcd');
      final b = _tab(paneId, name: 'b.vcd', path: '/tmp/b.vcd');
      final plan = planWorkspaceRestore(
        deviceClass: DeviceClass.phoneLandscape,
        surviving: [a, b],
        activeTabId: a.id,
        activePaneId: paneId,
      );
      expect(plan.tabsToOpen, [a]);
      expect(plan.otherTabs, [b]);
    });

    test('phone with active id that does not match any survivor falls back to '
        'first survivor', () {
      final a = _tab(paneId, name: 'a.vcd', path: '/tmp/a.vcd');
      final b = _tab(paneId, name: 'b.vcd', path: '/tmp/b.vcd');
      final stale = TabId.generate();
      final plan = planWorkspaceRestore(
        deviceClass: DeviceClass.phone,
        surviving: [a, b],
        activeTabId: stale,
        activePaneId: paneId,
      );
      expect(plan.tabsToOpen, [a]);
      expect(plan.otherTabs, [b]);
    });
  });

  group('planWorkspaceRestore — edge cases', () {
    test('empty survivor list produces empty plan', () {
      final plan = planWorkspaceRestore(
        deviceClass: DeviceClass.phone,
        surviving: const [],
        activeTabId: null,
        activePaneId: paneId,
      );
      expect(plan.tabsToOpen, isEmpty);
      expect(plan.otherTabs, isEmpty);
    });
  });
}
