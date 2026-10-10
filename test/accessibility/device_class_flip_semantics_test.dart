// A device-class flip (phone <-> desktop layout) with semantics on and a
// waveform open.
//
// `_FocusableWaveformPane` puts a `Semantics(container: true)` directly above
// the canvas's GlobalKey'd subtree. If a layout flip rebuilt the pane host, the
// canvas would migrate across that boundary in one frame, which is the pair
// Flutter asserts on in `flushSemantics` (see the dock-reveal test beside this
// one). This pins that the flip keeps the canvas in place: no framework
// exception, and the canvas's pane scope is the same container before and
// after.

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
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_panel.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

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
  DeviceClass build() => DeviceClass.desktop;

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
  testWidgets('flipping phone <-> desktop layout with a waveform open keeps '
      'the canvas in place and the semantics tree intact', (tester) async {
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

    ProviderContainer paneScope() => ProviderScope.containerOf(
      tester.element(find.byType(WaveformCanvas)),
    );
    final root = ProviderScope.containerOf(
      tester.element(find.byType(ViewerScreen)),
    );
    final initialScope = paneScope();
    expect(find.byType(SignalTreePanel), findsOneWidget);

    for (final flip in [
      (DeviceClass.phone, const Size(540, 900)),
      (DeviceClass.desktop, const Size(1600, 1000)),
      (DeviceClass.phone, const Size(540, 900)),
      (DeviceClass.desktop, const Size(1600, 1000)),
    ]) {
      tester.view.physicalSize = flip.$2;
      root.read(_classProvider.notifier).set(flip.$1);
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'flipping to ${flip.$1.name} with semantics enabled',
      );
      expect(find.byType(WaveformCanvas), findsOneWidget);
      expect(
        // Phone class collapses the side docks (still mounted, but clipped
        // away and unreachable); desktop restores them.
        find.byType(SignalTreePanel).hitTestable(),
        flip.$1 == DeviceClass.phone ? findsNothing : findsOneWidget,
        reason: 'the flip must actually change the layout',
      );
      expect(
        paneScope(),
        same(initialScope),
        reason:
            'a device-class flip must not rebuild the pane host; a rebuilt '
            'host migrates the canvas by GlobalKey across the semantics '
            'container above it',
      );
    }
    handle.dispose();
  });
}
