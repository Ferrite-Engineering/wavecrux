// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/canvas/value_column_scroll_alignment_test.dart
//
// Regression for the "last lane clipped / scroll bounce-back" bug.
//
// The waveform viewer has three synchronized vertical scroll columns: the
// signal-names list (IdeLayout left of the canvas), the waveform canvas
// (center pane), and the value column (full-height right pane). They must
// share one maxScrollExtent and one top offset, or the synced scroll clamps at
// the bottom and bounces, hiding the last lane behind the scrollbar band.
//
// Two real divergences this guards:
//   1. Timeline-overlay strips (cocotb, Pro SVA) render between the time ruler
//      and the canvas lanes — in the CENTER pane only. The names list and value
//      column must reserve the same rendered overlay height, or their viewports
//      are taller → smaller maxScrollExtent → the synced scroll clamps everyone
//      short of the canvas's last lane. (The Pro SVA strip is 10 dp and is
//      always mounted, so every Pro waveform hit this.) Reproduced here by
//      injecting a 10 dp test overlay through `extraTimelineOverlaysProvider`.
//   2. The value column's right pane is taller than the canvas's center pane by
//      the center↔bottom resizer (and bottom panel); it sizes its scroll region
//      to the published canvas viewport height to compensate.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/signal_list_panel.dart';
import 'package:wavecrux/features/viewer/widgets/value_column_panel.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/plugins/extra_timeline_overlays_provider.dart';
import 'package:wavecrux/plugins/timeline_overlay_layer.dart';

import '../helpers/app_driver.dart';

/// A fixed-height overlay strip standing in for the cocotb / Pro SVA layers.
class _TestOverlayLayer extends TimelineOverlayLayer {
  const _TestOverlayLayer();
  @override
  String get id => 'test_overlay';
  @override
  int get priority => 500;
  @override
  double get height => 10;
  @override
  Widget build(BuildContext context) => const SizedBox(height: 10);
}

({double top, double max}) _metrics(WidgetTester tester, Type panel) {
  final f = find.descendant(
    of: find.byType(panel),
    matching: find.byType(Scrollable),
  );
  expect(f, findsWidgets, reason: 'no Scrollable under $panel');
  final s = tester.state<ScrollableState>(f.first);
  return (top: tester.getTopLeft(f.first).dy, max: s.position.maxScrollExtent);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'names list, canvas, and value column share one top + maxScrollExtent '
    'with a timeline overlay active (no last-lane clip)',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 320);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Boot with a 10 dp overlay strip mounted — the condition that exposed
      // the bug (the names list / value column not reserving overlay height).
      await clearPersistedWorkspace();
      await seedFirstLaunchAnswers();
      await bootstrap(
        args: [
          p.join(
            Directory.current.path,
            'verification',
            'fixtures',
            'vcd',
            'vector_formats.vcd',
          ),
        ],
        extraOverrides: [
          extraTimelineOverlaysProvider.overrideWithValue(const [
            _TestOverlayLayer(),
          ]),
        ],
      );
      await tester.pump();
      await pumpUntilWaveformReady(
        tester,
        timeout: const Duration(seconds: 60),
      );
      await tester.pumpAndSettle();

      final tab = activeTabContainer(tester);
      final source = tab.read(waveformSourceProvider).value!;
      final allVars = source.findVariables(const SignalFilter());
      tab.read(signalGroupsProvider.notifier).addSignals(allVars);
      // Tall lanes so the list overflows the short window.
      final entries = tab.read(signalGroupsProvider).entries;
      final notifier = tab.read(signalGroupsProvider.notifier);
      for (var i = 0; i < entries.length; i++) {
        notifier.setLaneHeight(i, 56);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      // Extra frame so the canvas's post-frame viewport publish reaches the
      // value column and it re-lays-out to match.
      await tester.pump();

      final list = _metrics(tester, SignalListPanel);
      final canvas = _metrics(tester, WaveformCanvas);
      final value = _metrics(tester, ValueColumnPanel);

      expect(
        canvas.max,
        greaterThan(0),
        reason: 'lanes must overflow for this regression to be meaningful',
      );

      // All three scroll viewports start at the same y (rows align under the
      // ruler + overlay strip) ...
      expect(
        (list.top - canvas.top).abs(),
        lessThan(1.0),
        reason: 'names top ${list.top} != canvas top ${canvas.top}',
      );
      expect(
        (value.top - canvas.top).abs(),
        lessThan(1.0),
        reason: 'value top ${value.top} != canvas top ${canvas.top}',
      );
      // ... and reach exactly as far (last lane reachable, no bounce-back).
      expect(
        (list.max - canvas.max).abs(),
        lessThan(1.0),
        reason: 'names max ${list.max} != canvas max ${canvas.max}',
      );
      expect(
        (value.max - canvas.max).abs(),
        lessThan(1.0),
        reason: 'value max ${value.max} != canvas max ${canvas.max}',
      );
    },
  );
}
