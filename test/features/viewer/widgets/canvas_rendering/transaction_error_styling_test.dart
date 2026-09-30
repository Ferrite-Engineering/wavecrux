// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
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
  group('Transaction error styling', () {
    const errorColor = Color(0xFFEF5350);
    const normalColor = Color(0xFF1565C0);

    testWidgets('error transaction emits DrawRect with error color', (
      tester,
    ) async {
      final key = GlobalKey();
      const errorTx = DecodedTransaction(
        startTime: 100,
        endTime: 300,
        label: 'ERR',
        isError: true,
      );
      const lane = WaveformLaneData(
        kind: WaveformLaneKind.transaction,
        y: 0,
        height: 40,
        transactions: [errorTx],
      );

      await tester.pumpWidget(_canvas(key: key, lanes: const [lane]));
      await tester.pump();

      final commands = _renderObj(key).lastPaintCommands.value;
      final rects = commands.whereType<DrawRect>().toList();
      expect(
        rects.where((r) => r.paint.color.toARGB32() == errorColor.toARGB32()),
        isNotEmpty,
        reason: 'Expected a DrawRect with error color 0xFFEF5350',
      );
    });

    testWidgets('normal transaction emits DrawRect with transactionColor', (
      tester,
    ) async {
      final key = GlobalKey();
      const customColor = Color(0xFF4CAF50);
      const normalTx = DecodedTransaction(
        startTime: 100,
        endTime: 300,
        label: 'OK',
      );
      const lane = WaveformLaneData(
        kind: WaveformLaneKind.transaction,
        y: 0,
        height: 40,
        transactions: [normalTx],
        transactionColor: customColor,
      );

      await tester.pumpWidget(_canvas(key: key, lanes: const [lane]));
      await tester.pump();

      final commands = _renderObj(key).lastPaintCommands.value;
      final rects = commands.whereType<DrawRect>().toList();
      expect(
        rects.where((r) => r.paint.color.toARGB32() == customColor.toARGB32()),
        isNotEmpty,
        reason: 'Expected a DrawRect with transactionColor 0xFF4CAF50',
      );
    });

    testWidgets('error and normal transactions produce distinct colors', (
      tester,
    ) async {
      final key = GlobalKey();
      const errorTx = DecodedTransaction(
        startTime: 50,
        endTime: 200,
        label: 'ERR',
        isError: true,
      );
      const normalTx = DecodedTransaction(
        startTime: 300,
        endTime: 500,
        label: 'OK',
      );
      const lane = WaveformLaneData(
        kind: WaveformLaneKind.transaction,
        y: 0,
        height: 40,
        transactions: [errorTx, normalTx],
      );

      await tester.pumpWidget(_canvas(key: key, lanes: const [lane]));
      await tester.pump();

      final commands = _renderObj(key).lastPaintCommands.value;
      final rects = commands.whereType<DrawRect>().toList();
      final colorInts = rects.map((r) => r.paint.color.toARGB32()).toSet();
      expect(colorInts, contains(errorColor.toARGB32()));
      expect(colorInts, contains(normalColor.toARGB32()));
    });

    testWidgets('empty transactions list produces no transaction DrawRects', (
      tester,
    ) async {
      final key = GlobalKey();
      const lane = WaveformLaneData(
        kind: WaveformLaneKind.transaction,
        y: 0,
        height: 40,
      );

      await tester.pumpWidget(_canvas(key: key, lanes: const [lane]));
      await tester.pump();

      final commands = _renderObj(key).lastPaintCommands.value;
      final rects = commands.whereType<DrawRect>().toList();
      expect(
        rects.where((r) => r.paint.color.toARGB32() == errorColor.toARGB32()),
        isEmpty,
        reason: 'No transactions means no error-colored rects',
      );
      expect(
        rects.where((r) => r.paint.color.toARGB32() == normalColor.toARGB32()),
        isEmpty,
        reason: 'No transactions means no normal-colored rects',
      );
    });
  });
}
