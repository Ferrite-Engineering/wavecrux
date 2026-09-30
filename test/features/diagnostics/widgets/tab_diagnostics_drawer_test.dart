// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/file_stats.dart';
import 'package:wavecrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:wavecrux/features/diagnostics/providers/file_stats_provider.dart';
import 'package:wavecrux/features/diagnostics/widgets/tab_diagnostics_drawer.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import '../../../helpers/in_memory_workspace_service.dart';
import '../../../helpers/product_telemetry_config.dart';

FileStats _stats({String filePath = '/tmp/a.vcd'}) => FileStats(
  filePath: filePath,
  fileSizeBytes: 4096,
  formatName: 'VCD',
  parseTimeMs: 25,
  totalSignals: 4,
  scalarCount: 3,
  vectorCount: 1,
  realCount: 0,
  inputCount: 2,
  outputCount: 1,
  inoutCount: 0,
  unknownDirectionCount: 1,
  totalTransitions: 100,
  hierarchyDepth: 2,
  scopeCount: 3,
  startTime: 0,
  endTime: 1000,
  timescaleDisplay: '1ns',
);

ProviderContainer _container({
  DeviceClass deviceClass = DeviceClass.desktop,
  bool diagnosticsEnabled = true,
  FileStats? fileStats,
}) {
  // The drawer resolves a per-tab ProviderContainer through
  // [tabContainerManagerProvider] so the embedded FileInfoPanel /
  // SignalHealthPanel / ParserBenchmarkRunner widgets read the active tab's
  // per-tab providers (Issue 10).
  //
  // [fileStatsProvider] is overridden per-tab in [wavecruxTabOverrides]; we
  // pass the test fixture through `extraTabOverrides` so the per-tab
  // container's override wins inside the embedded panel's `ref.watch`. A
  // matching root-scope override is kept for any code path that resolves
  // the provider before the per-tab scope is mounted.
  final tcm = TabContainerManager(
    extraTabOverrides: [
      fileStatsProvider.overrideWithValue(fileStats),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      deviceClassProvider.overrideWithValue(deviceClass),
      diagnosticsEnabledProvider.overrideWithValue(diagnosticsEnabled),
      fileStatsProvider.overrideWithValue(fileStats),
      tabContainerManagerProvider.overrideWithValue(tcm),
      ...testWorkspaceOverrides(),
    ],
  );
  tcm.init(container);
  return container;
}

Future<void> _pumpHarness(
  WidgetTester tester,
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) async {
  await _useDesktopSurface(tester);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_harness(container, locale: locale));
}

Widget _harness(
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('openTrigger'),
            onPressed: () => TabDiagnosticsDrawer.open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('openTrigger')));
  await tester.pumpAndSettle();
}

// Larger-than-default surface size used by every test in this file. The drawer
// only renders on tablet+ device class, and several assertions depend on the
// drawer's 360-dp minimum width fitting inside the test surface.
const _kSurface = Size(1400, 900);

Future<void> _useDesktopSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(_kSurface);
}

