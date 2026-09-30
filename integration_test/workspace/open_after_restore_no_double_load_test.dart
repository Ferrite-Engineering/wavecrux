// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/open_after_restore_no_double_load_test.dart
//
// Regression: opening a file AFTER a workspace restore must not trigger a
// second, concurrent waveform load.
//
// The deferred-load listener installed by `_WaveCruxAppState._restoreFromWorkspace`
// (`ref.listenManual(activeTabIdProvider, …)`) exists only to lazily load the
// RESTORED tabs the first time the user visits them. A tab opened during the
// session (File→Open, CLI, recent files) is loaded by its own open path, which
// calls `waveformSourceProvider.notifier.openFile` right after
// `wavecruxWorkspace.openFile` creates AND activates the new tab.
//
// The activation fires the listener. Before the fix the listener re-entered
// `_ensureTabLoaded` for that brand-new tab — and because the open path had not
// yet flipped the source to `AsyncLoading`, the `source.isLoading` guard still
// saw `AsyncData(null)` and started a SECOND load on the same per-tab notifier.
// Two concurrent `openFile`s share the notifier's `_loadToken` / `_pendingSource`
// / `_activeSource` and tear down each other's in-flight wellen isolate, which
// can strand the surviving load in `AsyncLoading` forever (spinner never clears).
//
// The fix scopes the listener to `restoredPaths` only. This test asserts the
// listener does NOT auto-load a newly-opened (non-restored) tab: after
// `wavecruxWorkspace.openFile` creates + activates the tab, its source stays at
// `AsyncData(null)` until the opener loads it — proving exactly one load occurs.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Seeds a single-tab workspace (so the deferred-load listener is installed).
Future<void> _seedOneTabWorkspace(String path) async {
  final paneId = PaneId.generate();
  final tabId = TabId.generate();
  final seed = Workspace(
    tabs: [
      buildWorkspaceTab(
        id: tabId,
        displayName: 'A',
        paneId: paneId,
        filePath: path,
      ),
    ],
    panes: [WorkspacePane(id: paneId, activeTabId: tabId)],
    activePaneId: paneId,
  );
  await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).save(seed);
}

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
  final pathC = _fixturePath('vcd/vector_formats.vcd');

  testWidgets(
    'opening a new file after restore is loaded once by its opener — the '
    'deferred-load listener does not start a second concurrent load',
    (tester) async {
      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(
        () => WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear(),
      );
      SharedPreferences.setMockInitialValues(
        {'settings.restoreTabsOnLaunch': true},
      );
      await _seedOneTabWorkspace(pathA);

      // Normal cold start (no CLI file): restore runs, loads tab A, and installs
      // the activeTabIdProvider deferred-load listener.
      await seedFirstLaunchAnswers();
      await bootstrap();
      await _pumpUntilTabs(tester, 1);

      final root = rootContainer(tester);
      final restoredId = root.read(activeTabIdProvider);
      final restoredContainer = root
          .read(tabContainerManagerProvider)
          .containerFor(restoredId);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (restoredContainer.read(waveformSourceProvider).value != null) break;
      }
      expect(
        restoredContainer.read(waveformSourceProvider).value,
        isNotNull,
        reason: 'the restored tab loads via the deferred listener as before',
      );

      // Open a NEW file the way the open flow starts: create + activate the
      // tab. The real `_openPath` then loads the source itself; we deliberately
      // do NOT here, to isolate the deferred listener's behaviour.
      final newTabId = await root.wavecruxWorkspace.openFile(pathC);
      // Give the activeTabIdProvider listener ample frames to (mis)fire.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final newContainer = root
          .read(tabContainerManagerProvider)
          .containerFor(newTabId);
      final src = newContainer.read(waveformSourceProvider);
      expect(
        src.isLoading,
        isFalse,
        reason:
            'the deferred-load listener must NOT auto-load a newly-opened, '
            'non-restored tab — that races the opener and can strand the load',
      );
      expect(
        src.value,
        isNull,
        reason: 'no source is loaded by the listener; the opener owns the load',
      );

      // And the normal open path still loads it correctly (exactly once).
      await newContainer.read(waveformSourceProvider.notifier).openFile(pathC);
      expect(
        newContainer.read(waveformSourceProvider).value,
        isNotNull,
        reason: 'the opener loads the new tab to completion',
      );
    },
  );
}
