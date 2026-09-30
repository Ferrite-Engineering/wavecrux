// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/features/viewer/rendering/canvas_draw_command.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_canvas_render_object.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_lane_data.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

WaveformCanvasRenderObject _renderObj(GlobalKey key) =>
    key.currentContext!.findRenderObject()! as WaveformCanvasRenderObject;

Widget _canvas({
  required GlobalKey key,
  required List<WaveformLaneData> lanes,
  List<TimeRange> divergenceRegions = const [],
}) {
  final tm = TimeMapper.fitAll(
    startTime: 0,
    endTime: 1000,
    viewportWidth: 800,
  );
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 200,
        child: WaveformCanvasView(
          key: key,
          lanes: lanes,
          timeMapper: tm,
          cursorState: const CursorState(),
          colorTheme: defaultBuiltinPreset(),
          divergenceRegions: divergenceRegions,
          recordPaintCommands: true,
        ),
      ),
    ),
  );
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Divergence region ruler bands', () {
    // _divergenceFillPaint color in WaveformCanvasRenderObject
    const divergenceColor = Color(0x33FF9800);

    const lane = WaveformLaneData(
      kind: WaveformLaneKind.signal,
      y: 0,
      height: 40,
    );

    testWidgets('divergence region emits DrawRect with amber fill color', (
      tester,
    ) async {
      final key = GlobalKey();
      const region = TimeRange(start: 200, end: 400);

      await tester.pumpWidget(
        _canvas(
          key: key,
          lanes: const [lane],
          divergenceRegions: const [region],
        ),
      );
      await tester.pump();

      final commands = _renderObj(key).lastPaintCommands.value;
      final rects = commands.whereType<DrawRect>().toList();
      expect(
        rects.where(
          (r) => r.paint.color.toARGB32() == divergenceColor.toARGB32(),
        ),
        isNotEmpty,
        reason: 'Expected a DrawRect with divergence color 0x33FF9800',
      );
    });

    testWidgets('no divergence regions produces no amber DrawRect', (
      tester,
    ) async {
      final key = GlobalKey();

      await tester.pumpWidget(
        _canvas(key: key, lanes: const [lane]),
      );
      await tester.pump();

      final commands = _renderObj(key).lastPaintCommands.value;
      final rects = commands.whereType<DrawRect>().toList();
      expect(
        rects.where(
          (r) => r.paint.color.toARGB32() == divergenceColor.toARGB32(),
        ),
        isEmpty,
        reason: 'No divergence regions means no amber DrawRect',
      );
    });

    testWidgets('multiple divergence regions each emit a DrawRect', (
      tester,
    ) async {
      final key = GlobalKey();
      const regions = [
        TimeRange(start: 100, end: 200),
        TimeRange(start: 500, end: 700),
      ];

      await tester.pumpWidget(
        _canvas(
          key: key,
          lanes: const [lane],
          divergenceRegions: regions,
        ),
      );
      await tester.pump();

      final commands = _renderObj(key).lastPaintCommands.value;
      final divergenceRects = commands
          .whereType<DrawRect>()
          .where((r) => r.paint.color.toARGB32() == divergenceColor.toARGB32())
          .toList();
      expect(
        divergenceRects.length,
        greaterThanOrEqualTo(2),
        reason: 'Each divergence region should produce at least one amber rect',
      );
    });
  });
}
