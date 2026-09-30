// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/stage/providers/riscv_commit_landing_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_stage_renderer.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_views.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/translator_registry.dart';
import 'package:wavecrux/services/remote/cxp/cxp_inbound_handlers.dart';
import 'package:wavecrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:wavecrux/services/remote/cxp/riscv_stream_coordinate_resolver.dart';
import 'package:wavecrux/services/riscv/riscv_consistency_checker.dart'
    show riscvHexWord;
import 'package:wavecrux/services/riscv/riscv_retire_stream_service.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';
import 'package:wavecrux/services/riscv/rvfi_binding_set.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';
import 'package:wavecrux/services/riscv/rvfi_detection_service.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/waveform/streaming_vcd_service.dart';

import '../../../features/stage/widgets/riscv/_riscv_commit_harness.dart'
    show rv32Disassembler;
import '../../../helpers/in_memory_workspace_service.dart';
import '../../../helpers/product_telemetry_config.dart';

/// **The SimCrux → WaveCrux counterexample hand-off, end to end, from the real
/// file.**
///
/// Everything else covering this path builds its trace in memory: a handful of
/// `SignalChange` lists shaped exactly the way the resolver wants them. Those
/// tests passed while the feature did not work at all, because the artifact the
/// other product actually ships was a three-signal stub — `rvfi_valid`,
/// `rvfi_insn`, `rvfi_rd_wdata` — with no `rvfi_pc_rdata` in it. WaveCrux read
/// it correctly, found no RVFI bundle, and declined; SimCrux's driver tests
/// only ever asked whether a VCD existed on disk. Both halves were green and
/// the flagship demo opened a trace and did nothing.
///
/// So this file starts where the demo starts: at **bytes on disk**, in the
/// spelling SimCrux commits them, parsed by the production VCD reader and run
/// through the production detection → retire-stream → step-grid → resolver
/// chain, and then through [dispatchCxpHighlight] itself.
///
/// MUTATION: thin the fixture, drop `rvfi_pc_rdata`, or shorten it below step
/// 7, and every assertion about the landing fails.
void main() {
  // `dispatchCxpHighlight` nudges the OS attention affordance through a method
  // channel on a successful landing, so the binding has to exist.
  TestWidgetsFlutterBinding.ensureInitialized();

  // A byte-identical copy of
  //   simcrux/verification/fixtures/riscv_formal/insn_sub_counterexample/
  //     engine_0/trace.vcd
  // which SimCrux regenerates with
  // `dart run tool/generate_riscv_formal_fixtures.dart`.
  //
  // The two repositories cannot run each other's tests, so the copy is pinned
  // from both ends: [kCounterexampleTraceDigest] is asserted here AND in
  // SimCrux's `test/services/simulator/riscv_formal_trace_contract_test.dart`
  // against its original. Regenerating there without re-copying here — or
  // hand-editing here — turns one of the two red.
  final tracePath =
      '${Directory.current.path}/test/fixtures/riscv_formal/'
      'insn_sub_counterexample_trace.vcd';

  // What `sby.log` reports and what SimCrux's `riscvStreamCoordinateFor`
  // therefore emits: `riscv.formal.trace_step`, sequence_index = the depth
  // reached, sub_id = the check's RVFI channel.
  const violatingStep = 7;
  final coordinate = CxpStreamCoordinate(
    streamId: CxpStreamCoordinate.riscvFormalTraceStepStreamId,
    sequenceIndex: violatingStep,
    subId: 'ch0',
    attributes: const <String, String>{
      'riscv.formal.check': 'insn_sub_ch0',
      'riscv.formal.group': 'insn',
      'riscv.formal.verdict': 'FAIL',
      'riscv.formal.depth_configured': '20',
      'riscv.mode': 'demo',
    },
  );

  /// Opens [path] with the production streaming VCD reader and waits for the
  /// whole file, then loads every signal — the same pre-load the inbound
  /// handler does, because `valueAt` cannot distinguish "not loaded" from "no
  /// value yet" (ARCHITECTURE §6.6).
  Future<StreamingVcdService> openTrace(String path) async {
    final source = StreamingVcdService();
    await source.openFile(path);
    await source.streamEndedFuture;
    for (final v in source.findVariables(const SignalFilter())) {
      await source.loadSignal(v.signalRef);
    }
    return source;
  }

  test('the committed copy is the fixture SimCrux ships', () {
    // Not a checksum for its own sake: this file exists in two repositories
    // and only one of them is canonical. A change there that is not a change
    // here is the exact drift that let both sides look tested while the
    // feature did not work.
    expect(
      fixtureDigest(File(tracePath).readAsStringSync()),
      kCounterexampleTraceDigest,
      reason:
          'this trace must stay byte-identical to SimCrux’s '
          'verification/fixtures/riscv_formal/insn_sub_counterexample/'
          'engine_0/trace.vcd — regenerate it there and re-copy it here',
    );
  });

  group('the real counterexample trace', () {
    late StreamingVcdService source;
    late RvfiDetectionResult detection;
    late List<RiscvRetiredInstruction> retires;

    setUp(() async {
      source = await openTrace(tracePath);
      detection = const RvfiDetectionService().detect(<String, Variable>{
        for (final v in source.findVariables(const SignalFilter()))
          v.signalRef: v,
      });
      retires = const RiscvRetireStreamService(null).build(
        source: source,
        bindings: detection.bindings,
        startTime: source.startTime,
        endTime: source.endTime,
      );
    });

    tearDown(() => source.close());

    test('carries a fully bound RVFI bundle', () {
      // `reduced` would still resolve a coordinate, but the Commit Inspector
      // would show a degraded view — no registers, no memory, no traps — on
      // the one trace the announcement demo puts on screen.
      expect(detection.report.completeness, RvfiBindingCompleteness.full);
      expect(detection.report.missing, isEmpty);
      expect(detection.report.channelCount, 1);
    });

    test('yields a uniform step grid that reaches the violating step', () {
      final grid = RiscvTraceStepGrid.derive(
        source: source,
        bindings: detection.bindings,
      );
      expect(grid, isNotNull, reason: 'no lattice means every step declines');
      expect(grid!.origin, 0);
      expect(grid.pitch, 10);
      expect(
        grid.lastStep,
        greaterThanOrEqualTo(violatingStep),
        reason: 'a trace shorter than step 7 cannot answer for step 7',
      );
      expect(grid.tickForStep(violatingStep), 70);
    });

    test('resolves step 7 to the instruction that violated the property', () {
      final resolution = const RiscvStreamCoordinateResolver().resolve(
        coordinate: coordinate,
        source: source,
        bindings: detection.bindings,
        retires: retires,
      );
      expect(resolution.reason, isNull);
      expect(resolution.landed, isTrue);
      final retired = resolution.retired;
      expect(
        retired,
        isNotNull,
        reason:
            'a cursor placement is the degraded outcome; the card promises '
            'the violating instruction',
      );
      expect(retired!.time, 70);
      expect(retired.channelIndex, 0);
      expect(retired.order, 5);
      expect(retired.pc, 0x1014);
      expect(retired.insnWord, 0x402082B3, reason: 'sub x5, x1, x2');
      expect(retired.rs1Addr, 1);
      expect(retired.rs1Value, 7);
      expect(retired.rs2Addr, 2);
      expect(retired.rs2Value, 5);
      expect(retired.rdAddr, 5);
      // The bug the fictional core has: 7 - 5 is 2, and it wrote 3. Asserted
      // because it is what makes the demo land on something worth looking at.
      expect(retired.rdValue, 3);
      expect(retired.hasUnknownBits, isFalse);
    });

    test('reconstructs the whole retire log, memory effects included', () {
      // The Commit Inspector's views are all projections of this list, so a
      // trace that resolved step 7 and carried nothing else would still show
      // an empty inspector.
      expect(retires.map((r) => r.time), [10, 20, 40, 50, 60, 70]);
      expect(retires.map((r) => r.order), [0, 1, 2, 3, 4, 5]);
      final load = retires[2];
      expect(load.memory?.address, 0x20);
      expect(load.memory?.rmask, 0xF);
      expect(load.memory?.rdata, 42);
      final store = retires[3];
      expect(store.memory?.address, 0x24);
      expect(store.memory?.wmask, 0xF);
      expect(store.memory?.wdata, 7);
      expect(retires.every((r) => r.trap ?? true), isFalse);
    });

    test('a step with no retirement lands the cursor and says so', () {
      // CXP §9.9.2's prescribed fallback (https://edacrux.app/cxp#sec-9-9-2),
      // on a step the trace really has. Step 3
      // is the authored stall.
      final resolution = const RiscvStreamCoordinateResolver().resolve(
        coordinate: CxpStreamCoordinate(
          streamId: CxpStreamCoordinate.riscvFormalTraceStepStreamId,
          sequenceIndex: 3,
          subId: 'ch0',
        ),
        source: source,
        bindings: detection.bindings,
        retires: retires,
      );
      expect(resolution.time, 30);
      expect(resolution.retired, isNull);
    });
  });

  group('dispatchCxpHighlight against the real file', () {
    test('places the cursor on the violating retirement and records the '
        'landing', () async {
      final source = await openTrace(tracePath);
      addTearDown(source.close);
      final container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          waveformSourceProvider.overrideWith(
            () => _PreloadedSourceNotifier(source),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        const ElementId(kind: ElementKind.signal, path: 'rvfi.rvfi_valid'),
        const <String, Object?>{},
        coordinate,
      );

      expect(result.honored, isTrue);
      expect(
        result.reason,
        isNull,
        reason: 'a reason here means the coordinate did not fully land',
      );
      expect(container.read(cursorStateProvider).primaryCursorTime, 70);
      final landing = container.read(riscvCommitLandingProvider);
      expect(
        landing,
        isNotNull,
        reason: 'no landing = no banner, no inspector',
      );
      expect(landing!.time, 70);
      expect(landing.order, 5);
      expect(landing.sequenceIndex, violatingStep);
      expect(landing.subId, 'ch0');
      expect(landing.selectedRetirement, isTrue);
      expect(landing.attributes['riscv.formal.check'], 'insn_sub_ch0');
      expect(landing.attributes['riscv.mode'], 'demo');
    });

    test('a trace with no RVFI in it is declined WITH a reason, never '
        'silently', () async {
      // The path that stays reachable after the fixture fix: a user can
      // cross-probe any trace. CXP §9.4 — honour the element, explain the
      // coordinate. The originating app turns this string into a toast, so an
      // honoured-but-unresolved coordinate MUST carry one.
      final source = await openTrace(
        '${Directory.current.path}/test/fixtures/vcd/scalar_basics.vcd',
      );
      addTearDown(source.close);
      final container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          waveformSourceProvider.overrideWith(
            () => _PreloadedSourceNotifier(source),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        const ElementId(kind: ElementKind.signal, path: 'top.clk'),
        const <String, Object?>{},
        coordinate,
      );

      expect(result.honored, isTrue, reason: 'the element still opened');
      expect(result.reason, isNotNull);
      expect(result.reason, contains('RVFI'));
      expect(container.read(riscvCommitLandingProvider), isNull);
    });
  });

  // ── the payload: what the user actually sees ────────────────────────────────
  //
  // Everything above proves the coordinate lands. None of it proves the user
  // sees anything, and for one release it did not: WaveCrux opened the trace,
  // detected the bundle, converted step 7 to tick 70 and put the cursor there —
  // on a tab with no Stage panel, therefore no Commit Inspector, therefore no
  // landing banner (the banner lives *inside* the inspector). Right instant,
  // empty screen.
  group('the cross-probe mounts what the landing is supposed to be seen in', () {
    testWidgets('a tab the cross-probe opened gets a bound Commit Inspector, '
        'and the step-7 retirement is the current row', (tester) async {
      final harness = await _openCounterexampleByCrossProbe(
        tester,
        tracePath,
        coordinate,
      );

      // ── 1. a Stage panel exists, and the cross-probe made it ────────────────
      final workspace = harness.tab.read(stageWorkspaceProvider);
      expect(
        workspace.panels,
        hasLength(1),
        reason:
            'a freshly opened tab has no Stage panel; the hand-off adds one',
      );
      final panel = workspace.panels.single;
      expect(workspace.activePanelId, panel.id);
      expect(panel.instances, hasLength(1));
      final instance = panel.instances.single;
      expect(instance.widgetId, RiscvCommitStageWidget.widgetId);

      // ── 2. it is BOUND, through the detection service, to all 21 channels ───
      expect(
        instance.signalBindings.keys.toSet(),
        {for (final c in RvfiChannel.values) c.signalName},
        reason:
            'the trace carries the full bundle, so auto-bind must place every '
            'declared pin — a partially bound inspector renders a degraded view',
      );
      expect(
        instance.signalBindings[RvfiChannel.pcRdata.signalName]?.signalRef,
        isNotNull,
        reason: 'no pc_rdata means no usable inspector at all',
      );

      // ── 3. the panel is ON SCREEN, not merely in the workspace model ────────
      final layout = harness.tab.read(panelLayoutProvider);
      expect(layout.stageViewVisible, isTrue);
      expect(layout.transactionViewVisible, isTrue, reason: 'the dock is open');
      expect(
        layout.effectiveBottomDockTab,
        '$kBottomDockStagePrefix${panel.id}',
      );
      expect(layout.bottomDockShowsStage, isTrue);

      // ── 4. the landing itself ───────────────────────────────────────────────
      expect(harness.tab.read(cursorStateProvider).primaryCursorTime, 70);
      final landing = harness.tab.read(riscvCommitLandingProvider);
      expect(landing, isNotNull);
      expect(landing!.order, 5);
      expect(
        landing.autoMounted,
        isTrue,
        reason:
            'the panel appeared unbidden — the banner is the only surface that '
            'can account for it',
      );

      // ── 5. render it, and read what the user reads ──────────────────────────
      await _pumpMountedInspector(tester, harness, instance);

      // The banner, with the sender's claims and the provenance obligation.
      expect(find.byType(RiscvCommitLandingBanner), findsOneWidget);
      expect(find.textContaining('insn_sub_ch0'), findsOneWidget);
      expect(find.textContaining('step 7 of 20'), findsOneWidget);
      expect(find.textContaining('rvfi_order 5'), findsOneWidget);
      // Constraint 3: the panel says who put it there.
      expect(
        find.textContaining('opened by the incoming cross-probe'),
        findsOneWidget,
      );
      // And it is still a replayed fixture, said as loudly as before.
      expect(
        find.text('Replayed demo fixture, not a measured solver run.'),
        findsOneWidget,
      );

      // The commit log is populated up to the cursor: six retirements at
      // t ≤ 70, no more.
      expect(find.text(riscvHexWord(0x1014)), findsOneWidget);

      // …and exactly ONE row is marked current — the tinted one — and it is the
      // instruction the proof failed on. This is the assertion the whole
      // hand-off exists to make true.
      final currentRow = find.descendant(
        of: find.byType(ListView),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.color != null,
        ),
      );
      expect(currentRow, findsOneWidget);
      expect(
        find.descendant(of: currentRow, matching: find.textContaining('sub')),
        findsOneWidget,
        reason: 'the current row must be `sub x5, x1, x2` at pc 0x1014',
      );
      expect(
        find.descendant(
          of: currentRow,
          matching: find.textContaining(riscvHexWord(0x1014)),
        ),
        findsOneWidget,
      );
      // The bug itself: 7 − 5 is 2, and the core wrote 3.
      expect(
        find.descendant(
          of: currentRow,
          matching: find.textContaining(riscvHexWord(3)),
        ),
        findsOneWidget,
        reason: 'landing on the retirement is only useful if its effect shows',
      );

      // ── 6. and it is ON SCREEN, which is a different claim entirely ─────────
      //
      // Every assertion above was satisfied while the user could not see the
      // row: they got two `addi` rows and had to enlarge the panel by hand to
      // reach the `sub` the jump was about — the errand the hand-off exists to
      // spare them. The assertions did not lie, they were made at a size the
      // panel never has (see `_pumpMountedInspector`).
      //
      // Existence is therefore not the assertion. Geometry is: the landed
      // row's painted rect must lie inside the commits list's painted rect.
      // That stays true whatever the list decides to build ahead of the fold,
      // which "is the widget in the tree" does not.
      //
      // MUTATION: this test fails against the code before the scroll was
      // added — six 44 px rows overflow what the mounted panel gives the list,
      // and the landed row is the last of them.
      final listRect = tester.getRect(find.byType(ListView));
      final rowRect = tester.getRect(currentRow);
      expect(
        rowRect.top >= listRect.top - 0.5 &&
            rowRect.bottom <= listRect.bottom + 0.5,
        isTrue,
        reason:
            'the landed retirement paints at $rowRect, outside the commits '
            'list viewport $listRect — the row the whole hand-off is about is '
            'below the fold',
      );

      // Unmount inside the test body: the inspector's Riverpod subscriptions
      // schedule a zero-duration dispose timer on teardown, and the binding's
      // pending-timer invariant runs before it would otherwise fire.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('an ALREADY-OPEN, user-arranged tab keeps its layout — the '
        'cursor moves and nothing else does', (tester) async {
      // The other half of the rule, and the one that costs the user something
      // if it is wrong. The trace is open, the user has arranged that tab (no
      // Stage panel, no bottom dock, their own signals on the canvas), and the
      // same coordinate arrives. Moving the cursor is the hand-off's job.
      // Rearranging their tab is not.
      final harness = await _openCounterexampleByCrossProbe(
        tester,
        tracePath,
        null,
      );
      final designId = cxpDesignIdForPath(tracePath);
      await tester.runAsync(() => harness.publishArtifact(designId));

      // The user's arrangement, made by hand after the file opened.
      final layoutBefore = harness.tab.read(panelLayoutProvider);
      expect(layoutBefore.stageViewVisible, isFalse);
      final workspaceBefore = harness.tab.read(stageWorkspaceProvider);
      expect(workspaceBefore.panels, isEmpty);
      final tabsBefore = harness.root.read(tabListProvider).length;

      // The SAME coordinate, arriving at a tab that is already open. Routed
      // through the signal-like path, which is the one that can resolve against
      // an already-open trace (P21 activates rather than duplicating).
      final result = await tester.runAsync(
        () => dispatchCxpHighlight(
          harness.root.read(_refProvider),
          const ElementId(kind: ElementKind.signal, path: 'rvfi_valid'),
          <String, Object?>{cxpDesignIdMetadataKey: designId},
          coordinate,
        ),
      );

      expect(result!.honored, isTrue);
      // The navigation happened…
      expect(harness.tab.read(cursorStateProvider).primaryCursorTime, 70);
      final landing = harness.tab.read(riscvCommitLandingProvider);
      expect(landing, isNotNull);
      expect(landing!.order, 5, reason: 'the element was still honoured');
      // …and NOTHING about the layout did.
      expect(
        harness.tab.read(stageWorkspaceProvider),
        workspaceBefore,
        reason: 'the user arranged this tab; the cross-probe must not touch it',
      );
      expect(harness.tab.read(panelLayoutProvider), layoutBefore);
      expect(harness.root.read(tabListProvider).length, tabsBefore);
      expect(
        landing.autoMounted,
        isFalse,
        reason:
            'nothing was mounted, so the banner must not claim anything was',
      );
    });
  });
}

