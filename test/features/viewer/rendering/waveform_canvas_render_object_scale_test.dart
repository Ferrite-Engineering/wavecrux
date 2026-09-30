// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_canvas_render_object.dart';
import 'package:wavecrux/features/viewer/widgets/render_stats_collector.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

import '../../../helpers/render_benchmark_service.dart';

const _mapper = TimeMapper(
  startTime: 0,
  endTime: 100000,
  viewportWidth: 1920,
  ticksPerPixel: 100000 / 1920,
  panOffsetTicks: 0,
);

final CruxColorTheme _colorTheme = defaultBuiltinPreset();

void main() {
  group('WaveformCanvasRenderObject — large-scale rendering', () {
    testWidgets('renders 1000 signal lanes without error', (tester) async {
      const service = RenderBenchmarkService();
      final lanes = service.buildLanes(signalCount: 1000);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1920,
              height: 800,
              child: SingleChildScrollView(
                child: WaveformCanvasView(
                  lanes: lanes,
                  timeMapper: _mapper,
                  cursorState: const CursorState(),
                  colorTheme: _colorTheme,
                  // Realistic visible window — only ~33 lanes painted at
                  // 24 px/lane.
                  viewportTop: 0,
                  viewportBottom: 800,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      // The render object must size itself to the full lane stack height
      // (the SingleChildScrollView relies on this for scrollbar geometry).
      final ro = tester.renderObject<WaveformCanvasRenderObject>(
        find.byType(WaveformCanvasView),
      );
      expect(ro.lanes, hasLength(1000));
      expect(ro.size.height, greaterThanOrEqualTo(1000 * 24.0));
    });

    testWidgets(
      'viewport culling restricts visibleSignalRows to the on-screen window',
      (tester) async {
        const service = RenderBenchmarkService();
        final lanes = service.buildLanes(signalCount: 1000);

        // 800 px tall viewport at 24 px/lane → ~33 lanes visible.
        const visibleHeight = 800.0;
        final collector = RenderStatsCollector();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1920,
                height: visibleHeight,
                child: SingleChildScrollView(
                  child: WaveformCanvasView(
                    lanes: lanes,
                    timeMapper: _mapper,
                    cursorState: const CursorState(),
                    colorTheme: _colorTheme,
                    viewportTop: 0,
                    viewportBottom: visibleHeight,
                    statsCollector: collector,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Without culling we'd see ~1000 rows recorded; with culling enabled
        // the count must be a small multiple of the visible-window lane
        // count (33 ± 1 for the 800 px / 24 px-per-lane configuration).
        final rows = collector.stats?.visibleSignalRows ?? 0;
        expect(rows, greaterThan(0));
        expect(
          rows,
          lessThan(60),
          reason: 'expected viewport culling to limit rows; got $rows',
        );
      },
    );

    testWidgets('lineWidthScale propagates from view to render object', (
      tester,
    ) async {
      const service = RenderBenchmarkService();
      final lanes = service.buildLanes(signalCount: 8);

      Widget build(double scale) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1920,
            height: 400,
            child: SingleChildScrollView(
              child: WaveformCanvasView(
                lanes: lanes,
                timeMapper: _mapper,
                cursorState: const CursorState(),
                colorTheme: _colorTheme,
                lineWidthScale: scale,
              ),
            ),
          ),
        ),
      );

      // Default (legibility boost off) is 1.0.
      await tester.pumpWidget(build(1));
      var ro = tester.renderObject<WaveformCanvasRenderObject>(
        find.byType(WaveformCanvasView),
      );
      expect(ro.lineWidthScale, 1.0);

      // Boost on → the host passes a >1 multiplier; updateRenderObject must
      // carry it through without recreating the render object.
      await tester.pumpWidget(build(1.6));
      ro = tester.renderObject<WaveformCanvasRenderObject>(
        find.byType(WaveformCanvasView),
      );
      expect(ro.lineWidthScale, 1.6);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without culling all 1000 lanes are painted', (tester) async {
      const service = RenderBenchmarkService();
      final lanes = service.buildLanes(signalCount: 1000);

      final collector = RenderStatsCollector();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1920,
              height: 800,
              child: SingleChildScrollView(
                child: WaveformCanvasView(
                  lanes: lanes,
                  timeMapper: _mapper,
                  cursorState: const CursorState(),
                  colorTheme: _colorTheme,
                  // viewportTop / viewportBottom intentionally null —
                  // legacy un-culled path.
                  statsCollector: collector,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Every lane is reported as visible.
      expect(collector.stats?.visibleSignalRows, 1000);
    });
  });
}
