// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/web/web_drag_drop_test.dart
//
// Flutter Web drag-and-drop end-to-end.
//
// Verifies that when a file is dropped onto the WaveCrux browser
// window, the bytes flow through [WebDropZone.onFilesDropped] →
// `_openFromBytes` on the empty-canvas state → [WaveformSourceNotifier.openFromBytes]
// → [WellenWasmProvider.openBytes] and the waveform becomes available to
// every panel.
//
// Driving a real HTML5 drag-and-drop event sequence from inside
// `flutter drive` requires JS-interop gymnastics — `DragEventInit`
// has no `dataTransfer` field, so a faithful synthetic event must
// override the property via `Object.defineProperty` after construction.
// That path works but it is fragile (browser-version specific); the
// fully-faithful version is a WebDriver-driven variant.
//
// This test exercises the integration boundary that matters: the moment
// bytes-and-a-name arrive at the WebDropZone callback (which is exactly
// what the WebDropTarget delivers after a real browser drop event),
// the pipeline must route them through `openFromBytes` and surface a
// loaded WellenWasmProvider. The WebDropTarget itself (the
// `dragover`/`drop` document listener) is covered by the existing unit
// tests on the `web_drop_target_impl.dart` service.
//
// Gated to web only via `skip: !kIsWeb`.
//
// Run with:
//   flutter drive --target=integration_test/web/web_drag_drop_test.dart \
//     -d chrome

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/features/remote/providers/cxp_server_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/widgets/web_drop_zone.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/waveform/wellen_wasm_provider.dart';
import 'web_app_driver.dart';

// Same scalar_basics VCD embedded across the web suite so every
// web test exercises an identical payload regardless of host fixtures.
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'WebDropZone delivery routes bytes through openFromBytes to a WellenWasmProvider',
    (tester) async {
      // Boot the app with no CLI args — lands on the empty-canvas state, which
      // is the only screen that hosts a WebDropZone.
      await seedFirstLaunchAnswers();
      await bootstrap();
      await tester.pump();
      // The empty canvas hosts the indefinitely-animating GlowingAppIcon, so
      // pumpAndSettle would time out — poll for the drop zone instead.
      await pumpUntil(
        tester,
        () => find.byType(WebDropZone).evaluate().isNotEmpty,
      );

      // The WebDropZone is rendered unconditionally on web (gated by
      // `if (kIsWeb)` in the empty-canvas state). On non-web hosts the
      // zone renders an empty SizedBox.shrink — but we're skipped by
      // `skip: !kIsWeb` so the finder must succeed here.
      final dropZoneFinder = find.byType(WebDropZone);
      expect(
        dropZoneFinder,
        findsOneWidget,
        reason: 'empty-canvas state must render WebDropZone on web',
      );

      // Startup must not reach the desktop-only services a browser cannot
      // use: the CXP manifest directory (CXP has no transport on the web, and
      // the shared resolver reports the directory as unavailable there).
      expect(
        rootContainer(tester).exists(cxpManifestDirectoryProvider),
        isFalse,
        reason: 'the web build resolved the CXP manifest directory',
      );

      // Resolve the WebDropZone widget and invoke its onFilesDropped
      // callback with synthetic bytes. This callback is exactly the
      // bridge `_WebDropZoneState._onDrop` uses after the WebDropTarget's
      // `files` stream emits — every byte path from a real browser drop
      // converges here, so invoking it directly faithfully exercises
      // the post-drop pipeline (empty-canvas state → openFromBytes → router
      // navigation → WellenWasmProvider on the active tab).
      final dropZone = tester.widget<WebDropZone>(dropZoneFinder);
      final bytes = Uint8List.fromList(utf8.encode(_scalarBasicsVcd));
      dropZone.onFilesDropped(bytes, 'scalar_basics.vcd');
      await tester.pump();
      // The drop navigates off the empty canvas, but the GlowingAppIcon is
      // still mounted during the transition, so pumpAndSettle would hang. The
      // poll loop below waits for the loaded source; just flush a few frames.
      await settleEmptyCanvas(tester);

      // Resolve the active-tab container and assert a WellenWasmProvider
      // landed with the expected hierarchy.
      final root = rootContainer(tester);
      final tcm = root.read(tabContainerManagerProvider);

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
        reason:
            'drop-delivered bytes must install a WellenWasmProvider '
            'on the active tab',
      );

      // Hierarchy populates — the embedded VCD declares one scope `top`
      // with three signals. Asserting on this proves the bytes path crossed
      // every layer (empty-canvas state → notifier → openBytes → parser)
      // instead of being silently dropped.
      expect(loaded!.rootScopes, hasLength(1));
      expect(loaded.rootScopes.first.name, equals('top'));
      expect(
        loaded.rootScopes.first.variables.map((v) => v.name).toSet(),
        equals({'clk', 'rst', 'data'}),
        reason: 'hierarchy must surface every dropped signal',
      );

      expect(tester.takeException(), isNull);
    },
    skip: !kIsWeb,
  );
}