/// Everything the auto-mount tests need to reach into after a hand-off.
class _CrossProbeHarness {
  _CrossProbeHarness({
    required this.root,
    required this.tab,
    required this.store,
    required this.tracePath,
  });

  /// The root container the CXP server's `ref` resolves against.
  final ProviderContainer root;

  /// The per-tab container the hand-off's trace landed in.
  final ProviderContainer tab;

  /// The shared workspace store, so a follow-up cross-probe can resolve the
  /// same design by id.
  final CxpWorkspaceStore store;

  /// The trace the hand-off opened.
  final String tracePath;

  Future<void> publishArtifact(String designId) => store.upsertArtifact(
    designId: designId,
    kind: 'waveform',
    path: tracePath,
    producer: 'simcrux',
    topModule: 'rvfi',
    basename: 'trace.vcd',
  );
}

/// Runs the real inbound hand-off — a CXP `request_highlight` for an
/// [ElementKind.source] naming [tracePath], exactly what SimCrux's
/// `debug_in_wavecrux_dispatcher` sends — over the real workspace, tab
/// container manager and VCD reader, and returns the tab it opened.
///
/// Nothing here is a stand-in for the production path: [dispatchCxpHighlight]
/// is the production entry point, `WaveCruxWorkspaceNotifier.openFile` opens
/// the tab, and [StreamingVcdService] parses the bytes on disk.
///
/// **`runAsync` is not optional here.** `testWidgets` runs its body inside
/// `FakeAsync`, where a real filesystem future never completes — and this whole
/// file's premise is that the bytes on disk are real. Every step that touches
/// the disk (the VCD parse, the workspace save, the artifact store) runs in the
/// real zone; only the pumping afterwards runs in the fake one.
Future<_CrossProbeHarness> _openCounterexampleByCrossProbe(
  WidgetTester tester,
  String tracePath,
  CxpStreamCoordinate? coordinate,
) async {
  final tcm = TabContainerManager(
    extraTabOverrides: [
      waveformSourceProvider.overrideWith(_RealTraceSourceNotifier.new),
    ],
  );
  final store = CxpWorkspaceStore(
    workspaceDirectory: Directory.systemTemp
        .createTempSync('cxp_riscv_mount_')
        .path,
  );
  final root = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      ...testWorkspaceOverrides(),
      tabContainerManagerProvider.overrideWithValue(tcm),
      cxpWorkspaceStoreProvider.overrideWithValue(store),
      // The bundled TOML corpus, read straight off disk and composed as RV32 —
      // the same override the Commit Inspector's own widget tests use, so the
      // fixture's encodings are not shadowed by the RV64I redefinitions.
      riscvDisassemblerProvider.overrideWith((ref) async => rv32Disassembler()),
    ],
  );
  tcm.init(root);
  addTearDown(() {
    tcm.dispose();
    root.dispose();
  });

  final harness = await tester.runAsync(() async {
    final result = await dispatchCxpHighlight(
      root.read(_refProvider),
      ElementId(kind: ElementKind.source, path: tracePath),
      const <String, Object?>{},
      coordinate,
    );
    expect(result.honored, isTrue, reason: result.reason ?? '');
    await root.wavecruxWorkspace.flushPendingSave();
    return _CrossProbeHarness(
      root: root,
      tab: tcm.containerFor(root.read(activeTabIdProvider)),
      store: store,
      tracePath: tracePath,
    );
  });
  return harness!;
}