void main() {
  group('TabDiagnosticsDrawer', () {
    testWidgets('renders three collapsible sections, expanded by default', (
      tester,
    ) async {
      final c = _container(fileStats: _stats());
      addTearDown(c.dispose);

      await c.wavecruxWorkspace.openFile('/tmp/a.vcd');

      await _pumpHarness(tester, c);
      await _openDrawer(tester);

      final l10n = await L10N.delegate.load(const Locale('en'));

      expect(find.text(l10n.tabDiagnosticsTitle), findsOneWidget);
      expect(
        find.byKey(const Key('tabDiagnosticsSectionFileInfo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('tabDiagnosticsSectionSignalHealth')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('tabDiagnosticsSectionParserBackend')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('tabDiagnosticsSectionBenchmarkFile')),
        findsOneWidget,
      );
    });

    testWidgets('subtitle reflects active tab display name', (tester) async {
      final c = _container(fileStats: _stats());
      addTearDown(c.dispose);

      await c.wavecruxWorkspace.openFile('/tmp/alpha.vcd');

      await _pumpHarness(tester, c);
      await _openDrawer(tester);

      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(
        find.text(l10n.tabDiagnosticsSubtitle('alpha.vcd')),
        findsOneWidget,
      );
    });

    testWidgets('switching active tab updates the subtitle', (tester) async {
      final c = _container(fileStats: _stats());
      addTearDown(c.dispose);

      await c.wavecruxWorkspace.openFile('/tmp/alpha.vcd');
      await c.wavecruxWorkspace.openFile('/tmp/beta.vcd');

      await _pumpHarness(tester, c);
      await _openDrawer(tester);

      final l10n = await L10N.delegate.load(const Locale('en'));
      // The most recently opened tab (beta.vcd) is the active tab.
      expect(
        find.text(l10n.tabDiagnosticsSubtitle('beta.vcd')),
        findsOneWidget,
      );

      // Switch active tab back to the first one.
      final firstTabId = c.read(tabListProvider).first.id;
      c.read(activeTabIdProvider.notifier).activate(firstTabId);
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.tabDiagnosticsSubtitle('alpha.vcd')),
        findsOneWidget,
      );
    });

    // The drawer must remount its embedded
    // FileInfoPanel/SignalHealthPanel/ParserBenchmarkRunner subtree against
    // the new active tab's [ProviderContainer] when the user switches tabs.
    // The implementation keys the UncontrolledProviderScope by the active
    // tab id; this test pins that key change.
    testWidgets(
      'switching active tab reroutes drawer content to the new tab container',
      (tester) async {
        final c = _container(fileStats: _stats());
        addTearDown(c.dispose);

        await c.wavecruxWorkspace.openFile('/tmp/alpha.vcd');
        await c.wavecruxWorkspace.openFile('/tmp/beta.vcd');

        await _pumpHarness(tester, c);
        await _openDrawer(tester);

        // The drawer's embedded scope is keyed by the active tab id. Capture
        // it for the initial active tab (the most recently opened one, beta).
        final scrollKeyBefore = tester
            .widget<UncontrolledProviderScope>(
              find
                  .ancestor(
                    of: find.byKey(const Key('tabDiagnosticsScroll')),
                    matching: find.byType(UncontrolledProviderScope),
                  )
                  .first,
            )
            .key;

        // Switch the active tab to alpha.
        final tabs = c.read(tabListProvider);
        final alphaId = tabs
            .firstWhere((t) => t.filePath == '/tmp/alpha.vcd')
            .id;
        c.read(activeTabIdProvider.notifier).activate(alphaId);
        await tester.pumpAndSettle();

        final scrollKeyAfter = tester
            .widget<UncontrolledProviderScope>(
              find
                  .ancestor(
                    of: find.byKey(const Key('tabDiagnosticsScroll')),
                    matching: find.byType(UncontrolledProviderScope),
                  )
                  .first,
            )
            .key;

        expect(
          scrollKeyAfter,
          isNot(equals(scrollKeyBefore)),
          reason:
              'the embedded per-tab UncontrolledProviderScope must be re-keyed when the active tab changes',
        );
      },
    );

    testWidgets('closes when its target tab is closed', (tester) async {
      final c = _container(fileStats: _stats());
      addTearDown(c.dispose);

      await c.wavecruxWorkspace.openFile('/tmp/a.vcd');

      await _pumpHarness(tester, c);
      await _openDrawer(tester);

      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.tabDiagnosticsTitle), findsOneWidget);

      // Close the only tab — drawer must auto-dismiss when tabs.isEmpty.
      final id = c.read(tabListProvider).single.id;
      await c.wavecruxWorkspace.closeTab(id);
      await tester.pumpAndSettle();

      expect(find.text(l10n.tabDiagnosticsTitle), findsNothing);
    });

    testWidgets('explicit close button dismisses the drawer', (tester) async {
      final c = _container(fileStats: _stats());
      addTearDown(c.dispose);

      await c.wavecruxWorkspace.openFile('/tmp/a.vcd');

      await _pumpHarness(tester, c);
      await _openDrawer(tester);

      expect(
        find.byKey(const Key('tabDiagnosticsCloseButton')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('tabDiagnosticsCloseButton')));
      await tester.pumpAndSettle();

      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.tabDiagnosticsTitle), findsNothing);
    });

    // Issue 24 regression: the drawer must NOT install a modal barrier
    // beneath itself. The previous `showGeneralDialog` implementation —
    // even with `barrierColor: Colors.transparent` — captured every
    // pointer event outside the drawer's bounds, making the underlying
    // tab close (×) button and every other chrome surface unresponsive.
    // After the overlay-entry refactor, a button positioned outside the
    // drawer's right-aligned Material region must still fire its onTap
    // while the drawer is mounted.
    testWidgets(
      'pointer events outside the drawer reach underlying widgets (Issue 24)',
      (tester) async {
        var underlyingTapCount = 0;
        final c = _container(fileStats: _stats());
        addTearDown(c.dispose);

        await c.wavecruxWorkspace.openFile('/tmp/a.vcd');

        await tester.binding.setSurfaceSize(_kSurface);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Builder(
                builder: (context) => Scaffold(
                  body: Stack(
                    children: [
                      // Underlying button pinned to the LEFT edge of the
                      // surface — well outside the right-aligned drawer's
                      // bounds (the drawer takes ~45% of the viewport from
                      // the right, never reaching the left chrome).
                      Positioned(
                        left: 20,
                        top: 20,
                        child: ElevatedButton(
                          key: const Key('underlyingButton'),
                          onPressed: () => underlyingTapCount++,
                          child: const Text('underlying'),
                        ),
                      ),
                      Center(
                        child: ElevatedButton(
                          key: const Key('openTrigger'),
                          onPressed: () => TabDiagnosticsDrawer.open(context),
                          child: const Text('open'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        // Open the drawer. The underlying button must remain hit-testable.
        await _openDrawer(tester);
        final l10n = await L10N.delegate.load(const Locale('en'));
        expect(
          find.text(l10n.tabDiagnosticsTitle),
          findsOneWidget,
          reason: 'drawer should be open',
        );

        // Tap the underlying button while the drawer is open. Pre-fix this
        // tap would be absorbed by the dialog's ModalBarrier.
        await tester.tap(find.byKey(const Key('underlyingButton')));
        await tester.pump();
        expect(
          underlyingTapCount,
          equals(1),
          reason:
              'underlying button must remain interactive while drawer is open',
        );

        // Drawer is still open after the underlying tap (no incidental dismiss).
        expect(find.text(l10n.tabDiagnosticsTitle), findsOneWidget);
      },
    );

    testWidgets(
      'Copy Tab Diagnostics Report writes a structured report to clipboard',
      (tester) async {
        final c = _container(fileStats: _stats(filePath: '/tmp/alpha.vcd'));
        addTearDown(c.dispose);

        await c.wavecruxWorkspace.openFile('/tmp/alpha.vcd');

        // Capture clipboard writes via the test channel.
        final clipboardWrites = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                final args = call.arguments as Map<Object?, Object?>;
                clipboardWrites.add(args['text']! as String);
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        await _pumpHarness(tester, c);
        await _openDrawer(tester);

        await tester.tap(
          find.byKey(const Key('tabDiagnosticsCopyReportButton')),
        );
        await tester.pump();

        expect(clipboardWrites, isNotEmpty);
        final report = clipboardWrites.single;
        expect(report, contains('=== WaveCrux Tab Diagnostics Report ==='));
        expect(report, contains('Tab Name: alpha.vcd'));
        expect(report, contains('File: /tmp/alpha.vcd'));
        expect(report, contains('--- File Info ---'));
        expect(report, contains('--- Signal Health ---'));
        expect(report, contains('--- Benchmark This File ---'));
      },
    );

    testWidgets('auto-dismisses on phone device class', (tester) async {
      final c = _container(
        deviceClass: DeviceClass.phone,
        fileStats: _stats(),
      );
      addTearDown(c.dispose);

      await c.wavecruxWorkspace.openFile('/tmp/a.vcd');

      await _pumpHarness(tester, c);
      await _openDrawer(tester);

      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.tabDiagnosticsTitle), findsNothing);
    });

    testWidgets('auto-dismisses when diagnosticsEnabledProvider = false', (
      tester,
    ) async {
      final c = _container(
        diagnosticsEnabled: false,
        fileStats: _stats(),
      );
      addTearDown(c.dispose);

      await c.wavecruxWorkspace.openFile('/tmp/a.vcd');

      await _pumpHarness(tester, c);
      await _openDrawer(tester);

      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.tabDiagnosticsTitle), findsNothing);
    });

    // ── locale sweep ───────────────────────────────────────────────────────────

    for (final locale in [
      const Locale('en'),
      const Locale('zh', 'CN'),
      const Locale('ja'),
      const Locale('ko'),
    ]) {
      testWidgets('renders in ${locale.toLanguageTag()} without exceptions', (
        tester,
      ) async {
        final c = _container(fileStats: _stats());
        addTearDown(c.dispose);

        await c.wavecruxWorkspace.openFile('/tmp/a.vcd');

        await _pumpHarness(tester, c, locale: locale);
        await _openDrawer(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // Regression: Issues 32 & 33. The legacy _Section host bounded each
  // panel to SizedBox(height: 320, child: SingleChildScrollView(horizontal,
  // child: SizedBox(width: 720))). On a drawer narrower than 720 dp the
  // value column (Format, Total Signals, Transitions, parsed File Path /
  // File Size / Parse Time) was clipped past the right edge, and the
  // "Signals by Direction" section sat below the 320-dp fold and required
  // a hidden scroll to surface. After the fix, each panel renders directly
  // inside the drawer's outer SingleChildScrollView with no fixed height
  // or width, so a vertical scroll exposes all sections and metric values
  // never overflow the drawer's right edge.
  group('TabDiagnosticsDrawer — File Info section reachability', () {
    testWidgets(
      'Signals by Direction section header is reachable in scrollable drawer',
      (tester) async {
        final c = _container(fileStats: _stats());
        addTearDown(c.dispose);

        await c.wavecruxWorkspace.openFile('/tmp/a.vcd');

        await _pumpHarness(tester, c);
        await _openDrawer(tester);

        final l10n = await L10N.delegate.load(const Locale('en'));

        // Header may sit below the initial fold; reach it via the outer
        // drawer scroll view rather than the legacy 320-dp section box.
        final byDirection = find.text(
          l10n.diagnosticsFileInfoSectionByDirection,
        );
        await tester.scrollUntilVisible(
          byDirection,
          100,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('tabDiagnosticsScroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );

        expect(byDirection, findsOneWidget);
      },
    );

    testWidgets(
      'metric values render within the drawer without horizontal clipping',
      (tester) async {
        final c = _container(
          fileStats: _stats().copyWith(formatName: 'VCD', totalSignals: 4242),
        );
        addTearDown(c.dispose);

        await c.wavecruxWorkspace.openFile('/tmp/a.vcd');

        await _pumpHarness(tester, c);
        await _openDrawer(tester);

        // Format value ("VCD") must be inside the drawer's render area.
        final drawerRect = tester.getRect(
          find.byKey(const Key('tabDiagnosticsScroll')),
        );
        final formatValueRect = tester.getRect(find.text('VCD'));
        expect(
          formatValueRect.right,
          lessThanOrEqualTo(drawerRect.right + 0.5),
          reason:
              'Format value text must not extend past the drawer right edge '
              '(Issue 32/33: legacy 720-dp pinning clipped the value column)',
        );
      },
    );
  });

  group('TabDiagnosticsDrawer — touch target compliance', () {
    testWidgets('Close button hit area is at least 44 × 44 dp on tablet', (
      tester,
    ) async {
      final c = _container(
        deviceClass: DeviceClass.tablet,
        fileStats: _stats(),
      );
      addTearDown(c.dispose);

      await c.wavecruxWorkspace.openFile('/tmp/a.vcd');

      await _pumpHarness(tester, c);
      await _openDrawer(tester);

      final size = tester.getSize(
        find.byKey(const Key('tabDiagnosticsCloseButton')),
      );
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });
}
