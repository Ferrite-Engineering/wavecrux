// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

// LOCALE_SWEEP_EXEMPT: this file is a state-machine/timing regression
// harness (deep-link file-open races, real FFI parses under `runAsync`,
// bounded condition-polls up to 60s per test), not a UI presentational
// test. The Drawer text it asserts ('top', 'clk', 'cpu') is VCD scope/
// signal names, not localized strings; the one ARB string it touches
// ('Open a waveform file to browse signals') is checked only for absence,
// incidental to the state assertion. A 4-locale sweep would 4x an already
// expensive real-FFI test suite for no locale-rendering signal — the
// surface under test is timing/state correctness, not text rendering.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/core/startup_reconcile_provider.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/mobile_memory_guard_provider.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '../../../helpers/product_telemetry_config.dart';
import '../../../helpers/wellen_ffi_library_gate.dart';

/// Reproduces the LIVE phone file-open flow: the app builds first (empty
/// workspace, no tabs), and only then does a file arrive via the incoming-file
/// deep link (`/viewer?file=<path>`), which go_router delivers by rebuilding
/// the SAME ViewerScreen element with a new `filePath` — so the open runs from
/// `didUpdateWidget`, not `initState`.
///
/// This is the timing the pre-existing phone drawer regression test
/// (viewer_screen_test.dart, 'phone signal-tree drawer reads the active tab
/// scope') does NOT cover: there the tab is seeded before the first pump.
/// Symptoms under test (from on-device beta testing):
///   1. after the first file loads, the signal-tree drawer is empty even
///      though the status bar shows the file;
///   2. a second incoming file does not replace the first (single-tab phone).
void main() {
  if (!requireWellenFfiLibrary('phone incoming-file open')) return;

  TestWidgetsFlutterBinding.ensureInitialized();

  const fixture1 = 'test/fixtures/vcd/scalar_basics.vcd'; // top: clk/rst/data
  const fixture2 = 'test/fixtures/vcd/deep_hierarchy.vcd'; // top: cpu/mem

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets(
    'incoming file AFTER first build populates the phone signal-tree drawer, '
    'and a second incoming file replaces the visible content',
    (tester) async {
      await tester.runAsync(() async {
        final harness = _Harness();
        addTearDown(harness.dispose);

        // 1. Cold app, empty workspace — the empty-canvas branch renders.
        await tester.pumpWidget(harness.build(filePath: null));
        await _settle(tester);
        expect(harness.container.read(tabListProvider), isEmpty);

        // 2. The incoming-file path re-navigates to /viewer?file=<path>;
        //    go_router reuses the ViewerScreen element, so this is a
        //    didUpdateWidget-driven open. On iOS the OS ALSO fires the engine
        //    deep-link (router path (b)), which fileUrlRedirect absorbs into a
        //    bare `/viewer` — i.e. the same element rebuilds again with
        //    filePath: null moments later. Reproduce both navigations.
        await tester.pumpWidget(harness.build(filePath: fixture1));
        await tester.pump();
        await tester.pumpWidget(harness.build(filePath: null));
        await _pumpUntil(
          tester,
          () =>
              harness.container.read(tabListProvider).length == 1 &&
              harness.loadedIn(harness.activeTabId),
          reason: 'first incoming file should open and load a tab',
        );

        // 3. Open the phone signal-tree drawer. It must show the loaded
        //    file's hierarchy, not the empty-root placeholder.
        await _openDrawer(tester);
        expect(
          find.descendant(
            of: find.byType(Drawer),
            matching: find.text('top'),
          ),
          findsOneWidget,
          reason: 'drawer must show the loaded file hierarchy (symptom 1)',
        );
        expect(
          find.descendant(
            of: find.byType(Drawer),
            matching: find.text('Open a waveform file to browse signals'),
          ),
          findsNothing,
        );
        // Expand `top` — scalar_basics has vars clk/rst/data directly under it.
        // (The scope row registers onDoubleTap too, so the single-tap only
        // fires after the real ~300ms double-tap disambiguation timeout.)
        await tester.tap(
          find.descendant(of: find.byType(Drawer), matching: find.text('top')),
        );
        await _pumpUntil(
          tester,
          () => find
              .descendant(of: find.byType(Drawer), matching: find.text('clk'))
              .evaluate()
              .isNotEmpty,
          reason: 'expanding top should reveal clk (first file loaded)',
        );
        await _closeDrawer(tester);

        // 4. Second incoming file, same didUpdateWidget path (with the same
        //    trailing bare-/viewer absorb navigation as the first).
        await tester.pumpWidget(harness.build(filePath: fixture2));
        await tester.pump();
        await tester.pumpWidget(harness.build(filePath: null));
        await _pumpUntil(
          tester,
          () =>
              harness.container.read(tabListProvider).length == 2 &&
              harness.loadedIn(harness.activeTabId),
          reason: 'second incoming file should open and load a new tab',
        );

        // The new tab must be the ACTIVE one (visible replacement on phone).
        final tabs = harness.container.read(tabListProvider);
        final active = tabs.firstWhere(
          (t) => t.id == harness.container.read(activeTabIdProvider),
        );
        expect(
          active.filePath,
          fixture2,
          reason: 'second file must become the active tab (symptom 2)',
        );

        // 5. Drawer must now show the SECOND file's hierarchy: expanding
        //    `top` reveals cpu/mem (deep_hierarchy), not clk (scalar_basics).
        await _openDrawer(tester);
        await tester.tap(
          find.descendant(of: find.byType(Drawer), matching: find.text('top')),
        );
        await _pumpUntil(
          tester,
          () => find
              .descendant(of: find.byType(Drawer), matching: find.text('cpu'))
              .evaluate()
              .isNotEmpty,
          reason:
              'drawer must rebind to the newly active tab (symptom 2): '
              'expanding top should reveal cpu (second file)',
        );
        expect(
          find.descendant(of: find.byType(Drawer), matching: find.text('clk')),
          findsNothing,
          reason: 'drawer must not keep showing the first file',
        );
      });
    },
  );

  testWidgets(
    'incoming file whose path an existing tab holds RELOADS when the on-disk '
    'contents were replaced (share-sheet SharedImports/<name> overwrite)',
    (tester) async {
      // The iOS/Android share sheet imports every incoming file to
      // Documents/SharedImports/<basename>, OVERWRITING a same-named earlier
      // import in place. HDL dumps are all called dump.vcd, so the dedupe in
      // _openOrFocusFile used to focus the existing tab and silently keep
      // showing the PREVIOUS file's waveform (the on-device "second file
      // won't open / drawer shows the earlier file's signals" defect).
      await tester.runAsync(() async {
        final harness = _Harness();
        addTearDown(harness.dispose);

        final dir = await Directory.systemTemp.createTemp('wavecrux_share');
        addTearDown(() => dir.delete(recursive: true));
        // First share: scalar_basics contents (top: clk/rst/data).
        final dump = File('${dir.path}/dump.vcd')
          ..writeAsBytesSync(File(fixture1).readAsBytesSync());

        await tester.pumpWidget(harness.build(filePath: null));
        await _settle(tester);
        await tester.pumpWidget(
          harness.build(filePath: dump.path, openRequest: '1'),
        );
        await _pumpUntil(
          tester,
          () =>
              harness.container.read(tabListProvider).length == 1 &&
              harness.loadedIn(harness.activeTabId),
          reason: 'first share of dump.vcd should open and load',
        );

        // Second share, same basename → the import overwrites dump.vcd in
        // place with deep_hierarchy contents (top: cpu/mem). The router
        // location's ?file= value is IDENTICAL, so only the changing `req`
        // open-request token (stamped by _onIncomingFile) reaches
        // didUpdateWidget — exactly the production mechanism.
        dump.writeAsBytesSync(File(fixture2).readAsBytesSync());
        await tester.pumpWidget(
          harness.build(filePath: dump.path, openRequest: '2'),
        );
        await _pumpUntil(
          tester,
          () {
            // Still one tab (dedupe), but the reload must land the SECOND
            // file's hierarchy: expanding top reveals cpu, not clk.
            final tabs = harness.container.read(tabListProvider);
            if (tabs.length != 1) return false;
            final c = harness.tcm.containerFor(tabs.single.id);
            final roots = c.read(hierarchyProvider).value;
            if (roots == null || roots.isEmpty) return false;
            return roots.single.childScopes.isNotEmpty;
          },
          reason:
              'same-path share with replaced contents must reload '
              '(deep_hierarchy has child scopes under top; scalar has none)',
        );

        await _openDrawer(tester);
        await tester.tap(
          find.descendant(of: find.byType(Drawer), matching: find.text('top')),
        );
        await _pumpUntil(
          tester,
          () => find
              .descendant(of: find.byType(Drawer), matching: find.text('cpu'))
              .evaluate()
              .isNotEmpty,
          reason: 'drawer must show the reloaded (second) file hierarchy',
        );
        expect(
          find.descendant(of: find.byType(Drawer), matching: find.text('clk')),
          findsNothing,
          reason: 'drawer must not keep the stale first parse',
        );
      });
    },
  );

  testWidgets(
    'incoming file matching an ACTIVE but never-loaded tab loads it '
    '(deferred/suppressed restore + activate() no-op hole)',
    (tester) async {
      // A restored tab can exist without its waveform loaded (phone deferred
      // restore, crash-guard suppressed auto-load). Activating an
      // already-active tab emits no activeTabIdProvider change, so the
      // deferred-load listener never fires — the dedupe path itself must
      // load the file or the share appears to do nothing (empty drawer).
      await tester.runAsync(() async {
        final harness = _Harness();
        addTearDown(harness.dispose);

        await tester.pumpWidget(harness.build(filePath: null));
        await _settle(tester);

        // Stage: create the tab WITHOUT loading (what a deferred restore
        // leaves behind). openFile on the workspace only creates+activates.
        final tabId = await harness.container.wavecruxWorkspace.openFile(
          fixture1,
        );
        await _pumpUntil(
          tester,
          () => harness.container.read(activeTabIdProvider) == tabId,
          reason: 'staged tab should become active',
        );
        expect(harness.loadedIn(tabId), isFalse);

        // Share the same path → dedupe focuses the (already active) tab.
        // Pre-fix this was a complete no-op and the tree stayed empty.
        await tester.pumpWidget(harness.build(filePath: fixture1));
        await _pumpUntil(
          tester,
          () => harness.loadedIn(tabId),
          reason: 'sharing the path of an unloaded active tab must load it',
        );
        expect(harness.container.read(tabListProvider).length, 1);
      });
    },
  );

  testWidgets(
    'runtime open arriving mid-restore is QUEUED on the reconcile barrier and '
    'drains once restore completes (macOS open-during-restore, BETA W1)',
    (tester) async {
      // The reported defect: `open -a WaveCrux file.vcd` while a large session
      // (multi-hundred-MB FST) is restoring is dropped and never opens, even
      // after the restore settles. Root cause: the runtime-open path did not
      // wait for the cold-start reconcile, so it raced (and lost to) the
      // restore's focus/tab reconcile. The fix parks the open on
      // startupReconcileProvider and drains it when restore completes.
      await tester.runAsync(() async {
        final harness = _Harness(completeReconcile: false); // restore in flight
        addTearDown(harness.dispose);

        await tester.pumpWidget(harness.build(filePath: null));
        await _settle(tester);

        // A file arrives while the (simulated) restore is still in flight.
        await tester.pumpWidget(
          harness.build(filePath: fixture1, openRequest: '1'),
        );
        // Pump for a while — the open MUST NOT run yet (it is parked on the
        // barrier), but it must also NOT be dropped.
        for (var i = 0; i < 12; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
        expect(
          harness.container.read(tabListProvider),
          isEmpty,
          reason:
              'open must be queued until restore completes, not applied '
              'mid-restore and not dropped',
        );

        // Restore settles → the queued open drains and the tab opens + loads.
        harness.completeReconcile();
        await _pumpUntil(
          tester,
          () =>
              harness.container.read(tabListProvider).length == 1 &&
              harness.loadedIn(harness.activeTabId),
          reason: 'queued open must open once the reconcile barrier completes',
        );
        expect(
          harness.container.read(tabListProvider).single.filePath,
          fixture1,
        );
      });
    },
  );

  _designManifestTests(fixture1);
}

// ── design manifests ──────────────────────────────────────────────────────────

/// A manifest delivered the same way as any incoming file opens the waveform
/// it names; the legacy name and an ambiguous design folder are explained.
void _designManifestTests(String fixture) {
  group('design manifests', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('wc_manifest_open'));
    tearDown(() => tmp.deleteSync(recursive: true));

    String design(String name, {required String manifestName}) {
      final dir = Directory(p.join(tmp.path, name))..createSync();
      File(fixture).copySync(p.join(dir.path, 'sim.vcd'));
      File(
        p.join(dir.path, manifestName),
      ).writeAsStringSync('version: 1\nartifacts:\n  waveform: sim.vcd\n');
      return dir.path;
    }

    Future<void> openIncoming(
      WidgetTester tester,
      _Harness harness,
      String path,
    ) async {
      await tester.pumpWidget(harness.build(filePath: null));
      await _settle(tester);
      await tester.pumpWidget(harness.build(filePath: path));
    }

    testWidgets('a <design>.crux-project opens the waveform it names', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final dir = design('uart_tx', manifestName: 'uart_tx.crux-project');

        await openIncoming(
          tester,
          harness,
          p.join(dir, 'uart_tx.crux-project'),
        );
        await _pumpUntil(
          tester,
          () =>
              harness.container.read(tabListProvider).length == 1 &&
              harness.loadedIn(harness.activeTabId),
          reason: 'the manifest should open the waveform it names',
        );
        expect(
          harness.container.read(tabListProvider).single.filePath,
          endsWith('sim.vcd'),
        );
        expect(find.textContaining('Rename it to'), findsNothing);
      });
    });

    testWidgets('a legacy bare .crux-project opens and names the new file', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final dir = design('uart_tx', manifestName: '.crux-project');

        await openIncoming(tester, harness, p.join(dir, '.crux-project'));
        const notice =
            'This design manifest uses the old file name .crux-project, which '
            'file pickers hide. Rename it to uart_tx.crux-project.';
        await _pumpUntil(
          tester,
          () => find.text(notice).evaluate().isNotEmpty,
          reason: 'the legacy name should be explained once',
        );
        await _pumpUntil(
          tester,
          () =>
              harness.container.read(tabListProvider).length == 1 &&
              harness.loadedIn(harness.activeTabId),
          reason: 'a legacy manifest still opens its waveform',
        );
      });
    });

    testWidgets('a design folder with two manifests is refused by name', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final dir = design('soc', manifestName: 'a.crux-project');
        File(
          p.join(dir, 'b.crux-project'),
        ).writeAsStringSync('version: 1\nartifacts:\n  waveform: sim.vcd\n');

        await openIncoming(tester, harness, dir);
        const error =
            'soc contains more than one design manifest (a.crux-project, '
            'b.crux-project). Keep one .crux-project file per design folder.';
        await _pumpUntil(
          tester,
          () => find.text(error).evaluate().isNotEmpty,
          reason: 'an ambiguous design folder should say which files clash',
        );
        expect(harness.container.read(tabListProvider), isEmpty);
      });
    });
  });
}