/// Pumps the inspector the hand-off mounted, inside the very tab container it
/// mounted it into — so the widget reads the same per-tab source, cursor and
/// landing the hand-off wrote.
///
/// **At the instance's own rect, not the whole surface.** The Stage canvas
/// gives an instance exactly `Positioned(width: i.width, height: i.height)`,
/// and pumping the renderer into a full-screen `Scaffold` body instead handed
/// it 700 px of height it never has in the product — which is how a test could
/// assert the landed row existed and was tinted while the user, looking at a
/// 380 px panel, saw two `addi` rows and had to go hunting for it. The box now
/// tracks whatever size the auto-mount chose, so shrinking that size fails
/// here rather than in a walkthrough.
Future<void> _pumpMountedInspector(
  WidgetTester tester,
  _CrossProbeHarness harness,
  StageInstance instance,
) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.tab,
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: instance.width,
              height: instance.height,
              child: RiscvCommitStageRenderer(instance: instance),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A per-tab source notifier that opens the **real** VCD with the production
/// streaming reader — the point of this file is that nothing between the bytes
/// on disk and the rendered row is faked.
class _RealTraceSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() =>
      const AsyncData<WaveformDataSource?>(null);

  @override
  Future<void> openFile(String path, {bool preserveDecoders = false}) async {
    currentFilePath = path;
    final source = StreamingVcdService();
    await source.openFile(path);
    await source.streamEndedFuture;
    addTearDown(source.close);
    state = AsyncData(source);
  }
}

/// FNV-1a of SimCrux's committed `insn_sub_counterexample` trace.
///
/// The same constant is asserted in SimCrux's own contract test against the
/// canonical file, so the two copies cannot drift apart silently.
const String kCounterexampleTraceDigest = '9e3350f6';

/// FNV-1a/32 over [text] with carriage returns dropped, so a CRLF checkout
/// digests the same as an LF one. Hand-rolled because a cross-repo pin is not
/// worth a dependency in either package, and 32 bits because the literals then
/// stay exact on every compile target.
String fixtureDigest(String text) {
  var hash = 0x811C9DC5;
  for (final unit in text.codeUnits) {
    if (unit == 0x0D) continue;
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

final Provider<Ref> _refProvider = Provider<Ref>((ref) => ref);

class _PreloadedSourceNotifier extends WaveformSourceNotifier {
  _PreloadedSourceNotifier(this._source);
  final WaveformDataSource _source;
  @override
  AsyncValue<WaveformDataSource> build() => AsyncData(_source);
}
