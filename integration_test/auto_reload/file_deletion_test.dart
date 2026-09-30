// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/auto_reload/file_deletion_test.dart
//
// File deletion notification.
//
// When the watched waveform file is deleted on disk, WaveCrux must surface a
// non-crashing notification (the `fileWatcherFileDeleted` snackbar) while
// keeping the already-loaded waveform data viewable in memory. No unhandled
// exception is thrown.
//
// Real filesystem events drive this test, so the deletion notification is
// polled with a capped loop rather than a fixed settle.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/core/router.dart' show rootScaffoldMessengerKey;
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('deleting the file notifies the user and keeps data viewable', (
    tester,
  ) async {
    final fixture = File(
      path_join(
        Directory.current.path,
        'verification',
        'fixtures',
        'vcd/scalar_basics.vcd',
      ),
    );
    final tmp = Directory.systemTemp.createTempSync(
      'wavecrux_autoreload_delete_',
    );
    final tmpVcd = File('${tmp.path}/live.vcd');
    try {
      fixture.copySync(tmpVcd.path);

      await loadFixtureVcdAbsolute(tester, tmpVcd.path);

      final tab = activeTabContainer(tester);
      final beforeCount = tab.read(signalVariablesMapProvider).length;
      expect(beforeCount, greaterThan(0));

      // Let the 2 s file-watch settle window expire before deleting so the
      // deletion event is not suppressed as a startup artifact.
      await tester.pump(const Duration(seconds: 3));

      tmpVcd.deleteSync();

      // Poll up to ~5 s for the deletion notification snackbar.
      final l10n = L10N.of(rootScaffoldMessengerKey.currentContext!);
      var notified = false;
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text(l10n.fileWatcherFileDeleted).evaluate().isNotEmpty) {
          notified = true;
          break;
        }
      }
      expect(
        notified,
        isTrue,
        reason: 'file deletion must surface a non-crashing notification',
      );

      // The in-memory waveform data is not lost: the source is still loaded
      // and the signal hierarchy is intact.
      expect(
        tab.read(waveformSourceProvider).value,
        isNotNull,
        reason: 'loaded waveform data must remain viewable after deletion',
      );
      expect(tab.read(signalVariablesMapProvider).length, beforeCount);

      expect(tester.takeException(), isNull);
    } finally {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    }
  });
}
