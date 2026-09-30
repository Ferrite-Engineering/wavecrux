// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/features/stage/widgets/primitives/builtin_stage_widgets.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_renderer_registry.dart';
import 'package:wavecrux/plugins/stage_registry.dart';

void main() {
  setUp(clearBuiltinStageWidgets);
  tearDown(clearBuiltinStageWidgets);

  group('StageWidgetRendererRegistry', () {
    test('returns null for unknown widget id', () {
      expect(StageWidgetRendererRegistry.instance.get('nope'), isNull);
      expect(
        StageWidgetRendererRegistry.instance.isRegistered('nope'),
        isFalse,
      );
    });

    test('register stores and returns the renderer', () {
      Widget builder(BuildContext context, StageInstance instance) =>
          const SizedBox();
      StageWidgetRendererRegistry.instance.register('foo', builder);
      expect(
        StageWidgetRendererRegistry.instance.get('foo'),
        same(builder),
      );
      expect(
        StageWidgetRendererRegistry.instance.isRegistered('foo'),
        isTrue,
      );
    });

    test('unregister removes a single renderer', () {
      Widget foo(BuildContext c, StageInstance i) => const SizedBox(width: 1);
      Widget bar(BuildContext c, StageInstance i) => const SizedBox(width: 2);
      StageWidgetRendererRegistry.instance
        ..register('foo', foo)
        ..register('bar', bar)
        ..unregister('foo');
      expect(StageWidgetRendererRegistry.instance.get('foo'), isNull);
      expect(StageWidgetRendererRegistry.instance.get('bar'), same(bar));
    });

    test('unregister is a no-op for an unknown id', () {
      StageWidgetRendererRegistry.instance
        ..register('foo', (c, i) => const SizedBox())
        ..unregister('missing');
      expect(StageWidgetRendererRegistry.instance.isRegistered('foo'), isTrue);
    });

    test('clear removes all renderers', () {
      StageWidgetRendererRegistry.instance.register(
        'foo',
        (c, i) => const SizedBox(),
      );
      StageWidgetRendererRegistry.instance.clear();
      expect(StageWidgetRendererRegistry.instance.get('foo'), isNull);
    });

    test('register replaces existing entry under the same id', () {
      Widget first(BuildContext c, StageInstance i) => const SizedBox(width: 1);
      Widget second(BuildContext c, StageInstance i) =>
          const SizedBox(width: 2);
      StageWidgetRendererRegistry.instance
        ..register('foo', first)
        ..register('foo', second);
      expect(
        StageWidgetRendererRegistry.instance.get('foo'),
        same(second),
      );
    });
  });

  group('registerBuiltinStageWidgets', () {
    test('registers every primitive plus the four Open Core boards in '
        'both registries', () {
      registerBuiltinStageWidgets();

      const expectedIds = [
        // Primitives.
        'led',
        'toggle_switch',
        'seven_segment',
        'level_bar',
        'state_indicator',
        'bus_readout',
        'signal_graph',
        // Open Core FPGA boards (post v0.12.5 lineup).
        'basys3',
        'de10_lite',
        'nexysA7',
        'artyA7',
      ];

      for (final id in expectedIds) {
        expect(
          StageRegistry.instance.isRegistered(id),
          isTrue,
          reason: 'StageRegistry should have $id',
        );
        expect(
          StageWidgetRendererRegistry.instance.isRegistered(id),
          isTrue,
          reason: 'StageWidgetRendererRegistry should have $id',
        );
      }
    });

    test('clearBuiltinStageWidgets clears both registries', () {
      registerBuiltinStageWidgets();
      clearBuiltinStageWidgets();
      expect(StageRegistry.instance.listAll(), isEmpty);
      expect(StageWidgetRendererRegistry.instance.get('led'), isNull);
    });
  });
}
