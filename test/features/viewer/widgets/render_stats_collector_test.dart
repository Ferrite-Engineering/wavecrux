// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/widgets/render_stats_collector.dart';

void main() {
  group('RenderStatsCollector', () {
    late RenderStatsCollector collector;

    setUp(() => collector = RenderStatsCollector());
    tearDown(() => collector.dispose());

    test('starts with null stats', () {
      expect(collector.stats, isNull);
    });

    group('beginFrame resets accumulators', () {
      test('clears after first endFrame', () {
        collector
          ..beginFrame()
          ..recordScalarPaint(100, 5)
          ..endFrame()
          ..beginFrame()
          ..endFrame();

        expect(collector.stats!.scalarPaintTimeUs, 0);
        expect(collector.stats!.lineSegmentsDrawn, 0);
      });

      test('resets all counters independently', () {
        collector
          ..beginFrame()
          ..recordLayout(10)
          ..recordScalarPaint(20, 3)
          ..recordVectorPaint(30, 7)
          ..recordAnalogPaint(40, 2)
          ..recordCursorPaint(50)
          ..recordTransactionPaint(60)
          ..recordViewportInfo(8, 100, const Size(1200, 600))
          ..endFrame()
          ..beginFrame()
          ..endFrame();

        final s = collector.stats!;
        expect(s.layoutTimeUs, 0);
        expect(s.scalarPaintTimeUs, 0);
        expect(s.vectorPaintTimeUs, 0);
        expect(s.analogPaintTimeUs, 0);
        expect(s.cursorPaintTimeUs, 0);
        expect(s.transactionPaintTimeUs, 0);
        expect(s.visibleSignalRows, 0);
        expect(s.visibleTransitions, 0);
        expect(s.lineSegmentsDrawn, 0);
        expect(s.canvasWidth, 0.0);
        expect(s.canvasHeight, 0.0);
      });
    });

    group('record methods accumulate correctly', () {
      setUp(() => collector.beginFrame());

      test('recordLayout accumulates layout time', () {
        collector
          ..recordLayout(250)
          ..endFrame();
        expect(collector.stats!.layoutTimeUs, 250);
      });

      test('recordScalarPaint accumulates time and segments', () {
        collector
          ..recordScalarPaint(100, 5)
          ..recordScalarPaint(200, 3)
          ..endFrame();
        expect(collector.stats!.scalarPaintTimeUs, 300);
        expect(collector.stats!.lineSegmentsDrawn, 8);
      });

      test('recordVectorPaint accumulates time and segments', () {
        collector
          ..recordVectorPaint(150, 10)
          ..recordVectorPaint(50, 4)
          ..endFrame();
        expect(collector.stats!.vectorPaintTimeUs, 200);
        expect(collector.stats!.lineSegmentsDrawn, 14);
      });

      test('recordAnalogPaint accumulates time and segments', () {
        collector
          ..recordAnalogPaint(300, 100)
          ..endFrame();
        expect(collector.stats!.analogPaintTimeUs, 300);
        expect(collector.stats!.lineSegmentsDrawn, 100);
      });

      test('recordCursorPaint accumulates cursor time', () {
        collector
          ..recordCursorPaint(75)
          ..endFrame();
        expect(collector.stats!.cursorPaintTimeUs, 75);
      });

      test('recordTransactionPaint accumulates time', () {
        collector
          ..recordTransactionPaint(80)
          ..recordTransactionPaint(40)
          ..endFrame();
        expect(collector.stats!.transactionPaintTimeUs, 120);
      });

      test('lineSegmentsDrawn sums across all paint types', () {
        collector
          ..recordScalarPaint(10, 3)
          ..recordVectorPaint(10, 7)
          ..recordAnalogPaint(10, 4)
          ..endFrame();
        expect(collector.stats!.lineSegmentsDrawn, 14);
      });

      test('recordViewportInfo stores all fields', () {
        collector
          ..recordViewportInfo(12, 450, const Size(1920, 800))
          ..endFrame();
        final s = collector.stats!;
        expect(s.visibleSignalRows, 12);
        expect(s.visibleTransitions, 450);
        expect(s.canvasWidth, 1920.0);
        expect(s.canvasHeight, 800.0);
      });
    });

    group('endFrame produces correct RenderPipelineStats snapshot', () {
      test('totalPaintTimeUs is sum of all phase times', () {
        collector
          ..beginFrame()
          ..recordLayout(10)
          ..recordScalarPaint(20, 1)
          ..recordVectorPaint(30, 1)
          ..recordAnalogPaint(40, 1)
          ..recordCursorPaint(50)
          ..recordTransactionPaint(60)
          ..endFrame();

        expect(collector.stats!.totalPaintTimeUs, 10 + 20 + 30 + 40 + 50 + 60);
      });

      test('snapshot has correct values after full frame', () {
        collector
          ..beginFrame()
          ..recordLayout(5)
          ..recordScalarPaint(100, 8)
          ..recordVectorPaint(200, 12)
          ..recordCursorPaint(15)
          ..recordViewportInfo(20, 500, const Size(1600, 400))
          ..endFrame();

        final s = collector.stats!;
        expect(s.visibleSignalRows, 20);
        expect(s.visibleTransitions, 500);
        expect(s.lineSegmentsDrawn, 20); // 8 + 12
        expect(s.layoutTimeUs, 5);
        expect(s.scalarPaintTimeUs, 100);
        expect(s.vectorPaintTimeUs, 200);
        expect(s.analogPaintTimeUs, 0);
        expect(s.cursorPaintTimeUs, 15);
        expect(s.transactionPaintTimeUs, 0);
        expect(s.totalPaintTimeUs, 5 + 100 + 200 + 15);
        expect(s.canvasWidth, 1600.0);
        expect(s.canvasHeight, 400.0);
      });
    });

    group('notifies listeners on endFrame', () {
      test('notifies once per endFrame', () {
        var notifyCount = 0;
        collector
          ..addListener(() => notifyCount++)
          ..beginFrame()
          ..endFrame();
        expect(notifyCount, 1);

        collector
          ..beginFrame()
          ..endFrame();
        expect(notifyCount, 2);
      });

      test('does not notify on beginFrame or record calls', () {
        var notifyCount = 0;
        collector
          ..addListener(() => notifyCount++)
          ..beginFrame()
          ..recordScalarPaint(100, 5)
          ..recordCursorPaint(10);
        expect(notifyCount, 0);
      });
    });

    group('multiple frames accumulate independently', () {
      test('each frame produces an independent snapshot', () {
        collector
          ..beginFrame()
          ..recordScalarPaint(100, 5)
          ..endFrame();
        final frame1 = collector.stats!;

        collector
          ..beginFrame()
          ..recordVectorPaint(200, 10)
          ..endFrame();
        final frame2 = collector.stats!;

        expect(frame1.scalarPaintTimeUs, 100);
        expect(frame1.vectorPaintTimeUs, 0);
        expect(frame2.scalarPaintTimeUs, 0);
        expect(frame2.vectorPaintTimeUs, 200);
      });

      test('stats getter always returns the latest snapshot', () {
        collector
          ..beginFrame()
          ..recordScalarPaint(50, 2)
          ..endFrame();
        expect(collector.stats!.scalarPaintTimeUs, 50);

        collector
          ..beginFrame()
          ..recordScalarPaint(99, 3)
          ..endFrame();
        expect(collector.stats!.scalarPaintTimeUs, 99);
      });
    });
  });
}
