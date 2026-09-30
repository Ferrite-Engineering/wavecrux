// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/empty_canvas_drag_drop_test.dart
//
// A file dropped onto the desktop window while it shows the empty canvas
// opens as a new tab.
//
// Renamed from the legacy `welcome/welcome_drag_drop_desktop_test.dart`
// because the Welcome screen has been retired; the zero-tab state now
// renders [WaveCruxEmptyCanvas] (ARCHITECTURE.md §6.4).
//
// How the drop is delivered: the whole window is a `desktop_drop` target
// (`DesktopFileDropTarget`, mounted in `MaterialApp.builder`). This test feeds
// the plugin's Dart side the same method-channel messages its native runner
// sends for a real drag — `entered` with a window position, then
// `performOperation` with the dropped paths — so everything from the plugin's
// hit test onward runs as in the shipped app: the drop overlay, the drop
// router, and the viewer's File > Open dispatch. Only the OS drag session
// itself (Finder / Explorer / Files handing the paths to the runner) is out
// of reach of an integration test and stays on the manual verification list.
//
// The browser build keeps its own drop zone; that path is covered by
// `integration_test/web/web_drag_drop_test.dart`.
//
// What this test asserts:
//   * Booting with no CLI args lands on `WaveCruxEmptyCanvas` (find by the
//     `Key('empty_canvas_state')` anchor added in
//     `lib/features/workspace/widgets/wavecrux_empty_canvas.dart`).
//   * A drag entering the window shows the drop overlay.
//   * Releasing the fixture over the window opens it as a new tab.
//   * After the drop, `workspaceProvider.tabs.length` is exactly 1 and
//     the tab's `filePath` equals the dropped path.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/features/workspace/widgets/file_drop_overlay.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';
import '../helpers/app_driver.dart';

String _fixturePath(String relative) => [
  Directory.current.path,
  'verification',
  'fixtures',
  relative,
].join(Platform.pathSeparator);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'drop on WaveCruxEmptyCanvas opens the dropped file as a new tab',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Make sure the empty-canvas state actually renders by starting
      // from a clean workspace document.
      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(() async {
        await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      });

      final fixture = _fixturePath('vcd/scalar_basics.vcd');
      expect(File(fixture).existsSync(), isTrue);

      // Boot with no CLI args → zero-tab state → WaveCruxEmptyCanvas
      // (ARCHITECTURE.md §6.4).
      await seedFirstLaunchAnswers();
      await bootstrap();
      // Empty-canvas branding PNGs are not resolvable in the headless
      // test bundle — pump fixed frames instead of pumpAndSettle.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // The empty-canvas state must render — assert against the key on
      // [WaveCruxEmptyCanvas] (added in
      // `lib/features/workspace/widgets/wavecrux_empty_canvas.dart`).
      final emptyCanvasFinder = find.byKey(const Key('empty_canvas_state'));
      // Bounded poll rather than trusting the fixed drain above — same
      // fixed-loop flake the layout_* journeys hit on the 2026-09-06 sweep.
      await pumpUntil(
        tester,
        () => emptyCanvasFinder.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
      );
      expect(
        emptyCanvasFinder,
        findsOneWidget,
        reason: 'zero-tab boot must render the empty canvas under the drop',
      );

      // Play the drag through the plugin's channel, as its native runner
      // would: the pointer enters the middle of the window, then the file is
      // released there.
      Future<void> fromRunner(String method, Object? arguments) =>
          tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'desktop_drop',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, arguments),
            ),
            (_) {},
          );

      await fromRunner('entered', <double>[800, 500]);
      await tester.pump();
      expect(
        find.byType(FileDropOverlay),
        findsOneWidget,
        reason: 'a drag over the window shows the drop affordance',
      );

      await fromRunner('performOperation', <String>[fixture]);
      await tester.pump();
      expect(find.byType(FileDropOverlay), findsNothing);
      // Drain the open pipeline with a bounded poll: the FFI parse schedules
      // no frames until it completes.
      await pumpUntil(
        tester,
        () => rootContainer(tester).read(tabListProvider).isNotEmpty,
        timeout: const Duration(seconds: 30),
      );

      final root = rootContainer(tester);

      // Assertions: exactly one tab opens, pointing at the dropped file.
      final tabs = root.read(tabListProvider);
      expect(tabs, hasLength(1), reason: 'drop must produce exactly one tab');
      expect(
        tabs.first.filePath,
        equals(fixture),
        reason: 'dropped tab must reference the dropped file path',
      );

      // Workspace agrees with the live tab list. The workspace mutation
      // is debounced, so wait for it to converge before asserting.
      for (var i = 0; i < 30; i++) {
        final ws = root.read(workspaceProvider).value;
        if (ws != null && ws.tabs.length == 1) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      final workspace = root.read(workspaceProvider).value;
      expect(workspace, isNotNull);
      expect(
        workspace!.tabs.length,
        equals(1),
        reason:
            'workspaceProvider.tabs.length must agree with the live '
            'tab list after the drop',
      );
      expect(workspace.tabs.first.filePath, equals(fixture));

      // Branding-asset codec errors are an environment artifact of the
      // headless test bundle — drain rather than fail.
      tester.takeException();
    },
  );
}
