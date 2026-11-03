// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A context menu opens at the click, whichever navigator the tab lives in.
//
// Each file tab has its own `Navigator`, below the toolbar and tab bar, and
// the app's root `Navigator` can itself sit below a strip (the licence
// strip). `showMenu` lays a menu out in the overlay of the navigator it
// pushes onto, so a menu shown with a global pointer position on the tab's
// navigator opened by that navigator's offset too low (about 85 dp in the
// shipped app). These tests mount the viewer in a nested `Navigator` placed
// below a fixed-height strip, optionally with a second strip above the root
// navigator, right-click, and check the menu's top-left is at the click.
//
// LOCALE_SWEEP_EXEMPT: asserts where a menu opens, not what its labels say.

import 'dart:async';
import 'dart:math' show min;

import 'package:crux_workspace/crux_workspace.dart' show CruxGlowingAppIcon;
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/theme/wavecrux_theme.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/signal_tree/widgets/scope_tree_node.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_panel.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';
import 'package:wavecrux/features/viewer/widgets/signal_list_panel.dart';
import 'package:wavecrux/features/viewer/widgets/value_column_row.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../../../helpers/cxp_test_overrides.dart';
import '../../../helpers/fake_waveform_data_source.dart';
import '../../../helpers/product_telemetry_config.dart';

