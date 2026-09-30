// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/plugins/stage_registry.dart';
import 'package:wavecrux/services/collaboration/signal_identity_resolver.dart';

class _LedStub extends StageWidget {
  const _LedStub();
  @override
  String get id => 'led';
  @override
  String get displayName => 'LED';
  @override
  String get description => 'stub';
  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;
  @override
  List<SignalBinding> get requiredSignals => const [];
}

SignalIdentityResolver _presenter() => SignalIdentityResolver(
  pathToRef: const {'top.led': 'P1'},
  refToPath: const {'P1': 'top.led'},
);
SignalIdentityResolver _follower() => SignalIdentityResolver(
  pathToRef: const {'top.led': 'L1'},
  refToPath: const {'L1': 'top.led'},
);

void main() {
  setUp(StageRegistry.instance.clear);
  tearDown(StageRegistry.instance.clear);

  group('StageWorkspaceNotifier view-composition recipe seams', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    StageWorkspaceState workspace({
      String widgetId = 'led',
      String ref = 'P1',
    }) => StageWorkspaceState(
      activePanelId: 'p0',
      panels: [
        StagePanelConfig(
          id: 'p0',
          name: 'Panel',
          instances: [
            StageInstance(
              id: 's0',
              widgetId: widgetId,
              configuration: const {'color': 'red'},
              signalBindings: {
                'in': StageSignalBinding(signalRef: ref, bitIndex: 3),
              },
            ),
          ],
        ),
      ],
    );

    test(
      'toCompositionRecipe rewrites binding refs to paths, keeps config',
      () {
        c.read(stageWorkspaceProvider.notifier).restoreFromSession(workspace());
        final recipe = c
            .read(stageWorkspaceProvider.notifier)
            .toCompositionRecipe(
              _presenter(),
            );
        final binding =
            recipe.panels.first.instances.first.signalBindings['in']!;
        expect(binding.signalRef, 'top.led');
        expect(binding.bitIndex, 3); // bit-slice rides along
        expect(recipe.panels.first.instances.first.configuration, {
          'color': 'red',
        }); // schema config verbatim
      },
    );

    test('round-trip: apply re-binds to follower-local refs', () {
      StageRegistry.instance.register(const _LedStub());
      c.read(stageWorkspaceProvider.notifier).restoreFromSession(workspace());
      final recipe = c
          .read(stageWorkspaceProvider.notifier)
          .toCompositionRecipe(
            _presenter(),
          );

      final follower = ProviderContainer();
      addTearDown(follower.dispose);
      final result = follower
          .read(stageWorkspaceProvider.notifier)
          .applyCompositionRecipe(recipe, _follower());

      expect(result.missingWidgetIds, isEmpty);
      expect(result.missingSignalPaths, isEmpty);
      final applied = follower.read(stageWorkspaceProvider);
      final binding =
          applied.panels.first.instances.first.signalBindings['in']!;
      expect(binding.signalRef, 'L1');
      expect(binding.bitIndex, 3);
    });

    test('missing-widget degradation is reported', () {
      // _LedStub NOT registered in the follower's build.
      final result = c
          .read(stageWorkspaceProvider.notifier)
          .applyCompositionRecipe(workspace(), _follower());
      expect(result.missingWidgetIds, ['led']);
    });

    test('missing-signal degradation binds to empty + reports the path', () {
      StageRegistry.instance.register(const _LedStub());
      final result = c
          .read(stageWorkspaceProvider.notifier)
          .applyCompositionRecipe(workspace(ref: 'top.ghost'), _follower());
      // The recipe's signalRef is already a path on the wire; ghost won't
      // resolve on the follower.
      expect(result.missingSignalPaths, ['top.ghost']);
      final applied = c.read(stageWorkspaceProvider);
      expect(
        applied.panels.first.instances.first.signalBindings['in']!.signalRef,
        '',
      );
    });
  });
}
