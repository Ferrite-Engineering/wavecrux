// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/auto_reload/auto_reload_auto_mode_test.dart
//
// Auto-reload "Auto" mode silently reloads.
//
// With AutoReloadMode.auto selected, a change to the watched file on disk
// must reload the waveform WITHOUT showing the "Reload?" prompt banner. The
// extra signal introduced by the on-disk change appears in the signal tree,
// and the cursor position + per-signal display format of unchanged signals
// survive the reload (reloadCurrentFile snapshots and restores viewer state).
//
// session/auto_reload_test.dart covers the Prompt-mode reload offer; this
// test covers the finer-grained Auto mode.
//
// Real filesystem events drive this test, so the observable state (signal
// count, absence of the prompt banner) is polled with capped loops rather
// than a fixed settle.

import 'dart:io';

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/core/router.dart' show rootScaffoldMessengerKey;
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

import '../helpers/app_driver.dart';

// scalar_basics.vcd with one extra 1-bit signal (`enable`, idcode `$`). The
// original three signals (clk/rst/data) keep their idcodes and transitions so
// they read as "unchanged" across the reload.
const String _modifiedVcdWithExtraSignal = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 1 " rst $end
$var wire 8 # data $end
$var wire 1 $ enable $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
1"
b00000000 #
0$
$end
#10
1!
1$
#20
0!
#30
1!
0"
b00000001 #
#40
0!
#50
1!
b00000010 #
#60
0!
#70
1!
#80
0!
#90
1!
b11111111 #
#100
0!
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('Auto mode silently reloads and surfaces the extra signal', (
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
      'wavecrux_autoreload_auto_',
    );
    final tmpVcd = File('${tmp.path}/live.vcd');
    try {
      fixture.copySync(tmpVcd.path);

      await loadFixtureVcdAbsolute(tester, tmpVcd.path);

      final root = rootContainer(tester);
      final tab = activeTabContainer(tester);

      // Wait for the async settings load, then switch to Auto mode (the
      // "Settings → auto-reload = Auto" step, applied through the provider).
      for (var i = 0; i < 40; i++) {
        if (root.read(appSettingsProvider).value != null) break;
        await tester.pump(const Duration(milliseconds: 50));
      }
      await root
          .read(appSettingsProvider.notifier)
          .setAutoReloadMode(AutoReloadMode.auto);
      await tester.pump();
      expect(
        root.read(appSettingsProvider).value?.autoReloadMode,
        AutoReloadMode.auto,
      );

      final beforeCount = tab.read(signalVariablesMapProvider).length;
      expect(beforeCount, greaterThan(0));

      // Add clk to the viewer, give it a distinctive (non-default) format and
      // place the cursor — both must survive the silent reload.
      final clk = tab
          .read(signalVariablesMapProvider)
          .values
          .firstWhere((v) => v.name == 'clk');
      tab.read(signalGroupsProvider.notifier).addSignal(clk);
      tab
          .read(signalGroupsProvider.notifier)
          .setSignalFormatByRef(clk.signalRef, DisplayFormat.octal);
      tab.read(cursorStateProvider.notifier).placePrimary(50);
      await tester.pump();

      // Let the 2 s file-watch settle window expire before mutating the file
      // (otherwise the watcher suppresses the change as a startup artifact).
      await tester.pump(const Duration(seconds: 3));

      // Overwrite with the version that has one extra signal.
      tmpVcd.writeAsStringSync(_modifiedVcdWithExtraSignal);

      // Poll up to ~5 s for the silent reload to surface the extra signal.
      var reloaded = false;
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (tab.read(signalVariablesMapProvider).length > beforeCount) {
          reloaded = true;
          break;
        }
      }
      expect(
        reloaded,
        isTrue,
        reason: 'Auto mode must silently reload and show the extra signal',
      );

      // No reload prompt banner was shown in Auto mode.
      final l10n = L10N.of(rootScaffoldMessengerKey.currentContext!);
      expect(
        find.text(l10n.fileWatcherFileChanged),
        findsNothing,
        reason: 'Auto mode must not show the reload-prompt banner',
      );
      expect(find.text(l10n.fileWatcherReload), findsNothing);

      // Cursor preserved across the reload.
      expect(
        tab.read(cursorStateProvider).primaryCursorTime,
        50,
        reason: 'cursor time must survive the auto reload',
      );

      // Display-format preference for the unchanged clk signal preserved.
      final clkEntry = tab
          .read(signalGroupsProvider)
          .entries
          .firstWhere((e) => e.signalPath == 'top.clk');
      expect(
        clkEntry.format,
        DisplayFormat.octal,
        reason: 'per-signal display format must survive the auto reload',
      );

      expect(tester.takeException(), isNull);
    } finally {
      // Best-effort cleanup: on Windows the watched file's handle may not be
      // released yet, so deleting the temp dir throws PathAccessException
      // ("being used by another process"). The OS reclaims the temp dir.
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } on FileSystemException {
        // ignore
      }
    }
  });
}
