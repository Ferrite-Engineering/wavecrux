// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A pulse narrower than a pixel must still be on screen.
//
// The canvas reduces each lane to its pixel columns before painting (see
// `changesForDisplay`), and the painters coalesce whatever lands in one
// column. Both steps are allowed to drop detail, never a glitch: a value that
// leaves and comes back inside one column has to paint at least one pixel.
// These tests rasterise a lane and count the painted pixels in the pulse's
// column, so they measure what reaches the screen rather than what an
// intermediate list holds.

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/analog_interpolation.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/features/viewer/rendering/analog_signal_painter.dart';
import 'package:wavecrux/features/viewer/rendering/scalar_signal_painter.dart';
import 'package:wavecrux/features/viewer/rendering/vector_signal_painter.dart';
import 'package:wavecrux/services/waveform/display_changes.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

const _width = 200;
const _height = 40;
const _lane = Rect.fromLTWH(0, 0, 200, 40);
const _color = Color(0xFF00FF00);

// 10 ticks per pixel: the pulse at ticks 1000..1003 is 0.3 px wide, in
// pixel column 100.
const _mapper = TimeMapper(
  startTime: 0,
  endTime: 2000,
  viewportWidth: 200,
  ticksPerPixel: 10,
  panOffsetTicks: 0,
);

/// Rows painted (alpha > 0) in pixel columns 99..101 — the pulse's column
/// and its antialiasing neighbours.
Future<int> _paintedRowsAtPulse(
  WidgetTester tester,
  void Function(Canvas canvas) paint,
) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final bytes = await tester.runAsync(() async {
    final image = await picture.toImage(_width, _height);
    final data = await image.toByteData();
    image.dispose();
    return data!;
  });
  picture.dispose();
  final pixels = bytes!.buffer.asUint8List();
  var rows = 0;
  for (var y = 0; y < _height; y++) {
    var painted = false;
    for (var x = 99; x <= 101; x++) {
      if (pixels[(y * _width + x) * 4 + 3] > 0) painted = true;
    }
    if (painted) rows++;
  }
  return rows;
}

void _scalar(Canvas canvas, List<SignalChange> changes) =>
    ScalarSignalPainter.paint(
      canvas: canvas,
      laneBounds: _lane,
      changes: changes,
      valueAtStart: '0',
      timeMapper: _mapper,
      signalColor: _color,
      xColor: const Color(0xFFFF0000),
      xHatchColor: const Color(0x80FF0000),
      zColor: const Color(0xFF0000FF),
    );

void _analog(Canvas canvas, List<SignalChange> changes) =>
    AnalogSignalPainter.paint(
      canvas: canvas,
      laneBounds: _lane,
      changes: changes,
      valueAtStart: '0.0',
      timeMapper: _mapper,
      signalColor: _color,
      interpolation: AnalogInterpolation.linear,
      valueStyle: const TextStyle(fontSize: 10),
    );

void main() {
  group('a sub-pixel pulse still paints', () {
    testWidgets('1-bit lane: 0 → 1 → 0 inside one column', (tester) async {
      const pulse = [
        SignalChange(time: 1000, value: '1'),
        SignalChange(time: 1003, value: '0'),
      ];
      // A flat low lane paints a line two or three pixels thick.
      final flat = await _paintedRowsAtPulse(tester, (c) => _scalar(c, []));
      final glitch = await _paintedRowsAtPulse(
        tester,
        (c) => _scalar(c, pulse),
      );
      expect(flat, lessThanOrEqualTo(3));
      expect(
        glitch,
        greaterThanOrEqualTo(_height ~/ 2),
        reason: 'the pulse must draw a mark spanning both levels',
      );
    });

    testWidgets('analog lane: a spike inside one column', (tester) async {
      const spike = [
        SignalChange(time: 1000, value: '9.0'),
        SignalChange(time: 1003, value: '0.0'),
      ];
      final glitch = await _paintedRowsAtPulse(
        tester,
        (c) => _analog(c, spike),
      );
      expect(
        glitch,
        greaterThanOrEqualTo(_height ~/ 2),
        reason: 'the column is drawn at its min-to-max swing',
      );
    });

    // A bus coalesces a column to one value too, but the burst still opens a
    // new segment there, so the lane shows a segment boundary (slanted edges)
    // where the bus moved and came back. A bus lane's fill covers every row,
    // so this is asserted on the segments rather than on pixels.
    test('bus lane: A → B → A inside one column leaves a boundary', () {
      List<({double xStart, double xEnd, String value})> segments(
        List<SignalChange> changes,
      ) => VectorSignalPainter.debugBuildSegments(
        changes: changes,
        valueAtStart: 'b0101',
        timeMapper: _mapper,
        xMin: 0,
        xMax: 200,
      );
      expect(segments(const []), hasLength(1));
      final pulsed = segments(const [
        SignalChange(time: 1000, value: 'b1111'),
        SignalChange(time: 1003, value: 'b0101'),
      ]);
      expect(pulsed, hasLength(2));
      expect(pulsed.first.xEnd, 100);
      expect(pulsed.last.xStart, 100);
    });

    // End to end through the column reduction the canvas uses: the pulse is
    // buried in a column of redundant re-dumps, so the reduction has to drop
    // most of the column and keep the pulse.
    testWidgets('survives the reduction to pixel columns', (tester) async {
      final changes = <SignalChange>[
        const SignalChange(time: 0, value: '0'),
        for (var t = 1000; t < 1004; t++) SignalChange(time: t, value: '0'),
        const SignalChange(time: 1004, value: '1'),
        const SignalChange(time: 1005, value: '0'),
        for (var t = 1006; t < 1010; t++) SignalChange(time: t, value: '0'),
      ];
      final source = WellenProvider()..injectLoadedSignal('1', changes);
      final reduced = source.changesForDisplay(
        '1',
        0,
        2001,
        ticksPerColumn: _mapper.ticksPerPixel,
        columnOrigin: _mapper.panOffsetTicks,
      );
      expect(reduced.length, lessThan(changes.length));
      final rows = await _paintedRowsAtPulse(
        tester,
        (c) => _scalar(c, reduced),
      );
      expect(rows, greaterThanOrEqualTo(_height ~/ 2));
    });
  });
}
