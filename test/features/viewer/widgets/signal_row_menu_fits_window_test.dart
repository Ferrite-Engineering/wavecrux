// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A signal row's context menu fits the smallest window the suite tests.
//
// The macOS desktop integration run went red on x_trace_gesture_test: in an
// 800x600 window the row's menu, with every entry an x-state FSM-candidate
// row offers, was taller than the window. Material clamps the menu to the
// window and scrolls it, so "Trace X Origin" sat below the visible part of
// the menu at y=647 and a pointer could not reach it without scrolling the
// menu first. On a pointer layout the menu now uses the desktop row height
// (the one the shared Crux context menu uses), so the whole menu shows at
// 800x600. On a touch layout the items keep the 48 dp touch target, and the
// menu stays inside the window and scrolls.

import 'dart:async';

import 'package:crux_workspace/crux_workspace.dart' show CruxGlowingAppIcon;
import 'package:flutter/foundation.dart';
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
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_panel.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/providers/x_trace_provider.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';
import 'package:wavecrux/features/viewer/widgets/signal_list_panel.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../../../helpers/cxp_test_overrides.dart';
import '../../../helpers/fake_waveform_data_source.dart';
import '../../../helpers/product_telemetry_config.dart';

/// The smallest window the desktop integration suite runs in.
const _window = Size(800, 600);

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

/// An 8-bit bus that goes to x at T=200, like `data_out` in the
/// integration suite's xtrace.vcd: with the cursor at 200 the row offers
/// Trace X Origin, and at 8 bits it is an FSM candidate too, so the menu
/// carries every optional section a single row can show.
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

/// Pumps the viewer in an 800x600 window, adds `data_out` as the selected
/// row with the cursor on its x, and right-clicks it. Returns the tab and
/// pane containers.
Future<(ProviderContainer, ProviderContainer)> _openRowMenu(
  WidgetTester tester, {
  required TargetPlatform platform,
  Locale locale = const Locale('en'),
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
          platform: platform,
          isWeb: false,
        ),
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const ViewerScreen(),
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

  final pane = ProviderScope.containerOf(
    tester.element(find.byType(WaveformCanvas)),
  );
  pane.read(cursorStateProvider.notifier).placePrimary(200);
  await tester.pumpAndSettle();

  final entry = tab.read(signalGroupsProvider).entries.single;
  final row = find.byKey(ValueKey(SignalListPanel.signalRowKeyValue(entry)));
  expect(row, findsOneWidget);
  // Select the row first: a selected row adds "Remove Selected".
  tab.read(selectedVariablesProvider.notifier).selectOnly('top.data_out');
  await tester.pumpAndSettle();
  await tester.tap(row, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
  return (tab, pane);
}

/// The labels of every actionable entry the row's menu shows for
/// `data_out` here, top to bottom.
List<String> _menuLabels(L10N l10n) => [
  l10n.signalListChangeColor,
  l10n.valueColumnRenderAsAnalog,
  l10n.valueColumnProperties,
  l10n.signalListCopyValue,
  l10n.signalListCopyPath,
  l10n.translateFilterAssign,
  l10n.processFilterAssign,
  l10n.xTraceMenuLabel,
  l10n.fsmMenuVisualize,
  l10n.fsmMenuAnnotateStates,
  l10n.signalListRemoveSelected,
];

Finder _inMenu(String label) => find.descendant(
  of: find.byType(SingleChildScrollView).last,
  matching: find.text(label),
);

/// Whether a pointer at [finder]'s centre reaches [finder]'s render object.
bool _hittable(WidgetTester tester, Finder finder) {
  final target = tester.renderObject(finder);
  final result = tester.hitTestOnBinding(tester.getCenter(finder));
  return result.path.any((e) => e.target == target);
}

void main() {
  // English first, then the CJK sweep locales: a translated label must not
  // push the menu past the window either.
  for (final locale in const [
    Locale('en'),
    Locale('zh', 'CN'),
    Locale('ja'),
    Locale('ko'),
  ]) {
    testWidgets(
      '[$locale] on a pointer layout the whole row menu shows in an 800x600 '
      'window and Trace X Origin is tapped without scrolling the menu',
      (tester) => _pointerMenuFits(tester, locale),
    );
  }

  testWidgets(
    'on a touch layout the row menu stays inside an 800x600 window and every '
    'item can be scrolled to and tapped',
    (tester) async {
      final (_, pane) = await _openRowMenu(
        tester,
        platform: TargetPlatform.android,
      );
      final l10n = await L10N.delegate.load(const Locale('en'));
      final window = Offset.zero & _window;

      final menu = tester.getRect(find.byType(SingleChildScrollView).last);
      expect(
        window.contains(menu.topLeft) && window.contains(menu.bottomRight),
        isTrue,
        reason: 'menu $menu must lie inside the window $window',
      );
      expect(
        Scrollable.of(
          tester.element(_inMenu(l10n.xTraceMenuLabel)),
        ).position.maxScrollExtent,
        greaterThan(0),
        reason:
            'at 48 dp a row this menu is taller than the window, which is '
            'the case this test is for',
      );
      for (final label in _menuLabels(l10n)) {
        final item = _inMenu(label);
        expect(item, findsOneWidget, reason: label);
        await tester.ensureVisible(item);
        await tester.pumpAndSettle();
        expect(
          _hittable(tester, item),
          isTrue,
          reason: '"$label" must be reachable by scrolling the menu',
        );
      }

      final traceX = _inMenu(l10n.xTraceMenuLabel);
      await tester.ensureVisible(traceX);
      await tester.pumpAndSettle();
      await tester.tap(traceX);
      await tester.pumpAndSettle();
      expect(pane.read(xTraceProvider).isActive, isTrue);
    },
  );
}

Future<void> _pointerMenuFits(WidgetTester tester, Locale locale) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    final (_, pane) = await _openRowMenu(
      tester,
      platform: TargetPlatform.macOS,
      locale: locale,
    );
    final l10n = await L10N.delegate.load(locale);
    final window = Offset.zero & _window;
    expect(tester.takeException(), isNull);

    final traceX = _inMenu(l10n.xTraceMenuLabel);
    expect(traceX, findsOneWidget);
    final menuScroll = Scrollable.of(tester.element(traceX)).position;
    expect(
      menuScroll.maxScrollExtent,
      0,
      reason: 'the menu must fit the window whole, not scroll',
    );

    final menu = tester.getRect(find.byType(SingleChildScrollView).last);
    expect(
      window.contains(menu.topLeft) && window.contains(menu.bottomRight),
      isTrue,
      reason: 'menu $menu must lie inside the window $window',
    );
    for (final label in _menuLabels(l10n)) {
      final item = _inMenu(label);
      expect(item, findsOneWidget, reason: label);
      expect(
        _hittable(tester, item),
        isTrue,
        reason: '"$label" must take a click where it is drawn',
      );
    }

    await tester.tap(traceX);
    await tester.pumpAndSettle();
    expect(pane.read(xTraceProvider).isActive, isTrue);
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
