// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_timeline_overlay_layer.dart';
import 'package:wavecrux/plugins/extra_timeline_overlays_provider.dart';
import 'package:wavecrux/plugins/timeline_overlay_layer.dart';
import 'package:wavecrux/plugins/timeline_overlay_layers_provider.dart';

class _StubLayer extends TimelineOverlayLayer {
  const _StubLayer(this.id, this.priority);
  @override
  final String id;
  @override
  final int priority;
  @override
  double get height => 0;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  group('timelineOverlayLayersProvider', () {
    test('open-core default exposes the cocotb layer', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final layers = container.read(timelineOverlayLayersProvider);
      expect(layers, hasLength(1));
      expect(layers.single, isA<CocotbTimelineOverlayLayer>());
      expect(layers.single.id, 'cocotb');
      expect(layers.single.priority, 100);
    });

    test('combines cocotb default with contributed extras and sorts by '
        'ascending priority', () {
      final container = ProviderContainer(
        overrides: [
          extraTimelineOverlaysProvider.overrideWithValue(
            const <TimelineOverlayLayer>[
              _StubLayer('coverage', 300),
              _StubLayer('sva', 200),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      final layers = container.read(timelineOverlayLayersProvider);
      expect(layers.map((l) => l.id), ['cocotb', 'sva', 'coverage']);
      expect(layers.map((l) => l.priority), [100, 200, 300]);
    });

    test('extras default empty list still includes the cocotb layer', () {
      final container = ProviderContainer(
        overrides: [
          extraTimelineOverlaysProvider.overrideWithValue(
            const <TimelineOverlayLayer>[],
          ),
        ],
      );
      addTearDown(container.dispose);
      final layers = container.read(timelineOverlayLayersProvider);
      expect(layers, hasLength(1));
      expect(layers.single.id, 'cocotb');
    });
  });
}
