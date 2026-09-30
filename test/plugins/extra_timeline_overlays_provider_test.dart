// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/plugins/extra_timeline_overlays_provider.dart';
import 'package:wavecrux/plugins/timeline_overlay_layer.dart';

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
  group('extraTimelineOverlaysProvider', () {
    test('open-core default returns an empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(extraTimelineOverlaysProvider), isEmpty);
    });

    test('overrides replace the default list', () {
      const layers = [_StubLayer('sva', 200), _StubLayer('coverage', 300)];
      final container = ProviderContainer(
        overrides: [extraTimelineOverlaysProvider.overrideWithValue(layers)],
      );
      addTearDown(container.dispose);
      final result = container.read(extraTimelineOverlaysProvider);
      expect(result.length, 2);
      expect(result.first.id, 'sva');
      expect(result.last.priority, 300);
    });
  });
}
