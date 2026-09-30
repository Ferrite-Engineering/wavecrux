// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_io/crux_io.dart' show SpawnHost;
import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/core/router.dart' show rootScaffoldMessengerKey;
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/stage/providers/riscv_commit_landing_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/recent_files_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/remote/cxp/cxp_inbound_handlers.dart';
import 'package:wavecrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_server.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/services/settings/settings_service.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../../../helpers/fake_waveform_data_source.dart';
import '../../../helpers/in_memory_workspace_service.dart';
import '../../../helpers/platform_absolute_path.dart';
import '../../../helpers/product_telemetry_config.dart';

void main() {
  // ── Test fixtures ───────────────────────────────────────────────────────────

  Scope buildScope() => const Scope(
    name: 'top',
    path: 'top',
    type: ScopeType.module,
    variables: [
      Variable(
        name: 'clk',
        varType: VarType.wire,
        direction: VarDirection.input,
        signalRef: 'top.clk',
        scopePath: 'top',
        bitWidth: 1,
      ),
      Variable(
        name: 'data',
        varType: VarType.wire,
        direction: VarDirection.input,
        signalRef: 'top.data',
        scopePath: 'top',
        bitWidth: 8,
      ),
    ],
    childScopes: [
      Scope(
        name: 'cpu',
        path: 'top.cpu',
        type: ScopeType.module,
        variables: [
          Variable(
            name: 'sum',
            varType: VarType.wire,
            direction: VarDirection.output,
            signalRef: 'top.cpu.sum',
            scopePath: 'top.cpu',
            bitWidth: 32,
          ),
        ],
      ),
    ],
  );

  ProviderContainer makeContainer({
    FakeWaveformDataSource? source,
    AppSettings settings = const AppSettings(),
    CxpEditorCommandRunner? editorRunner,
    List<String>? openDirectories,
  }) {
    final overrides = <Override>[
      // CXP §11's containment rule, stood up with a fixed root set instead of
      // the live "directories the user has opened" one: these tests drive the
      // handlers directly, with no workspace and no tabs, so the production
      // provider would report nothing open and refuse every path. The rule
      // object is the real one — only where its roots come from is faked.
      cxpPathContainmentProvider.overrideWithValue(
        CxpPathContainment(
          roots: () => openDirectories ?? <String>[platformAbsolute('/rtl')],
        ),
      ),
      settingsServiceProvider.overrideWithValue(
        const _FakeSettingsService(),
      ),
      // Pre-populate the AppSettings so cxpEditorCommand-based tests don't
      // have to await an async load.
      appSettingsProvider.overrideWith(
        () => _FakeAppSettingsNotifier(settings),
      ),
      if (source != null)
        waveformSourceProvider.overrideWith(
          () => _PreloadedSourceNotifier(source),
        ),
      if (editorRunner != null)
        cxpEditorCommandRunnerProvider.overrideWithValue(editorRunner),
    ];
    return ProviderContainer(overrides: [productTelemetryConfig, ...overrides]);
  }

  // ── dispatchCxpHighlight ────────────────────────────────────────────────────

  group('dispatchCxpHighlight signal', () {
    test('returns no_waveform_file_loaded when source is null', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        const ElementId(kind: ElementKind.signal, path: 'top.clk'),
      );
      expect(result.honored, isFalse);
      expect(result.reason, contains('no waveform file loaded'));
    });

    test('adds the signal to the viewer and focuses it', () async {
      final source = FakeWaveformDataSource(scopes: [buildScope()]);
      final container = makeContainer(source: source);
      addTearDown(container.dispose);
      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        const ElementId(kind: ElementKind.signal, path: 'top.clk'),
      );
      expect(result.honored, isTrue);
      final entries = container.read(signalGroupsProvider).entries;
      expect(entries.map((e) => e.signalRef), contains('top.clk'));
      expect(container.read(selectedSignalProvider), 'top.clk');
      // The VIEWER draws its highlight from the per-tab selection (keyed by
      // fullPath), not the root focus — so the row is visibly selected too.
      expect(container.read(selectedVariablesProvider), contains('top.clk'));
    });

    test(
      'is idempotent — does not duplicate an already-present signal',
      () async {
        final source = FakeWaveformDataSource(scopes: [buildScope()]);
        final container = makeContainer(source: source);
        addTearDown(container.dispose);
        const id = ElementId(kind: ElementKind.signal, path: 'top.clk');
        await dispatchCxpHighlight(container.read(_refProvider), id);
        await dispatchCxpHighlight(container.read(_refProvider), id);
        final entries = container.read(signalGroupsProvider).entries;
        final matches = entries.where((e) => e.signalRef == 'top.clk');
        expect(matches, hasLength(1));
      },
    );

    test(
      'returns honored=false when the signal is not in the loaded file',
      () async {
        final source = FakeWaveformDataSource(scopes: [buildScope()]);
        final container = makeContainer(source: source);
        addTearDown(container.dispose);
        final result = await dispatchCxpHighlight(
          container.read(_refProvider),
          const ElementId(kind: ElementKind.signal, path: 'top.nosuch'),
        );
        expect(result.honored, isFalse);
        expect(result.reason, contains('element not found'));
      },
    );
  });

  // Cross-tool net cross-probe (NetCrux → WaveCrux). NetCrux now emits the
  // net's hierarchical NAME, e.g. `cdc_capture.sample_a`; WaveCrux resolves
  // that against a differently-rooted testbench signal by matching the leaf.
  group('dispatchCxpHighlight net (cross-tool leaf resolution)', () {
    // A testbench-rooted hierarchy: `tb_cdc_capture.dut.sample_a`, leaf
    // `sample_a`. This is exactly the shape a VCD from the SimCrux bench of
    // cdc_capture.v produces (dut instance under the tb top).
    Scope tbScope() => const Scope(
      name: 'tb_cdc_capture',
      path: 'tb_cdc_capture',
      type: ScopeType.module,
      variables: <Variable>[
        Variable(
          name: 'clk_b',
          varType: VarType.wire,
          direction: VarDirection.input,
          signalRef: 'sig-clkb',
          scopePath: 'tb_cdc_capture',
          bitWidth: 1,
        ),
      ],
      childScopes: <Scope>[
        Scope(
          name: 'dut',
          path: 'tb_cdc_capture.dut',
          type: ScopeType.module,
          variables: <Variable>[
            Variable(
              name: 'sample_a',
              varType: VarType.reg,
              direction: VarDirection.unknown,
              signalRef: 'sig-sample-a',
              scopePath: 'tb_cdc_capture.dut',
              bitWidth: 8,
            ),
          ],
        ),
      ],
    );

    test(
      "a NetCrux net path 'cdc_capture.sample_a' resolves to the "
      'testbench-rooted signal by leaf and focuses it',
      () async {
        final source = FakeWaveformDataSource(scopes: [tbScope()]);
        final container = makeContainer(source: source);
        addTearDown(container.dispose);
        final result = await dispatchCxpHighlight(
          container.read(_refProvider),
          const ElementId(kind: ElementKind.net, path: 'cdc_capture.sample_a'),
        );
        expect(result.honored, isTrue);
        expect(
          container.read(signalGroupsProvider).entries.map((e) => e.signalRef),
          contains('sig-sample-a'),
        );
        expect(container.read(selectedSignalProvider), 'sig-sample-a');
        // The row the viewer renders is highlighted via the per-tab selection,
        // keyed by fullPath (the leaf-resolved testbench path).
        expect(
          container.read(selectedVariablesProvider),
          contains('tb_cdc_capture.dut.sample_a'),
        );
      },
    );

    test('an exact fullPath still wins over the leaf tier', () async {
      final source = FakeWaveformDataSource(scopes: [tbScope()]);
      final container = makeContainer(source: source);
      addTearDown(container.dispose);
      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        const ElementId(
          kind: ElementKind.net,
          path: 'tb_cdc_capture.dut.sample_a',
        ),
      );
      expect(result.honored, isTrue);
      expect(container.read(selectedSignalProvider), 'sig-sample-a');
    });

    test('a completely unknown net path selects nothing', () async {
      final source = FakeWaveformDataSource(scopes: [tbScope()]);
      final container = makeContainer(source: source);
      addTearDown(container.dispose);
      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        const ElementId(kind: ElementKind.net, path: 'cdc_capture.no_such_net'),
      );
      expect(result.honored, isFalse);
      expect(result.reason, contains('element not found'));
      expect(container.read(signalGroupsProvider).entries, isEmpty);
    });

    test(
      'a leaf that matches multiple signals picks the shortest fullPath '
      'deterministically',
      () async {
        // Two `sample_a` signals at different depths. The shallower
        // `top.sample_a` (shorter fullPath) is the documented tie-break.
        final source = FakeWaveformDataSource(
          scopes: <Scope>[
            const Scope(
              name: 'top',
              path: 'top',
              type: ScopeType.module,
              variables: <Variable>[
                Variable(
                  name: 'sample_a',
                  varType: VarType.reg,
                  direction: VarDirection.unknown,
                  signalRef: 'sig-shallow',
                  scopePath: 'top',
                  bitWidth: 8,
                ),
              ],
              childScopes: <Scope>[
                Scope(
                  name: 'dut',
                  path: 'top.dut',
                  type: ScopeType.module,
                  variables: <Variable>[
                    Variable(
                      name: 'sample_a',
                      varType: VarType.reg,
                      direction: VarDirection.unknown,
                      signalRef: 'sig-deep',
                      scopePath: 'top.dut',
                      bitWidth: 8,
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        final container = makeContainer(source: source);
        addTearDown(container.dispose);
        final result = await dispatchCxpHighlight(
          container.read(_refProvider),
          const ElementId(kind: ElementKind.net, path: 'cdc_capture.sample_a'),
        );
        expect(result.honored, isTrue);
        expect(container.read(selectedSignalProvider), 'sig-shallow');
      },
    );

    // ── Regression: the scope-blind tiebreak ────────────────────────────────
    //
    // Found by a temporal fan-in name-resolution spike against picorv32.
    // Elaborated with
    // ENABLE_MUL/ENABLE_DIV, picorv32 has two real submodules behind `generate`
    // blocks, and the parent declares its OWN `pcpi_rd` while connecting each
    // child's `pcpi_rd` to a differently-named net (`pcpi_mul_rd`). Under the
    // old shortest-path tiebreak, a cross-probe of the child's `pcpi_rd`
    // resolved to the PARENT's — a different wire, a different value, and no
    // indication to the user that anything was wrong.
    //
    // Measured over 229 public nets: 197 exactly correct before, 218 after;
    // 8 wrong-wire resolutions before, 0 after. Zero misses either way — the
    // old matcher always found something, it just sometimes found the wrong
    // thing, which is the failure mode worth a regression test.
    test(
      'a submodule net whose name also exists in the parent resolves to the '
      'SUBMODULE, not the shallower parent net',
      () async {
        final source = FakeWaveformDataSource(
          scopes: <Scope>[
            const Scope(
              name: 'testbench',
              path: 'testbench',
              type: ScopeType.module,
              childScopes: <Scope>[
                Scope(
                  name: 'uut',
                  path: 'testbench.uut',
                  type: ScopeType.module,
                  // The parent's own pcpi_rd — the mux output, a different wire
                  // from either child's. Shorter path, so the old tiebreak
                  // always picked it.
                  variables: <Variable>[
                    Variable(
                      name: 'pcpi_rd',
                      varType: VarType.wire,
                      direction: VarDirection.unknown,
                      signalRef: 'sig-parent-pcpi-rd',
                      scopePath: 'testbench.uut',
                      bitWidth: 32,
                    ),
                  ],
                  childScopes: <Scope>[
                    Scope(
                      name: 'genblk2',
                      path: 'testbench.uut.genblk2',
                      type: ScopeType.module,
                      childScopes: <Scope>[
                        Scope(
                          name: 'pcpi_div',
                          path: 'testbench.uut.genblk2.pcpi_div',
                          type: ScopeType.module,
                          variables: <Variable>[
                            Variable(
                              name: 'pcpi_rd',
                              varType: VarType.wire,
                              direction: VarDirection.output,
                              signalRef: 'sig-div-pcpi-rd',
                              scopePath: 'testbench.uut.genblk2.pcpi_div',
                              bitWidth: 32,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        final container = makeContainer(source: source);
        addTearDown(container.dispose);
        // What NetCrux actually sends: top module name + the instance path.
        // Yosys keeps the generate-block prefix in the instance name
        // (`genblk2.pcpi_div`), which is what makes the tail agree with the
        // VCD's own scope path and lets the right candidate win.
        final result = await dispatchCxpHighlight(
          container.read(_refProvider),
          const ElementId(
            kind: ElementKind.net,
            path: 'picorv32.genblk2.pcpi_div.pcpi_rd',
          ),
        );
        expect(result.honored, isTrue);
        expect(
          container.read(selectedSignalProvider),
          'sig-div-pcpi-rd',
          reason:
              'the parent net is shallower and would win a shortest-path '
              'tiebreak, but it is a different wire carrying a different value',
        );
      },
    );

    test(
      'no waveform loaded returns an actionable no-waveform result '
      '(surfaced as a snackbar on the notify_selection path)',
      () async {
        final container = makeContainer();
        addTearDown(container.dispose);
        final result = await dispatchCxpHighlight(
          container.read(_refProvider),
          const ElementId(kind: ElementKind.net, path: 'cdc_capture.sample_a'),
        );
        expect(result.honored, isFalse);
        expect(result.reason, contains('no waveform file loaded'));
      },
    );
  });

  // handleInboundSelection is the notify_selection front door: it stashes
  // (for a following source-open) AND, when a waveform is already open,
  // highlights the referenced signal live so a NetCrux cross-probe visibly
  // does something.
  group('handleInboundSelection (live cross-probe highlight)', () {
    Scope tbScope() => const Scope(
      name: 'tb_cdc_capture',
      path: 'tb_cdc_capture',
      type: ScopeType.module,
      childScopes: <Scope>[
        Scope(
          name: 'dut',
          path: 'tb_cdc_capture.dut',
          type: ScopeType.module,
          variables: <Variable>[
            Variable(
              name: 'sample_a',
              varType: VarType.reg,
              direction: VarDirection.unknown,
              signalRef: 'sig-sample-a',
              scopePath: 'tb_cdc_capture.dut',
              bitWidth: 8,
            ),
          ],
        ),
      ],
    );

    test(
      'a net notify_selection with a waveform open highlights the signal live',
      () async {
        final source = FakeWaveformDataSource(scopes: [tbScope()]);
        final container = makeContainer(source: source);
        addTearDown(container.dispose);

        handleInboundSelection(
          container.read(_refProvider),
          const [
            ElementId(kind: ElementKind.net, path: 'cdc_capture.sample_a'),
          ],
          const <String, Object?>{},
        );
        // The live highlight is fire-and-forget; let the microtask complete.
        await Future<void>.delayed(Duration.zero);

        expect(container.read(selectedSignalProvider), 'sig-sample-a');
        expect(
          container.read(signalGroupsProvider).entries.map((e) => e.signalRef),
          contains('sig-sample-a'),
        );
        // The per-tab selection (the row the viewer highlights) is asserted
        // deterministically by the direct-dispatch cases above; this
        // fire-and-forget path shares a real (un-overridden) workspace whose
        // async tab creation makes which container `_readActive` targets
        // nondeterministic, so it is intentionally not asserted here.
      },
    );

    test(
      'still stashes signal-like elements for a following source-open handoff',
      () async {
        // A source is loaded so the live-highlight path runs headlessly
        // (the no-waveform branch would try to raise a snackbar, which needs
        // a widget binding — covered separately by a testWidgets case).
        final source = FakeWaveformDataSource(scopes: [tbScope()]);
        final container = makeContainer(source: source);
        addTearDown(container.dispose);
        handleInboundSelection(
          container.read(_refProvider),
          const [
            ElementId(kind: ElementKind.net, path: 'cdc_capture.sample_a'),
          ],
          const <String, Object?>{},
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(cxpSuggestedSignalsProvider),
          const ['cdc_capture.sample_a'],
        );
      },
    );

    testWidgets(
      'a net notify_selection with NO waveform open surfaces the '
      '"open a waveform first" snackbar',
      (tester) async {
        final container = makeContainer();
        addTearDown(container.dispose);
        // Mount a MaterialApp wired to the same global messenger key the
        // handler posts to, so the snackbar has a live binding + Localizations.
        await tester.pumpWidget(
          MaterialApp(
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              L10N.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L10N.supportedLocales,
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        );

        handleInboundSelection(
          container.read(_refProvider),
          const [
            ElementId(kind: ElementKind.net, path: 'cdc_capture.sample_a'),
          ],
          const <String, Object?>{},
        );
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.text('Open a waveform file to cross-probe this signal'),
          findsOneWidget,
        );
      },
    );
  });

  // Port / cell cross-probe (NetCrux → WaveCrux). NetCrux now emits a CLEAN
  // dot-joined hierarchical name for a boundary port (`fsm_lock.state`) with
  // kind `port` — never the old `fsm_lock:port:state` marked form that split on
  // `.` to the whole string and never matched. WaveCrux resolves the clean path
  // by leaf against a differently-rooted testbench signal, and also tolerates
  // the marked form as a safety net for a pre-fix peer.
  group('dispatchCxpHighlight port/cell (cross-tool leaf resolution)', () {
    // A testbench-rooted hierarchy whose DUT exposes the FSM `state` register,
    // exactly the shape a bench VCD of fsm_lock.v produces.
    Scope fsmTbScope() => const Scope(
      name: 'tb_fsm_lock',
      path: 'tb_fsm_lock',
      type: ScopeType.module,
      childScopes: <Scope>[
        Scope(
          name: 'dut',
          path: 'tb_fsm_lock.dut',
          type: ScopeType.module,
          variables: <Variable>[
            Variable(
              name: 'state',
              varType: VarType.reg,
              direction: VarDirection.output,
              signalRef: 'sig-state',
              scopePath: 'tb_fsm_lock.dut',
              bitWidth: 3,
            ),
          ],
        ),
      ],
    );

    test(
      "a clean boundary-port path 'fsm_lock.state' (kind port) resolves to the "
      'testbench signal by leaf, and adds + selects + reveals it',
      () async {
        final source = FakeWaveformDataSource(scopes: [fsmTbScope()]);
        final container = makeContainer(source: source);
        addTearDown(container.dispose);
        final result = await dispatchCxpHighlight(
          container.read(_refProvider),
          const ElementId(kind: ElementKind.port, path: 'fsm_lock.state'),
        );
        expect(result.honored, isTrue);
        // Added to the canvas…
        expect(
          container.read(signalGroupsProvider).entries.map((e) => e.signalRef),
          contains('sig-state'),
        );
        expect(container.read(selectedSignalProvider), 'sig-state');
        // …SELECTED (the per-tab highlight the viewer draws, keyed by fullPath)…
        expect(
          container.read(selectedVariablesProvider),
          contains('tb_fsm_lock.dut.state'),
        );
        // …and REVEALED (its lane scrolled into view).
        expect(
          container.read(revealSignalRequestProvider)?.fullPath,
          'tb_fsm_lock.dut.state',
        );
      },
    );

    test(
      "a MARKED port path 'top:port:state' still leaf-resolves to a signal "
      'whose fullPath ends in .state (pre-fix-peer safety net)',
      () async {
        final source = FakeWaveformDataSource(scopes: [fsmTbScope()]);
        final container = makeContainer(source: source);
        addTearDown(container.dispose);
        final result = await dispatchCxpHighlight(
          container.read(_refProvider),
          const ElementId(kind: ElementKind.port, path: 'top:port:state'),
        );
        expect(result.honored, isTrue);
        expect(container.read(selectedSignalProvider), 'sig-state');
        expect(
          container.read(selectedVariablesProvider),
          contains('tb_fsm_lock.dut.state'),
        );
      },
    );

    test(
      'a MARKED net path "top:net:state" also leaf-resolves via the marker '
      '(net/cell markers tolerated too)',
      () async {
        final source = FakeWaveformDataSource(scopes: [fsmTbScope()]);
        final container = makeContainer(source: source);
        addTearDown(container.dispose);
        final result = await dispatchCxpHighlight(
          container.read(_refProvider),
          const ElementId(kind: ElementKind.net, path: 'top:net:state'),
        );
        expect(result.honored, isTrue);
        expect(container.read(selectedSignalProvider), 'sig-state');
      },
    );
  });

  group('dispatchCxpHighlight scope', () {
    test('adds every variable in the scope', () async {
      final source = FakeWaveformDataSource(scopes: [buildScope()]);
      final container = makeContainer(source: source);
      addTearDown(container.dispose);
      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        const ElementId(kind: ElementKind.scope, path: 'top'),
      );
      expect(result.honored, isTrue);
      final refs = container
          .read(signalGroupsProvider)
          .entries
          .map((e) => e.signalRef);
      expect(refs, containsAll(['top.clk', 'top.data', 'top.cpu.sum']));
    });

    test('returns honored=false for an unknown scope', () async {
      final source = FakeWaveformDataSource(scopes: [buildScope()]);
      final container = makeContainer(source: source);
      addTearDown(container.dispose);
      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        const ElementId(kind: ElementKind.scope, path: 'nosuch'),
      );
      expect(result.honored, isFalse);
      expect(result.reason, contains('scope not found'));
    });
  });

  group('dispatchCxpHighlight marker', () {
    test('moves the primary cursor to the marker time', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      container.read(markerStateProvider.notifier).setMarker('a', 12345);
      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        const ElementId(kind: ElementKind.marker, path: 'a'),
      );
      expect(result.honored, isTrue);
      expect(container.read(cursorStateProvider).primaryCursorTime, 12345);
    });

    test('returns honored=false when the marker is not set', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        const ElementId(kind: ElementKind.marker, path: 'z'),
      );
      expect(result.honored, isFalse);
      expect(result.reason, contains('marker not set'));
    });

    test('returns honored=false for a malformed marker name', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        const ElementId(kind: ElementKind.marker, path: 'ab'),
      );
      expect(result.honored, isFalse);
    });
  });

  group('dispatchCxpHighlight unsupported kinds', () {
    test(
      'source (RTL/lint citation) returns honored=false with the documented '
      'v1 "no signal mapping" reason + request_open_source hint (P47 c)',
      () async {
        final container = makeContainer();
        addTearDown(container.dispose);
        final result = await dispatchCxpHighlight(
          container.read(_refProvider),
          // A LintCrux lint citation (file:line:column) — not a waveform file.
          const ElementId(kind: ElementKind.source, path: 'rtl/cpu.v:61:7'),
        );
        expect(result.honored, isFalse);
        // Documented v1 behaviour: WaveCrux has no source-line→signal mapping,
        // so LintCrux (P47 b) can surface "can't map a source line to a signal".
        expect(result.reason, contains('no signal mapping'));
        // Still hints the RTL-navigation caller to retry as an open request.
        expect(result.reason, contains('request_open_source'));
      },
    );

    test('rule/test/breakpoint return honored=false', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      for (final kind in const [
        ElementKind.rule,
        ElementKind.test,
        ElementKind.breakpoint,
      ]) {
        final result = await dispatchCxpHighlight(
          container.read(_refProvider),
          ElementId(kind: kind, path: 'x'),
        );
        expect(result.honored, isFalse, reason: kind.name);
        expect(result.reason, contains('wavecrux does not handle'));
      }
    });

    test('a kind this build has never heard of is ignored gracefully', () async {
      // `ElementKind` is an open wire type — a peer built against a later
      // protocol revision may send a kind that is not in `ElementKind.values`.
      // The ruling: no-op the handler and reply honored=false. It must not
      // throw, and it must not guess that the path is signal-like and
      // highlight the wrong object.
      final container = makeContainer();
      addTearDown(container.dispose);
      final unknown = ElementKind('quantum_gate');
      expect(unknown.known, isNull);

      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        ElementId(kind: unknown, path: 'top.clk'),
      );

      expect(result.honored, isFalse);
      expect(result.reason, contains('quantum_gate'));
    });
  });

  // ── notify_selection suggested-signal resolution ────────────────────────────

  group('resolveSuggestedSignals', () {
    // The flattened variable set the source hierarchy exposes:
    //   top.clk, top.data          (directly under the top scope)
    //   top.cpu.sum                (nested one level down)
    final allVars = FakeWaveformDataSource(
      scopes: [buildScope()],
    ).findVariables(const SignalFilter());

    test(
      "a '<scope>.*' glob resolves to every signal under the scope, "
      'nested instances included',
      () {
        // This is exactly what SimCrux's "Debug in WaveCrux" handoff sends —
        // deriveSuggestedSignalsFromTopModule returns ['<topModule>.*'].
        final resolved = resolveSuggestedSignals(const ['top.*'], allVars);
        expect(
          resolved.map((v) => v.fullPath),
          containsAll(<String>['top.clk', 'top.data', 'top.cpu.sum']),
        );
        // The nested cpu.sum proves the glob spans the '.' separator.
        expect(resolved.map((v) => v.fullPath), contains('top.cpu.sum'));
        expect(resolved, hasLength(3));
      },
    );

    test('a nested-scope glob resolves only that subtree', () {
      final resolved = resolveSuggestedSignals(const ['top.cpu.*'], allVars);
      expect(resolved.map((v) => v.fullPath), <String>['top.cpu.sum']);
    });

    test('a glob that matches no scope resolves to nothing', () {
      final resolved = resolveSuggestedSignals(const ['missing.*'], allVars);
      expect(resolved, isEmpty);
    });

    test('an exact name still resolves by fullPath', () {
      final resolved = resolveSuggestedSignals(const ['top.clk'], allVars);
      expect(resolved.map((v) => v.fullPath), <String>['top.clk']);
    });

    test('an exact name still resolves by opaque signalRef', () {
      // buildScope() sets signalRef == fullPath here, but the exact branch
      // must accept a match on signalRef independently.
      final resolved = resolveSuggestedSignals(const ['top.cpu.sum'], allVars);
      expect(resolved.single.signalRef, 'top.cpu.sum');
    });

    test('overlapping entries are de-duplicated by signalRef', () {
      final resolved = resolveSuggestedSignals(
        const ['top.*', 'top.clk', 'top.cpu.*'],
        allVars,
      );
      // top.clk (exact) and top.cpu.sum (nested glob) already came in via
      // 'top.*'; the union stays at the three distinct variables.
      expect(resolved, hasLength(3));
    });
  });

  // ── notify_selection stash (metadata channel) ───────────────────────────────

  group('stashCxpSelectionSignals', () {
    final allVars = FakeWaveformDataSource(
      scopes: [buildScope()],
    ).findVariables(const SignalFilter());

    test(
      'stashes the simcrux.suggested_signals globs from metadata even when '
      'elements carries only the source VCD, and the stash resolves to the '
      'right variables',
      () {
        final container = makeContainer();
        addTearDown(container.dispose);
        final ref = container.read(_refProvider);

        // Mirror the real SimCrux "Debug in WaveCrux" send: elements is just
        // the source-VCD element (no signal hints); the globs live in
        // metadata under 'simcrux.suggested_signals'.
        stashCxpSelectionSignals(
          ref,
          const [ElementId(kind: ElementKind.source, path: '/tmp/cdc.vcd')],
          const <String, Object?>{
            'simcrux.suggested_signals': <String>['top.*'],
          },
        );

        final stashed = container.read(cxpSuggestedSignalsProvider);
        expect(stashed, <String>['top.*']);

        // Full pipeline: the stashed glob expands to the whole scope subtree.
        final resolved = resolveSuggestedSignals(stashed, allVars);
        expect(
          resolved.map((v) => v.fullPath),
          containsAll(<String>['top.clk', 'top.data', 'top.cpu.sum']),
        );
        expect(resolved, hasLength(3));
      },
    );

    test('guards the metadata value — only String entries survive', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProvider);

      stashCxpSelectionSignals(
        ref,
        const <ElementId>[],
        const <String, Object?>{
          'simcrux.suggested_signals': <Object?>['top.*', 42, null],
        },
      );

      expect(container.read(cxpSuggestedSignalsProvider), <String>['top.*']);
    });

    test('ignores a non-List metadata value and stashes nothing', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProvider);

      stashCxpSelectionSignals(
        ref,
        const <ElementId>[],
        const <String, Object?>{'simcrux.suggested_signals': 'top.*'},
      );

      expect(container.read(cxpSuggestedSignalsProvider), isEmpty);
    });

    test(
      'falls back to signal-like element paths when the metadata key is absent',
      () {
        final container = makeContainer();
        addTearDown(container.dispose);
        final ref = container.read(_refProvider);

        stashCxpSelectionSignals(
          ref,
          const [
            ElementId(kind: ElementKind.signal, path: 'top.clk'),
            ElementId(kind: ElementKind.source, path: '/tmp/cdc.vcd'),
          ],
          const <String, Object?>{},
        );

        // The source element is dropped; the signal element is kept.
        expect(
          container.read(cxpSuggestedSignalsProvider),
          <String>['top.clk'],
        );
      },
    );
  });

  // ── dispatchCxpOpenSource ───────────────────────────────────────────────────

  group('dispatchCxpOpenSource', () {
    // Absolute on the host: see `platformAbsolute`.
    final cpuV = platformAbsolute('/rtl/cpu.v');
    final shadow = platformAbsolute('/etc/shadow');

    test(
      'returns honored=false when no editor command is configured',
      () async {
        final container = makeContainer();
        addTearDown(container.dispose);
        final result = await dispatchCxpOpenSource(
          container.read(_refProvider),
          cpuV,
          42,
          null,
        );
        expect(result.honored, isFalse);
        expect(result.reason, contains('no editor command configured'));
      },
    );

    test('invokes the editor command runner with file:line', () async {
      final calls = <(String, String)>[];
      final container = makeContainer(
        settings: const AppSettings(cxpEditorCommand: 'code -g'),
        editorRunner: (command, target) async {
          calls.add((command, target));
          return CxpHandlerResult.honoredOk;
        },
      );
      addTearDown(container.dispose);
      // Wait for the async appSettingsProvider build to resolve.
      await container.read(appSettingsProvider.future);
      final result = await dispatchCxpOpenSource(
        container.read(_refProvider),
        cpuV,
        42,
        null,
      );
      expect(result.honored, isTrue);
      expect(calls, [('code -g', '$cpuV:42')]);
    });

    test('invokes the editor command runner with file:line:column', () async {
      final calls = <(String, String)>[];
      final container = makeContainer(
        settings: const AppSettings(cxpEditorCommand: 'subl'),
        editorRunner: (command, target) async {
          calls.add((command, target));
          return CxpHandlerResult.honoredOk;
        },
      );
      addTearDown(container.dispose);
      await container.read(appSettingsProvider.future);
      await dispatchCxpOpenSource(
        container.read(_refProvider),
        cpuV,
        42,
        7,
      );
      expect(calls, [('subl', '$cpuV:42:7')]);
    });

    test('passes through honored=false from the runner', () async {
      final container = makeContainer(
        settings: const AppSettings(cxpEditorCommand: 'nope'),
        editorRunner: (_, _) async => const CxpHandlerResult(
          honored: false,
          reason: 'editor not found: nope',
        ),
      );
      addTearDown(container.dispose);
      await container.read(appSettingsProvider.future);
      final result = await dispatchCxpOpenSource(
        container.read(_refProvider),
        cpuV,
        1,
        null,
      );
      expect(result.honored, isFalse);
      expect(result.reason, contains('not found'));
    });

    // `file_path` is whatever reached the listening socket. It is
    // concatenated into a `file:line` target and appended to the editor's
    // argv; the exposure is not a shell (there is none) but the editor's own
    // option parser — to `vim` and `emacs` an argv element beginning with `+`
    // is an ex command, not a filename.
    //
    // The CXP specification already requires `file_path` to be an absolute
    // path on the local filesystem, so refusing everything else costs no
    // legitimate caller anything.
    //
    // MUTATION: deleting the containment check in `dispatchCxpOpenSource`
    // makes every test in the two groups below red.
    Future<CxpHandlerResult> dispatch(
      String filePath, {
      required List<(String, String)> calls,
      List<String>? openDirectories,
    }) async {
      final container = makeContainer(
        settings: const AppSettings(cxpEditorCommand: 'vim +'),
        editorRunner: (command, target) async {
          calls.add((command, target));
          return CxpHandlerResult.honoredOk;
        },
        openDirectories: openDirectories,
      );
      addTearDown(container.dispose);
      await container.read(appSettingsProvider.future);
      return await dispatchCxpOpenSource(
        container.read(_refProvider),
        filePath,
        42,
        null,
      );
    }

    group('refuses a file_path that is not an absolute path', () {
      test('an ex command whose second character is a colon', () async {
        final calls = <(String, String)>[];
        final result = await dispatch('+:!curl x|sh', calls: calls);
        expect(result.honored, isFalse);
        expect(result.reason, contains('absolute'));
        expect(calls, isEmpty, reason: 'nothing may be spawned');
      });

      test('a drive letter not followed by a separator', () async {
        final calls = <(String, String)>[];
        final result = await dispatch('Z:+!curl x|sh', calls: calls);
        expect(result.honored, isFalse);
        expect(calls, isEmpty);
      });

      test('a relative path climbing out of the tree', () async {
        final calls = <(String, String)>[];
        final result = await dispatch('../../../etc/shadow', calls: calls);
        expect(result.honored, isFalse);
        expect(calls, isEmpty);
      });

      test('a plain relative path', () async {
        final calls = <(String, String)>[];
        final result = await dispatch('rtl/cpu.v', calls: calls);
        expect(result.honored, isFalse);
        expect(calls, isEmpty);
      });

      test('an empty path, and one carrying a NUL', () async {
        final empty = <(String, String)>[];
        expect((await dispatch('', calls: empty)).honored, isFalse);
        expect(empty, isEmpty);
        final nul = <(String, String)>[];
        expect(
          (await dispatch('$cpuV\u0000-evil', calls: nul)).honored,
          isFalse,
        );
        expect(nul, isEmpty);
      });

      test(
        'but still dispatches an absolute path inside an open root',
        () async {
          for (final path in <String>[
            cpuV,
            platformAbsolute('/rtl/core/alu.sv'),
          ]) {
            final calls = <(String, String)>[];
            final result = await dispatch(path, calls: calls);
            expect(result.honored, isTrue, reason: path);
            expect(calls, [('vim +', '$path:42')], reason: path);
          }
        },
      );
    });

    // CXP §11: resolve the path against the directories the user has already
    // opened and refuse the rest. This is the SHOULD the four products did
    // not implement — each checked only that the path was *absolute*, which
    // `/etc/shadow` is.
    //
    // These stand the rule up over fixed roots (see `makeContainer`), so they
    // prove the handler consults it and not where production roots come
    // from: dropping `roots` from `cxpPathContainmentProvider` leaves them
    // green. The production root set is held by the "production roots" group
    // below, which goes through the real provider.
    group('refuses a peer-supplied path outside the open directories', () {
      test('an absolute path in a directory nothing has opened', () async {
        final calls = <(String, String)>[];
        final result = await dispatch(shadow, calls: calls);
        expect(result.honored, isFalse);
        expect(result.reason, contains('outside the directories'));
        expect(
          result.reason,
          isNot(contains(shadow)),
          reason:
              'the reason travels back to the sender; §9.11 forbids '
              'echoing its own input at it',
        );
        expect(calls, isEmpty, reason: 'nothing may be spawned');
      });

      test('a sibling whose name merely starts with an open root', () async {
        final calls = <(String, String)>[];
        final result = await dispatch(
          platformAbsolute('/rtl-private/secrets.v'),
          calls: calls,
        );
        expect(result.honored, isFalse);
        expect(calls, isEmpty);
      });

      test('everything, while the session has nothing open', () async {
        final calls = <(String, String)>[];
        final result = await dispatch(
          cpuV,
          calls: calls,
          openDirectories: const <String>[],
        );
        expect(result.honored, isFalse);
        expect(result.reason, contains('no directory is open'));
        expect(calls, isEmpty);
      });
    });
  });

  group('splitEditorCommandArgs', () {
    test('single token', () {
      expect(splitEditorCommandArgs('code'), ['code']);
    });
    test('flags', () {
      expect(splitEditorCommandArgs('code -g'), ['code', '-g']);
    });
    test('quoted argument with spaces', () {
      expect(
        splitEditorCommandArgs('subl -a "open path"'),
        ['subl', '-a', 'open path'],
      );
    });
    test('mixed single + double quotes', () {
      expect(
        splitEditorCommandArgs("emacsclient -e '(switch-to-buffer)'"),
        ['emacsclient', '-e', '(switch-to-buffer)'],
      );
    });
    test('empty', () {
      expect(splitEditorCommandArgs(''), <String>[]);
    });
  });

  // The editor spawn behind `request_open_source`, on a Windows host laid out
  // with a synthetic PATH so the branch runs on every CI machine. On Windows a
  // bare editor name would be searched for in the directory WaveCrux was
  // launched from, ahead of PATH.
  group('runEditorCommand on Windows', () {
    const target = r'C:\rtl\cpu.v:12';

    test('spawns the editor PATH resolves to, with the target last', () async {
      final spawned = <(String, List<String>)>[];
      final result = await runEditorCommand(
        'code -g',
        target,
        host: SpawnHost(
          windows: true,
          environment: const {'PATH': r'C:\rtl;C:\VSCode\bin'},
          exists: (path) => path == r'C:\VSCode\bin\code.CMD',
        ),
        run: (exe, args) async {
          spawned.add((exe, args));
          return ProcessResult(0, 0, '', '');
        },
      );
      expect(result.honored, isTrue);
      expect(spawned, hasLength(1));
      expect(spawned.single.$1, r'C:\VSCode\bin\code.CMD');
      expect(spawned.single.$2, ['-g', target]);
    });

    test('an editor nothing on PATH answers to starts nothing', () async {
      var spawns = 0;
      final result = await runEditorCommand(
        'code -g',
        target,
        host: SpawnHost(
          windows: true,
          environment: const {'PATH': r'C:\Windows'},
          exists: (_) => false,
        ),
        run: (_, _) async {
          spawns++;
          return ProcessResult(0, 0, '', '');
        },
      );
      expect(spawns, 0);
      expect(result.honored, isFalse);
      expect(result.reason, 'editor not found: not found on PATH');
    });
  });

  _perTabRoutingTests(buildScope);
  _workspaceLinkR8Tests(buildScope);
  _sourceHandoffSelectionTests();
  _productionRootsTests();
  _streamCoordinateTests();
}

/// A root container wired the way the running app is: the real
/// `cxpPathContainmentProvider` (no override), so its roots come from the
/// real open-tab list and the real recent-files list. [recentFiles] seeds the
/// latter's persisted store.
///
/// The workspace store is pointed at [workspaceDirectory] so no test reads
/// the real per-user workspace, but it keeps the production wiring: it is
/// handed the same real containment rule.
Future<({ProviderContainer root, TabContainerManager tcm})> _productionRoots({
  required List<String> recentFiles,
  required String workspaceDirectory,
  CxpEditorCommandRunner? editorRunner,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'recent_files': recentFiles,
  });
  final tcm = TabContainerManager(
    extraTabOverrides: [
      waveformSourceProvider.overrideWith(
        _WorkspaceOpenableSourceNotifier.new,
      ),
    ],
  );
  final root = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      ...testWorkspaceOverrides(),
      tabContainerManagerProvider.overrideWithValue(tcm),
      settingsServiceProvider.overrideWithValue(const _FakeSettingsService()),
      appSettingsProvider.overrideWith(
        () => _FakeAppSettingsNotifier(
          const AppSettings(cxpEditorCommand: 'vim'),
        ),
      ),
      if (editorRunner != null)
        cxpEditorCommandRunnerProvider.overrideWithValue(editorRunner),
      cxpWorkspaceStoreProvider.overrideWith(
        (ref) => CxpWorkspaceStore(
          workspaceDirectory: workspaceDirectory,
          containment: ref.watch(cxpPathContainmentProvider),
        ),
      ),
    ],
  );
  tcm.init(root);
  await root.read(appSettingsProvider.future);
  await root.read(recentFilesProvider.future);
  return (root: root, tcm: tcm);
}

