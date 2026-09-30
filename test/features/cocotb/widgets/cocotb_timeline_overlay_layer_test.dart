// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_timeline_overlay.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_timeline_overlay_layer.dart';

void main() {
  group('CocotbTimelineOverlayLayer', () {
    test('exposes id, priority, height matching the historical strip', () {
      const layer = CocotbTimelineOverlayLayer();
      expect(layer.id, 'cocotb');
      expect(layer.priority, 100);
      expect(layer.height, cocotbTimelineOverlayHeight);
    });

    testWidgets('build returns a CocotbTimelineOverlay widget', (tester) async {
      const layer = CocotbTimelineOverlayLayer();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: Builder(builder: layer.build)),
          ),
        ),
      );
      expect(find.byType(CocotbTimelineOverlay), findsOneWidget);
    });
  });
}
