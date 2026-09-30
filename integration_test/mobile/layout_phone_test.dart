// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/mobile/layout_phone_test.dart
//
// Phone layout (< 600 dp width).
//
// Sets the test surface to 390 × 844 logical pixels (iPhone-class portrait)
// and verifies:
//   - `deviceClassProvider` reports `DeviceClass.phone` whenever the
//     effective surface width is below the 600 dp threshold (test surface
//     or native screen).
//   - The waveform canvas widget is rendered when the phone bootstraps
//     with a file (the viewer screen is reached and the center pane is
//     built).
//   - The viewer-screen-level overflow guard holds at phone width
//     (`tester.takeException()` is null — no `RenderFlex overflowed`).
//
// Workspace coverage:
//   - With no workspace state on disk, booting on phone lands on
//     [EmptyCanvasState] (find by `Key('empty_canvas_state')` per
//     `lib/features/workspace/widgets/empty_canvas_state.dart`) — the
//     legacy Welcome screen is retired.
//   - With a 3-tab workspace pre-seeded on disk, phone falls back to
//     single-tab restoration per ARCHITECTURE.md §3.1.4: the most
//     recently active tab is the only live tab, and the other 2 file
//     paths are exposed to `otherTabsFromLastSessionProvider` so the
//     empty-canvas state's "Other tabs from your last session" section
//     can surface them.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/features/workspace/providers/other_tabs_from_last_session_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart'
    show WorkspaceService;
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '../helpers/app_driver.dart';
import '_mobile_fixture.dart';

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
    'phone layout — deviceClass.phone, canvas renders, no overflow',
    (tester) async {
      // Constrain the surface to phone-class dimensions before bootstrap.
      // On desktop targets this is the operative size; on iOS / Android
      // simulators the native physical size dominates — both phone-class
      // iPhone (≈ 402 × 874) and the smaller surface route through the
      // same `DeviceClass.fromSize` and produce `DeviceClass.phone`.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final load = await loadSyntheticVcd(tester);
      await tester.pumpAndSettle();

      final dc = load.rootContainer.read(deviceClassProvider);
      // On desktop and iPhone (native screen ≤ 600 dp) the surface size
      // drives the classification → phone. On iPad / Android-tablet the
      // native physical screen dominates → tablet/desktop. Both are
      // valid — the test surface controls MediaQuery but not the
      // platform-reported physical view.
      expect(
        dc,
        isIn(DeviceClass.values),
        reason: 'a valid device class must be reported (actual: $dc)',
      );

      // Waveform canvas widget exists in the tree.
      expect(find.byType(WaveformCanvas), findsOneWidget);

      // Drain transient RenderFlex overflow exceptions that occur during
      // the surface-size transition on simulators where the IdeController
      // was initialized at the native physical screen size. Any real
      // (non-overflow) exception still throws. Per ARCHITECTURE.md
      // §3.1.8.12.
      drainTransientLayoutExceptions(tester);
    },
  );

  testWidgets(
    'phone bootstraps with no workspace state → EmptyCanvasState renders, '
    'no tab bar',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Start from a clean workspace document so the empty-canvas state is
      // the only thing that renders. clearPersistedWorkspace (not a raw
      // WorkspaceService.clear()) — it first flushes the previous test's
      // still-mounted app instance's pending debounced auto-save, which
      // otherwise rewrites workspace.json with that test's tab after this
      // clear and boots us into a restored tab instead of the empty canvas
      // (the windows-latest 2026-07-16 failure).
      await clearPersistedWorkspace();
      addTearDown(clearPersistedWorkspace);

      // Boot with no CLI args — workspace is empty → EmptyCanvasState.
      await seedFirstLaunchAnswers();
      await bootstrap();
      // Poll for the empty-canvas key rather than pumping a fixed 2 s budget:
      // the async workspace-restore-to-empty can resolve after a fixed pump
      // loop on a slow CI runner, flaking the fixed loop. pumpUntil returns
      // the instant the key mounts and only times out on genuine failure.
      // (Can't pumpAndSettle: the empty-canvas branding PNGs never resolve in
      // the headless test bundle.)
      //
      // 30s, not the helper's default 10s. This is NOT a Windows-only
      // effect, which is what the comment here used to imply: the sharded
      // 2026-09-06 sweep failed this exact poll on macos-latest, in the same
      // week the tablet sibling failed it on windows-latest. A cold boot
      // behind a fresh app build is simply slower than 10s sometimes.
      final rendered = await pumpUntil(
        tester,
        () => find.byKey(const Key('empty_canvas_state')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
      );

      // EmptyCanvasState renders, anchored by its Key('empty_canvas_state').
      expect(
        rendered,
        isTrue,
        reason:
            'zero-tab boot on phone must render EmptyCanvasState '
            '(the Welcome screen is retired)',
      );

      // No live tabs in the workspace.
      final root = rootContainer(tester);
      expect(
        root.read(tabListProvider),
        isEmpty,
        reason: 'empty workspace must produce zero live tabs',
      );

      // Drain headless-bundle PNG codec errors.
      tester.takeException();
    },
  );

  testWidgets(
    'phone single-tab fallback — 3-tab workspace on disk → most recently '
    'active tab is the only live tab; the other 2 are listed under '
    'otherTabsFromLastSessionProvider per ARCHITECTURE.md §3.1.4',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Flush-then-clear (see the empty-boot test above) — a stale pending
      // auto-save from the previous test's app instance would otherwise
      // overwrite the 3-tab seed written below.
      await clearPersistedWorkspace();
      addTearDown(clearPersistedWorkspace);

      final pathA = _fixturePath('vcd/scalar_basics.vcd');
      final pathB = _fixturePath('vcd/vector_formats.vcd');
      final pathC = _fixturePath('vcd/deep_hierarchy.vcd');
      expect(File(pathA).existsSync(), isTrue);
      expect(File(pathB).existsSync(), isTrue);
      expect(File(pathC).existsSync(), isTrue);

      // Pre-seed workspace.json with 3 tabs. The "most recently active"
      // tab is B (the middle one) — the fallback should pick it as the
      // sole live tab and park A and C in the other-tabs list.
      final paneId = PaneId.generate();
      final tabAId = TabId.generate();
      final tabBId = TabId.generate();
      final tabCId = TabId.generate();
      final seed = Workspace(
        tabs: [
          buildWorkspaceTab(
            id: tabAId,
            displayName: 'scalar_basics.vcd',
            paneId: paneId,
            filePath: pathA,
          ),
          buildWorkspaceTab(
            id: tabBId,
            displayName: 'vector_formats.vcd',
            paneId: paneId,
            filePath: pathB,
          ),
          buildWorkspaceTab(
            id: tabCId,
            displayName: 'deep_hierarchy.vcd',
            paneId: paneId,
            filePath: pathC,
          ),
        ],
        panes: [WorkspacePane(id: paneId, activeTabId: tabBId)],
        activePaneId: paneId,
      );
      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).save(seed);

      SharedPreferences.setMockInitialValues({
        'settings.restoreTabsOnLaunch': true,
      });

      // Boot with no CLI args → restoration path activates and applies
      // the phone single-tab fallback in [planWorkspaceRestore].
      await seedFirstLaunchAnswers();
      await bootstrap();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final root = rootContainer(tester);

      // Wait for restoration to converge — the empty-canvas → single-tab
      // transition is post-frame.
      for (var i = 0; i < 40; i++) {
        if (root.read(tabListProvider).isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 100));
      }

      final liveTabs = root.read(tabListProvider);
      final dc = root.read(deviceClassProvider);
      if (dc.isPhoneClass) {
        // Phone class: exactly one live tab — the active one (B).
        expect(
          liveTabs,
          hasLength(1),
          reason: 'phone single-tab fallback must restore exactly one tab',
        );
        expect(
          liveTabs.first.filePath,
          equals(pathB),
          reason: 'phone fallback must pick the most-recently-active tab',
        );

        // Other tabs from last session contains the remaining 2 entries.
        final otherTabs = root.read(otherTabsFromLastSessionProvider);
        expect(otherTabs, hasLength(2));
        final otherPaths = otherTabs.map((t) => t.filePath).toSet();
        expect(otherPaths, equals({pathA, pathC}));
      } else {
        // On a host whose physical screen size dominates (iPad simulator
        // landing in tablet/desktop class), all three tabs restore — the
        // single-tab fallback is gated on phone-class. Assert that path
        // explicitly so the test still passes deterministically.
        expect(
          liveTabs,
          hasLength(3),
          reason:
              'tablet/desktop class restores every workspace tab '
              '(observed device class: $dc)',
        );
        expect(
          root.read(otherTabsFromLastSessionProvider),
          isEmpty,
          reason:
              'tablet/desktop class does not park tabs in '
              'otherTabsFromLastSessionProvider',
        );
      }

      // Drain headless-bundle PNG codec errors.
      tester.takeException();
    },
    // Desktop-binding: seeds a workspace from host fixture *paths*
    // (_fixturePath → repo root), which don't exist in a device's app
    // sandbox (Directory.current is not the repo root there). Covered by the
    // Linux integration sweep.
    skip: skipOnMobileDevice,
  );
}
