// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_renderer_registry.dart';
import 'package:wavecrux/plugins/extra_stage_widgets_provider.dart';
import 'package:wavecrux/plugins/stage_registry.dart';

void main() {
  group('extraStageWidgetsProvider', () {
    test('open-core default is an empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(extraStageWidgetsProvider), isEmpty);
    });

    test('overlay override surfaces additional registrations', () {
      const def = _StubStageWidget(
        id: 'fake_pro_widget',
        displayName: 'Fake Pro Widget',
      );
      Widget renderer(BuildContext context, StageInstance instance) =>
          const SizedBox.shrink();

      final container = ProviderContainer(
        overrides: [
          extraStageWidgetsProvider.overrideWithValue(
            <ExtraStageWidgetRegistration>[
              (definition: def, renderer: renderer),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);

      final extras = container.read(extraStageWidgetsProvider);
      expect(extras, hasLength(1));
      expect(extras.first.definition, def);
      expect(identical(extras.first.renderer, renderer), isTrue);
    });

    test('bootstrap-style loop registers each contribution into both '
        'StageRegistry and StageWidgetRendererRegistry', () {
      // Mirror the loop in WaveCruxApp.initState to confirm the typedef
      // contract drives both registries correctly. Clear first so the test
      // is hermetic — built-in widgets are not registered in this context.
      StageRegistry.instance.clear();
      StageWidgetRendererRegistry.instance.clear();
      addTearDown(StageRegistry.instance.clear);
      addTearDown(StageWidgetRendererRegistry.instance.clear);

      const def = _StubStageWidget(
        id: 'fake_pro_framebuffer',
        displayName: 'Fake Pro Framebuffer',
      );
      Widget renderer(BuildContext context, StageInstance instance) =>
          const Placeholder();

      final container = ProviderContainer(
        overrides: [
          extraStageWidgetsProvider.overrideWithValue(
            <ExtraStageWidgetRegistration>[
              (definition: def, renderer: renderer),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);

      for (final extra in container.read(extraStageWidgetsProvider)) {
        StageRegistry.instance.register(extra.definition);
        StageWidgetRendererRegistry.instance.register(
          extra.definition.id,
          extra.renderer,
        );
      }

      expect(StageRegistry.instance.get('fake_pro_framebuffer'), same(def));
      expect(
        StageWidgetRendererRegistry.instance.isRegistered(
          'fake_pro_framebuffer',
        ),
        isTrue,
      );
      expect(
        identical(
          StageWidgetRendererRegistry.instance.get('fake_pro_framebuffer'),
          renderer,
        ),
        isTrue,
      );
    });

    test('multiple contributions all land in both registries', () {
      StageRegistry.instance.clear();
      StageWidgetRendererRegistry.instance.clear();
      addTearDown(StageRegistry.instance.clear);
      addTearDown(StageWidgetRendererRegistry.instance.clear);

      const a = _StubStageWidget(id: 'a', displayName: 'A');
      const b = _StubStageWidget(id: 'b', displayName: 'B');
      Widget rendererA(BuildContext context, StageInstance instance) =>
          const SizedBox.shrink();
      Widget rendererB(BuildContext context, StageInstance instance) =>
          const SizedBox.shrink();

      final container = ProviderContainer(
        overrides: [
          extraStageWidgetsProvider.overrideWithValue(
            <ExtraStageWidgetRegistration>[
              (definition: a, renderer: rendererA),
              (definition: b, renderer: rendererB),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);

      for (final extra in container.read(extraStageWidgetsProvider)) {
        StageRegistry.instance.register(extra.definition);
        StageWidgetRendererRegistry.instance.register(
          extra.definition.id,
          extra.renderer,
        );
      }

      expect(StageRegistry.instance.listAll(), hasLength(2));
      expect(
        StageWidgetRendererRegistry.instance.isRegistered('a'),
        isTrue,
      );
      expect(
        StageWidgetRendererRegistry.instance.isRegistered('b'),
        isTrue,
      );
    });
  });
}

class _StubStageWidget extends StageWidget {
  const _StubStageWidget({
    required this.id,
    required this.displayName,
  });

  @override
  final String id;

  @override
  final String displayName;

  @override
  String get description => 'Test fixture for the Stage extension-point seam';

  @override
  StageWidgetCategory get category => StageWidgetCategory.peripheral;

  @override
  List<SignalBinding> get requiredSignals => const [];
}