/// The containment roots as production computes them: the folder of every
/// open tab's file plus the folder of every recent-files entry. Every other
/// containment test in this file overrides `cxpPathContainmentProvider` with
/// fixed roots, which proves the handlers consult the rule but not that the
/// rule the app actually builds has the right roots.
///
/// MUTATION: deleting the `refuse` check in `dispatchCxpOpenSource`, or
/// dropping `roots:` from `cxpPathContainmentProvider` (leaving the floor),
/// turns the refusal test red; dropping either loop in `cxpOpenDirectories`
/// turns the matching honoured case red.
void _productionRootsTests() {
  group('production roots (open tabs + recent files)', () {
    late Directory tabDir;
    late Directory recentDir;
    late Directory elsewhere;

    setUp(() {
      tabDir = Directory.systemTemp.createTempSync('cxp_roots_tab_');
      recentDir = Directory.systemTemp.createTempSync('cxp_roots_recent_');
      elsewhere = Directory.systemTemp.createTempSync('cxp_roots_out_');
    });
    tearDown(() {
      for (final d in [tabDir, recentDir, elsewhere]) {
        d.deleteSync(recursive: true);
      }
    });

    Future<({ProviderContainer root, List<(String, String)> calls})>
    openSession() async {
      final calls = <(String, String)>[];
      final session = await _productionRoots(
        recentFiles: <String>[p.join(recentDir.path, 'earlier.vcd')],
        workspaceDirectory: p.join(elsewhere.path, 'workspace'),
        editorRunner: (command, target) async {
          calls.add((command, target));
          return CxpHandlerResult.honoredOk;
        },
      );
      addTearDown(() {
        session.tcm.dispose();
        session.root.dispose();
      });
      // The user has a waveform open in a tab.
      await session.root.wavecruxWorkspace.openFile(
        p.join(tabDir.path, 'design.vcd'),
      );
      await session.root.wavecruxWorkspace.flushPendingSave();
      return (root: session.root, calls: calls);
    }

    test(
      'honours a path under an open tab and under a recent file',
      () async {
        final session = await openSession();
        for (final path in <String>[
          p.join(tabDir.path, 'rtl', 'cpu.v'),
          p.join(recentDir.path, 'alu.sv'),
        ]) {
          final result = await dispatchCxpOpenSource(
            session.root.read(_refProvider),
            path,
            42,
            null,
          );
          expect(result.honored, isTrue, reason: path);
        }
        expect(session.calls, [
          ('vim', '${p.join(tabDir.path, 'rtl', 'cpu.v')}:42'),
          ('vim', '${p.join(recentDir.path, 'alu.sv')}:42'),
        ]);
      },
    );

    test('refuses a path outside every open tab and recent file', () async {
      final session = await openSession();
      final outside = p.join(elsewhere.path, 'secret.v');
      final result = await dispatchCxpOpenSource(
        session.root.read(_refProvider),
        outside,
        42,
        null,
      );
      expect(result.honored, isFalse);
      expect(result.reason, contains('outside the directories'));
      expect(result.reason, isNot(contains(outside)));
      expect(session.calls, isEmpty, reason: 'nothing may be spawned');
    });

    // `request_open_artifact` is held to the floor, not these roots: it
    // exists to open a waveform WaveCrux has never opened, which is what
    // "Open in WaveCrux Desktop" in VS Code sends (`kCxpOpenArtifactContainment`
    // says why). The route's refusals are in `cxp_open_artifact_test.dart`.
    //
    // MUTATION: checking the path with `cxpPathContainmentProvider` in
    // `dispatchCxpOpenArtifact` instead of `kCxpOpenArtifactContainment`
    // turns this red.
    test(
      'an open_artifact hint for a waveform never opened is honoured under '
      'the floor',
      () async {
        _quietAttention();
        final session = await openSession();
        final vcd = File(p.join(elsewhere.path, 'hint.vcd'))
          ..writeAsStringSync(r'$date $end $enddefinitions $end');
        expect(
          session.root.read(cxpPathContainmentProvider).allows(vcd.path),
          isFalse,
          reason: 'the premise: the roots would refuse this hand-off',
        );
        final tabsBefore = session.root.read(tabListProvider).length;
        final result = await dispatchCxpOpenArtifact(
          session.root.read(_refProvider),
          'no-such-design',
          'waveform',
          vcd.path,
        );
        expect(result.honored, isTrue, reason: result.reason);
        expect(session.root.read(tabListProvider).length, tabsBefore + 1);
        final activeTab = session.root
            .read(tabContainerManagerProvider)
            .containerFor(session.root.read(activeTabIdProvider));
        expect(
          activeTab.read(waveformSourceProvider.notifier).currentFilePath,
          vcd.path,
        );
      },
    );

    // A `request_highlight(source)` naming a waveform is SimCrux's "Debug in
    // WaveCrux" hand-off, and it is held to the containment FLOOR only
    // (absolute, well-formed, no NUL), never the roots: the dump it names is
    // in a simulation run folder no tab or recent file covers.
    //
    // MUTATION: deleting the floor check in `_highlightSource` turns the two
    // refusal tests red; switching it to `cxpPathContainmentProvider` (the
    // roots) turns the run-folder test red.
    group('a source hand-off is held to the floor, not the roots', () {
      Future<CxpHandlerResult> handOff(ProviderContainer root, String path) =>
          dispatchCxpHighlight(
            root.read(_refProvider),
            ElementId(kind: ElementKind.source, path: path),
          );

      test('a relative waveform path opens nothing', () async {
        final session = await openSession();
        final tabsBefore = session.root.read(tabListProvider).length;
        final result = await handOff(session.root, '../../evil.vcd');
        expect(result.honored, isFalse);
        expect(result.reason, contains('absolute path'));
        expect(result.reason, isNot(contains('evil.vcd')));
        expect(
          session.root.read(tabListProvider).length,
          tabsBefore,
          reason: 'no tab may be created for a path that was never openable',
        );
      });

      test('a waveform path carrying a NUL opens nothing', () async {
        final session = await openSession();
        final tabsBefore = session.root.read(tabListProvider).length;
        // Absolute, inside an open tab's folder, and ending in `.vcd`: only
        // the NUL is wrong with it.
        final result = await handOff(
          session.root,
          '${p.join(tabDir.path, 'dump')} .vcd',
        );
        expect(result.honored, isFalse);
        expect(result.reason, contains('NUL'));
        expect(session.root.read(tabListProvider).length, tabsBefore);
      });

      test(
        'an absolute run-folder waveform outside every root still opens',
        () async {
          final session = await openSession();
          final runDir = Directory(p.join(elsewhere.path, 'run_0001'))
            ..createSync();
          final vcd = File(p.join(runDir.path, 'dump.vcd'))
            ..writeAsStringSync(r'$date $end $enddefinitions $end');
          expect(
            session.root.read(cxpPathContainmentProvider).allows(vcd.path),
            isFalse,
            reason: 'the premise: the roots would refuse this hand-off',
          );

          final result = await handOff(session.root, vcd.path);

          expect(result.honored, isTrue, reason: result.reason);
          final activeTab = session.root
              .read(tabContainerManagerProvider)
              .containerFor(session.root.read(activeTabIdProvider));
          expect(
            activeTab.read(waveformSourceProvider.notifier).currentFilePath,
            vcd.path,
          );
        },
      );
    });
  });
}

