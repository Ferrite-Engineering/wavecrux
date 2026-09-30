// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/coexistence/_coexistence_helpers.dart
//
// Shared setup for the Stage + FSM coexistence tests (desktop and tablet).
//
// Both tests load `stage/stage_demo.vcd` (which carries `top.primitives.led_blink`
// — an LED-bindable scalar — and `top.primitives.fsm_state` — an enum FSM
// signal), stand up a Stage panel with an LED widget bound to the scalar, show
// the Stage panel in the bottom dock, and activate FSM analysis on the enum.
//
// Architecture note (open-core): the bottom region is a `CruxDock` tab strip
// (`WaveCruxBottomDock`), which retired the 8-deep priority chain Stage > FSM >
// … that these helpers were originally written against. Stage and FSM now each
// contribute a *tab*; both are always present while their features are on, but
// only the fronted tab's content is built — so two bottom-dock panels still
// cannot render at the same instant in one pane. These coexistence tests verify
// the meaningful guarantee — both features are concurrently active with no
// cross-interference, each panel renders correctly when its tab is fronted, and
// scrubbing the cursor updates both — and (14.5) genuine simultaneity for panels
// that live in *different* regions (Stage in the bottom dock, RTL source in the
// right dock).
//
// One consequence drives [setUpStageAndFsm]'s tail: activating FSM analysis
// makes a new *closable* FSM tab appear, and `CruxDock` auto-reveals newly
// appearing closable tabs (`onAutoReveal` → `revealBottomDockTab`) on the
// theory that "the most recent thing you asked for is what you see". That is
// deliberate product behaviour, so the setup fronts the Stage tab explicitly
// once FSM is up rather than assuming Stage out-prioritises it.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/pane_id.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/panes/providers/active_pane_id_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/stage_panel.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/fsm_panel.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../helpers/app_driver.dart';

export '../helpers/app_driver.dart'
    show rootContainer, suppressPlatformSemanticsLeak;

/// The result of [setUpStageAndFsm]: the active tab's container, its pane id,
/// the two driven signals, the Stage LED instance id, and the id of the Stage
/// panel that owns it (which is also what names its bottom-dock tab — see
/// [stageDockTabId]).
typedef StageFsmSetup = ({
  ProviderContainer container,
  PaneId paneId,
  Variable led,
  Variable fsm,
  String stageInstanceId,
  String stagePanelId,
});

/// The bottom-dock tab id for the Stage panel [panelId], mirroring the id
/// scheme `WaveCruxBottomDock` builds its stage entries with.
String stageDockTabId(String panelId) => '$kBottomDockStagePrefix$panelId';

/// Two cursor times where both `led_blink` and `fsm_state` hold different
/// values in `stage_demo.vcd`, and where each `fsm_state` value was entered
/// via a real transition (so `fsmCurrentStateId` is non-null — the initial
/// `000` state at t=0 has no transition into it and reports null):
///   * `led_blink` toggles every 100 ns → 1 at [1100,1200), 0 at [2000,2100).
///   * `fsm_state` → `001` in [800,1600), `010` in [1600,2400).
const int scrubTimeA = 1100;
const int scrubTimeB = 2000;

