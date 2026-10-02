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

// P1: an inbound cross-probe selection must be visible on the waveform CANVAS,
// not only in the signal-name / value panes. The render object paints a
// full-lane tint + a left accent bar on any lane whose row path (or, without
// one, signalRef) is in the selected set; these tests assert that treatment
// through the recorded
// draw-command snapshot.

WaveformCanvasRenderObject _renderObj(GlobalKey key) =>
    key.currentContext!.findRenderObject()! as WaveformCanvasRenderObject;

// A distinct accent (not the widget's default) so the assertions also prove
// the host-supplied selection color reaches the paint.
const _selectionColor = Color(0xFFAB47BC);

Widget _canvas({
  required GlobalKey key,
  required List<WaveformLaneData> lanes,
  Set<String> selectedRowPaths = const {},
}) {
  final tm = TimeMapper.fitAll(startTime: 0, endTime: 1000, viewportWidth: 800);
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
          selectedRowPaths: selectedRowPaths,
          selectionColor: _selectionColor,
          recordPaintCommands: true,
        ),
      ),
    ),
  );
}

void main() {
  group('selected-lane highlight', () {
    // Mirrors the render object's own derivation so the assertion is exact.
    // Tint alpha raised to 0.30 (from 0.18) so an inbound cross-probe selection
    // reads clearly behind a dense trace — keep this in lockstep with
    // WaveformCanvasRenderObject's `_selectionLaneBgPaint` alpha.
    final tintArgb = _selectionColor.withValues(alpha: 0.30).toARGB32();
    final accentArgb = _selectionColor.toARGB32();

    testWidgets('selected signal lane emits both the tint and accent rects', (
      tester,
    ) async {
      final key = GlobalKey();
      const lanes = [
        WaveformLaneData(
          kind: WaveformLaneKind.signal,
          y: 0,
          height: 40,
          signalRef: 'top.clk',
          displayName: 'clk',
          isScalar: true,
        ),
      ];

      await tester.pumpWidget(
        _canvas(key: key, lanes: lanes, selectedRowPaths: {'top.clk'}),
      );
      await tester.pump();

      final rects = _renderObj(
        key,
      ).lastPaintCommands.value.whereType<DrawRect>().toList();
      expect(
        rects.where((r) => r.paint.color.toARGB32() == tintArgb),
        isNotEmpty,
        reason: 'selected lane should paint a full-lane selection tint',
      );
      expect(
        rects.where((r) => r.paint.color.toARGB32() == accentArgb),
        isNotEmpty,
        reason: 'selected lane should paint a left accent bar',
      );
    });

    testWidgets('unselected signal lane paints no selection rects', (
      tester,
    ) async {
      final key = GlobalKey();
      const lanes = [
        WaveformLaneData(
          kind: WaveformLaneKind.signal,
          y: 0,
          height: 40,
          signalRef: 'top.clk',
          displayName: 'clk',
          isScalar: true,
        ),
      ];

      // Selected set names a different signal — this lane must stay plain.
      await tester.pumpWidget(
        _canvas(key: key, lanes: lanes, selectedRowPaths: {'top.other'}),
      );
      await tester.pump();

      final rects = _renderObj(
        key,
      ).lastPaintCommands.value.whereType<DrawRect>().toList();
      expect(
        rects.where(
          (r) =>
              r.paint.color.toARGB32() == tintArgb ||
              r.paint.color.toARGB32() == accentArgb,
        ),
        isEmpty,
      );
    });

    testWidgets('only the selected lane among several is highlighted', (
      tester,
    ) async {
      final key = GlobalKey();
      const lanes = [
        WaveformLaneData(
          kind: WaveformLaneKind.signal,
          y: 0,
          height: 40,
          signalRef: 'top.a',
          displayName: 'a',
          isScalar: true,
        ),
        WaveformLaneData(
          kind: WaveformLaneKind.signal,
          y: 40,
          height: 40,
          signalRef: 'top.b',
          displayName: 'b',
          isScalar: true,
        ),
      ];

      await tester.pumpWidget(
        _canvas(key: key, lanes: lanes, selectedRowPaths: {'top.b'}),
      );
      await tester.pump();

      final accentRects = _renderObj(key).lastPaintCommands.value
          .whereType<DrawRect>()
          .where((r) => r.paint.color.toARGB32() == accentArgb)
          .toList();
      expect(accentRects, hasLength(1));
      // The accent bar sits on the second lane (y = 40).
      expect(accentRects.single.rect.top, 40);
    });

    // counter_tb.vcd: `down.clk`, `up.clk` and the testbench's own `clk` are
    // one net under three names, so they share a ref. Selecting one row must
    // tint that row's lane only.
    testWidgets(
      'aliased lanes sharing a ref: only the selected row is tinted',
      (
        tester,
      ) async {
        final key = GlobalKey();
        const lanes = [
          WaveformLaneData(
            kind: WaveformLaneKind.signal,
            y: 0,
            height: 40,
            signalRef: '#',
            rowPath: 'tb.down.clk',
            displayName: 'clk',
            isScalar: true,
          ),
          WaveformLaneData(
            kind: WaveformLaneKind.signal,
            y: 40,
            height: 40,
            signalRef: '#',
            rowPath: 'tb.up.clk',
            displayName: 'clk',
            isScalar: true,
          ),
        ];

        await tester.pumpWidget(
          _canvas(key: key, lanes: lanes, selectedRowPaths: {'tb.up.clk'}),
        );
        await tester.pump();

        final accentRects = _renderObj(key).lastPaintCommands.value
            .whereType<DrawRect>()
            .where((r) => r.paint.color.toARGB32() == accentArgb)
            .toList();
        expect(accentRects, hasLength(1));
        expect(accentRects.single.rect.top, 40);
      },
    );

    testWidgets('changing selectedRowPaths marks the render object dirty', (
      tester,
    ) async {
      final key = GlobalKey();
      const lanes = [
        WaveformLaneData(
          kind: WaveformLaneKind.signal,
          y: 0,
          height: 40,
          signalRef: 'top.clk',
          displayName: 'clk',
          isScalar: true,
        ),
      ];

      await tester.pumpWidget(_canvas(key: key, lanes: lanes));
      await tester.pump();

      final ro = _renderObj(key)..selectedRowPaths = {'top.clk'};
      expect(ro.debugNeedsPaint, isTrue);
    });
  });
}
