// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
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
          recordPaintCommands: true,
        ),
      ),
    ),
  );
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('XOR diff lane rendering', () {
    // _xorBgPaint color in WaveformCanvasRenderObject
    const xorBgColor = Color(0x1AFF9800);

    testWidgets('xorDiff lane emits DrawRect with XOR background color', (
      tester,
    ) async {
      final key = GlobalKey();
      const lane = WaveformLaneData(
        kind: WaveformLaneKind.xorDiff,
        y: 0,
        height: 40,
      );

      await tester.pumpWidget(_canvas(key: key, lanes: const [lane]));
      await tester.pump();

      final commands = _renderObj(key).lastPaintCommands.value;
      final rects = commands.whereType<DrawRect>().toList();
      expect(
        rects.where((r) => r.paint.color.toARGB32() == xorBgColor.toARGB32()),
        isNotEmpty,
        reason: 'Expected a DrawRect with XOR background color 0x1AFF9800',
      );
    });

    testWidgets('signal lane does not emit XOR background DrawRect', (
      tester,
    ) async {
      final key = GlobalKey();
      const lane = WaveformLaneData(
        kind: WaveformLaneKind.signal,
        y: 0,
        height: 40,
      );

      await tester.pumpWidget(_canvas(key: key, lanes: const [lane]));
      await tester.pump();

      final commands = _renderObj(key).lastPaintCommands.value;
      final rects = commands.whereType<DrawRect>().toList();
      expect(
        rects.where((r) => r.paint.color.toARGB32() == xorBgColor.toARGB32()),
        isEmpty,
        reason: 'A signal lane should not produce an XOR background rect',
      );
    });

    testWidgets(
      'multiple xorDiff lanes each emit a DrawRect with XOR background color',
      (tester) async {
        final key = GlobalKey();
        const lanes = [
          WaveformLaneData(kind: WaveformLaneKind.xorDiff, y: 0, height: 40),
          WaveformLaneData(kind: WaveformLaneKind.xorDiff, y: 40, height: 40),
        ];

        await tester.pumpWidget(_canvas(key: key, lanes: lanes));
        await tester.pump();

        final commands = _renderObj(key).lastPaintCommands.value;
        final xorRects = commands
            .whereType<DrawRect>()
            .where((r) => r.paint.color.toARGB32() == xorBgColor.toARGB32())
            .toList();
        expect(
          xorRects.length,
          greaterThanOrEqualTo(2),
          reason:
              'Each xorDiff lane should produce at least one XOR background rect',
        );
      },
    );
  });
}
