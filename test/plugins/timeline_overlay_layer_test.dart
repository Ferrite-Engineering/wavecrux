// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/plugins/timeline_overlay_layer.dart';

class _StubLayer extends TimelineOverlayLayer {
  const _StubLayer({
    required this.id,
    required this.priority,
    required this.height,
  });

  @override
  final String id;
  @override
  final int priority;
  @override
  final double height;

  @override
  Widget build(BuildContext context) =>
      SizedBox(key: Key('layer-$id'), width: 1, height: height);
}

void main() {
  group('TimelineOverlayLayer', () {
    test('subclasses expose id / priority / height', () {
      const layer = _StubLayer(id: 'sva', priority: 200, height: 10);
      expect(layer.id, 'sva');
      expect(layer.priority, 200);
      expect(layer.height, 10);
    });

    testWidgets('build returns the layer widget at the declared height', (
      tester,
    ) async {
      const layer = _StubLayer(id: 'sva', priority: 200, height: 12);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: Builder(builder: layer.build)),
          ),
        ),
      );
      final size = tester.getSize(find.byKey(const Key('layer-sva')));
      expect(size.height, 12);
    });
  });
}
