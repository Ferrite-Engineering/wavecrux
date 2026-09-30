// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A signal row's context menu opens a dock while a screen reader is attached.
//
// Both desktop integration suites that right-click a signal row (X-Trace and
// Visualize as FSM) went red on every OS with Flutter's own
// `identical(childRenderObject, parentRenderObject)` assertion out of
// `flushSemantics`. The menu was innocent: the action behind it reveals a
// bottom-dock tab, and `WaveCruxDockRestoreBars` used to change its widget
// TYPE when the bottom bar went away, so the whole IDE layout was torn down
// and rebuilt. The canvas came back through its GlobalKey'd RepaintBoundary —
// one element migrating between two trees in a frame — under the waveform
// pane's semantics container, and that is the pair the framework asserts on.
// Headless, this needs `ensureSemantics()`; on CI the platform enables
// semantics for the whole integration run, which is why it only showed there.

import 'dart:async';

import 'package:crux_workspace/crux_workspace.dart' show CruxGlowingAppIcon;
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_panel.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';
import 'package:wavecrux/features/viewer/widgets/fsm_panel.dart';
import 'package:wavecrux/features/viewer/widgets/signal_list_panel.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../helpers/fake_waveform_data_source.dart';
import '../helpers/product_telemetry_config.dart';

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

/// A 3-bit register: an FSM candidate, so the row's menu offers Visualize
/// as FSM, and activating it reveals the bottom dock's FSM tab.
const _fsmState = Variable(
  name: 'fsm_state',
  varType: VarType.reg,
  direction: VarDirection.unknown,
  signalRef: '0',
  scopePath: 'tb',
  bitWidth: 3,
);

class _LoadedSource extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() {
    currentFilePath = '/kit/sample.vcd';
    return AsyncData(
      FakeWaveformDataSource(
        signals: {
          _fsmState.signalRef: const [
            SignalChange(time: 0, value: '000'),
            SignalChange(time: 100, value: '001'),
            SignalChange(time: 200, value: '010'),
            SignalChange(time: 300, value: '000'),
          ],
        },
        scopes: const [
          Scope(
            name: 'tb',
            type: ScopeType.module,
            path: 'tb',
            variables: [_fsmState],
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
        productTelemetryConfig,
        tabContainerManagerProvider.overrideWithValue(_tcm),
        paneContainerManagerProvider.overrideWithValue(_pcm),
        workspaceServiceProvider.overrideWithValue(_InMemoryWorkspaceService()),
        waveformIsLoadedProvider.overrideWithValue(true),
      ],
    );
    _tcm.init(_container);
    _pcm.init(_container);
    unawaited(_container.wavecruxWorkspace.newTab(displayName: 'sample.vcd'));
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

Future<void> _pumpViewer(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1600, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  CruxGlowingAppIcon.debugDisableAnimations = true;
  addTearDown(() => CruxGlowingAppIcon.debugDisableAnimations = false);
  await tester.pumpWidget(
    _Scope(
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const ViewerScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Visualize as FSM from a signal row reveals the dock without remounting '
    'the pane or breaking the semantics tree',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpViewer(tester);

      final tab = ProviderScope.containerOf(
        tester.element(find.byType(SignalTreePanel)),
      );
      await tab
          .read(waveformSourceProvider)
          .value!
          .loadSignal(_fsmState.signalRef);
      tab.read(signalGroupsProvider.notifier).addSignal(_fsmState);
      await tester.pumpAndSettle();

      final entry = tab.read(signalGroupsProvider).entries.single;
      final row = find.byKey(
        ValueKey(SignalListPanel.signalRowKeyValue(entry)),
      );
      expect(row, findsOneWidget);
      final paneScope = ProviderScope.containerOf(
        tester.element(find.byType(WaveformCanvas)),
      );

      await tester.tap(row, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.fsmMenuVisualize), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'opening the menu');

      await tester.tap(find.text(l10n.fsmMenuVisualize));
      await tester.pumpAndSettle();
      expect(tab.read(fsmProvider).isActive, isTrue);
      expect(find.byType(FsmPanel), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'revealing the FSM dock tab with semantics enabled',
      );
      expect(
        ProviderScope.containerOf(tester.element(find.byType(WaveformCanvas))),
        same(paneScope),
        reason:
            'revealing a dock must not rebuild the IDE layout; a rebuilt '
            'layout migrates the canvas by GlobalKey, which is the corruption',
      );
      handle.dispose();
    },
  );
}
