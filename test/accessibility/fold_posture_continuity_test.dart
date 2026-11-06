// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Folding a foldable into tabletop ("laptop") posture and back, with semantics
// on and a waveform open.
//
// The fold is the demo, so the transition must be invisible to the session:
// the canvas stays in place (same pane scope, no GlobalKey migration across
// the semantics container above it), the loaded source is the same object (no
// re-parse), the cursor stays put, and the user's dock preferences come back
// untouched when the device goes flat. In tabletop posture the side docks step
// aside and the bottom dock starts below the crease.

import 'dart:async';

import 'package:crux_workspace/crux_workspace.dart' show CruxGlowingAppIcon;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/fold_state.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_panel.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';
import 'package:wavecrux/features/viewer/widgets/bottom_dock.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/shared/layouts/fold_state_provider.dart';

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

/// A 3-bit register with a few changes, enough for the canvas to paint a lane.
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

class _ClassNotifier extends Notifier<DeviceClass> {
  @override
  DeviceClass build() => DeviceClass.tablet;

  // ignore: use_setters_to_change_properties, a setter cannot be torn off here
  void set(DeviceClass value) => state = value;
}

final _classProvider = NotifierProvider<_ClassNotifier, DeviceClass>(
  _ClassNotifier.new,
);

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
        deviceClassProvider.overrideWith((ref) => ref.watch(_classProvider)),
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

Future<void> _pumpViewer(WidgetTester tester, {required Size size}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  CruxGlowingAppIcon.debugDisableAnimations = true;
  addTearDown(() => CruxGlowingAppIcon.debugDisableAnimations = false);
  await tester.pumpWidget(
    _Scope(
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
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

// iPhone Duo inner panel upright, with its 40 pt division region across the
// middle, as the simulator reports it.
const _panel = Size(669, 951);
const _crease = Rect.fromLTWH(0, 455.5, 669, 40);

void main() {
  testWidgets('tabletop and back keeps the canvas, the source and the cursor, '
      'and restores the docks', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpViewer(tester, size: _panel);

    final tab = ProviderScope.containerOf(
      tester.element(find.byType(SignalTreePanel)),
    );
    final source = tab.read(waveformSourceProvider).value!;
    await source.loadSignal(_fsmState.signalRef);
    tab.read(signalGroupsProvider.notifier).addSignal(_fsmState);
    tab.read(cursorStateProvider.notifier).placePrimary(200);
    await tester.pumpAndSettle();

    ProviderContainer paneScope() => ProviderScope.containerOf(
      tester.element(find.byType(WaveformCanvas)),
    );
    final root = ProviderScope.containerOf(
      tester.element(find.byType(ViewerScreen)),
    );
    final initialScope = paneScope();
    final panelBefore = tab.read(panelLayoutProvider);
    expect(find.byType(SignalTreePanel).hitTestable(), findsOneWidget);

    for (final tabletop in [true, false, true, false]) {
      root
          .read(foldStateProvider.notifier)
          .set(
            tabletop
                ? const FoldState(
                    status: HingeStatus.partiallyOpen,
                    hingeAngle: 100,
                    crease: _crease,
                  )
                : const FoldState(
                    status: HingeStatus.fullyOpen,
                    hingeAngle: 180,
                  ),
          );
      await tester.pumpAndSettle();

      final label = tabletop ? 'tabletop' : 'flat';
      expect(tester.takeException(), isNull, reason: label);
      expect(find.byType(WaveformCanvas), findsOneWidget, reason: label);
      expect(paneScope(), same(initialScope), reason: '$label: no remount');
      expect(
        tab.read(waveformSourceProvider).value,
        same(source),
        reason: '$label: the trace must not be parsed again',
      );
      expect(
        tab.read(cursorStateProvider).primaryCursorTime,
        200,
        reason: '$label: cursor kept',
      );
      expect(
        find.byType(SignalTreePanel).hitTestable(),
        tabletop ? findsNothing : findsOneWidget,
        reason: '$label: side docks step aside only while half-folded',
      );
      if (tabletop) {
        final dockTop = tester.getTopLeft(find.byType(WaveCruxBottomDock)).dy;
        expect(
          dockTop,
          closeTo(_crease.bottom, 4),
          reason: 'the bottom dock starts just below the crease band',
        );
        final canvasBottom = tester
            .getBottomLeft(find.byType(WaveformCanvas))
            .dy;
        expect(
          canvasBottom,
          lessThanOrEqualTo(_crease.top + 4),
          reason: 'the waveform stays above the crease band',
        );
      } else {
        expect(
          tab.read(panelLayoutProvider),
          panelBefore,
          reason: "the user's dock preferences are untouched by the fold",
        );
      }
    }
    handle.dispose();
  });

  testWidgets('without a hinge the layout is the one it always was', (
    tester,
  ) async {
    await _pumpViewer(tester, size: _panel);
    final root = ProviderScope.containerOf(
      tester.element(find.byType(ViewerScreen)),
    );
    expect(root.read(foldStateProvider), FoldState.none);
    expect(find.byType(SignalTreePanel).hitTestable(), findsOneWidget);
  });
}