/// The SimCrux "Debug in WaveCrux" handoff: a `notify_selection` stashes the
/// signals-to-show globs, then a `request_highlight(source)` opens the VCD in a
/// new tab. This proves the opened tab ends with those signals not just ADDED
/// to the canvas but SELECTED — the per-tab highlight the viewer renders — so
/// the handoff lands with a visible highlight instead of an inert canvas.
void _sourceHandoffSelectionTests() {
  group('source handoff suggested-signal selection (Debug in WaveCrux)', () {
    test(
      'opening a source VCD selects ONLY the primary suggested signal on the '
      'new tab, while adding the whole suggested set to the canvas',
      () async {
        // _WorkspaceOpenableSourceNotifier ignores file contents, but
        // wavecruxWorkspace.openFile expects a real path — write a stub VCD.
        final tempDir = Directory.systemTemp.createTempSync('cxp_src_sel_');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final vcd = File('${tempDir.path}/cdc_capture.vcd')
          ..writeAsStringSync(r'$date $end $enddefinitions $end');

        final tcm = TabContainerManager(
          extraTabOverrides: [
            waveformSourceProvider.overrideWith(
              _WorkspaceOpenableSourceNotifier.new,
            ),
          ],
        );
        final root = ProviderContainer(
          overrides: [
            productTelemetryConfig,
            ...testWorkspaceOverrides(),
            tabContainerManagerProvider.overrideWithValue(tcm),
          ],
        );
        tcm.init(root);
        addTearDown(() {
          tcm.dispose();
          root.dispose();
        });

        final ref = root.read(_refProvider);
        // 1) notify_selection — the signals-to-show globs (SimCrux sends
        //    ['<topModule>.*']; the opened fake exposes `top.clk`).
        stashCxpSelectionSignals(
          ref,
          const [ElementId(kind: ElementKind.source, path: '/tmp/cdc.vcd')],
          const <String, Object?>{
            'simcrux.suggested_signals': <String>['top.*'],
          },
        );
        // 2) request_highlight(source) — opens the VCD in a NEW tab and drains
        //    the stash onto its canvas.
        final result = await dispatchCxpHighlight(
          ref,
          ElementId(kind: ElementKind.source, path: vcd.path),
        );
        expect(result.honored, isTrue);

        final activeTab = tcm.containerFor(root.read(activeTabIdProvider));
        // The WHOLE suggested set (`top.*` → clk + data) was added to the fresh
        // tab's canvas…
        expect(
          activeTab.read(signalGroupsProvider).entries.map((e) => e.signalRef),
          containsAll(<String>['top.clk', 'top.data']),
        );
        // …but ONLY the PRIMARY (first) suggestion is selected — one clear
        // focus, not a wall of highlights. `top.data` is on the canvas yet NOT
        // in the selection.
        expect(
          activeTab.read(selectedVariablesProvider),
          <String>{'top.clk'},
        );
      },
    );
  });
}

