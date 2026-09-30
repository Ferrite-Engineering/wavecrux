// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

// LOCALE_SWEEP_EXEMPT: routing harness for files dropped on the desktop
// window — real FFI parses under `runAsync`, bounded polls on tab and load
// state. The strings it reads are waveform names and the English GTKWave
// import summary, checked as state, not as rendering. The drop overlay's
// locale sweep lives with the overlay, in
// test/features/workspace/widgets/file_drop_overlay_test.dart.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/core/startup_reconcile_provider.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/wavecrux_tab.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/mobile_memory_guard_provider.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';
import 'package:wavecrux/features/viewer/widgets/gtkw_import_result_dialog.dart';
import 'package:wavecrux/features/workspace/providers/recent_files_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/features/workspace/widgets/desktop_file_drop_target.dart';
import 'package:wavecrux/features/workspace/widgets/file_drop_overlay.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '../../../helpers/product_telemetry_config.dart';
import '../../../helpers/wellen_ffi_library_gate.dart';

/// Files dropped on the desktop window, end to end below the plugin: the
/// window-level [DesktopFileDropTarget] (driven through its drop-target seam,
/// so no `desktop_drop` channel is involved) → the drop router → the viewer's
/// File > Open dispatch → tabs, recents, the GTKWave import.
void main() {
  if (!requireWellenFfiLibrary('desktop window file drop')) return;

  TestWidgetsFlutterBinding.ensureInitialized();

  const vcdA = 'test/fixtures/vcd/scalar_basics.vcd'; // top: clk/rst/data
  const vcdB = 'test/fixtures/vcd/deep_hierarchy.vcd'; // top: cpu/mem

  // The drop target only mounts on a native desktop host.
  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

  late Directory scratch;
  late String gtkw;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    scratch = Directory.systemTemp.createTempSync('wavecrux_drop');
    // A GTKWave save naming scalar_basics.vcd's three signals.
    gtkw = p.join(scratch.path, 'scalar_basics.gtkw');
    File(gtkw).writeAsStringSync(
      '[dumpfile] "scalar_basics.vcd"\n'
      '[timestart] 0\n'
      '@28\n'
      'top.clk\n'
      'top.rst\n'
      '@22\n'
      'top.data[7:0]\n',
    );
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  testWidgets(
    'a drop on the empty canvas opens the file in a tab and records it',
    variant: macOS,
    (tester) async {
      await tester.runAsync(() async {
        final h = await _Harness.pump(tester);
        expect(h.tabs, isEmpty);

        h.drag.enter();
        await tester.pump();
        expect(find.byType(FileDropOverlay), findsOneWidget);

        h.drag.drop([vcdA]);
        await tester.pump();
        expect(
          find.byType(FileDropOverlay),
          findsNothing,
          reason: 'the overlay goes as soon as the drop lands',
        );
        await _pumpUntil(
          tester,
          () => h.tabs.length == 1 && h.loadedIn(h.activeTabId),
          reason: 'the dropped file should open and load',
        );
        expect(h.tabs.single.filePath, vcdA);
        expect(
          await h.container.read(recentFilesProvider.future),
          contains(vcdA),
          reason: 'a drop is recorded in Recent Files like File > Open',
        );
      });
    },
  );

  testWidgets(
    'a drop over an open waveform opens a new tab, not a replacement',
    variant: macOS,
    (tester) async {
      await tester.runAsync(() async {
        final h = await _Harness.pump(tester);
        await h.dropAndWait(tester, [vcdA], tabs: 1);
        final first = h.activeTabId;

        await h.dropAndWait(tester, [vcdB], tabs: 2);
        expect(h.tabs.map((t) => t.filePath), [vcdA, vcdB]);
        expect(h.activeTabId, isNot(first));
        expect(h.loadedIn(first), isTrue, reason: 'the first tab is kept');
      });
    },
  );

  testWidgets(
    'dropping the same file twice opens it twice, as File > Open does',
    variant: macOS,
    (tester) async {
      await tester.runAsync(() async {
        final h = await _Harness.pump(tester);
        await h.dropAndWait(tester, [vcdA], tabs: 1);
        await h.dropAndWait(tester, [vcdA], tabs: 2);
        expect(h.tabs.map((t) => t.filePath), [vcdA, vcdA]);
      });
    },
  );

  testWidgets(
    'several files in one drop each open in their own tab',
    variant: macOS,
    (tester) async {
      await tester.runAsync(() async {
        final h = await _Harness.pump(tester);
        await h.dropAndWait(tester, [vcdA, vcdB], tabs: 2);
        expect(h.tabs.map((t) => t.filePath), [vcdA, vcdB]);
        for (final tab in h.tabs) {
          expect(h.loadedIn(tab.id), isTrue);
        }
      });
    },
  );

  testWidgets(
    'a dropped .gtkw with a waveform open is imported into the active tab',
    variant: macOS,
    (tester) async {
      await tester.runAsync(() async {
        final h = await _Harness.pump(tester);
        await h.dropAndWait(tester, [vcdA], tabs: 1);

        h.drag.drop([gtkw]);
        await _pumpUntil(
          tester,
          () => find.byType(GtkwImportResultDialog).evaluate().isNotEmpty,
          reason: 'the GTKWave import summary should appear',
        );
        expect(h.tabs, hasLength(1), reason: 'an import opens no tab');
        expect(find.text('3 signals imported'), findsOneWidget);
        expect(
          await h.container.read(recentFilesProvider.future),
          contains(gtkw),
        );
      });
    },
  );

  testWidgets(
    'a dropped .gtkw with nothing open shows the import summary, as '
    'File > Import GTKWave Session does',
    variant: macOS,
    (tester) async {
      await tester.runAsync(() async {
        final h = await _Harness.pump(tester);

        h.drag.drop([gtkw]);
        await _pumpUntil(
          tester,
          () => find.byType(GtkwImportResultDialog).evaluate().isNotEmpty,
          reason: 'the import path reports what it could not match',
        );
        expect(h.tabs, isEmpty);
        expect(find.text('0 signals imported'), findsOneWidget);
        expect(find.text('Signals not found in waveform (3):'), findsOneWidget);
      });
    },
  );

  testWidgets(
    'a waveform and its .gtkw dropped together: the waveform opens first and '
    'the session lands on it, whatever order they arrive in',
    variant: macOS,
    (tester) async {
      await tester.runAsync(() async {
        final h = await _Harness.pump(tester);

        h.drag.drop([gtkw, vcdA]);
        await _pumpUntil(
          tester,
          () => find.byType(GtkwImportResultDialog).evaluate().isNotEmpty,
          reason: 'the import summary should follow the open',
        );
        expect(h.tabs.single.filePath, vcdA);
        expect(find.text('3 signals imported'), findsOneWidget);
      });
    },
  );

  testWidgets(
    'an unsupported file opens into the load error, never silently',
    variant: macOS,
    (tester) async {
      await tester.runAsync(() async {
        final h = await _Harness.pump(tester);
        final notes = p.join(scratch.path, 'notes.txt');
        File(notes).writeAsStringSync('not a waveform\n');

        h.drag.drop([notes]);
        await _pumpUntil(
          tester,
          () =>
              h.tabs.length == 1 &&
              h.tcm
                  .containerFor(h.activeTabId)
                  .read(waveformSourceProvider)
                  .hasError,
          reason: 'the parse failure is shown in the tab, as for any open',
        );
        expect(find.text('Failed to load waveform'), findsWidgets);
      });
    },
  );

  testWidgets(
    'no overlay and no open while a dialog is in front of the viewer',
    variant: macOS,
    (tester) async {
      await tester.runAsync(() async {
        final h = await _Harness.pump(tester);
        unawaited(
          showDialog<void>(
            context: tester.element(find.byType(ViewerScreen)),
            builder: (_) => const AlertDialog(content: Text('busy')),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        h.drag.enter();
        await tester.pump();
        expect(find.byType(FileDropOverlay), findsNothing);

        h.drag.drop([vcdA]);
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
        expect(h.tabs, isEmpty, reason: 'nothing opens behind a dialog');
      });
    },
  );

  testWidgets(
    'no overlay and no open while a modal gate covers the app',
    variant: macOS,
    (tester) async {
      // The licence agreement and the telemetry disclosure stack over the app
      // as a `CruxModalGate`, not a route: the viewer stays current, and only
      // the `ExcludeFocus` around it says it is covered.
      await tester.runAsync(() async {
        final h = await _Harness.pump(tester, gated: true);
        h.drag.enter();
        await tester.pump();
        expect(find.byType(FileDropOverlay), findsNothing);

        h.drag.drop([vcdA]);
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
        expect(h.tabs, isEmpty, reason: 'nothing opens behind a gate');
      });
    },
  );

  testWidgets(
    'a drag that leaves the window takes the overlay with it',
    variant: macOS,
    (tester) async {
      await tester.runAsync(() async {
        final h = await _Harness.pump(tester);
        h.drag.enter();
        await tester.pump();
        expect(find.byType(FileDropOverlay), findsOneWidget);
        h.drag.exit();
        await tester.pump();
        expect(find.byType(FileDropOverlay), findsNothing);
        expect(h.tabs, isEmpty);
      });
    },
  );
}

// ── helpers ───────────────────────────────────────────────────────────────────

/// Bounded condition-poll under `runAsync`: real async (FFI isolate parse)
/// makes progress between pumps; returns the moment [ready] is true.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  required String reason,
}) async {
  for (var i = 0; i < 400; i++) {
    if (ready()) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
    await tester.pump();
  }
  fail('timed out: $reason');
}

