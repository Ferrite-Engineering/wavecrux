// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';
import 'package:wavecrux/features/stage/providers/stage_selection_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/plugins/stage_registry.dart';

class _LedStub extends StageWidget {
  const _LedStub();
  @override
  String get id => 'led';
  @override
  String get displayName => 'LED';
  @override
  String get description => '';
  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;
  @override
  List<SignalBinding> get requiredSignals => const [];
}

ProviderContainer _container() {
  StageRegistry.instance
    ..clear()
    ..register(const _LedStub());
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUp(StageRegistry.instance.clear);
  tearDown(StageRegistry.instance.clear);

  group('StageSelectedInstance', () {
    test('starts null', () {
      final c = _container();
      expect(c.read(stageSelectedInstanceProvider), isNull);
    });

    test('select(id) sets state', () {
      final c = _container();
      c.read(stageSelectedInstanceProvider.notifier).select('i1');
      expect(c.read(stageSelectedInstanceProvider), 'i1');
    });

    test('clear() sets state to null', () {
      final c = _container();
      c.read(stageSelectedInstanceProvider.notifier)
        ..select('i1')
        ..clear();
      expect(c.read(stageSelectedInstanceProvider), isNull);
    });

    test('select(null) clears state', () {
      final c = _container();
      c.read(stageSelectedInstanceProvider.notifier)
        ..select('i1')
        ..select(null);
      expect(c.read(stageSelectedInstanceProvider), isNull);
    });

    test('clears when active panel changes', () {
      final c = _container();
      // Seed two panels with one instance each.
      c
          .read(stageWorkspaceProvider.notifier)
          .restoreFromSession(
            const StageWorkspaceState(
              panels: [
                StagePanelConfig(
                  id: 'p0',
                  name: 'A',
                  instances: [
                    StageInstance(id: 'i0', widgetId: 'led'),
                  ],
                ),
                StagePanelConfig(
                  id: 'p1',
                  name: 'B',
                  instances: [
                    StageInstance(id: 'i1', widgetId: 'led'),
                  ],
                ),
              ],
              activePanelId: 'p0',
            ),
          );
      // Subscribe so the listener attached in build() runs.
      c.listen(stageSelectedInstanceProvider, (_, _) {});
      c.read(stageSelectedInstanceProvider.notifier).select('i0');
      expect(c.read(stageSelectedInstanceProvider), 'i0');

      c.read(stageWorkspaceProvider.notifier).selectPanel('p1');
      expect(c.read(stageSelectedInstanceProvider), isNull);
    });

    test('clears when selected instance is removed', () {
      final c = _container();
      c
          .read(stageWorkspaceProvider.notifier)
          .restoreFromSession(
            const StageWorkspaceState(
              panels: [
                StagePanelConfig(
                  id: 'p0',
                  name: 'A',
                  instances: [
                    StageInstance(id: 'i0', widgetId: 'led'),
                    StageInstance(id: 'i1', widgetId: 'led'),
                  ],
                ),
              ],
              activePanelId: 'p0',
            ),
          );
      c.listen(stageSelectedInstanceProvider, (_, _) {});
      c.read(stageSelectedInstanceProvider.notifier).select('i0');
      expect(c.read(stageSelectedInstanceProvider), 'i0');

      c.read(stageWorkspaceProvider.notifier).removeInstance('i0');
      expect(c.read(stageSelectedInstanceProvider), isNull);
    });

    test('survives unrelated workspace mutations', () {
      final c = _container();
      c
          .read(stageWorkspaceProvider.notifier)
          .restoreFromSession(
            const StageWorkspaceState(
              panels: [
                StagePanelConfig(
                  id: 'p0',
                  name: 'A',
                  instances: [
                    StageInstance(id: 'i0', widgetId: 'led'),
                    StageInstance(id: 'i1', widgetId: 'led'),
                  ],
                ),
              ],
              activePanelId: 'p0',
            ),
          );
      c.listen(stageSelectedInstanceProvider, (_, _) {});
      c.read(stageSelectedInstanceProvider.notifier).select('i0');

      // Remove a non-selected instance — selection should remain.
      c.read(stageWorkspaceProvider.notifier).removeInstance('i1');
      expect(c.read(stageSelectedInstanceProvider), 'i0');
    });
  });
}
