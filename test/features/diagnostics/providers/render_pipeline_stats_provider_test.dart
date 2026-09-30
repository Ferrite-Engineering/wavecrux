// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/diagnostics/providers/render_pipeline_stats_provider.dart';
import 'package:wavecrux/features/panes/providers/pane_render_stats_provider.dart';
import 'package:wavecrux/features/viewer/widgets/render_stats_collector.dart';

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('renderStatsCollectorProvider', () {
    test('returns a RenderStatsCollector instance', () {
      final c = _container();
      expect(c.read(renderStatsCollectorProvider), isA<RenderStatsCollector>());
    });

    test('returns the same instance on repeated reads', () {
      final c = _container();
      final a = c.read(renderStatsCollectorProvider);
      final b = c.read(renderStatsCollectorProvider);
      expect(identical(a, b), isTrue);
    });

    test('disposes collector when container is disposed', () {
      // ref.onDispose → collector.dispose() — verify no exception thrown.
      expect(
        () => ProviderContainer()
          ..read(renderStatsCollectorProvider)
          ..dispose(),
        returnsNormally,
      );
    });
  });

  // Regression: Issue 31 (VERIFICATION_GUIDE §22.9.11). The root-scope
  // `renderStatsCollectorProvider` previously registered an `onPaint`
  // listener that bridged every collector pulse into the root-scope
  // `paneRenderStatsProvider`. In tests that built the canvas outside the
  // `_PaneScopedCanvas` ProviderScope (and in any future code path that
  // bypassed the per-pane override) the bridge silently mixed paint
  // samples from every pane into the root notifier — breaking the
  // per-pane sparkline contract. The bridge is now removed: the root
  // collector receives no paint events in production, but even if a
  // caller pulses it directly, the root `paneRenderStatsProvider`
  // notifier must remain empty.
  group('renderStatsCollectorProvider — per-pane isolation (Issue 31)', () {
    test(
      'pulsing the root collector does NOT feed root paneRenderStatsProvider',
      () async {
        final c = _container();

        c.read(renderStatsCollectorProvider)
          ..beginFrame()
          ..recordScalarPaint(100, 5)
          ..endFrame();

        // The microtask is what the old bridge would have used; flush any
        // pending microtasks so a regressing bridge has a chance to fire.
        await Future<void>.delayed(Duration.zero);

        final root = c.read(paneRenderStatsProvider);
        expect(
          root.latest,
          isNull,
          reason:
              'root paneRenderStatsProvider must stay empty — paint '
              'samples are per-pane and the root-scope bridge has been '
              'deliberately removed (Issue 31)',
        );
        expect(
          root.paintTimesMs,
          isEmpty,
          reason: 'root sparkline buffer must stay empty for the same reason',
        );
      },
    );
  });
}