// ── helpers ───────────────────────────────────────────────────────────────────

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Bounded condition-poll under `runAsync`: real async (FFI isolate parse)
/// makes progress between pumps; returns the moment [ready] is true.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  required String reason,
}) async {
  for (var i = 0; i < 200; i++) {
    if (ready()) {
      // A final frame so the UI reflects the ready state.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
    await tester.pump();
  }
  fail('timed out: $reason');
}

Future<void> _openDrawer(WidgetTester tester) async {
  tester
      .state<ScaffoldState>(
        find.byWidgetPredicate((w) => w is Scaffold && w.drawer != null),
      )
      .openDrawer();
  await tester.pumpAndSettle();
  expect(find.byType(Drawer), findsOneWidget);
}

Future<void> _closeDrawer(WidgetTester tester) async {
  tester
      .state<ScaffoldState>(
        find.byWidgetPredicate((w) => w is Scaffold && w.drawer != null),
      )
      .closeDrawer();
  await tester.pumpAndSettle();
}

/// In-memory [WorkspaceService]: loads an empty single-pane workspace and
/// persists nothing (path_provider is unavailable in widget tests).
class _InMemoryWorkspaceService implements WorkspaceService {
  @override
  Future<Workspace> load() async {
    const pane = WorkspacePane(id: PaneId.primary);
    return Workspace(
      tabs: const [],
      panes: const [pane],
      activePaneId: pane.id,
    );
  }

  @override
  Future<void> save(Workspace workspace) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Inert memory guard — the real one arms a periodic Timer on phone class.
class _InertMemoryGuardNotifier extends MobileMemoryGuardNotifier {
  @override
  MemoryGuardState build() => const MemoryGuardState();
}

/// Inert per-tab session autosave — skips the debounce Timer chain.
class _InertSessionAutoSaveNotifier extends SessionAutoSaveNotifier {
  @override
  void build() {}
}

/// Root container + managers harness. [build] returns the app widget with the
/// supplied route-level [filePath]; calling it again with a different path
/// mimics go_router rebuilding the same ViewerScreen element.
class _Harness {
  /// [completeReconcile] mirrors "the cold-start workspace restore has already
  /// settled". The runtime-open path (`didUpdateWidget` → `_openRuntimeFile`)
  /// now waits on [startupReconcileProvider] before opening — in the real app
  /// `_WaveCruxAppState` completes it after restore; this harness has no such
  /// widget, so completing it up front keeps the warm-share tests exercising
  /// the post-restore behavior. Pass `false` to hold the barrier open and
  /// simulate an open arriving *mid-restore*.
  _Harness({bool completeReconcile = true}) {
    tcm = TabContainerManager(
      extraTabOverrides: [
        sessionAutoSaveProvider.overrideWith(_InertSessionAutoSaveNotifier.new),
      ],
    );
    pcm = PaneContainerManager();
    container = ProviderContainer(
      overrides: [
        productTelemetryConfig,
        tabContainerManagerProvider.overrideWithValue(tcm),
        paneContainerManagerProvider.overrideWithValue(pcm),
        workspaceServiceProvider.overrideWithValue(_InMemoryWorkspaceService()),
        deviceClassProvider.overrideWithValue(DeviceClass.phone),
        mobileMemoryGuardProvider.overrideWith(_InertMemoryGuardNotifier.new),
      ],
    );
    tcm.init(container);
    pcm.init(container);
    if (completeReconcile) container.read(startupReconcileProvider).complete();
  }

  /// Releases the reconcile barrier (used by the mid-restore test once the
  /// simulated restore is done).
  void completeReconcile() =>
      container.read(startupReconcileProvider).complete();

  late final TabContainerManager tcm;
  late final PaneContainerManager pcm;
  late final ProviderContainer container;

  TabId get activeTabId => container.read(activeTabIdProvider);

  bool loadedIn(TabId id) =>
      tcm.containerFor(id).read(waveformIsLoadedProvider);

  Widget build({required String? filePath, String? openRequest}) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: ViewerScreen(filePath: filePath, openRequest: openRequest),
        ),
      );

  void dispose() {
    tcm.dispose();
    pcm.dispose();
    container.dispose();
  }
}
