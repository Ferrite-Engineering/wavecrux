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
  int? xOriginTime,
  Set<String> xOriginSignalRefs = const {},
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
          xOriginTime: xOriginTime,
          xOriginSignalRefs: xOriginSignalRefs,
          recordPaintCommands: true,
        ),
      ),
    ),
  );
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('X-trace origin canvas markers', () {
    // Colors from WaveformCanvasRenderObject
    const xOriginBgColor = Color(0x15EF5350); // _xOriginBgPaint
    const xOriginLineColor = Color(
      0xFFEF5350,
    ); // _xOriginLinePaint / _xOriginDiamondPaint

    const signalRef = 'tb.clk';

    testWidgets('x-origin signal emits background DrawRect with red tint', (
      tester,
    ) async {
      final key = GlobalKey();
      const lane = WaveformLaneData(
        kind: WaveformLaneKind.signal,
        y: 0,
        height: 40,
        signalRef: signalRef,
      );

      await tester.pumpWidget(
        _canvas(
          key: key,
          lanes: const [lane],
          xOriginTime: 500,
          xOriginSignalRefs: {signalRef},
        ),
      );
      await tester.pump();

      final commands = _renderObj(key).lastPaintCommands.value;
      final rects = commands.whereType<DrawRect>().toList();
      expect(
        rects.where(
          (r) => r.paint.color.toARGB32() == xOriginBgColor.toARGB32(),
        ),
        isNotEmpty,
        reason: 'Expected a DrawRect with X-origin background color 0x15EF5350',
      );
    });

    testWidgets('x-origin signal emits DrawLine segments with red color', (
      tester,
    ) async {
      final key = GlobalKey();
      const lane = WaveformLaneData(
        kind: WaveformLaneKind.signal,
        y: 0,
        height: 40,
        signalRef: signalRef,
      );

      await tester.pumpWidget(
        _canvas(
          key: key,
          lanes: const [lane],
          xOriginTime: 500,
          xOriginSignalRefs: {signalRef},
        ),
      );
      await tester.pump();

      final commands = _renderObj(key).lastPaintCommands.value;
      final lines = commands.whereType<DrawLine>().toList();
      expect(
        lines.where(
          (l) => l.paint.color.toARGB32() == xOriginLineColor.toARGB32(),
        ),
        isNotEmpty,
        reason:
            'Expected DrawLine commands with X-origin line color 0xFFEF5350',
      );
    });

    testWidgets('x-origin signal emits DrawPath diamond with red color', (
      tester,
    ) async {
      final key = GlobalKey();
      const lane = WaveformLaneData(
        kind: WaveformLaneKind.signal,
        y: 0,
        height: 40,
        signalRef: signalRef,
      );

      await tester.pumpWidget(
        _canvas(
          key: key,
          lanes: const [lane],
          xOriginTime: 500,
          xOriginSignalRefs: {signalRef},
        ),
      );
      await tester.pump();

      final commands = _renderObj(key).lastPaintCommands.value;
      final paths = commands.whereType<DrawPath>().toList();
      expect(
        paths.where(
          (p) => p.paint.color.toARGB32() == xOriginLineColor.toARGB32(),
        ),
        isNotEmpty,
        reason: 'Expected a DrawPath diamond with X-origin color 0xFFEF5350',
      );
    });

    testWidgets(
      'lane with non-matching signalRef does not emit X-origin markers',
      (tester) async {
        final key = GlobalKey();
        const lane = WaveformLaneData(
          kind: WaveformLaneKind.signal,
          y: 0,
          height: 40,
          signalRef: 'tb.other',
        );

        await tester.pumpWidget(
          _canvas(
            key: key,
            lanes: const [lane],
            xOriginTime: 500,
            xOriginSignalRefs: {signalRef},
          ),
        );
        await tester.pump();

        final commands = _renderObj(key).lastPaintCommands.value;
        final rects = commands.whereType<DrawRect>().toList();
        final lines = commands.whereType<DrawLine>().toList();
        final paths = commands.whereType<DrawPath>().toList();
        expect(
          rects.where(
            (r) => r.paint.color.toARGB32() == xOriginBgColor.toARGB32(),
          ),
          isEmpty,
          reason:
              'Non-matching signalRef should produce no X-origin background rect',
        );
        expect(
          lines.where(
            (l) => l.paint.color.toARGB32() == xOriginLineColor.toARGB32(),
          ),
          isEmpty,
          reason: 'Non-matching signalRef should produce no X-origin lines',
        );
        expect(
          paths.where(
            (p) => p.paint.color.toARGB32() == xOriginLineColor.toARGB32(),
          ),
          isEmpty,
          reason:
              'Non-matching signalRef should produce no X-origin diamond path',
        );
      },
    );

    testWidgets('no xOriginTime produces no X-origin markers', (tester) async {
      final key = GlobalKey();
      const lane = WaveformLaneData(
        kind: WaveformLaneKind.signal,
        y: 0,
        height: 40,
        signalRef: signalRef,
      );

      await tester.pumpWidget(
        _canvas(
          key: key,
          lanes: const [lane],
          xOriginSignalRefs: {signalRef},
          // xOriginTime intentionally omitted (null)
        ),
      );
      await tester.pump();

      final commands = _renderObj(key).lastPaintCommands.value;
      final rects = commands.whereType<DrawRect>().toList();
      expect(
        rects.where(
          (r) => r.paint.color.toARGB32() == xOriginBgColor.toARGB32(),
        ),
        isEmpty,
        reason: 'No xOriginTime means no X-origin background rect',
      );
    });
  });
}
