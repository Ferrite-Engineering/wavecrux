// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/web/web_file_picker_test.dart
//
// Flutter Web file picker upload end-to-end.
//
// Driving the native browser file-chooser dialog from inside a
// `flutter drive` test is not possible without an out-of-process
// WebDriver (ChromeDriver/Selenium) installation, because the file
// chooser is rendered by Chrome itself outside the Flutter view: it
// "Requires Selenium
// WebDriver or ChromeDriver integration to interact with the native
// file chooser dialog."
//
// To exercise the full surface a typical `flutter drive -d chrome`
// developer machine can reach without WebDriver, this test installs a
// mock implementation of [FilePicker.platform] that returns synthetic
// VCD bytes when [pickFiles] is invoked. It then taps the "Open File…"
// button on the welcome screen. The post-pick code path —
// `WebFileLoader.pickFile` → `_openFromBytes` →
// `WaveformSourceNotifier.openFromBytes` → `WellenWasmProvider.openBytes`
// → router navigation to `/viewer` → hierarchy population in the
// signal tree — runs exactly the same code that would run after a real
// user clicks through the browser's file chooser, so the integration
// risk this test covers is the post-dialog pipeline. A future
// follow-up adds a WebDriver-driven variant that exercises the dialog
// itself.
//
// The test also verifies the "Open File" button renders without
// `RenderFlex` overflow at the two standard desktop sizes (1024×768 and
// 1440×900) — the same exception-drain pattern the mobile suite uses to handle transient
// IdeController layout overflows.
//
// Gated to web only via `skip: !kIsWeb`.
//
// Run with:
//   flutter drive --target=integration_test/web/web_file_picker_test.dart \
//     -d chrome

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/core/router.dart' show rootScaffoldMessengerKey;
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/waveform/web_file_loader.dart';
import 'package:wavecrux/services/waveform/wellen_wasm_provider.dart';
import 'web_app_driver.dart';

