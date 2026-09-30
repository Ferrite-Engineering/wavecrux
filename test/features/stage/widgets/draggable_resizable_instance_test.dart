// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/stage/providers/stage_selection_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/draggable_resizable_instance.dart';
import 'package:wavecrux/features/stage/widgets/signal_binding_picker_dialog.dart';
import 'package:wavecrux/features/stage/widgets/stage_instance_tile.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/stage_registry.dart';

class _LedStub extends StageWidget {
  const _LedStub();
  @override
  String get id => 'led';
  @override
  String get displayName => 'LED';
  @override
  String get description => '1-bit indicator';
  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;
  @override
  List<SignalBinding> get requiredSignals => const [];
  @override
  (double, double) get defaultSize => (160, 100);
}

/// Stub that declares exactly one input pin so a tap on its tile opens
/// the single-pin binding picker.
class _SinglePinStub extends StageWidget {
  const _SinglePinStub();
  @override
  String get id => 'single_pin';
  @override
  String get displayName => 'Single Pin';
  @override
  String get description => '';
  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;
  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(name: 'in', description: 'the one input'),
  ];
  @override
  (double, double) get defaultSize => (160, 100);
}

/// Stub that declares a custom minSize so we can verify the resize
/// handles honor [StageWidget.minSize] instead of the global fallback.
class _LargeMinStub extends StageWidget {
  const _LargeMinStub();
  @override
  String get id => 'large_min';
  @override
  String get displayName => 'Large Min';
  @override
  String get description => '';
  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;
  @override
  List<SignalBinding> get requiredSignals => const [];
  @override
  (double, double) get defaultSize => (300, 200);
  @override
  (double, double) get minSize => (200, 150);
}

/// Pumps a [DraggableResizableInstance] inside a [Stack] / [Positioned]
/// that mirrors the production canvas layout, and returns the active
/// [ProviderContainer] so tests can read state directly.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required StageInstance instance,
  Locale locale = const Locale('en'),
  Size canvasSize = const Size(800, 600),
}) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: canvasSize.width,
              height: canvasSize.height,
              child: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  // Seed the workspace with a panel containing the
                  // instance under test so the notifier mutations have a
                  // target.
                  return _WorkspaceSeed(
                    instance: instance,
                    builder: (current) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: current.x,
                          top: current.y,
                          width: current.width,
                          height: current.height,
                          child: DraggableResizableInstance(
                            instance: current,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Helper that seeds the workspace with one panel + one instance and
/// rebuilds when the instance's position/size changes in state.
class _WorkspaceSeed extends ConsumerStatefulWidget {
  const _WorkspaceSeed({required this.instance, required this.builder});

  final StageInstance instance;
  final Widget Function(StageInstance current) builder;

  @override
  ConsumerState<_WorkspaceSeed> createState() => _WorkspaceSeedState();
}

class _WorkspaceSeedState extends ConsumerState<_WorkspaceSeed> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Seed via restoreFromSession so the instance keeps its
      // caller-supplied id (the auto-generator would assign
      // 'stageInstance_0' instead, breaking key-based widget finders).
      ref
          .read(stageWorkspaceProvider.notifier)
          .restoreFromSession(
            StageWorkspaceState(
              panels: [
                StagePanelConfig(
                  id: 'p0',
                  name: 'Test',
                  instances: [widget.instance],
                ),
              ],
              activePanelId: 'p0',
            ),
          );
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(stageWorkspaceProvider);
    final panel = workspace.activePanel;
    final current = panel?.instances.isNotEmpty ?? false
        ? panel!.instances.first
        : widget.instance;
    return widget.builder(current);
  }
}

