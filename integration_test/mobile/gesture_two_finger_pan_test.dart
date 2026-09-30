// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/mobile/gesture_two_finger_pan_test.dart
//
// Two-finger pan gesture on the waveform canvas.
//
// Performs a two-finger pan gesture and verifies the viewport panned
// forward in time: the `TimeMapper.panOffsetTicks` value increases when the
// fingers move leftward (dragging the timeline left = revealing later
// times on the right).

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
    'two-finger leftward pan advances panOffsetTicks',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final load = await loadSyntheticVcd(tester);
      await tester.pumpAndSettle();

      // Add a signal so the canvas paints lanes.
      final source = load.tabContainer.read(waveformSourceProvider).value;
      expect(source, isNotNull);
      final vars = source!.findVariables(const SignalFilter());
      if (vars.isNotEmpty) {
        await source.loadSignal(vars.first.signalRef);
        load.tabContainer
            .read(signalGroupsProvider.notifier)
            .addSignal(vars.first);
        await tester.pumpAndSettle();
      }

      // Zoom in first so there is room to pan in either direction —
      // fit-all leaves no room to pan because the full range is visible.
      final canvas = find.byType(WaveformCanvas);
      expect(canvas, findsOneWidget);

      await pinchZoom(tester, canvas, 3);
      await tester.pumpAndSettle();

      final initialPan = load.tabContainer
          .read(timeMapperProvider)
          .panOffsetTicks;

      // Pan leftward: fingers move left → canvas shifts left → viewport
      // reveals later times → panOffsetTicks increases.
      await twoFingerPan(tester, canvas, const Offset(-150, 0));
      await tester.pumpAndSettle();

      final afterPan = load.tabContainer
          .read(timeMapperProvider)
          .panOffsetTicks;
      expect(
        afterPan,
        greaterThan(initialPan),
        reason:
            'leftward two-finger pan should advance panOffsetTicks '
            '(initial: $initialPan, after: $afterPan)',
      );

      drainTransientLayoutExceptions(tester);
    },
  );
}