/// Shared-workspace consumer: an inbound cross-probe that cannot be satisfied
/// locally (no waveform open) resolves the design's waveform from the shared
/// workspace via `resolveArtifact` and opens it, then applies the highlight.
void _workspaceLinkR8Tests(Scope Function() buildScope) {
  /// The CXP §11 rule the production wiring hands to both the workspace store
  /// and the inbound handlers, stood up here over a fixed [root].
  ///
  /// These tests have no tabs and no recent-files list, so the production
  /// root callback would report nothing open and the store would resolve
  /// nothing at all. Naming the design's own directory as a root is what the
  /// user opening a waveform from it does in the running app.
  CxpPathContainment containmentOver(String root) =>
      CxpPathContainment(roots: () => <String>[root]);

  group('shared-workspace open-on-receive', () {
    test(
      'notify_selection with crux.design_id and NO waveform open resolves and '
      'opens the VCD via resolveArtifact, then highlights the signal',
      () async {
        // A real on-disk "VCD" so the workspace store's existence-prune keeps
        // the artifact — resolveArtifact drops entries whose file is gone.
        final tempDir = Directory.systemTemp.createTempSync('cxp_r8_');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final vcd = File('${tempDir.path}/cdc_capture.vcd')
          ..writeAsStringSync(r'$date $end $enddefinitions $end');
        final designId = cxpDesignIdForPath(vcd.path);

        // Producer side (SimCrux/NetCrux): a workspace record for the design.
        final workspaceDir = Directory('${tempDir.path}/workspace')
          ..createSync();
        final containment = containmentOver(tempDir.path);
        final store = CxpWorkspaceStore(
          workspaceDirectory: workspaceDir.path,
          containment: containment,
        );
        await store.upsertArtifact(
          designId: designId,
          kind: 'waveform',
          path: vcd.path,
          producer: 'simcrux',
          topModule: 'tb_cdc_capture',
          basename: 'cdc_capture.vcd',
        );

        // Consumer side: no waveform open anywhere. The per-tab source starts
        // null and "opens" into the fake (top.clk) when openFile is called —
        // standing in for a real wellen parse in this unit test.
        final tcm = TabContainerManager(
          extraTabOverrides: [
            waveformSourceProvider.overrideWith(
              _WorkspaceOpenableSourceNotifier.new,
            ),
          ],
        );
        final root = ProviderContainer(
          overrides: [
            productTelemetryConfig,
            ...testWorkspaceOverrides(),
            tabContainerManagerProvider.overrideWithValue(tcm),
            cxpPathContainmentProvider.overrideWithValue(containment),
            cxpWorkspaceStoreProvider.overrideWithValue(store),
          ],
        );
        tcm.init(root);
        addTearDown(() {
          tcm.dispose();
          root.dispose();
        });

        final ref = root.read(_refProvider);
        // Sanity: nothing is open before the cross-probe arrives.
        expect(ref.read(waveformSourceProvider).value, isNull);

        // The exact NetCrux → WaveCrux message the R8 scenario sends: a signal
        // selection tagged with the shared design id, no VCD element.
        handleInboundSelection(
          ref,
          const [ElementId(kind: ElementKind.signal, path: 'top.clk')],
          <String, Object?>{cxpDesignIdMetadataKey: designId},
        );

        // handleInboundSelection is fire-and-forget; let the resolve+open+
        // re-highlight microtasks drain.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // The design's VCD was opened in the active tab…
        final activeTab = tcm.containerFor(root.read(activeTabIdProvider));
        expect(
          activeTab.read(waveformSourceProvider.notifier).currentFilePath,
          vcd.path,
          reason: 'resolveArtifact-resolved VCD must have been opened',
        );
        // …and the requested signal was highlighted on it.
        expect(
          activeTab.read(signalGroupsProvider).entries.map((e) => e.signalRef),
          contains('top.clk'),
        );
      },
    );

    test(
      'an inbound highlight for a signal in a NOT-yet-open design opens the '
      'workspace VCD AND ends with the signal added + selected + revealed',
      () async {
        // This is the Fix 3 payoff, asserted DETERMINISTICALLY: the awaitable
        // dispatchCxpHighlight fully resolves the open-then-highlight before it
        // returns, so the per-tab select + reveal (autoDispose providers) are
        // read synchronously on the same turn — no event loop runs in between
        // to dispose them, and no race: openFile awaits the parse before the
        // re-highlight sees the (now indexed) variables.
        final tempDir = Directory.systemTemp.createTempSync('cxp_fix3_');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final vcd = File('${tempDir.path}/cdc_capture.vcd')
          ..writeAsStringSync(r'$date $end $enddefinitions $end');
        final designId = cxpDesignIdForPath(vcd.path);

        final workspaceDir = Directory('${tempDir.path}/workspace')
          ..createSync();
        final containment = containmentOver(tempDir.path);
        final store = CxpWorkspaceStore(
          workspaceDirectory: workspaceDir.path,
          containment: containment,
        );
        await store.upsertArtifact(
          designId: designId,
          kind: 'waveform',
          path: vcd.path,
          producer: 'netcrux',
          topModule: 'top',
          basename: 'cdc_capture.vcd',
        );

        final tcm = TabContainerManager(
          extraTabOverrides: [
            waveformSourceProvider.overrideWith(
              _WorkspaceOpenableSourceNotifier.new,
            ),
          ],
        );
        final root = ProviderContainer(
          overrides: [
            productTelemetryConfig,
            ...testWorkspaceOverrides(),
            tabContainerManagerProvider.overrideWithValue(tcm),
            cxpPathContainmentProvider.overrideWithValue(containment),
            cxpWorkspaceStoreProvider.overrideWithValue(store),
          ],
        );
        tcm.init(root);
        addTearDown(() {
          tcm.dispose();
          root.dispose();
        });

        final ref = root.read(_refProvider);
        // Nothing open before the cross-probe.
        expect(ref.read(waveformSourceProvider).value, isNull);

        // Awaitable front door — a `port` cross-probe carrying the shared
        // design id, exactly as NetCrux now emits (clean `top.clk` leaf, kind
        // port). It opens the design's VCD, then re-highlights on the fresh tab.
        final result = await dispatchCxpHighlight(
          ref,
          const ElementId(kind: ElementKind.port, path: 'top.clk'),
          <String, Object?>{cxpDesignIdMetadataKey: designId},
        );
        expect(result.honored, isTrue);

        final activeTab = tcm.containerFor(root.read(activeTabIdProvider));
        // ADDED to the freshly-opened tab's canvas…
        expect(
          activeTab.read(signalGroupsProvider).entries.map((e) => e.signalRef),
          contains('top.clk'),
        );
        // …SELECTED (the per-tab row highlight)…
        expect(activeTab.read(selectedVariablesProvider), contains('top.clk'));
        // …and REVEALED (lane scrolled into view).
        expect(
          activeTab.read(revealSignalRequestProvider)?.fullPath,
          'top.clk',
        );
      },
    );

    test(
      'P21: an inbound cross-probe for a signal whose file is already open in a '
      'NON-active tab ACTIVATES that tab and adds+selects+reveals there, '
      'WITHOUT opening a second tab',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('cxp_p21_');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final vcd = File('${tempDir.path}/fsm_trap.vcd')
          ..writeAsStringSync(r'$date $end $enddefinitions $end');
        final designId = cxpDesignIdForPath(vcd.path);

        final workspaceDir = Directory('${tempDir.path}/workspace')
          ..createSync();
        final containment = containmentOver(tempDir.path);
        final store = CxpWorkspaceStore(
          workspaceDirectory: workspaceDir.path,
          containment: containment,
        );
        await store.upsertArtifact(
          designId: designId,
          kind: 'waveform',
          path: vcd.path,
          producer: 'netcrux',
          topModule: 'top',
          basename: 'fsm_trap.vcd',
        );

        final tcm = TabContainerManager(
          extraTabOverrides: [
            waveformSourceProvider.overrideWith(
              _WorkspaceOpenableSourceNotifier.new,
            ),
          ],
        );
        final root = ProviderContainer(
          overrides: [
            productTelemetryConfig,
            ...testWorkspaceOverrides(),
            tabContainerManagerProvider.overrideWithValue(tcm),
            cxpPathContainmentProvider.overrideWithValue(containment),
            cxpWorkspaceStoreProvider.overrideWithValue(store),
          ],
        );
        tcm.init(root);
        addTearDown(() {
          tcm.dispose();
          root.dispose();
        });

        // The target file is ALREADY open in a tab…
        final targetTabId = await root.wavecruxWorkspace.openFile(vcd.path);
        // …but a DIFFERENT (placeholder) tab is the active one — so the file is
        // open-but-not-active, the exact P21 precondition (the case that used to
        // open a duplicate).
        final activeTabId = await root.wavecruxWorkspace.newTab(
          displayName: 'Other',
        );
        await root.wavecruxWorkspace.flushPendingSave();
        expect(root.read(activeTabIdProvider), activeTabId);
        expect(targetTabId, isNot(activeTabId));

        final tabsBefore = root.read(tabListProvider).length;
        expect(tabsBefore, 2);

        // Inbound cross-probe for a signal in the already-open file, tagged with
        // the shared design id — the same message the open-on-receive path resolves.
        final ref = root.read(_refProvider);
        final result = await dispatchCxpHighlight(
          ref,
          const ElementId(kind: ElementKind.port, path: 'top.clk'),
          <String, Object?>{cxpDesignIdMetadataKey: designId},
        );
        expect(result.honored, isTrue);

        // No SECOND instance of the file was opened — the tab count is unchanged.
        expect(
          root.read(tabListProvider).length,
          tabsBefore,
          reason: 'must activate the existing tab, not open a duplicate',
        );
        // The EXISTING (previously non-active) tab is now the active one…
        expect(
          root.read(activeTabIdProvider),
          targetTabId,
          reason: 'the already-open tab must be activated, not reopened',
        );
        // …and the signal was ADDED + SELECTED + REVEALED on it.
        final targetTab = tcm.containerFor(targetTabId);
        expect(
          targetTab.read(signalGroupsProvider).entries.map((e) => e.signalRef),
          contains('top.clk'),
        );
        expect(targetTab.read(selectedVariablesProvider), contains('top.clk'));
        expect(
          targetTab.read(revealSignalRequestProvider)?.fullPath,
          'top.clk',
        );
      },
    );

    test(
      'no design_id in metadata → keeps the existing "open a waveform" miss '
      '(no resolveArtifact open)',
      () async {
        final tcm = TabContainerManager(
          extraTabOverrides: [
            waveformSourceProvider.overrideWith(
              _WorkspaceOpenableSourceNotifier.new,
            ),
          ],
        );
        final emptyDir = Directory.systemTemp.createTempSync('cxp_r8_empty_');
        addTearDown(() => emptyDir.deleteSync(recursive: true));
        final containment = containmentOver(emptyDir.path);
        final emptyStore = CxpWorkspaceStore(
          workspaceDirectory: emptyDir.path,
          containment: containment,
        );
        final root = ProviderContainer(
          overrides: [
            productTelemetryConfig,
            ...testWorkspaceOverrides(),
            tabContainerManagerProvider.overrideWithValue(tcm),
            cxpPathContainmentProvider.overrideWithValue(containment),
            cxpWorkspaceStoreProvider.overrideWithValue(emptyStore),
          ],
        );
        tcm.init(root);
        addTearDown(() {
          tcm.dispose();
          root.dispose();
        });

        final ref = root.read(_refProvider);
        handleInboundSelection(
          ref,
          const [ElementId(kind: ElementKind.signal, path: 'top.clk')],
          const <String, Object?>{},
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // No workspace record + no design_id → nothing resolves or opens; the
        // active tab's source stays empty (the existing "open a waveform" miss).
        final activeTab = tcm.containerFor(root.read(activeTabIdProvider));
        expect(
          activeTab.read(waveformSourceProvider.notifier).currentFilePath,
          isNull,
        );
      },
    );

    // CXP §11's MUST: the artifact a receiver resolved through its OWN
    // records gets the same scrutiny as a `file_path` on the wire. The
    // workspace directory is user-writable and the sender chose the
    // `design_id` that selects the record, so "we looked it up ourselves" is
    // not a provenance — a record can name any file on the machine.
    //
    // MUTATION: dropping `containment:` from `cxpWorkspaceStoreProvider`
    // makes this red while every other test in this group stays green.
    test(
      'a workspace record naming a file outside the open directories resolves '
      'to nothing and opens nothing',
      () async {
        final openDir = Directory.systemTemp.createTempSync('cxp_open_');
        addTearDown(() => openDir.deleteSync(recursive: true));
        final elsewhere = Directory.systemTemp.createTempSync('cxp_elsewhere_');
        addTearDown(() => elsewhere.deleteSync(recursive: true));

        // The record's file exists — the store's existence-prune is not what
        // is being tested — but it sits outside every directory this session
        // has open.
        final vcd = File('${elsewhere.path}/exfiltrate.vcd')
          ..writeAsStringSync(r'$date $end $enddefinitions $end');
        final designId = cxpDesignIdForPath(vcd.path);

        final workspaceDir = Directory('${openDir.path}/workspace')
          ..createSync();
        final containment = containmentOver(openDir.path);
        final store = CxpWorkspaceStore(
          workspaceDirectory: workspaceDir.path,
          containment: containment,
        );
        // Written WITHOUT the rule: a producer records what it produced, and
        // which of it a given consumer may open is the consumer's rule — so
        // the record has to reach disk for the read side to be under test.
        await CxpWorkspaceStore(
          workspaceDirectory: workspaceDir.path,
        ).upsertArtifact(
          designId: designId,
          kind: 'waveform',
          path: vcd.path,
          producer: 'hostile-peer',
          topModule: 'top',
          basename: 'exfiltrate.vcd',
        );
        expect(
          CxpWorkspaceStore(
            workspaceDirectory: workspaceDir.path,
          ).readArtifacts(designId),
          hasLength(1),
          reason: 'the record must be on disk for the filter to be proven',
        );

        final tcm = TabContainerManager(
          extraTabOverrides: [
            waveformSourceProvider.overrideWith(
              _WorkspaceOpenableSourceNotifier.new,
            ),
          ],
        );
        final root = ProviderContainer(
          overrides: [
            productTelemetryConfig,
            ...testWorkspaceOverrides(),
            tabContainerManagerProvider.overrideWithValue(tcm),
            cxpPathContainmentProvider.overrideWithValue(containment),
            cxpWorkspaceStoreProvider.overrideWithValue(store),
          ],
        );
        tcm.init(root);
        addTearDown(() {
          tcm.dispose();
          root.dispose();
        });

        final ref = root.read(_refProvider);
        final result = await dispatchCxpHighlight(
          ref,
          const ElementId(kind: ElementKind.port, path: 'top.clk'),
          <String, Object?>{cxpDesignIdMetadataKey: designId},
        );

        expect(result.honored, isFalse);
        final activeTab = tcm.containerFor(root.read(activeTabIdProvider));
        expect(
          activeTab.read(waveformSourceProvider.notifier).currentFilePath,
          isNull,
          reason: 'the out-of-tree artifact must never be opened',
        );
      },
    );

    // Not the same rule on the OTHER front door: `request_open_artifact` is
    // held to the floor, because it exists to open a waveform WaveCrux has
    // never opened (`kCxpOpenArtifactContainment` says why). A hint outside
    // the open directories is honoured; the floor's refusals are in
    // `cxp_open_artifact_test.dart`.
    //
    // MUTATION: checking the path with `cxpPathContainmentProvider` in
    // `dispatchCxpOpenArtifact` instead of `kCxpOpenArtifactContainment`
    // turns this red.
    test(
      'dispatchCxpOpenArtifact honours a hint outside the open directories '
      'under the floor',
      () async {
        _quietAttention();
        final openDir = Directory.systemTemp.createTempSync('cxp_hint_open_');
        addTearDown(() => openDir.deleteSync(recursive: true));
        final elsewhere = Directory.systemTemp.createTempSync('cxp_hint_out_');
        addTearDown(() => elsewhere.deleteSync(recursive: true));
        final vcd = File('${elsewhere.path}/hint.vcd')
          ..writeAsStringSync(r'$date $end $enddefinitions $end');

        final containment = containmentOver(openDir.path);
        final tcm = TabContainerManager(
          extraTabOverrides: [
            waveformSourceProvider.overrideWith(
              _WorkspaceOpenableSourceNotifier.new,
            ),
          ],
        );
        final root = ProviderContainer(
          overrides: [
            productTelemetryConfig,
            ...testWorkspaceOverrides(),
            tabContainerManagerProvider.overrideWithValue(tcm),
            cxpPathContainmentProvider.overrideWithValue(containment),
            cxpWorkspaceStoreProvider.overrideWithValue(
              CxpWorkspaceStore(
                workspaceDirectory: Directory('${openDir.path}/workspace').path,
                containment: containment,
              ),
            ),
          ],
        );
        tcm.init(root);
        addTearDown(() {
          tcm.dispose();
          root.dispose();
        });

        final result = await dispatchCxpOpenArtifact(
          root.read(_refProvider),
          'no-such-design',
          'waveform',
          vcd.path,
        );

        expect(result.honored, isTrue, reason: result.reason);
        final activeTab = tcm.containerFor(root.read(activeTabIdProvider));
        expect(
          activeTab.read(waveformSourceProvider.notifier).currentFilePath,
          vcd.path,
        );
      },
    );
  });
}