void main() {
  setUp(() {
    StageRegistry.instance
      ..clear()
      ..register(const _LedStub())
      ..register(const _SinglePinStub())
      ..register(const _LargeMinStub());
  });

  tearDown(StageRegistry.instance.clear);

  group('DraggableResizableInstance — locale sweep', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await _pump(
          tester,
          instance: const StageInstance(
            id: 'i0',
            widgetId: 'led',
            x: 20,
            y: 20,
          ),
          locale: Locale(locale),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('DraggableResizableInstance — move', () {
    testWidgets('drag on tile body updates x/y', (tester) async {
      const start = StageInstance(
        id: 'i0',
        widgetId: 'led',
        x: 20,
        y: 20,
      );
      final container = await _pump(tester, instance: start);

      // Drag from the center of the tile (tile body) by (40, 30).
      final center = tester.getCenter(
        find.byType(DraggableResizableInstance),
      );
      await tester.dragFrom(center, const Offset(40, 30));
      await tester.pumpAndSettle();

      final updated = container
          .read(stageWorkspaceProvider)
          .activePanel!
          .instances
          .first;
      expect(updated.x, closeTo(60, 0.1));
      expect(updated.y, closeTo(50, 0.1));
      expect(updated.width, 160);
      expect(updated.height, 100);
    });

    testWidgets('drag clamps x and y to canvas origin', (tester) async {
      const start = StageInstance(
        id: 'i0',
        widgetId: 'led',
        x: 10,
        y: 10,
      );
      final container = await _pump(tester, instance: start);

      // Drag well past origin.
      final center = tester.getCenter(
        find.byType(DraggableResizableInstance),
      );
      await tester.dragFrom(center, const Offset(-200, -200));
      await tester.pumpAndSettle();

      final updated = container
          .read(stageWorkspaceProvider)
          .activePanel!
          .instances
          .first;
      expect(updated.x, 0);
      expect(updated.y, 0);
    });
  });

  group('DraggableResizableInstance — resize', () {
    testWidgets('bottom-right corner grows the tile', (tester) async {
      const start = StageInstance(
        id: 'i0',
        widgetId: 'led',
        x: 50,
        y: 50,
      );
      final container = await _pump(tester, instance: start);

      final bottomRight = find.byKey(
        const ValueKey('stageResizeBottomRight:i0'),
      );
      expect(bottomRight, findsOneWidget);
      await tester.drag(bottomRight, const Offset(40, 20));
      await tester.pumpAndSettle();

      final updated = container
          .read(stageWorkspaceProvider)
          .activePanel!
          .instances
          .first;
      expect(updated.width, closeTo(200, 0.1));
      expect(updated.height, closeTo(120, 0.1));
      expect(updated.x, 50);
      expect(updated.y, 50);
    });

    testWidgets('top-left corner moves position and resizes', (tester) async {
      const start = StageInstance(
        id: 'i0',
        widgetId: 'led',
        x: 100,
        y: 100,
      );
      final container = await _pump(tester, instance: start);

      final topLeft = find.byKey(
        const ValueKey('stageResizeTopLeft:i0'),
      );
      await tester.drag(topLeft, const Offset(-20, -10));
      await tester.pumpAndSettle();

      final updated = container
          .read(stageWorkspaceProvider)
          .activePanel!
          .instances
          .first;
      expect(updated.x, closeTo(80, 0.1));
      expect(updated.y, closeTo(90, 0.1));
      expect(updated.width, closeTo(180, 0.1));
      expect(updated.height, closeTo(110, 0.1));
    });

    testWidgets('clamps to minimum width and height', (tester) async {
      const start = StageInstance(
        id: 'i0',
        widgetId: 'led',
        x: 50,
        y: 50,
      );
      final container = await _pump(tester, instance: start);

      final bottomRight = find.byKey(
        const ValueKey('stageResizeBottomRight:i0'),
      );
      // Drag inward far enough to push below the minimum.
      await tester.drag(bottomRight, const Offset(-500, -500));
      await tester.pumpAndSettle();

      final updated = container
          .read(stageWorkspaceProvider)
          .activePanel!
          .instances
          .first;
      expect(updated.width, kStageInstanceMinWidth);
      expect(updated.height, kStageInstanceMinHeight);
    });

    testWidgets('top-left corner clamped at minimum anchors bottom-right', (
      tester,
    ) async {
      const start = StageInstance(
        id: 'i0',
        widgetId: 'led',
        x: 50,
        y: 50,
      );
      final container = await _pump(tester, instance: start);

      // The original right edge sits at x = 50 + 160 = 210; bottom at y = 150.
      final topLeft = find.byKey(
        const ValueKey('stageResizeTopLeft:i0'),
      );
      // Pull top-left inward far past the minimum.
      await tester.drag(topLeft, const Offset(500, 500));
      await tester.pumpAndSettle();

      final updated = container
          .read(stageWorkspaceProvider)
          .activePanel!
          .instances
          .first;
      expect(updated.width, kStageInstanceMinWidth);
      expect(updated.height, kStageInstanceMinHeight);
      // Right and bottom edges should still match the original tile.
      expect(updated.x + updated.width, closeTo(210, 0.1));
      expect(updated.y + updated.height, closeTo(150, 0.1));
    });

    testWidgets('honors per-widget minSize from registry', (tester) async {
      const start = StageInstance(
        id: 'i0',
        widgetId: 'large_min',
        x: 50,
        y: 50,
        width: 400,
        height: 300,
      );
      final container = await _pump(tester, instance: start);

      // Drag the bottom-right corner well inside the per-widget min so
      // the clamp logic engages.
      final bottomRight = find.byKey(
        const ValueKey('stageResizeBottomRight:i0'),
      );
      await tester.drag(bottomRight, const Offset(-1000, -1000));
      await tester.pumpAndSettle();

      final updated = container
          .read(stageWorkspaceProvider)
          .activePanel!
          .instances
          .first;
      // Should clamp to the widget-declared min (200, 150), NOT the
      // global fallback (80, 60).
      expect(updated.width, 200);
      expect(updated.height, 150);
    });
  });

  group('DraggableResizableInstance — drag-and-drop wiring', () {
    testWidgets('wraps the tile in a DragTarget<String>', (tester) async {
      await _pump(
        tester,
        instance: const StageInstance(id: 'i0', widgetId: 'led'),
      );
      // The wrapper exposes a DragTarget<String> that accepts dropped
      // signal refs from VariableTreeLeaf draggables.
      expect(find.byType(DragTarget<String>), findsWidgets);
      expect(find.byType(StageInstanceTile), findsOneWidget);
    });
  });

  group('DraggableResizableInstance — resize handles present', () {
    testWidgets('all 8 resize handles render', (tester) async {
      await _pump(
        tester,
        instance: const StageInstance(
          id: 'i0',
          widgetId: 'led',
          x: 10,
          y: 10,
          width: 200,
          height: 120,
        ),
      );

      const ids = [
        'stageResizeTop:i0',
        'stageResizeBottom:i0',
        'stageResizeLeft:i0',
        'stageResizeRight:i0',
        'stageResizeTopLeft:i0',
        'stageResizeTopRight:i0',
        'stageResizeBottomLeft:i0',
        'stageResizeBottomRight:i0',
      ];
      for (final id in ids) {
        expect(find.byKey(ValueKey(id)), findsOneWidget, reason: id);
      }
    });
  });

  group('DraggableResizableInstance — selection + context menu', () {
    testWidgets('tap selects the instance', (tester) async {
      final container = await _pump(
        tester,
        instance: const StageInstance(id: 'i0', widgetId: 'led', x: 20, y: 20),
      );
      await tester.tap(find.byType(DraggableResizableInstance));
      await tester.pumpAndSettle();
      expect(container.read(stageSelectedInstanceProvider), 'i0');
    });

    testWidgets('tapping a single-pin widget selects it and opens the '
        'binding picker', (tester) async {
      final container = await _pump(
        tester,
        instance: const StageInstance(
          id: 'i0',
          widgetId: 'single_pin',
          x: 20,
          y: 20,
        ),
      );
      await tester.tap(find.byType(DraggableResizableInstance));
      await tester.pumpAndSettle();
      expect(container.read(stageSelectedInstanceProvider), 'i0');
      // The single-pin binding picker dialog opened.
      expect(find.byType(SignalBindingPickerDialog), findsOneWidget);
    });

    testWidgets('right-click opens the stack-order context menu', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        instance: const StageInstance(id: 'i0', widgetId: 'led', x: 40, y: 40),
      );
      final center = tester.getCenter(find.byType(DraggableResizableInstance));
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      // The menu offers the four stack-order operations + remove. Opening
      // it also selects the instance (mirrors tap-to-select).
      expect(container.read(stageSelectedInstanceProvider), 'i0');
      expect(find.text('Bring to Front'), findsOneWidget);
      expect(find.text('Send to Back'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('context-menu Remove deletes the instance', (tester) async {
      final container = await _pump(
        tester,
        instance: const StageInstance(id: 'i0', widgetId: 'led', x: 40, y: 40),
      );
      expect(
        container.read(stageWorkspaceProvider).activePanel!.instances,
        hasLength(1),
      );
      final center = tester.getCenter(find.byType(DraggableResizableInstance));
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(
        container.read(stageWorkspaceProvider).activePanel!.instances,
        isEmpty,
      );
    });

    testWidgets('context-menu Bring to Front reorders the instance forward', (
      tester,
    ) async {
      // Two instances; selecting the lower one and bringing it to front
      // moves it to the end of the panel's instance list (top of z-order).
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const SizedBox(
                    width: 800,
                    height: 600,
                    child: _TwoInstanceCanvas(),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      container
          .read(stageWorkspaceProvider.notifier)
          .restoreFromSession(
            const StageWorkspaceState(
              panels: [
                StagePanelConfig(
                  id: 'p0',
                  name: 'T',
                  instances: [
                    StageInstance(id: 'a', widgetId: 'led', x: 10, y: 10),
                    StageInstance(id: 'b', widgetId: 'led', x: 300, y: 10),
                  ],
                ),
              ],
              activePanelId: 'p0',
            ),
          );
      await tester.pumpAndSettle();
      expect(
        container
            .read(stageWorkspaceProvider)
            .activePanel!
            .instances
            .map((i) => i.id)
            .toList(),
        ['a', 'b'],
      );

      // Right-click instance 'a' (the lower one) and bring it to front.
      final aFinder = find.byKey(const ValueKey('drag_a'));
      final gesture = await tester.startGesture(
        tester.getCenter(aFinder),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bring to Front'));
      await tester.pumpAndSettle();
      expect(
        container
            .read(stageWorkspaceProvider)
            .activePanel!
            .instances
            .map((i) => i.id)
            .toList(),
        ['b', 'a'],
      );
    });
  });

  group('DraggableResizableInstance — edge resize + origin clamp', () {
    testWidgets('top edge drag moves y and shrinks height', (tester) async {
      const start = StageInstance(
        id: 'i0',
        widgetId: 'led',
        x: 100,
        y: 100,
        width: 200,
        height: 150,
      );
      final container = await _pump(tester, instance: start);

      await tester.drag(
        find.byKey(const ValueKey('stageResizeTop:i0')),
        const Offset(0, 30),
      );
      await tester.pumpAndSettle();
      final updated = container
          .read(stageWorkspaceProvider)
          .activePanel!
          .instances
          .first;
      expect(updated.y, closeTo(130, 0.1));
      expect(updated.height, closeTo(120, 0.1));
      // x / width unchanged by a pure-vertical top-edge drag.
      expect(updated.x, 100);
      expect(updated.width, 200);
    });

    testWidgets('right edge drag grows width only', (tester) async {
      const start = StageInstance(
        id: 'i0',
        widgetId: 'led',
        x: 50,
        y: 50,
        width: 200,
        height: 150,
      );
      final container = await _pump(tester, instance: start);
      await tester.drag(
        find.byKey(const ValueKey('stageResizeRight:i0')),
        const Offset(40, 0),
      );
      await tester.pumpAndSettle();
      final updated = container
          .read(stageWorkspaceProvider)
          .activePanel!
          .instances
          .first;
      expect(updated.width, closeTo(240, 0.1));
      expect(updated.height, 150);
      expect(updated.x, 50);
    });

    testWidgets('dragging the top-left corner past the canvas origin clamps '
        'x/y to 0 and absorbs the overshoot into width/height', (tester) async {
      const start = StageInstance(
        id: 'i0',
        widgetId: 'led',
        x: 20,
        y: 20,
        width: 200,
        height: 150,
      );
      final container = await _pump(tester, instance: start);
      // The right edge is at x = 220, bottom at y = 170. Pulling the
      // top-left corner up-left by more than (20, 20) drives newX/newY
      // negative; the clamp pins them to 0 and folds the overshoot into
      // width/height so the right/bottom edges stay put.
      await tester.drag(
        find.byKey(const ValueKey('stageResizeTopLeft:i0')),
        const Offset(-60, -50),
      );
      await tester.pumpAndSettle();
      final updated = container
          .read(stageWorkspaceProvider)
          .activePanel!
          .instances
          .first;
      expect(updated.x, 0);
      expect(updated.y, 0);
      // Right and bottom edges unchanged.
      expect(updated.x + updated.width, closeTo(220, 0.1));
      expect(updated.y + updated.height, closeTo(170, 0.1));
    });
  });

  group('DraggableResizableInstance — applyDropBinding helper', () {
    /// Pumps a Consumer that captures a live [WidgetRef] and seeds one
    /// instance, then runs [body] with that ref + container. Used to drive
    /// the top-level [applyDropBinding] helper through its no-dialog
    /// branches (a real ref is required; the helper reads providers off it).
    Future<void> withRef(
      WidgetTester tester, {
      required Future<void> Function(WidgetRef ref, ProviderContainer c) body,
    }) async {
      late WidgetRef capturedRef;
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          // An empty variables map → applyDropBinding treats every dropped
          // signal as 1-bit, which keeps both assertions on the no-dialog
          // path.
          overrides: [
            signalVariablesMapProvider.overrideWithValue(const {}),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  capturedRef = ref;
                  container = ProviderScope.containerOf(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      container
          .read(stageWorkspaceProvider.notifier)
          .restoreFromSession(
            const StageWorkspaceState(
              panels: [
                StagePanelConfig(
                  id: 'p0',
                  name: 'T',
                  instances: [StageInstance(id: 'i0', widgetId: 'led')],
                ),
              ],
              activePanelId: 'p0',
            ),
          );
      await tester.pump();
      await body(capturedRef, container);
    }

    testWidgets(
      'binds the whole signal when the slot accepts any width (bitWidth '
      'null) — no bit-picker prompt',
      (tester) async {
        await withRef(
          tester,
          body: (ref, container) async {
            final ctx = tester.element(find.byType(SizedBox));
            // bitWidth null ("accepts any width") never prompts, even for a
            // wide signal, so this stays on the synchronous no-dialog path.
            await applyDropBinding(
              ctx,
              ref,
              instanceId: 'i0',
              pinName: 'data',
              pinBitWidth: null,
              signalRef: 'top.bus',
            );
            final binding = container
                .read(stageWorkspaceProvider)
                .activePanel!
                .instances
                .first
                .signalBindings['data'];
            expect(binding, isNotNull);
            expect(binding!.signalRef, 'top.bus');
            expect(binding.bitIndex, isNull);
          },
        );
      },
    );

    testWidgets(
      'binds directly when a 1-bit slot receives a 1-bit signal (no prompt)',
      (tester) async {
        await withRef(
          tester,
          body: (ref, container) async {
            final ctx = tester.element(find.byType(SizedBox));
            // Unknown signal → width defaults to 1; a 1-bit slot + 1-bit
            // signal does not trigger the bit picker.
            await applyDropBinding(
              ctx,
              ref,
              instanceId: 'i0',
              pinName: 'd',
              pinBitWidth: 1,
              signalRef: 'top.clk',
            );
            final binding = container
                .read(stageWorkspaceProvider)
                .activePanel!
                .instances
                .first
                .signalBindings['d'];
            expect(binding, isNotNull);
            expect(binding!.signalRef, 'top.clk');
          },
        );
      },
    );
  });
}

/// Canvas that renders two LED instances with stable drag keys so the
/// reorder test can right-click a specific one.
class _TwoInstanceCanvas extends ConsumerWidget {
  const _TwoInstanceCanvas();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(stageWorkspaceProvider);
    final panel = ws.activePanel;
    final instances = panel?.instances ?? const [];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final i in instances)
          Positioned(
            key: ValueKey('drag_${i.id}'),
            left: i.x,
            top: i.y,
            width: i.width,
            height: i.height,
            child: DraggableResizableInstance(instance: i),
          ),
      ],
    );
  }
}