/// Large enough that no menu here is clamped by the window edge, which would
/// move it off the click for a reason other than the one under test.
const _window = Size(1400, 900);

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
  Future<String?> sidecarPathFor(
    String tabId, {
    String extension = '.wavecrux',
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An 8-bit bus with a few changes.
const _dataOut = Variable(
  name: 'data_out',
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: '#',
  scopePath: 'top',
  bitWidth: 8,
);

class _LoadedSource extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() {
    currentFilePath = '/kit/xtrace.vcd';
    return AsyncData(
      FakeWaveformDataSource(
        signals: {
          _dataOut.signalRef: const [
            SignalChange(time: 0, value: '00000000'),
            SignalChange(time: 20, value: '00000001'),
            SignalChange(time: 200, value: 'xxxxxxxx'),
          ],
        },
        scopes: const [
          Scope(
            name: 'top',
            type: ScopeType.module,
            path: 'top',
            variables: [_dataOut],
          ),
        ],
      ),
    );
  }
}

class _Scope extends StatefulWidget {
  const _Scope({required this.child});

  final Widget child;

  @override
  State<_Scope> createState() => _ScopeState();
}

class _ScopeState extends State<_Scope> {
  late final TabContainerManager _tcm;
  late final PaneContainerManager _pcm;
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _tcm = TabContainerManager(
      extraTabOverrides: [
        waveformSourceProvider.overrideWith(_LoadedSource.new),
      ],
    );
    _pcm = PaneContainerManager();
    _container = ProviderContainer(
      overrides: [
        ...cxpTestOverrides,
        productTelemetryConfig,
        tabContainerManagerProvider.overrideWithValue(_tcm),
        paneContainerManagerProvider.overrideWithValue(_pcm),
        workspaceServiceProvider.overrideWithValue(_InMemoryWorkspaceService()),
        waveformIsLoadedProvider.overrideWithValue(true),
      ],
    );
    _tcm.init(_container);
    _pcm.init(_container);
    unawaited(_container.wavecruxWorkspace.newTab(displayName: 'xtrace.vcd'));
  }

  @override
  void dispose() {
    _tcm.dispose();
    _pcm.dispose();
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      UncontrolledProviderScope(container: _container, child: widget.child);
}

/// Height of the strip above a tab's navigator: the toolbar and tab bar.
const _tabStrip = 85.0;

/// Height of the strip above the root navigator, when one shows.
const _rootStrip = 30.0;

/// Pumps the viewer inside its own `Navigator`, below a [_tabStrip]-high
/// strip, as a file tab is, with `data_out` added to the viewer. The root
/// navigator sits below a [rootStrip]-high strip when that is above zero.
Future<void> _pumpTabbedViewer(
  WidgetTester tester, {
  required double rootStrip,
}) async {
  tester.view
    ..physicalSize = _window
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  CruxGlowingAppIcon.debugDisableAnimations = true;
  addTearDown(() => CruxGlowingAppIcon.debugDisableAnimations = false);
  await tester.pumpWidget(
    _Scope(
      child: MaterialApp(
        theme: WavecruxTheme.resolve(
          brightness: Brightness.dark,
          highContrast: false,
          extensions: const [WavecruxColorExtension.dark()],
          platform: TargetPlatform.macOS,
          isWeb: false,
        ),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        builder: (context, child) => Column(
          children: [
            if (rootStrip > 0) SizedBox(height: rootStrip),
            Expanded(child: child!),
          ],
        ),
        home: Column(
          children: [
            const SizedBox(height: _tabStrip),
            Expanded(
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const ViewerScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();

  final tab = ProviderScope.containerOf(
    tester.element(find.byType(SignalTreePanel)),
  );
  await tab.read(waveformSourceProvider).value!.loadSignal(_dataOut.signalRef);
  tab.read(signalGroupsProvider.notifier).addSignal(_dataOut);
  await tester.pumpAndSettle();
}

/// Right-clicks [target], at its centre or [fromLeft] in from its left edge,
/// and returns the top-left of the menu that opens.
///
/// The Values dock hugs the window's right edge, where a menu is moved left
/// to fit; a click near the left edge of its rows keeps that out of the way.
Future<Offset> _menuTopLeftAfterRightClick(
  WidgetTester tester,
  Finder target, {
  double? fromLeft,
}) async {
  expect(target, findsOneWidget);
  final click = fromLeft == null
      ? tester.getCenter(target)
      : Offset(
          tester.getTopLeft(target).dx + fromLeft,
          tester.getCenter(target).dy,
        );
  await tester.tapAt(click, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
  final menu = find.byType(SingleChildScrollView).last;
  expect(menu, findsOneWidget);
  final rect = tester.getRect(menu);
  // The menu's top edge is at the click. Horizontally, its left edge is, or
  // its right edge when it was flipped to fit beside the window's edge.
  expect(
    (rect.top - click.dy).abs(),
    lessThan(4),
    reason: 'the menu $rect opened for a click at $click',
  );
  expect(
    min((rect.left - click.dx).abs(), (rect.right - click.dx).abs()),
    lessThan(4),
    reason: 'the menu $rect opened for a click at $click',
  );
  final topLeft = rect.topLeft;
  return topLeft;
}

void main() {
  // Without a strip above the root navigator, and with one: the root
  // overlay is itself offset in the second case.
  for (final rootStrip in const [0.0, _rootStrip]) {
    final where = rootStrip > 0
        ? 'below a strip, in a tab navigator'
        : 'in a tab navigator';

    testWidgets("a signal row's menu opens at the click $where", (
      tester,
    ) async {
      await _pumpTabbedViewer(tester, rootStrip: rootStrip);
      final entry = ProviderScope.containerOf(
        tester.element(find.byType(SignalTreePanel)),
      ).read(signalGroupsProvider).entries.single;
      await _menuTopLeftAfterRightClick(
        tester,
        find.byKey(ValueKey(SignalListPanel.signalRowKeyValue(entry))),
      );
    });

    testWidgets("a Values row's menu opens at the click $where", (
      tester,
    ) async {
      await _pumpTabbedViewer(tester, rootStrip: rootStrip);
      await _menuTopLeftAfterRightClick(
        tester,
        find.byType(ValueColumnRow),
        fromLeft: 8,
      );
    });

    testWidgets("the Display Format submenu opens where the Values row's menu "
        'did $where', (tester) async {
      await _pumpTabbedViewer(tester, rootStrip: rootStrip);
      final first = await _menuTopLeftAfterRightClick(
        tester,
        find.byType(ValueColumnRow),
        fromLeft: 8,
      );
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      final submenu = tester.getRect(find.byType(SingleChildScrollView).last);
      expect(
        (submenu.top - first.dy).abs(),
        lessThan(4),
        reason: 'the submenu $submenu opened for a menu at $first',
      );
    });

    testWidgets("a Signal Tree scope's menu opens at the click $where", (
      tester,
    ) async {
      await _pumpTabbedViewer(tester, rootStrip: rootStrip);
      await _menuTopLeftAfterRightClick(tester, find.byType(ScopeTreeNode));
    });
  }
}