/// Swaps the window-attention backend for the no-op one for the rest of the
/// test. An honoured `request_open_artifact` nudges the window through a
/// platform channel, and these plain `test()` bodies may run with no binding.
void _quietAttention() {
  windowAttentionRequester = const NoopWindowAttentionRequester();
  addTearDown(
    () => windowAttentionRequester =
        const MethodChannelWindowAttentionRequester(),
  );
}

/// A per-tab [WaveformSourceNotifier] that starts empty and "opens" a waveform
/// into a fixed fake source (with `top.clk`) — a stand-in for a real wellen
/// parse so the shared-workspace open path is exercisable in a unit test.
class _WorkspaceOpenableSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<FakeWaveformDataSource?> build() =>
      const AsyncData<FakeWaveformDataSource?>(null);

  @override
  Future<void> openFile(String path, {bool preserveDecoders = false}) async {
    currentFilePath = path;
    state = AsyncData(
      FakeWaveformDataSource(
        scopes: const [
          Scope(
            name: 'top',
            path: 'top',
            type: ScopeType.module,
            variables: [
              Variable(
                name: 'clk',
                varType: VarType.wire,
                direction: VarDirection.input,
                signalRef: 'top.clk',
                scopePath: 'top',
                bitWidth: 1,
              ),
              // A SECOND signal so a `top.*` suggested glob resolves to more
              // than one variable — lets the source-handoff test prove only the
              // PRIMARY (first) suggestion is selected while both are added.
              Variable(
                name: 'data',
                varType: VarType.wire,
                direction: VarDirection.input,
                signalRef: 'top.data',
                scopePath: 'top',
                bitWidth: 8,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Provider exposing the container's [Ref] so tests can pass it to the
/// dispatch functions without subclassing a notifier.
final _refProvider = Provider<Ref>((ref) => ref);

void _perTabRoutingTests(Scope Function() buildScope) {
  // Regression for the CXP scope-leak (the same issue #44 class that broke RTL):
  // the server is a root keepAlive notifier, so per-tab providers must be read
  // through the ACTIVE TAB's container, never the root scope.
  group('per-tab routing (scope-leak regression)', () {
    test(
      'highlight resolves the ACTIVE tab container, not the root scope',
      () async {
        final source = FakeWaveformDataSource(scopes: [buildScope()]);
        // The waveform lives ONLY in per-tab containers; the root scope stays
        // empty. Before the fix the handler read root and replied "no waveform
        // file loaded" even with a file open in the focused tab.
        final tcm = TabContainerManager(
          extraTabOverrides: [
            waveformSourceProvider.overrideWith(
              () => _PreloadedSourceNotifier(source),
            ),
          ],
        );
        final root = ProviderContainer(
          overrides: [
            productTelemetryConfig,
            ...testWorkspaceOverrides(),
            tabContainerManagerProvider.overrideWithValue(tcm),
          ],
        );
        tcm.init(root);
        addTearDown(() {
          tcm.dispose();
          root.dispose();
        });

        // Seed a real, active tab so activeTabContainer() resolves it.
        final tabId = await root.wavecruxWorkspace.newTab(displayName: 'Tab');
        await root.wavecruxWorkspace.flushPendingSave();
        expect(root.read(activeTabIdProvider), tabId);
        final tab = tcm.containerFor(tabId);

        final result = await dispatchCxpHighlight(
          root.read(_refProvider),
          const ElementId(kind: ElementKind.signal, path: 'top.clk'),
        );

        expect(
          result.honored,
          isTrue,
          reason: "must resolve the active tab's loaded source, not empty root",
        );
        // The signal landed in the ACTIVE TAB's container…
        expect(
          tab.read(signalGroupsProvider).entries.map((e) => e.signalRef),
          contains('top.clk'),
        );
        // …and the root scope was never written.
        expect(
          root.read(signalGroupsProvider).entries,
          isEmpty,
          reason: 'the root signalGroups must not be touched',
        );
      },
    );
  });
}

/// The CXP §9.9 semantic stream coordinate
/// (https://edacrux.app/cxp#sec-9-9), end to end through the inbound handler.
///
/// Everything here runs on a **plain, unlicensed** container. The whole
/// SimCrux → WaveCrux hand-off is open core — a counterexample hand-off answers
/// whether a core is correct, which is never gated — and these tests are where that is mechanically asserted: there is no
/// license, entitlement, or tier override anywhere below, so a gate added to
/// this path stops them passing.
void _streamCoordinateTests() {
  ProviderContainer makeContainer(FakeWaveformDataSource source) =>
      ProviderContainer(
        overrides: [
          productTelemetryConfig,
          waveformSourceProvider.overrideWith(
            () => _PreloadedSourceNotifier(source),
          ),
        ],
      );

  // A four-step bounded-proof counterexample, dumped the way `sby` dumps one:
  // one value per step on a pitch of 10 ticks, retirements at step 1 and step
  // 3, nothing at step 2.
  String bits(int value, int width) =>
      value.toRadixString(2).padLeft(width, '0');

  Scope rvfiScope() => Scope(
    name: 'top',
    path: 'top',
    type: ScopeType.module,
    childScopes: [
      Scope(
        name: 'core',
        path: 'top.core',
        type: ScopeType.module,
        variables: [
          for (final name in const [
            'rvfi_valid',
            'rvfi_order',
            'rvfi_insn',
            'rvfi_pc_rdata',
          ])
            Variable(
              name: name,
              varType: VarType.wire,
              direction: VarDirection.output,
              signalRef: 'top.core.$name',
              scopePath: 'top.core',
              bitWidth: name == 'rvfi_valid' ? 1 : 32,
            ),
        ],
      ),
    ],
  );

  FakeWaveformDataSource rvfiSource() => FakeWaveformDataSource(
    scopes: [rvfiScope()],
    endTime: 30,
    signals: {
      'top.core.rvfi_valid': const [
        SignalChange(time: 0, value: '0'),
        SignalChange(time: 10, value: '1'),
        SignalChange(time: 20, value: '0'),
        SignalChange(time: 30, value: '1'),
      ],
      'top.core.rvfi_order': [
        SignalChange(time: 0, value: bits(0, 64)),
        SignalChange(time: 30, value: bits(1, 64)),
      ],
      'top.core.rvfi_insn': [
        SignalChange(time: 0, value: bits(0x00000013, 32)),
        SignalChange(time: 10, value: bits(0x00000013, 32)),
        SignalChange(time: 30, value: bits(0x00000013, 32)),
      ],
      'top.core.rvfi_pc_rdata': [
        SignalChange(time: 0, value: bits(0x1000, 32)),
        SignalChange(time: 10, value: bits(0x1000, 32)),
        SignalChange(time: 30, value: bits(0x1004, 32)),
      ],
    },
  );

  CxpStreamCoordinate formalStep(
    int step, {
    Map<String, String> attributes = const {},
  }) => CxpStreamCoordinate(
    streamId: CxpStreamCoordinate.riscvFormalTraceStepStreamId,
    sequenceIndex: step,
    subId: 'ch0',
    attributes: attributes,
  );

  const rvfiElement = ElementId(
    kind: ElementKind.signal,
    path: 'top.core.rvfi_valid',
  );

  group('dispatchCxpHighlight stream coordinate', () {
    test('moves the cursor to the addressed step and records the landing', () {
      // Note what this container is NOT: there is no license, entitlement, or
      // tier override anywhere in it. The whole counterexample hand-off is open
      // core and this is where that is asserted —
      // if a gate is ever added to the path, this test stops passing on the
      // unlicensed default.
      final container = makeContainer(rvfiSource());
      addTearDown(container.dispose);
      return dispatchCxpHighlight(
        container.read(_refProvider),
        rvfiElement,
        const <String, Object?>{},
        formalStep(1),
      ).then((result) {
        expect(result.honored, isTrue);
        expect(result.reason, isNull);
        expect(container.read(cursorStateProvider).primaryCursorTime, 10);
        final landing = container.read(riscvCommitLandingProvider);
        expect(landing, isNotNull);
        expect(landing!.time, 10);
        expect(landing.order, 0);
        expect(landing.sequenceIndex, 1);
        expect(landing.subId, 'ch0');
        expect(landing.selectedRetirement, isTrue);
      });
    });

    test('loads the RVFI channels before walking the source', () async {
      // The lazy-load trap (ARCHITECTURE §6.6). A cross-probe opens a trace
      // nobody has added anything from, so nothing is loaded; `valueAt`
      // answers null for an unloaded signal exactly as it does for "no value
      // yet", and an unguarded resolver would report an empty retire stream
      // on a perfectly good trace.
      final source = rvfiSource();
      for (final ref in const [
        'top.core.rvfi_valid',
        'top.core.rvfi_order',
        'top.core.rvfi_insn',
        'top.core.rvfi_pc_rdata',
      ]) {
        await source.unloadSignal(ref);
        expect(source.isSignalLoaded(ref), isFalse);
      }
      final container = makeContainer(source);
      addTearDown(container.dispose);

      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        rvfiElement,
        const <String, Object?>{},
        formalStep(3),
      );
      expect(result.honored, isTrue);
      expect(container.read(cursorStateProvider).primaryCursorTime, 30);
      expect(container.read(riscvCommitLandingProvider)?.order, 1);
    });

    test('places the cursor and says so when nothing retired there', () async {
      final container = makeContainer(rvfiSource());
      addTearDown(container.dispose);
      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        rvfiElement,
        const <String, Object?>{},
        formalStep(2),
      );
      expect(result.honored, isTrue);
      expect(result.reason, contains('No instruction retired'.toLowerCase()));
      expect(container.read(cursorStateProvider).primaryCursorTime, 20);
      final landing = container.read(riscvCommitLandingProvider);
      expect(landing?.selectedRetirement, isFalse);
    });

    test('carries the advisory attributes through to the landing', () async {
      final container = makeContainer(rvfiSource());
      addTearDown(container.dispose);
      await dispatchCxpHighlight(
        container.read(_refProvider),
        rvfiElement,
        const <String, Object?>{},
        formalStep(
          1,
          attributes: const {
            'riscv.formal.check': 'insn_sub_ch0',
            'riscv.formal.group': 'insn',
            'riscv.formal.depth_configured': '20',
            'riscv.isa': 'rv32i',
            'riscv.mode': 'demo',
          },
        ),
      );
      final landing = container.read(riscvCommitLandingProvider)!;
      expect(landing.check, 'insn_sub_ch0');
      expect(landing.group, 'insn');
      expect(landing.depthConfigured, 20);
      expect(landing.isa, 'rv32i');
      // The provenance obligation: a replayed fixture is marked as one, so
      // the banner can never present it as a measured solver run.
      expect(landing.isReplayedFixture, isTrue);
    });

    test('honours the element and explains an unknown stream', () async {
      final container = makeContainer(rvfiSource());
      addTearDown(container.dispose);
      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        rvfiElement,
        const <String, Object?>{},
        CxpStreamCoordinate(streamId: 'axi.transaction', sequenceIndex: 4),
      );
      expect(result.honored, isTrue, reason: 'the element still landed');
      expect(result.reason, contains('does not implement'));
      expect(container.read(cursorStateProvider).primaryCursorTime, isNull);
      expect(container.read(riscvCommitLandingProvider), isNull);
    });

    test('honours the element when the trace has no RVFI bundle', () async {
      // A trace of an uninstrumented core: the file opens, the signal
      // highlights, and there is simply no retire stream for a RISC-V
      // coordinate to index into.
      final container = makeContainer(
        FakeWaveformDataSource(
          scopes: const [
            Scope(
              name: 'top',
              path: 'top',
              type: ScopeType.module,
              variables: [
                Variable(
                  name: 'clk',
                  varType: VarType.wire,
                  direction: VarDirection.input,
                  signalRef: 'top.clk',
                  scopePath: 'top',
                  bitWidth: 1,
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(container.dispose);
      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        const ElementId(kind: ElementKind.signal, path: 'top.clk'),
        const <String, Object?>{},
        formalStep(1),
      );
      expect(result.honored, isTrue);
      expect(result.reason, contains('no RVFI bundle'));
      expect(container.read(cursorStateProvider).primaryCursorTime, isNull);
    });

    test("leaves an unhonoured element's own reason intact", () async {
      final container = makeContainer(rvfiSource());
      addTearDown(container.dispose);
      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        const ElementId(kind: ElementKind.signal, path: 'top.core.nosuch'),
        const <String, Object?>{},
        formalStep(1),
      );
      expect(result.honored, isFalse);
      expect(result.reason, contains('element not found'));
      expect(container.read(riscvCommitLandingProvider), isNull);
    });

    test('a null coordinate changes nothing at all', () async {
      final container = makeContainer(rvfiSource());
      addTearDown(container.dispose);
      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        rvfiElement,
      );
      expect(result.honored, isTrue);
      expect(result.reason, isNull);
      expect(container.read(riscvCommitLandingProvider), isNull);
    });

    test('resolves the normative riscv.rvfi.retire binding too', () async {
      final container = makeContainer(rvfiSource());
      addTearDown(container.dispose);
      final result = await dispatchCxpHighlight(
        container.read(_refProvider),
        rvfiElement,
        const <String, Object?>{},
        CxpStreamCoordinate(
          streamId: CxpStreamCoordinate.riscvRvfiRetireStreamId,
          sequenceIndex: 1,
          attributes: const {'riscv.pc': '0x00001004'},
        ),
      );
      expect(result.honored, isTrue);
      expect(container.read(cursorStateProvider).primaryCursorTime, 30);
      expect(container.read(riscvCommitLandingProvider)?.order, 1);
    });
  });
}

class _FakeSettingsService implements WaveCruxSettingsService {
  const _FakeSettingsService();

  @override
  Future<AppSettings> load() async => const AppSettings();

  @override
  Future<void> save(AppSettings settings) async {}
}

class _FakeAppSettingsNotifier extends AppSettingsNotifier {
  _FakeAppSettingsNotifier(this._settings);
  final AppSettings _settings;
  @override
  Future<AppSettings> build() async => _settings;
}

class _PreloadedSourceNotifier extends WaveformSourceNotifier {
  _PreloadedSourceNotifier(this._source);
  final FakeWaveformDataSource _source;
  @override
  AsyncValue<FakeWaveformDataSource> build() => AsyncData(_source);
}