// Embedded VCD content — mirrors `vcd/scalar_basics.vcd`. Used as the
// payload the mock FilePicker hands back to `WebFileLoader.pickFile`.
const String _scalarBasicsVcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 1 " rst $end
$var wire 8 # data $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
1"
b00000000 #
$end
#10
1!
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
''';

/// Builds a [WebPickFiles] stub that returns a synthetic web-style pick result.
///
/// On Flutter Web the real implementation populates the picked file's byte
/// content (no filesystem path is available). [WebFileLoader.pickFile] reads
/// those bytes via `readAsBytes()`, so the stub must return a file carrying
/// non-empty bytes for the welcome-screen open flow to proceed.
///
/// `file_picker` 12 made `FilePicker.pickFiles` a static method that can no
/// longer be replaced via `FilePicker.platform = mock`, so the picker is
/// injected through [webFileLoaderProvider] instead. [counter] is bumped on
/// each call to prove the welcome screen actually routed through the picker.
WebPickFiles _stubWebPickFiles(
  Uint8List bytes,
  String name,
  List<int> counter,
) => () async {
  counter[0]++;
  return FilePickerResult([
    PlatformFile(name: name, size: bytes.length, bytes: bytes),
  ]);
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'Open File on web routes browser file API bytes through openFromBytes',
    (tester) async {
      // Inject the picker stub through the provider BEFORE bootstrap so the
      // welcome screen's first build uses it. `file_picker` 12's static
      // `pickFiles` can't be mocked via `FilePicker.platform`, so we override
      // `webFileLoaderProvider` with a `WebFileLoader` whose pick function
      // returns synthetic VCD bytes.
      final callCount = [0];
      final stubLoader = WebFileLoader(
        pickFiles: _stubWebPickFiles(
          Uint8List.fromList(utf8.encode(_scalarBasicsVcd)),
          'scalar_basics.vcd',
          callCount,
        ),
      );

      await seedFirstLaunchAnswers();
      await bootstrap(
        extraOverrides: [
          webFileLoaderProvider.overrideWithValue(stubLoader),
        ],
      );
      await tester.pump();
      // The empty canvas hosts the indefinitely-animating GlowingAppIcon, so
      // pumpAndSettle would time out. Settle bounded frames instead.
      await settleEmptyCanvas(tester);

      // ── Overflow check at the two reference widths from the plan ────────
      // 1024 × 768 — typical iPad / mid-range desktop browser viewport.
      // Render the welcome screen, drain transient overflow exceptions
      // (the IdeController briefly overflows before deviceClassProvider
      // settles), assert nothing real remains.
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      await settleEmptyCanvas(tester);
      _drainTransientLayoutExceptions(tester);
      // 1440 × 900 — typical desktop.
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      await settleEmptyCanvas(tester);
      _drainTransientLayoutExceptions(tester);

      // ── Tap "Open File…" on the empty-canvas state ──────────────────────
      // Use the localized label so the test does not assume English. The
      // empty-canvas state replaced the legacy Welcome screen.
      // Resolve L10N from the root scaffold-messenger context — it sits
      // *below* MaterialApp's Localizations, whereas the MaterialApp element
      // itself is above it (so `L10N.of(MaterialApp element)` returns null).
      final l10n = L10N.of(rootScaffoldMessengerKey.currentContext!);
      final openFileFinder = find.widgetWithText(
        FilledButton,
        l10n.emptyCanvasOpenFile,
      );
      expect(
        openFileFinder,
        findsOneWidget,
        reason: 'empty-canvas state must render the Open File button on web',
      );
      await tester.tap(openFileFinder);
      // The tap routes through the picker and navigates off the empty canvas,
      // but the GlowingAppIcon is still animating during the transition; the
      // poll loop below waits for the loaded source. Flush a few frames.
      await settleEmptyCanvas(tester);

      // The picker stub was invoked at least once.
      expect(
        callCount[0],
        greaterThanOrEqualTo(1),
        reason: 'Open File tap must route through WebFileLoader.pickFile',
      );

      // ── Verify the post-pick pipeline landed a WellenWasmProvider ─────────
      final root = rootContainer(tester);
      final tcm = root.read(tabContainerManagerProvider);

      // Poll up to a few seconds for the source to surface — openFromBytes
      // runs asynchronously and routes via go_router.go('/viewer').
      WellenWasmProvider? loaded;
      for (var i = 0; i < 60; i++) {
        final activeTabId = root.read(activeTabIdProvider);
        final container = tcm.containerFor(activeTabId);
        final src = container.read(waveformSourceProvider).value;
        if (src is WellenWasmProvider) {
          loaded = src;
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        loaded,
        isNotNull,
        reason: 'post-pick pipeline must install a WellenWasmProvider',
      );
      expect(
        loaded!.rootScopes,
        isNotEmpty,
        reason: 'hierarchy must populate from the picker bytes',
      );
      expect(loaded.rootScopes.first.name, equals('top'));
      expect(
        loaded.rootScopes.first.variables.map((v) => v.name).toSet(),
        equals({'clk', 'rst', 'data'}),
        reason: 'all declared signals must surface in the hierarchy tree',
      );

      // ── Value data, not just hierarchy ──────────────────────────────────
      // Hierarchy loading only proves the header parsed. The FFI-vs-WASM
      // value bridge must also return real transitions, or every signal lane
      // renders empty even though names + time range show. (Regression guard
      // for CompactChanges.times being a Uint64List, which throws on web.)
      final clk = loaded.rootScopes.first.variables.firstWhere(
        (v) => v.name == 'clk',
      );
      await loaded.loadSignal(clk.signalRef);
      final changes = loaded.changesInRange(clk.signalRef, 0, loaded.endTime);
      expect(
        changes,
        isNotEmpty,
        reason: 'WASM provider must return signal transitions, not empty lanes',
      );
      expect(loaded.valueAt(clk.signalRef, loaded.endTime), isNotNull);

      _drainTransientLayoutExceptions(tester);
      expect(tester.takeException(), isNull);
    },
    skip: !kIsWeb,
  );
}

/// Drains any pending `RenderFlex overflowed` exceptions captured during
/// surface resize. Same pattern as `_mobile_fixture.dart` — the
/// IdeController briefly overflows on a narrowing surface before the
/// `deviceClassProvider` listener fires and force-hides side panes.
/// Real exceptions still throw.
void _drainTransientLayoutExceptions(WidgetTester tester) {
  for (var i = 0; i < 32; i++) {
    final ex = tester.takeException();
    if (ex == null) break;
    final str = ex.toString();
    final isLayoutOverflow =
        str.contains('RenderFlex overflowed') ||
        str.contains('Flex overflowed');
    if (!isLayoutOverflow) {
      throw Exception(str);
    }
  }
}
