// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/file_stats.dart';
import 'package:wavecrux/domain/models/memory_stats.dart';
import 'package:wavecrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:wavecrux/features/diagnostics/providers/file_stats_provider.dart';
import 'package:wavecrux/features/diagnostics/providers/memory_stats_provider.dart';
import 'package:wavecrux/features/diagnostics/widgets/app_diagnostics_dialog.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import '../../../helpers/in_memory_workspace_service.dart';
import '../../../helpers/product_telemetry_config.dart';

/// Stub notifier that returns a fixed [MemoryStats] snapshot without
/// starting a polling Timer. The real [MemoryStatsNotifier] arms a
/// `Timer.periodic` in its `build()`; without this stub the per-tab
/// container leaves a pending timer in tester after the widget tree is
/// disposed, which `AutomatedTestWidgetsFlutterBinding` flags as a failure.
class _StubMemoryStatsNotifier extends MemoryStatsNotifier {
  @override
  MemoryStats? build() => const MemoryStats(
    wellenEstimateBytes: 1024 * 1024,
    loadedSignalCount: 1,
    totalSignalCount: 4,
    dartProcessRssBytes: 64 * 1024 * 1024,
  );
}

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

({ProviderContainer root, TabContainerManager tcm}) _bootstrap({
  DeviceClass deviceClass = DeviceClass.desktop,
  bool diagnosticsEnabled = true,
  FileStats? fileStats,
}) {
  // Per-tab containers replace the polling MemoryStatsNotifier with a stub
  // that returns a static snapshot; otherwise each tab's Timer.periodic
  // outlives the widget tree and trips the test framework's "pending
  // timer" check.
  final tcm = TabContainerManager(
    extraTabOverrides: [
      memoryStatsProvider.overrideWith(_StubMemoryStatsNotifier.new),
    ],
  );
  final root = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      tabContainerManagerProvider.overrideWithValue(tcm),
      workspaceServiceProvider.overrideWithValue(InMemoryWorkspaceService()),
      deviceClassProvider.overrideWithValue(deviceClass),
      diagnosticsEnabledProvider.overrideWithValue(diagnosticsEnabled),
      fileStatsProvider.overrideWithValue(fileStats),
    ],
  );
  tcm.init(root);
  return (root: root, tcm: tcm);
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
            onPressed: () => AppDiagnosticsDialog.open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _pumpHarness(
  WidgetTester tester,
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_harness(container, locale: locale));
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('openTrigger')));
  await tester.pumpAndSettle();
}

/// Dismisses an open dialog by popping its route. Necessary because the
/// dialog's state owns a [Timer.periodic] that is cancelled in [State.dispose];
/// without an explicit pop the timer survives test teardown and trips the
/// framework's pending-timer check.
Future<void> _closeDialog(WidgetTester tester) async {
  if (find.byKey(const Key('appDiagnosticsCloseButton')).evaluate().isEmpty) {
    return;
  }
  await tester.tap(find.byKey(const Key('appDiagnosticsCloseButton')));
  await tester.pumpAndSettle();
}

/// Closes the dialog (so its `Timer.periodic` is cancelled and Riverpod
/// listener subscriptions close), detaches the widget tree, drains the
/// FakeAsync timer queue, and disposes the container + TabContainerManager.
/// Must be called at the END of each test body (not via `addTearDown`):
/// `AutomatedTestWidgetsFlutterBinding` checks for pending timers
/// *before* tear-down callbacks run, so any periodic timer alive at the
/// moment the body returns trips the test framework.
Future<void> _teardown(
  WidgetTester tester,
  ({ProviderContainer root, TabContainerManager tcm}) boot,
) async {
  await _closeDialog(tester);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  boot.tcm.dispose();
  boot.root.dispose();
  await tester.pumpAndSettle();
}

