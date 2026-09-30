// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/session/auto_reload_test.dart
//
// Auto-reload on file change integration test.
//
// Verifies that when the loaded waveform file is modified on disk, the
// app shows the "Reload" snackbar action and successfully reloads after
// the user taps it.

import 'dart:io';

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('file change triggers reload snackbar', (tester) async {
    // Copy the fixture to a temp file so we can modify it in place.
    final fixture = File(
      path_join(
        Directory.current.path,
        'verification',
        'fixtures',
        'vcd/scalar_basics.vcd',
      ),
    );
    final tmp = Directory.systemTemp.createTempSync('wavecrux_autoreload_');
    final tmpVcd = File('${tmp.path}/live.vcd');
    try {
      fixture.copySync(tmpVcd.path);

      // Load the temporary VCD — this starts the file watcher.
      await loadFixtureVcdAbsolute(tester, tmpVcd.path);

      // Force prompt mode rather than relying on persisted settings (a prior
      // run on this machine may have set auto/off), so the file-change
      // MaterialBanner with its "Reload" action is shown instead of a silent
      // reload or nothing.
      final root = rootContainer(tester);
      for (var i = 0; i < 30; i++) {
        if (root.read(appSettingsProvider).value != null) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      await root
          .read(appSettingsProvider.notifier)
          .setAutoReloadMode(AutoReloadMode.prompt);

      // Wait for the 2-second settle window to expire so the watcher is active.
      await tester.pump(const Duration(seconds: 3));

      // Overwrite the file with a slightly modified version. The watcher fires
      // when mtime changes; copying the same bytes but with an appended blank
      // comment is sufficient to trigger the event while keeping valid VCD.
      final original = fixture.readAsStringSync();
      tmpVcd.writeAsStringSync('$original\n\$comment modified \$end\n');

      // Poll up to 8 seconds for the snackbar "Reload" action to appear.
      var found = false;
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Reload').evaluate().isNotEmpty) {
          found = true;
          break;
        }
      }
      expect(found, isTrue, reason: 'Expected "Reload" snackbar action');

      // Tap the Reload action and wait for the waveform to re-parse.
      // reloadCurrentFile() reopens the file via WaveformSourceNotifier.openFile,
      // which installs a NEW source instance on the background isolate (no
      // frames scheduled until it lands) — poll for that fresh instance rather
      // than burning a fixed real-time budget.
      final sourceBeforeReload = activeTabContainer(
        tester,
      ).read(waveformSourceProvider).value;
      await tester.tap(find.text('Reload'));
      await pumpUntil(tester, () {
        final src = activeTabContainer(tester).read(waveformSourceProvider);
        return src.value != null && !identical(src.value, sourceBeforeReload);
      });
      await tester.pumpAndSettle();

      // Verify no unhandled exceptions occurred during reload.
      expect(tester.takeException(), isNull);
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });
}
