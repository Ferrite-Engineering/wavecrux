// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/plugins/stage_registry.dart';

import '../../../helpers/product_telemetry_config.dart';

// ── stub StageWidget for tests that touch the registry ──────────────────────

class _LedStub extends StageWidget {
  const _LedStub();

  @override
  String get id => 'led';

  @override
  String get displayName => 'LED';

  @override
  String get description => 'A 1-bit indicator';

  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;

  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(name: 'in', description: '1-bit input', bitWidth: 1),
  ];

  @override
  (double, double) get defaultSize => (80, 60);
}

void main() {
  late ProviderContainer container;
  StageWorkspaceNotifier notifier() =>
      container.read(stageWorkspaceProvider.notifier);
  StageWorkspaceState read() => container.read(stageWorkspaceProvider);

  setUp(() {
    StageRegistry.instance
      ..clear()
      ..register(const _LedStub());
    container = ProviderContainer(overrides: [productTelemetryConfig]);
  });

  tearDown(() {
    container.dispose();
    StageRegistry.instance.clear();
  });

  group('StageWorkspaceNotifier', () {
    // ── initial state ─────────────────────────────────────────────────────

    test('initial state is empty', () {
      expect(read().panels, isEmpty);
      expect(read().activePanelId, isNull);
    });

    // ── panel management ──────────────────────────────────────────────────

    test('addPanel inserts a panel and selects it', () {
      final id = notifier().addPanel('Bus Monitor');
      expect(id, isNotEmpty);
      expect(read().panels, hasLength(1));
      expect(read().panels.first.name, 'Bus Monitor');
      expect(read().activePanelId, id);
    });

    test('addPanel generates unique ids', () {
      final a = notifier().addPanel('A');
      final b = notifier().addPanel('B');
      expect(a, isNot(equals(b)));
    });

    test('removePanel removes a panel and reselects the next one', () {
      final n = notifier();
      final p0 = n.addPanel('A');
      final p1 = n.addPanel('B');
      n
        ..selectPanel(p0)
        ..removePanel(p0);
      expect(read().panels.map((p) => p.id), [p1]);
      expect(read().activePanelId, p1);
    });

    test('removePanel removing inactive panel keeps active id', () {
      final n = notifier();
      final p0 = n.addPanel('A');
      final p1 = n.addPanel('B');
      // Active is p1 (last added). Remove p0 while p1 is active.
      n.removePanel(p0);
      expect(read().activePanelId, p1);
    });

    test('removePanel clears active id when removing last panel', () {
      final n = notifier();
      final p = n.addPanel('A');
      n.removePanel(p);
      expect(read().panels, isEmpty);
      expect(read().activePanelId, isNull);
    });

    test('renamePanel updates the panel name', () {
      final n = notifier();
      final id = n.addPanel('Old');
      n.renamePanel(id, 'New');
      expect(read().panels.first.name, 'New');
    });

    test('renamePanel is a no-op for unknown ids', () {
      notifier()
        ..addPanel('A')
        ..renamePanel('missing', 'X');
      expect(read().panels.first.name, 'A');
    });

    test('selectPanel updates the active id', () {
      final n = notifier();
      final p0 = n.addPanel('A');
      final p1 = n.addPanel('B');
      expect(read().activePanelId, p1);
      n.selectPanel(p0);
      expect(read().activePanelId, p0);
    });

    test('selectPanel ignores unknown id', () {
      final n = notifier();
      final p0 = n.addPanel('A');
      n.selectPanel('missing');
      expect(read().activePanelId, p0);
    });

    // ── instance management ───────────────────────────────────────────────

    test('addInstance returns null when no active panel', () {
      expect(notifier().addInstance('led'), isNull);
    });

    test('addInstance creates an instance with widget defaults', () {
      final n = notifier()..addPanel('A');
      final id = n.addInstance('led');
      expect(id, isNotNull);

      final inst = read().panels.first.instances.single;
      expect(inst.id, id);
      expect(inst.widgetId, 'led');
      // Stub widget reports default size (80, 60)
      expect(inst.width, 80);
      expect(inst.height, 60);
    });

    test('addInstance uses fallback size for unknown widgets', () {
      notifier()
        ..addPanel('A')
        ..addInstance('unknownWidget');
      final inst = read().panels.first.instances.single;
      expect(inst.width, 160);
      expect(inst.height, 100);
    });

    test('addInstance offsets successive widgets so they cascade', () {
      notifier()
        ..addPanel('A')
        ..addInstance('led')
        ..addInstance('led');
      final instances = read().panels.first.instances;
      expect(instances, hasLength(2));
      // Cascade: first at (0,0), second at (24,24)
      expect(instances[0].x, 0);
      expect(instances[0].y, 0);
      expect(instances[1].x, 24);
      expect(instances[1].y, 24);
    });

    test('removeInstance removes by id from any panel', () {
      final n = notifier()..addPanel('A');
      final i0 = n.addInstance('led');
      final i1 = n.addInstance('led');
      n.removeInstance(i0!);
      final ids = read().panels.first.instances.map((i) => i.id).toList();
      expect(ids, [i1]);
    });

    // ── addInstanceAt (drop-position-precise create) ──────────────────────

    test('addInstanceAt returns null when no active panel', () {
      expect(notifier().addInstanceAt('led', x: 10, y: 20), isNull);
    });

    test('addInstanceAt places the instance at the requested origin', () {
      final id = (notifier()..addPanel('A')).addInstanceAt(
        'led',
        x: 120,
        y: 40,
      );
      expect(id, isNotNull);
      final inst = read().panels.first.instances.single;
      expect(inst.x, 120);
      expect(inst.y, 40);
      expect(inst.width, 80);
      expect(inst.height, 60);
    });

    test('addInstanceAt clamps negative origins to (0, 0)', () {
      (notifier()..addPanel('A')).addInstanceAt('led', x: -50, y: -10);
      final inst = read().panels.first.instances.single;
      expect(inst.x, 0);
      expect(inst.y, 0);
    });

    test(
      'addInstanceAt overrides registry size when width/height supplied',
      () {
        (notifier()..addPanel('A')).addInstanceAt(
          'led',
          x: 0,
          y: 0,
          width: 240,
          height: 96,
        );
        final inst = read().panels.first.instances.single;
        expect(inst.width, 240);
        expect(inst.height, 96);
      },
    );

    test('addInstanceAt uses fallback size for unknown widgets', () {
      (notifier()..addPanel('A')).addInstanceAt('unknownWidget', x: 0, y: 0);
      final inst = read().panels.first.instances.single;
      expect(inst.width, 160);
      expect(inst.height, 100);
    });

    test('addInstanceAt does not cascade — drop position is the source of '
        'truth', () {
      notifier()
        ..addPanel('A')
        ..addInstanceAt('led', x: 50, y: 60)
        ..addInstanceAt('led', x: 50, y: 60);
      final instances = read().panels.first.instances;
      expect(instances, hasLength(2));
      expect(instances[0].x, 50);
      expect(instances[0].y, 60);
      expect(instances[1].x, 50);
      expect(instances[1].y, 60);
    });

    // ── bindings ──────────────────────────────────────────────────────────

    test('setBinding stores a signal ref', () {
      final n = notifier()..addPanel('A');
      final id = n.addInstance('led')!;
      n.setBinding(id, 'in', 'top.clk');
      final inst = read().panels.first.instances.single;
      expect(
        inst.signalBindings,
        const {'in': StageSignalBinding(signalRef: 'top.clk')},
      );
    });

    test('setBinding stores a signal ref with a bit index', () {
      final n = notifier()..addPanel('A');
      final id = n.addInstance('led')!;
      n.setBinding(id, 'in', 'top.leds[15:0]', bitIndex: 3);
      final inst = read().panels.first.instances.single;
      expect(
        inst.signalBindings,
        const {
          'in': StageSignalBinding(
            signalRef: 'top.leds[15:0]',
            bitIndex: 3,
          ),
        },
      );
    });

    test('setBinding(null) removes a binding', () {
      final n = notifier()..addPanel('A');
      final id = n.addInstance('led')!;
      n
        ..setBinding(id, 'in', 'top.clk')
        ..setBinding(id, 'in', null);
      final inst = read().panels.first.instances.single;
      expect(inst.signalBindings, isEmpty);
    });

    test('setBinding with empty string clears the binding', () {
      final n = notifier()..addPanel('A');
      final id = n.addInstance('led')!;
      n
        ..setBinding(id, 'in', 'top.clk')
        ..setBinding(id, 'in', '');
      final inst = read().panels.first.instances.single;
      expect(inst.signalBindings, isEmpty);
    });

    test('setBinding leaves other bindings intact', () {
      final n = notifier()..addPanel('A');
      final id = n.addInstance('led')!;
      n
        ..setBinding(id, 'in', 'top.clk')
        ..setBinding(id, 'enable', 'top.en');
      final inst = read().panels.first.instances.single;
      expect(
        inst.signalBindings,
        const {
          'in': StageSignalBinding(signalRef: 'top.clk'),
          'enable': StageSignalBinding(signalRef: 'top.en'),
        },
      );
    });

    test('setBindings replaces the entire bindings map', () {
      final n = notifier()..addPanel('A');
      final id = n.addInstance('led')!;
      n
        ..setBinding(id, 'in', 'top.clk')
        ..setBindings(id, const {
          'in': StageSignalBinding(signalRef: 'top.rst'),
          'enable': StageSignalBinding(signalRef: 'top.en'),
        });
      final inst = read().panels.first.instances.single;
      expect(
        inst.signalBindings,
        const {
          'in': StageSignalBinding(signalRef: 'top.rst'),
          'enable': StageSignalBinding(signalRef: 'top.en'),
        },
      );
    });

    // ── layout ────────────────────────────────────────────────────────────

    test('updateLayout updates only provided fields', () {
      final n = notifier()..addPanel('A');
      final id = n.addInstance('led')!;
      n.updateLayout(id, x: 100, y: 50);
      final inst = read().panels.first.instances.single;
      expect(inst.x, 100);
      expect(inst.y, 50);
      expect(inst.width, 80);
      expect(inst.height, 60);
    });

    test('updateLayout can resize instance', () {
      final n = notifier()..addPanel('A');
      final id = n.addInstance('led')!;
      n.updateLayout(id, width: 240, height: 180);
      final inst = read().panels.first.instances.single;
      expect(inst.width, 240);
      expect(inst.height, 180);
    });

    test('setLabel applies and clears label', () {
      final n = notifier()..addPanel('A');
      final id = n.addInstance('led')!;
      n.setLabel(id, 'Status LED');
      expect(read().panels.first.instances.single.label, 'Status LED');
      n.setLabel(id, null);
      expect(read().panels.first.instances.single.label, isNull);
    });

    // ── persistence ───────────────────────────────────────────────────────

    test('restoreFromSession replaces state', () {
      const restored = StageWorkspaceState(
        panels: [
          StagePanelConfig(id: 'stagePanel_3', name: 'Restored'),
        ],
        activePanelId: 'stagePanel_3',
      );
      notifier().restoreFromSession(restored);
      expect(read(), restored);
    });

    test(
      'restoreFromSession seeds id counters past the highest restored id',
      () {
        const restored = StageWorkspaceState(
          panels: [
            StagePanelConfig(id: 'stagePanel_5', name: 'A'),
            StagePanelConfig(id: 'stagePanel_2', name: 'B'),
          ],
          activePanelId: 'stagePanel_5',
        );
        final n = notifier()..restoreFromSession(restored);
        final newId = n.addPanel('Fresh');
        expect(newId, 'stagePanel_6');
      },
    );

    test('clear resets to empty', () {
      notifier()
        ..addPanel('A')
        ..addInstance('led')
        ..clear();
      expect(read(), const StageWorkspaceState());
    });
  });

  group('z-order', () {
    /// Returns the active panel's instance ids in list order — list
    /// order IS the z-order (later index = paints on top).
    List<String> ids() =>
        read().activePanel!.instances.map((i) => i.id).toList();

    /// Adds three instances; returns their ids in insertion order.
    List<String> seedThree() {
      final n = notifier()..addPanel('Test');
      final a = n.addInstance('led')!;
      final b = n.addInstance('led')!;
      final c = n.addInstance('led')!;
      return [a, b, c];
    }

    test('bringInstanceToFront moves the target to the end', () {
      final triple = seedThree();
      notifier().bringInstanceToFront(triple[0]);
      expect(ids(), [triple[1], triple[2], triple[0]]);
    });

    test('bringInstanceToFront on an already-top instance is a no-op', () {
      final triple = seedThree();
      notifier().bringInstanceToFront(triple[2]);
      expect(ids(), triple);
    });

    test('sendInstanceToBack moves the target to the start', () {
      final triple = seedThree();
      notifier().sendInstanceToBack(triple[2]);
      expect(ids(), [triple[2], triple[0], triple[1]]);
    });

    test('sendInstanceToBack on an already-bottom instance is a no-op', () {
      final triple = seedThree();
      notifier().sendInstanceToBack(triple[0]);
      expect(ids(), triple);
    });

    test('bringInstanceForward shifts the target one slot toward end', () {
      final triple = seedThree();
      notifier().bringInstanceForward(triple[0]);
      expect(ids(), [triple[1], triple[0], triple[2]]);
    });

    test('bringInstanceForward at the top is a no-op', () {
      final triple = seedThree();
      notifier().bringInstanceForward(triple[2]);
      expect(ids(), triple);
    });

    test('sendInstanceBackward shifts the target one slot toward start', () {
      final triple = seedThree();
      notifier().sendInstanceBackward(triple[2]);
      expect(ids(), [triple[0], triple[2], triple[1]]);
    });

    test('sendInstanceBackward at the bottom is a no-op', () {
      final triple = seedThree();
      notifier().sendInstanceBackward(triple[0]);
      expect(ids(), triple);
    });

    test('reordering an unknown instance id is a no-op', () {
      final triple = seedThree();
      notifier()
        ..bringInstanceToFront('does-not-exist')
        ..sendInstanceToBack('does-not-exist')
        ..bringInstanceForward('does-not-exist')
        ..sendInstanceBackward('does-not-exist');
      expect(ids(), triple);
    });
  });

  // ── undo / redo ───────────────────────────────────────────────────────────

  group('StageWorkspaceNotifier — undo/redo', () {
    test('initial canUndo / canRedo are false', () {
      expect(notifier().canUndo, isFalse);
      expect(notifier().canRedo, isFalse);
    });

    test('undo / redo are no-ops when stacks are empty', () {
      notifier()
        ..undo()
        ..redo();
      expect(read().panels, isEmpty);
    });

    test('addPanel pushes the prior empty state onto the undo stack', () {
      notifier().addPanel('A');
      expect(notifier().canUndo, isTrue);
      expect(notifier().canRedo, isFalse);
    });

    test('undo reverts addPanel and re-enables redo', () {
      notifier().addPanel('A');
      expect(read().panels, hasLength(1));
      notifier().undo();
      expect(read().panels, isEmpty);
      expect(notifier().canUndo, isFalse);
      expect(notifier().canRedo, isTrue);
    });

    test('redo restores the undone change', () {
      final id = notifier().addPanel('A');
      notifier()
        ..undo()
        ..redo();
      expect(read().panels, hasLength(1));
      expect(read().panels.first.id, id);
    });

    test('a fresh edit clears the redo stack', () {
      notifier().addPanel('A');
      notifier().undo();
      expect(notifier().canRedo, isTrue);
      notifier().addPanel('B');
      expect(notifier().canRedo, isFalse);
    });

    test('addInstance is undoable', () {
      final panelId = notifier().addPanel('A');
      final instanceId = notifier().addInstance('led');
      expect(instanceId, isNotNull);
      expect(read().panels.first.instances, hasLength(1));
      notifier().undo();
      // Undo the addInstance — panel still exists, no instances.
      expect(read().panels.first.id, panelId);
      expect(read().panels.first.instances, isEmpty);
    });

    test('updateLayout is undoable', () {
      notifier().addPanel('A');
      final id = notifier().addInstance('led')!;
      final originalX = read().panels.first.instances.first.x;
      notifier().updateLayout(id, x: 200, y: 300);
      expect(read().panels.first.instances.first.x, 200);
      notifier().undo();
      expect(read().panels.first.instances.first.x, originalX);
    });

    test('beginTransaction + endTransaction coalesce many updateLayouts '
        'into one undo step', () {
      notifier().addPanel('A');
      final id = notifier().addInstance('led')!;
      // Drag-style: many incremental position updates inside one
      // transaction should be a single undo step.
      notifier().beginTransaction();
      for (var x = 100.0; x <= 300.0; x += 20.0) {
        notifier().updateLayout(id, x: x);
      }
      notifier().endTransaction();
      expect(read().panels.first.instances.first.x, 300);
      // One undo reverts the entire drag.
      notifier().undo();
      expect(
        read().panels.first.instances.first.x,
        lessThan(20),
        reason:
            'undo of a coalesced drag should revert all the way to '
            'the pre-drag position, not just the last micro-step',
      );
    });

    test('endTransaction without changes does not push an undo entry', () {
      notifier().addPanel('A');
      notifier().addInstance('led');
      // Snapshot the current undo depth.
      final priorUndoExists = notifier().canUndo;
      expect(priorUndoExists, isTrue);
      notifier()
        ..beginTransaction()
        ..endTransaction();
      // No new entry was pushed (state didn't change), so canUndo
      // still pops the addInstance step from before.
      notifier().undo();
      expect(read().panels.first.instances, isEmpty);
    });

    test('cancelTransaction discards mid-flight changes from undo history', () {
      notifier().addPanel('A');
      final id = notifier().addInstance('led')!;
      notifier()
        ..beginTransaction()
        ..updateLayout(id, x: 999); // mid-drag position
      // User presses Esc — discard the open transaction. The state
      // change still happened (updateLayout is "live"), but the
      // cancel just prevents pushing an undo entry for the drag
      // group. The drag's individual mutations did not push entries
      // because a transaction was open.
      notifier().cancelTransaction();
      // Undo should now revert the addInstance, not the drag.
      notifier().undo();
      expect(read().panels.first.instances, isEmpty);
    });

    test('selectPanel is NOT undoable', () {
      notifier()
        ..addPanel('A')
        ..addPanel('B');
      // Two adds → two undo entries.
      final activeAfterAdds = read().activePanelId;
      // Select the other panel.
      final firstPanelId = read().panels.first.id;
      notifier().selectPanel(firstPanelId);
      expect(read().activePanelId, firstPanelId);
      // Undo should revert the most recent addPanel, not the
      // selectPanel call.
      notifier().undo();
      expect(read().panels, hasLength(1));
      // Active panel post-undo should be whatever the workspace had
      // *before* the `addPanel('B')` call — i.e. the only remaining
      // panel.
      expect(activeAfterAdds, isNotNull);
    });

    test('restoreFromSession clears undo + redo history', () {
      notifier()
        ..addPanel('A')
        ..addPanel('B')
        ..undo();
      expect(notifier().canUndo, isTrue);
      expect(notifier().canRedo, isTrue);
      notifier().restoreFromSession(const StageWorkspaceState());
      expect(notifier().canUndo, isFalse);
      expect(notifier().canRedo, isFalse);
    });

    test('clear() resets workspace and clears undo + redo history', () {
      notifier()
        ..addPanel('A')
        ..addInstance('led');
      expect(notifier().canUndo, isTrue);
      notifier().clear();
      expect(read().panels, isEmpty);
      expect(notifier().canUndo, isFalse);
      expect(notifier().canRedo, isFalse);
    });

    test('undo history is bounded at kStageWorkspaceUndoHistoryLimit', () {
      for (var i = 0; i < kStageWorkspaceUndoHistoryLimit + 25; i++) {
        notifier().addPanel('panel-$i');
      }
      // History dropped the oldest 25 entries, but still has the
      // most-recent kStageWorkspaceUndoHistoryLimit available. Undoing
      // the cap-many times must not throw.
      for (var i = 0; i < kStageWorkspaceUndoHistoryLimit; i++) {
        notifier().undo();
      }
      // 25 panels remain — they pre-date the undo history.
      expect(read().panels, hasLength(25));
      expect(notifier().canUndo, isFalse);
    });
  });
}
