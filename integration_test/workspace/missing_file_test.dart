// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/missing_file_test.dart
//
// Missing-file recovery on workspace restore.
//
// The user opens two waveform files in separate tabs, quits, then
// deletes one of the files (or simulates the file disappearing by
// pointing the workspace at a path that no longer exists). On the
// next launch the restoration path must:
//
//   1. Open the surviving file as a tab.
//   2. Drop the missing-file tab from the live workspace without
//      crashing.
//   3. Surface a non-blocking localized snackbar listing the missing
//      path so the user knows why one of their tabs vanished.
//
// Setup approach: rather than open a real fixture and then delete it
// mid-test (race conditions, leftover state on failure), we pre-seed
// `workspace.json` with two `WorkspaceTab` entries — one pointing at a
// real fixture and one pointing at a path under the OS temp directory
// that has never existed. The restoration code's file-exists filter
// dispatches on `File(path).existsSync()`; a stable never-existed path
// is indistinguishable from a deleted-since-quit path from its point
// of view.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../helpers/workspace_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'workspace restore drops missing-file tabs, opens survivors, and surfaces a localized snackbar',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(() async {
        await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      });

      final existing = fixturePath('vcd/scalar_basics.vcd');
      expect(File(existing).existsSync(), isTrue);

      // Stable never-existed path under the OS temp dir. We deliberately do
      // NOT create it — the restore code's File.existsSync() filter is the
      // surface under test.
      final missingDir = Directory.systemTemp.createTempSync(
        'wavecrux_missing_file_',
      );
      addTearDown(() => missingDir.deleteSync(recursive: true));
      final missing = '${missingDir.path}/never_existed.vcd';
      expect(File(missing).existsSync(), isFalse);

      // Pre-seed workspace.json with two tabs (one survivor, one missing)
      // sharing one pane — matches the user's "quit-with-two-tabs, one
      // file later deleted on disk" scenario from §22.9.6.
      final paneId = PaneId.generate();
      final missingTabId = TabId.generate();
      final survivingTabId = TabId.generate();
      final seed = Workspace(
        tabs: [
          buildWorkspaceTab(
            id: missingTabId,
            displayName: 'never_existed.vcd',
            paneId: paneId,
            filePath: missing,
          ),
          buildWorkspaceTab(
            id: survivingTabId,
            displayName: 'scalar_basics.vcd',
            paneId: paneId,
            filePath: existing,
          ),
        ],
        panes: [WorkspacePane(id: paneId, activeTabId: missingTabId)],
        activePaneId: paneId,
      );
      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).save(seed);

      // Ensure restoration runs (default is true; set explicitly so the
      // test contract is obvious).
      SharedPreferences.setMockInitialValues({
        'settings.restoreTabsOnLaunch': true,
      });

      // Boot with no CLI files so the restoration path activates.
      await seedFirstLaunchAnswers();
      await bootstrap();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final root = rootContainer(tester);

      // Force-resolve settings so the post-frame restore callback runs.
      await root.read(appSettingsProvider.future);

      // Wait for the live tab list to settle at the survivor-only state.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (root.read(tabListProvider).length == 1) break;
      }

      // ----- Live tab list assertions -----
      final tabs = root.read(tabListProvider);
      expect(
        tabs,
        hasLength(1),
        reason:
            'missing-file tab must be dropped during restore; only the '
            'survivor opens',
      );
      expect(
        tabs.single.filePath,
        equals(existing),
        reason:
            'the survivor must be the still-existing fixture, not the '
            'deleted one',
      );
      expect(
        tabs.single.id,
        equals(survivingTabId),
        reason:
            'restore must preserve the persisted TabId so the per-tab '
            'sidecar still resolves',
      );

      // ----- Localized missing-file snackbar -----
      //
      // The single-missing-file case uses the `workspaceRestoreDroppedSingle`
      // l10n key (per `_restoreFromWorkspace`). Pump until the MaterialApp's
      // `Localizations` delegate completes its async load (`L10N.delegate`
      // is a Future that resolves over one or more frames), then locate the
      // SnackBar by the expected localized message text.
      //
      // CRITICAL: `Localizations.of(context, T)` walks UP the widget tree
      // from `context` looking for a Localizations inherited widget. The
      // `MaterialApp`'s own element is ABOVE the Localizations it creates
      // (Localizations is a descendant, not an ancestor) — using
      // `tester.element(find.byType(MaterialApp))` returns null because
      // the lookup never finds the Localizations widget. We need a
      // DESCENDANT of the MaterialApp. The Scaffold mounted inside the
      // running app sits below the Localizations widget, so its element is
      // a valid lookup target.
      L10N? l10n;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final scaffolds = find.byType(Scaffold);
        if (scaffolds.evaluate().isEmpty) continue;
        l10n = Localizations.of<L10N>(
          tester.element(scaffolds.first),
          L10N,
        );
        if (l10n != null) break;
      }
      expect(
        l10n,
        isNotNull,
        reason: 'L10N delegate must resolve before the snackbar assertion',
      );
      final expectedMessage = l10n!.workspaceRestoreDroppedSingle(missing);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(expectedMessage),
        ),
        findsOneWidget,
        reason:
            'restoration must surface a non-blocking, localized snackbar '
            'listing the missing path so the user knows why one of their '
            'tabs vanished',
      );

      // ----- No crash -----
      //
      // The takeException check is the explicit "no crash" assertion the
      // §22.9.6 contract requires; branding-asset codec errors are an
      // environment artifact and not a regression.
      final pendingException = tester.takeException();
      expect(
        pendingException == null ||
            pendingException.toString().contains('Unable to load asset'),
        isTrue,
        reason:
            'restore must not crash on a missing-file tab; only the '
            'headless branding-asset codec exception is permitted to bubble',
      );

      // Workspace document agrees with the live state: the missing tab is
      // not re-persisted on the next flush.
      await flushLiveWorkspace(root);
      final persisted = await WorkspaceService(
        codec: const WaveCruxWorkspaceCodec(),
      ).load();
      expect(persisted.tabs, hasLength(1));
      expect(persisted.tabs.single.filePath, equals(existing));
    },
  );
}
