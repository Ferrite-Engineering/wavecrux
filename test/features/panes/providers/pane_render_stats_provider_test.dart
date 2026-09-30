// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/pane_id.dart';
import 'package:wavecrux/domain/models/pane_render_stats.dart';
import 'package:wavecrux/domain/models/render_pipeline_stats.dart';
import 'package:wavecrux/features/panes/providers/pane_render_stats_provider.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';

RenderPipelineStats _stats(int totalUs) => RenderPipelineStats(
  visibleSignalRows: 1,
  visibleTransitions: 1,
  lineSegmentsDrawn: 1,
  layoutTimeUs: 0,
  scalarPaintTimeUs: 0,
  vectorPaintTimeUs: 0,
  analogPaintTimeUs: 0,
  cursorPaintTimeUs: 0,
  transactionPaintTimeUs: 0,
  totalPaintTimeUs: totalUs,
  canvasWidth: 800,
  canvasHeight: 600,
);

void main() {
  group('PaneRenderStatsNotifier (root scope)', () {
    test('initial state is empty', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final stats = c.read(paneRenderStatsProvider);
      expect(stats.latest, isNull);
      expect(stats.paintTimesMs, isEmpty);
    });

    test('record appends to sparkline history', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(paneRenderStatsProvider.notifier)
        ..record(_stats(1000))
        ..record(_stats(2000))
        ..record(_stats(3000));
      final stats = c.read(paneRenderStatsProvider);
      expect(stats.paintTimesMs, [1.0, 2.0, 3.0]);
      expect(stats.latest!.totalPaintTimeUs, 3000);
    });

    test('sparkline history caps at kPaneRenderStatsHistoryDepth samples', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = c.read(paneRenderStatsProvider.notifier);
      for (var i = 0; i < kPaneRenderStatsHistoryDepth + 10; i++) {
        notifier.record(_stats(i * 100));
      }
      final stats = c.read(paneRenderStatsProvider);
      expect(stats.paintTimesMs.length, kPaneRenderStatsHistoryDepth);
      // Oldest 10 samples evicted in FIFO order — last sample is the most
      // recent (kPaneRenderStatsHistoryDepth + 9) * 0.1 ms.
      expect(
        stats.paintTimesMs.last,
        closeTo((kPaneRenderStatsHistoryDepth + 9) * 0.1, 1e-9),
      );
    });

    test('reset clears the buffer back to empty', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(paneRenderStatsProvider.notifier)
        ..record(_stats(500))
        ..reset();
      final stats = c.read(paneRenderStatsProvider);
      expect(stats.paintTimesMs, isEmpty);
      expect(stats.latest, isNull);
    });
  });

  group('Per-pane isolation via PaneContainerManager', () {
    test('two pane containers hold independent sparkline buffers', () {
      final pcm = PaneContainerManager();
      final root = ProviderContainer(
        overrides: [paneContainerManagerProvider.overrideWithValue(pcm)],
      );
      pcm.init(root);
      addTearDown(() {
        pcm.dispose();
        root.dispose();
      });

      final paneA = pcm.containerFor(PaneId.generate());
      final paneB = pcm.containerFor(PaneId.generate());

      paneA.read(paneRenderStatsProvider.notifier).record(_stats(1500));
      paneB.read(paneRenderStatsProvider.notifier)
        ..record(_stats(800))
        ..record(_stats(900));

      final statsA = paneA.read(paneRenderStatsProvider);
      final statsB = paneB.read(paneRenderStatsProvider);
      expect(statsA.paintTimesMs, [1.5]);
      expect(statsB.paintTimesMs, [0.8, 0.9]);
    });
  });

  group('PaneRenderStats model', () {
    test('equality is value-based across paintTimesMs list contents', () {
      const a = PaneRenderStats(paintTimesMs: [1.0, 2.0, 3.0]);
      const b = PaneRenderStats(paintTimesMs: [1.0, 2.0, 3.0]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when paintTimesMs differs in length', () {
      const a = PaneRenderStats(paintTimesMs: [1.0]);
      const b = PaneRenderStats(paintTimesMs: [1.0, 2.0]);
      expect(a, isNot(equals(b)));
    });
  });
}