/// Boots the app at [surface], loads the Stage demo, binds an LED widget to
/// `led_blink`, shows the Stage panel in the bottom dock, and activates FSM
/// analysis on `fsm_state`.
Future<StageFsmSetup> setUpStageAndFsm(
  WidgetTester tester, {
  required Size surface,
}) async {
  // Force a deterministic logical size + device class regardless of the host
  // display's physical size / DPR (on real macOS, `setSurfaceSize` alone is
  // divided by the host DPR and yields an unpredictable device class).
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = surface;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await loadFixtureVcd(tester, 'stage/stage_demo.vcd');

  final root = rootContainer(tester);
  final tab = root.read(tabListProvider).first;
  final container = root.read(tabContainerManagerProvider).containerFor(tab.id);
  final paneId = root.read(activePaneIdProvider);

  final source = container.read(waveformSourceProvider).value!;
  final vars = source.findVariables(const SignalFilter());
  final led = vars.firstWhere((v) => v.name == 'led_blink');
  final fsm = vars.firstWhere((v) => v.name == 'fsm_state');
  // Load both signals up front so `valueAt` (used by the scrub assertions and
  // by the FSM current-state highlight) returns real data synchronously.
  await source.loadSignal(led.signalRef);
  await source.loadSignal(fsm.signalRef);

  // Stage panel + LED widget bound to the scalar.
  final stage = container.read(stageWorkspaceProvider.notifier);
  final panelId = stage.addPanel('Coexistence');
  final instanceId = stage.addInstance('led');
  expect(instanceId, isNotNull, reason: 'Stage LED instance must be created');
  stage.setBinding(instanceId!, 'input', led.signalRef);

  // Show the bottom dock with the Stage panel as its front content. Panel
  // visibility is per-tab (`panelLayoutProvider`, overridden per-tab in
  // `wavecruxTabOverrides`); set it on this tab's own container.
  container.read(panelLayoutProvider.notifier)
    ..setTransactionViewVisible(visible: true)
    ..setStageViewVisible(visible: true);

  // Activate FSM analysis on the enum signal (per-tab provider).
  await container.read(fsmProvider.notifier).analyzeSignal(fsm.signalRef);
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (container.read(fsmProvider).isActive) break;
  }

  // The FSM tab's arrival auto-reveals it (see the architecture note above),
  // and the dock schedules that as a post-frame callback. Pump past it before
  // fronting Stage, or the reveal lands *after* this selection and undoes it.
  await tester.pump();
  await tester.pump();
  container
      .read(panelLayoutProvider.notifier)
      .setBottomDockTab(stageDockTabId(panelId));
  await tester.pump();

  return (
    container: container,
    paneId: paneId,
    led: led,
    fsm: fsm,
    stageInstanceId: instanceId,
    stagePanelId: panelId,
  );
}

/// Drains transient `RenderFlex`/`Flex` overflow exceptions emitted while
/// several panels open and the multi-pane layout reflows, re-throwing anything
/// that is not a layout overflow so real defects still fail the test.
///
/// Mirrors `drainTransientLayoutExceptions` in
/// `integration_test/mobile/_mobile_fixture.dart`: the IdeController seeds
/// initial pane visibility from the host view metrics, so opening the desktop
/// triple-panel layout (Stage dock + RTL right slot + side panels) can briefly
/// overflow before the `deviceClassProvider` listener re-syncs.
void drainTransientOverflow(WidgetTester tester) {
  for (var i = 0; i < 32; i++) {
    final ex = tester.takeException();
    if (ex == null) break;
    final s = ex.toString();
    final isOverflow =
        s.contains('RenderFlex overflowed') || s.contains('Flex overflowed');
    if (!isOverflow) {
      throw Exception(s);
    }
  }
}

/// Pumps a bounded number of frames until [finder] matches, then returns
/// whether it matched. Avoids `pumpAndSettle(Duration)` (see
/// integration-test conventions).
Future<bool> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 40,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    if (finder.evaluate().isNotEmpty) return true;
    await tester.pump(const Duration(milliseconds: 50));
  }
  return finder.evaluate().isNotEmpty;
}

/// Fronts the FSM tab in the bottom dock, asserts its panel renders, then
/// fronts the Stage tab again and asserts Stage comes back.
///
/// This demonstrates that the FSM panel renders correctly while coexisting
/// with an active Stage panel in the same pane, given that the bottom dock
/// builds only the fronted tab's content.
///
/// Switches by *tab selection*, not by toggling `setStageViewVisible`. Turning
/// the Stage feature off would destroy the Stage tab (and, on the last panel,
/// the feature) rather than merely backgrounding it — a different scenario, and
/// one that leaves what comes forward up to the dock's fallback rather than
/// this test.
Future<void> assertFsmPanelRendersThenRestoreStage(
  WidgetTester tester,
  StageFsmSetup setup,
) async {
  setup.container
      .read(panelLayoutProvider.notifier)
      .setBottomDockTab(kBottomDockTabFsm);
  expect(
    await pumpUntilFound(tester, find.byType(FsmPanel)),
    isTrue,
    reason: 'FSM panel must render when its dock tab is fronted',
  );

  setup.container
      .read(panelLayoutProvider.notifier)
      .setBottomDockTab(stageDockTabId(setup.stagePanelId));
  expect(
    await pumpUntilFound(tester, find.byType(StagePanel)),
    isTrue,
    reason: 'Stage panel must return to the dock front',
  );
}
