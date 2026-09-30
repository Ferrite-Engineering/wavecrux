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
  List<TimeRange> patternMatchRegions = const [],
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
          patternMatchRegions: patternMatchRegions,
          recordPaintCommands: true,
        ),
      ),
    ),
  );
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Pattern search highlight regions', () {
    // _patternFillPaint color in WaveformCanvasRenderObject
    const patternColor = Color(0x2256AB4E);

    const lane = WaveformLaneData(
      kind: WaveformLaneKind.signal,
      y: 0,
      height: 40,
    );

    testWidgets('pattern match region emits DrawRect with green fill color', (
      tester,
    ) async {
      final key = GlobalKey();
      const region = TimeRange(start: 100, end: 300);

      await tester.pumpWidget(
        _canvas(
          key: key,
          lanes: const [lane],
          patternMatchRegions: const [region],
        ),
      );
      await tester.pump();

      final commands = _renderObj(key).lastPaintCommands.value;
      final rects = commands.whereType<DrawRect>().toList();
      expect(
        rects.where((r) => r.paint.color.toARGB32() == patternColor.toARGB32()),
        isNotEmpty,
        reason: 'Expected a DrawRect with pattern match color 0x2256AB4E',
      );
    });

    testWidgets('no pattern match regions produces no green DrawRect', (
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
        rects.where((r) => r.paint.color.toARGB32() == patternColor.toARGB32()),
        isEmpty,
        reason: 'No pattern match regions means no green DrawRect',
      );
    });

    testWidgets('multiple pattern match regions each emit a DrawRect', (
      tester,
    ) async {
      final key = GlobalKey();
      const regions = [
        TimeRange(start: 50, end: 150),
        TimeRange(start: 400, end: 600),
        TimeRange(start: 750, end: 900),
      ];

      await tester.pumpWidget(
        _canvas(
          key: key,
          lanes: const [lane],
          patternMatchRegions: regions,
        ),
      );
      await tester.pump();

      final commands = _renderObj(key).lastPaintCommands.value;
      final matchRects = commands
          .whereType<DrawRect>()
          .where((r) => r.paint.color.toARGB32() == patternColor.toARGB32())
          .toList();
      expect(
        matchRects.length,
        greaterThanOrEqualTo(3),
        reason:
            'Each pattern match region should produce at least one green rect',
      );
    });

    testWidgets('pattern match color is distinct from divergence color', (
      tester,
    ) async {
      final key = GlobalKey();
      const region = TimeRange(start: 200, end: 400);

      await tester.pumpWidget(
        _canvas(
          key: key,
          lanes: const [lane],
          patternMatchRegions: const [region],
        ),
      );
      await tester.pump();

      final commands = _renderObj(key).lastPaintCommands.value;
      final rects = commands.whereType<DrawRect>().toList();
      const divergenceColor = Color(0x33FF9800);
      expect(
        rects.where(
          (r) => r.paint.color.toARGB32() == divergenceColor.toARGB32(),
        ),
        isEmpty,
        reason: 'Pattern match rects should not use the divergence amber color',
      );
    });
  });
}
