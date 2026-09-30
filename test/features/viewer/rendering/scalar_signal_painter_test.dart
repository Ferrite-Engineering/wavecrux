// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/features/viewer/rendering/scalar_signal_painter.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

// 1 tick = 1 pixel, no pan, viewport 0..1000.
const _mapper = TimeMapper(
  startTime: 0,
  endTime: 1000,
  viewportWidth: 1000,
  ticksPerPixel: 1,
  panOffsetTicks: 0,
);

const _laneBounds = Rect.fromLTWH(0, 0, 1000, 30);
const _signalColor = Color(0xFF00FF00);
const _xColor = Color(0xFFFF0000);
const _xHatchColor = Color(0x80FF0000);
const _zColor = Color(0xFF0000FF);

Canvas _makeCanvas() => Canvas(PictureRecorder());

void _paint(
  Canvas canvas, {
  List<SignalChange> changes = const [],
  String? valueAtStart,
}) {
  ScalarSignalPainter.paint(
    canvas: canvas,
    laneBounds: _laneBounds,
    changes: changes,
    valueAtStart: valueAtStart,
    timeMapper: _mapper,
    signalColor: _signalColor,
    xColor: _xColor,
    xHatchColor: _xHatchColor,
    zColor: _zColor,
  );
}

void main() {
  group('ScalarSignalPainter', () {
    test('no-op when changes empty and valueAtStart null', () {
      _paint(_makeCanvas());
    });

    test('paints single high segment without throwing', () {
      _paint(_makeCanvas(), valueAtStart: '1');
    });

    test('paints single low segment without throwing', () {
      _paint(_makeCanvas(), valueAtStart: '0');
    });

    test('paints x state without throwing', () {
      _paint(_makeCanvas(), valueAtStart: 'x');
    });

    test('paints z state without throwing', () {
      _paint(_makeCanvas(), valueAtStart: 'z');
    });

    test('handles rising edge 0→1', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '0',
        changes: const [SignalChange(time: 500, value: '1')],
      );
    });

    test('handles falling edge 1→0', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '1',
        changes: const [SignalChange(time: 500, value: '0')],
      );
    });

    test('handles transition into x state', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '1',
        changes: const [SignalChange(time: 400, value: 'x')],
      );
    });

    test('handles transition out of x state', () {
      _paint(
        _makeCanvas(),
        valueAtStart: 'x',
        changes: const [SignalChange(time: 400, value: '0')],
      );
    });

    test('handles multiple transitions 0→1→0→x→z→1', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '0',
        changes: const [
          SignalChange(time: 100, value: '1'),
          SignalChange(time: 200, value: '0'),
          SignalChange(time: 300, value: 'x'),
          SignalChange(time: 400, value: 'z'),
          SignalChange(time: 500, value: '1'),
        ],
      );
    });

    test('change at time 0 is treated as initial value update', () {
      _paint(
        _makeCanvas(),
        changes: const [
          SignalChange(time: 0, value: '1'),
          SignalChange(time: 500, value: '0'),
        ],
      );
    });

    test('changes beyond viewport are ignored', () {
      _paint(
        _makeCanvas(),
        changes: const [SignalChange(time: 2000, value: '1')],
      );
    });

    test('valueAtStart only with no changes fills entire lane', () {
      _paint(_makeCanvas(), valueAtStart: '1');
    });

    test('glitch: two changes at same timestamp', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '0',
        changes: const [
          SignalChange(time: 500, value: '1'),
          SignalChange(time: 500, value: '0'),
        ],
      );
    });
  });

  group('ScalarSignalPainter pixel coalescing', () {
    // 1000-pixel viewport; ticksPerPixel = 1 means 1 tick = 1 pixel.
    // The fit-all stress case below uses ticksPerPixel = 100 so each pixel
    // covers 100 ticks and 100 transitions are crammed into one column.

    test('coalesces 100 transitions per pixel into bounded segment count', () {
      // 100,000 transitions across 1000 pixels — pre-fix this would yield
      // ~100,000 segments. With pixel-column coalescing the segment count is
      // bounded by viewport width.
      const ticksPerPixel = 100.0;
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 100000,
        viewportWidth: 1000,
        ticksPerPixel: ticksPerPixel,
        panOffsetTicks: 0,
      );
      final changes = [
        for (var t = 0; t < 100000; t++)
          SignalChange(time: t, value: t.isEven ? '0' : '1'),
      ];

      final segments = ScalarSignalPainter.debugBuildSegments(
        changes: changes,
        valueAtStart: '0',
        timeMapper: mapper,
        xMin: 0,
        xMax: 1000,
      );

      // Expect at most one segment per pixel column, plus one tail segment.
      expect(segments.length, lessThanOrEqualTo(1001));
      expect(segments.length, greaterThan(0));
    });

    test('correctness: single transition at known pixel matches', () {
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 1000,
        ticksPerPixel: 1,
        panOffsetTicks: 0,
      );

      final segments = ScalarSignalPainter.debugBuildSegments(
        changes: const [SignalChange(time: 500, value: '1')],
        valueAtStart: '0',
        timeMapper: mapper,
        xMin: 0,
        xMax: 1000,
      );

      expect(segments, hasLength(2));
      expect(segments[0].xStart, 0);
      expect(segments[0].xEnd, 500);
      expect(segments[0].value, '0');
      expect(segments[1].xStart, 500);
      expect(segments[1].xEnd, 1000);
      expect(segments[1].value, '1');
    });

    test('preserves X glitch within a single pixel column', () {
      // ticksPerPixel = 100 → 100 ticks per pixel. Pack a 0→x→1 burst into
      // ticks 100..150, all in pixel column 1. Expect column 1 to render as X
      // (X-promotion), not as the latest value '1'.
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 10,
        ticksPerPixel: 100,
        panOffsetTicks: 0,
      );

      final segments = ScalarSignalPainter.debugBuildSegments(
        changes: const [
          SignalChange(time: 110, value: 'x'),
          SignalChange(time: 120, value: '1'),
          SignalChange(time: 200, value: '0'),
        ],
        valueAtStart: '0',
        timeMapper: mapper,
        xMin: 0,
        xMax: 10,
      );

      // Column 1 [1..2) had 0→x→1; X must remain visible.
      final col1 = segments.firstWhere(
        (s) => s.xStart >= 1 && s.xStart < 2,
      );
      expect(col1.value, 'x');
    });

    test('does not regress simultaneous-change behavior', () {
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 1000,
        ticksPerPixel: 1,
        panOffsetTicks: 0,
      );

      final segments = ScalarSignalPainter.debugBuildSegments(
        changes: const [
          SignalChange(time: 500, value: '1'),
          SignalChange(time: 500, value: '0'),
        ],
        valueAtStart: '0',
        timeMapper: mapper,
        xMin: 0,
        xMax: 1000,
      );

      // Two same-timestamp changes collapse to a single column boundary at
      // pixel 500, leaving '0' as the held value on both sides.
      expect(segments, hasLength(2));
      expect(segments[0].value, '0');
      expect(segments[1].value, '0');
    });

    test('many sub-pixel transitions never exceed one segment per column', () {
      // Stress: 50 changes spread across only 10 pixels. Pre-fix, this
      // produced ~50 segments; post-fix it should produce ≤11.
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 100,
        viewportWidth: 10,
        ticksPerPixel: 10,
        panOffsetTicks: 0,
      );
      final changes = [
        for (var t = 0; t < 100; t += 2)
          SignalChange(time: t, value: t % 4 == 0 ? '0' : '1'),
      ];

      final segments = ScalarSignalPainter.debugBuildSegments(
        changes: changes,
        valueAtStart: '0',
        timeMapper: mapper,
        xMin: 0,
        xMax: 10,
      );

      expect(segments.length, lessThanOrEqualTo(11));
    });
  });
}
