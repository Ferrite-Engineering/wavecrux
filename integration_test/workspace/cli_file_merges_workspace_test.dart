// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/cli_file_merges_workspace_test.dart
//
// Launching with a file argument (e.g. double-clicking a `.vcd` in Finder)
// while a saved multi-tab workspace exists must RESTORE the saved tabs and open
// the file as the active tab — non-destructive ("restore session + add file"),
// not a broken hybrid where the saved tabs surface as orphan chips that never
// load. Covers three launch shapes:
//
//   1. New file → saved tabs restored + the new file appended and active.
//   2. File already in the workspace → focused (de-duplicated), not opened a
//      second time.
//   3. `restoreTabsOnLaunch` disabled → the hydrated chips are reconciled away
//      and only the opened file shows.
//
// These exercise `_WaveCruxAppState._restoreFromWorkspace` (always runs now,
// gated by `restoreTabsOnLaunch`, de-dupes against CLI paths, defers focus to
// the CLI open) coordinated with `ViewerScreen._openInitialCliFiles` via the
// `startupReconcileProvider` barrier.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../helpers/app_driver.dart';

String _fixturePath(String relative) => [
  Directory.current.path,
  'verification',
  'fixtures',
  relative,
].join(Platform.pathSeparator);

/// Seeds a two-tab (`pathA`, `pathB`) workspace with `pathA` active.
Future<void> _seedTwoTabWorkspace(String pathA, String pathB) async {
  final paneId = PaneId.generate();
  final tabAId = TabId.generate();
  final tabBId = TabId.generate();
  final seed = Workspace(
    tabs: [
      buildWorkspaceTab(
        id: tabAId,
        displayName: 'A',
        paneId: paneId,
        filePath: pathA,
      ),
      buildWorkspaceTab(
        id: tabBId,
        displayName: 'B',
        paneId: paneId,
        filePath: pathB,
      ),
    ],
    panes: [WorkspacePane(id: paneId, activeTabId: tabAId)],
    activePaneId: paneId,
  );
  await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).save(seed);
}

/// Pumps fixed frames until the tab list reaches [expected] (or the budget is
/// exhausted) — restore + the post-reconcile CLI open are post-frame async.
Future<void> _pumpUntilTabs(WidgetTester tester, int expected) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (rootContainer(tester).read(tabListProvider).length == expected) return;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  final pathA = _fixturePath('vcd/scalar_basics.vcd');
  final pathB = _fixturePath('vcd/vector_formats.vcd');
  final pathC = _fixturePath('vcd/deep_hierarchy.vcd');

  testWidgets(
    'launching with a NEW file restores the saved tabs and adds the file as '
    'the active tab',
    (tester) async {
      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(
        () => WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear(),
      );
      SharedPreferences.setMockInitialValues(
        {'settings.restoreTabsOnLaunch': true},
      );
      await _seedTwoTabWorkspace(pathA, pathB);

      await seedFirstLaunchAnswers();
      await bootstrap(args: [pathC]);
      await _pumpUntilTabs(tester, 3);

      final root = rootContainer(tester);
      final tabs = root.read(tabListProvider);
      expect(
        tabs.map((t) => t.filePath).toList(),
        equals([pathA, pathB, pathC]),
        reason: 'saved tabs restored, opened file appended — no orphan chips',
      );

      final activeId = root.read(activeTabIdProvider);
      final activeTab = tabs.firstWhere((t) => t.id == activeId);
      expect(
        activeTab.filePath,
        equals(pathC),
        reason: 'the file opened on the CLI must be the active tab',
      );

      // The active (opened) file's source actually loads — not a blank tab.
      final activeContainer = root
          .read(tabContainerManagerProvider)
          .containerFor(activeId);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (activeContainer.read(waveformSourceProvider).value != null) break;
      }
      expect(activeContainer.read(waveformSourceProvider).value, isNotNull);
    },
  );

  testWidgets(
    'launching with a file ALREADY in the workspace focuses it instead of '
    'opening a duplicate',
    (tester) async {
      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(
        () => WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear(),
      );
      SharedPreferences.setMockInitialValues(
        {'settings.restoreTabsOnLaunch': true},
      );
      await _seedTwoTabWorkspace(pathA, pathB);

      // Re-open pathB, which is already the second saved tab.
      await seedFirstLaunchAnswers();
      await bootstrap(args: [pathB]);
      await _pumpUntilTabs(tester, 2);
      // Give the de-dup activation a few extra frames to settle.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final root = rootContainer(tester);
      final tabs = root.read(tabListProvider);
      expect(
        tabs.map((t) => t.filePath).toList(),
        equals([pathA, pathB]),
        reason: 'no duplicate tab for the re-opened file',
      );

      final activeId = root.read(activeTabIdProvider);
      expect(
        tabs.firstWhere((t) => t.id == activeId).filePath,
        equals(pathB),
        reason: 'the re-opened file is focused',
      );
    },
  );

  testWidgets(
    'with restoreTabsOnLaunch disabled, launching with a file shows only that '
    'file (hydrated chips reconciled away)',
    (tester) async {
      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(
        () => WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear(),
      );
      SharedPreferences.setMockInitialValues(
        {'settings.restoreTabsOnLaunch': false},
      );
      await _seedTwoTabWorkspace(pathA, pathB);

      await seedFirstLaunchAnswers();
      await bootstrap(args: [pathC]);
      await _pumpUntilTabs(tester, 1);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final root = rootContainer(tester);
      final tabs = root.read(tabListProvider);
      expect(
        tabs.map((t) => t.filePath).toList(),
        equals([pathC]),
        reason: 'restore disabled → saved chips closed, only the file remains',
      );
    },
  );
}
