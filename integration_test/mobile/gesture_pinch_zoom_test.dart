// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/mobile/gesture_pinch_zoom_test.dart
//
// Pinch-zoom gesture on the waveform canvas.
//
// Loads a fixture VCD, adds a signal so the canvas paints lanes, captures
// the initial `TimeMapper.ticksPerPixel`, then performs a pinch-out gesture
// (`scale > 1` — fingers move apart from center → zoom in) and verifies
// `ticksPerPixel` decreased. Then pinch-in and verify it increased.
//
// This test is platform-agnostic — the multi-touch simulation in
// `gesture_helpers.pinchZoom` uses `tester.startGesture()` which works on
// every platform Flutter integration tests run on.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';

import '../helpers/app_driver.dart';
import '../helpers/gesture_helpers.dart';
import '_mobile_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'pinch zoom-in decreases ticksPerPixel; pinch zoom-out increases it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final load = await loadSyntheticVcd(tester);
      await tester.pumpAndSettle();

      // Add a signal so the canvas paints lanes — without lanes the
      // canvas may receive gestures but the zoom is more meaningful with
      // real content.
      final source = load.tabContainer.read(waveformSourceProvider).value;
      expect(
        source,
        isNotNull,
        reason: 'synthetic VCD must finish loading before gesture',
      );
      final vars = source!.findVariables(const SignalFilter());
      if (vars.isNotEmpty) {
        await source.loadSignal(vars.first.signalRef);
        load.tabContainer
            .read(signalGroupsProvider.notifier)
            .addSignal(vars.first);
        await tester.pumpAndSettle();
      }

      final canvas = find.byType(WaveformCanvas);
      expect(canvas, findsOneWidget);

      final initialTicksPerPixel = load.tabContainer
          .read(timeMapperProvider)
          .ticksPerPixel;

      // Pinch-OUT (scale > 1: fingers move apart from center) → zoom-in →
      // ticksPerPixel decreases (more pixels per tick).
      await pinchZoom(tester, canvas, 2);
      await tester.pumpAndSettle();
      final afterZoomIn = load.tabContainer
          .read(timeMapperProvider)
          .ticksPerPixel;
      expect(
        afterZoomIn,
        lessThan(initialTicksPerPixel),
        reason:
            'pinch-out (scale > 1) should zoom in — ticksPerPixel '
            'should decrease (initial: $initialTicksPerPixel, '
            'after: $afterZoomIn)',
      );

      // Pinch-IN (scale < 1: fingers move together toward center) →
      // zoom-out → ticksPerPixel increases.
      await pinchZoom(tester, canvas, 0.25);
      await tester.pumpAndSettle();
      final afterZoomOut = load.tabContainer
          .read(timeMapperProvider)
          .ticksPerPixel;
      expect(
        afterZoomOut,
        greaterThan(afterZoomIn),
        reason:
            'pinch-in (scale < 1) should zoom out — ticksPerPixel '
            'should increase (was: $afterZoomIn, after: $afterZoomOut)',
      );

      drainTransientLayoutExceptions(tester);
    },
  );
}