void main() {
  group('AppDiagnosticsDialog', () {
    testWidgets('renders Memory and Frame Stats sections', (tester) async {
      final boot = _bootstrap(fileStats: _stats());
      await boot.root.wavecruxWorkspace.openFile('/tmp/a.vcd');

      await _pumpHarness(tester, boot.root);
      await _openDialog(tester);

      expect(
        find.byKey(const Key('appDiagnosticsSectionMemory')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('appDiagnosticsSectionFrameStats')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('appDiagnosticsSectionPerTabBreakdown')),
        findsOneWidget,
      );
      await _teardown(tester, boot);
    });

    testWidgets('per-tab breakdown table has one row per open tab', (
      tester,
    ) async {
      final boot = _bootstrap(fileStats: _stats());
      final ws = boot.root.wavecruxWorkspace;
      await ws.openFile('/tmp/alpha.vcd');
      await ws.openFile('/tmp/beta.vcd');
      await ws.openFile('/tmp/gamma.vcd');

      await _pumpHarness(tester, boot.root);
      await _openDialog(tester);

      final table = tester.widget<DataTable>(
        find.byKey(const Key('appDiagnosticsPerTabTable')),
      );
      expect(table.rows.length, equals(3));
      await _teardown(tester, boot);
    });

    testWidgets(
      'Copy Full Diagnostics Report writes structured report to clipboard',
      (tester) async {
        final boot = _bootstrap(fileStats: _stats(filePath: '/tmp/alpha.vcd'));
        final ws = boot.root.wavecruxWorkspace;
        await ws.openFile('/tmp/alpha.vcd');
        await ws.openFile('/tmp/beta.vcd');

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

        await _pumpHarness(tester, boot.root);
        await _openDialog(tester);

        await tester.tap(
          find.byKey(const Key('appDiagnosticsCopyReportButton')),
        );
        await tester.pumpAndSettle();

        expect(clipboardWrites, isNotEmpty);
        final report = clipboardWrites.single;
        expect(report, contains('=== WaveCrux Full Diagnostics Report ==='));
        expect(report, contains('--- App Memory ---'));
        expect(report, contains('--- Frame Stats ---'));
        expect(report, contains('--- Active Pane Render Stats ---'));
        expect(report, contains('--- Per-Tab Breakdown ---'));
        // Per-tab breakdown should mention both tabs by display name.
        expect(report, contains('alpha.vcd'));
        expect(report, contains('beta.vcd'));

        await _teardown(tester, boot);
      },
    );

    // ── Issue 20 regression: scrollable content + Scrollbar ───────────────
    //
    // Pre-fix the dialog had a plain `SingleChildScrollView` with no
    // Scrollbar wrapper and no custom `ScrollBehavior`. Two-finger
    // trackpad pan and mouse-drag scrolling did not work on macOS desktop
    // when the per-tab memory breakdown exceeded the dialog's fixed
    // 620 dp height — the user had no visual indication that scrolling
    // was possible and no usable input gesture to reach the lower
    // section. These tests pin the structural fix: the dialog must
    // expose a `Scrollbar` over a `SingleChildScrollView`, and the
    // surrounding `ScrollConfiguration` must accept trackpad + mouse
    // drag devices in addition to touch.
    testWidgets('wraps content in a Scrollbar so scroll is discoverable', (
      tester,
    ) async {
      final boot = _bootstrap(fileStats: _stats());
      await boot.root.wavecruxWorkspace.openFile('/tmp/a.vcd');

      await _pumpHarness(tester, boot.root);
      await _openDialog(tester);

      expect(find.byType(Scrollbar), findsAtLeastNWidgets(1));
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      await _teardown(tester, boot);
    });

    testWidgets('ScrollConfiguration accepts trackpad + mouse drag input', (
      tester,
    ) async {
      final boot = _bootstrap(fileStats: _stats());
      await boot.root.wavecruxWorkspace.openFile('/tmp/a.vcd');

      await _pumpHarness(tester, boot.root);
      await _openDialog(tester);

      // Find the ScrollConfiguration scoped to the dialog's content
      // (descendant of SingleChildScrollView's ancestor chain). Walk the
      // tree to grab the nearest ScrollConfiguration above the scroll view
      // and assert its behavior accepts trackpad + mouse input.
      final scrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      // The ScrollConfiguration is an ancestor of the SingleChildScrollView.
      final config = tester.widget<ScrollConfiguration>(
        find
            .ancestor(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(ScrollConfiguration),
            )
            .first,
      );
      // Build a fake context-less behavior probe by reading dragDevices
      // from the configured ScrollBehavior.
      final devices = config.behavior.dragDevices;
      expect(devices, contains(PointerDeviceKind.touch));
      expect(devices, contains(PointerDeviceKind.mouse));
      expect(devices, contains(PointerDeviceKind.trackpad));
      // Sanity: the SingleChildScrollView is still vertical (default).
      expect(scrollView.scrollDirection, Axis.vertical);
      await _teardown(tester, boot);
    });

    testWidgets('hidden when diagnosticsEnabledProvider = false', (
      tester,
    ) async {
      final boot = _bootstrap(
        diagnosticsEnabled: false,
        fileStats: _stats(),
      );
      await boot.root.wavecruxWorkspace.openFile('/tmp/a.vcd');

      await _pumpHarness(tester, boot.root);
      await _openDialog(tester);

      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.appDiagnosticsTitle), findsNothing);
      await _teardown(tester, boot);
    });

    testWidgets('hidden on phone device class', (tester) async {
      final boot = _bootstrap(
        deviceClass: DeviceClass.phone,
        fileStats: _stats(),
      );
      await boot.root.wavecruxWorkspace.openFile('/tmp/a.vcd');

      await _pumpHarness(tester, boot.root);
      await _openDialog(tester);

      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.appDiagnosticsTitle), findsNothing);
      await _teardown(tester, boot);
    });

    // ── locale sweep ─────────────────────────────────────────────────────────

    for (final locale in [
      const Locale('en'),
      const Locale('zh', 'CN'),
      const Locale('ja'),
      const Locale('ko'),
    ]) {
      testWidgets('renders in ${locale.toLanguageTag()} without exceptions', (
        tester,
      ) async {
        final boot = _bootstrap(fileStats: _stats());
        await boot.root.wavecruxWorkspace.openFile('/tmp/a.vcd');

        await _pumpHarness(tester, boot.root, locale: locale);
        await _openDialog(tester);
        expect(tester.takeException(), isNull);
        await _teardown(tester, boot);
      });
    }
  });
}