/// Stands in for `desktop_drop`: captures the callbacks the window drop
/// target hands its drop-target builder, so a test can play a drag.
class _FakeDrag {
  late VoidCallback _enter;
  late VoidCallback _exit;
  late ValueChanged<List<String>> _drop;

  Widget build({
    required Widget child,
    required VoidCallback onEntered,
    required VoidCallback onExited,
    required ValueChanged<List<String>> onDropped,
  }) {
    _enter = onEntered;
    _exit = onExited;
    _drop = onDropped;
    return child;
  }

  void enter() => _enter();
  void exit() => _exit();

  /// A whole gesture: the drag enters, then releases [paths].
  void drop(List<String> paths) {
    _enter();
    _drop(paths);
  }
}

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

class _InertMemoryGuardNotifier extends MobileMemoryGuardNotifier {
  @override
  MemoryGuardState build() => const MemoryGuardState();
}

class _InertSessionAutoSaveNotifier extends SessionAutoSaveNotifier {
  @override
  void build() {}
}

/// The viewer inside a `MaterialApp` whose builder mounts the window drop
/// target exactly as `WaveCruxApp` does, with the cold-start restore settled.
class _Harness {
  _Harness._() {
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
        deviceClassProvider.overrideWithValue(DeviceClass.desktop),
        mobileMemoryGuardProvider.overrideWith(_InertMemoryGuardNotifier.new),
      ],
    );
    tcm.init(container);
    pcm.init(container);
    container.read(startupReconcileProvider).complete();
  }

  static Future<_Harness> pump(
    WidgetTester tester, {
    bool gated = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final h = _Harness._();
    addTearDown(h.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          builder: (context, child) => DesktopFileDropTarget(
            dropTargetBuilder: h.drag.build,
            child: ExcludeFocus(
              excluding: gated,
              child: child ?? const SizedBox(),
            ),
          ),
          home: const ViewerScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return h;
  }

  final _FakeDrag drag = _FakeDrag();
  late final TabContainerManager tcm;
  late final PaneContainerManager pcm;
  late final ProviderContainer container;

  List<WavecruxTab> get tabs => container.read(tabListProvider);

  TabId get activeTabId => container.read(activeTabIdProvider);

  bool loadedIn(TabId id) =>
      tcm.containerFor(id).read(waveformIsLoadedProvider);

  /// Drops [paths] and waits until [tabs] are open and the active one loaded.
  Future<void> dropAndWait(
    WidgetTester tester,
    List<String> paths, {
    required int tabs,
  }) async {
    drag.drop(paths);
    await _pumpUntil(
      tester,
      () => this.tabs.length == tabs && loadedIn(activeTabId),
      reason: 'drop of $paths should leave $tabs loaded tab(s)',
    );
  }

  void dispose() {
    tcm.dispose();
    pcm.dispose();
    container.dispose();
  }
}
