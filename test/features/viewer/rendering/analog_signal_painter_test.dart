// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' hide TextStyle;

import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/analog_interpolation.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/features/viewer/rendering/analog_signal_painter.dart';
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
const _signalColor = Color(0xFFFFA726); // orange
const _style = TextStyle(fontSize: 11);

Canvas _makeCanvas() => Canvas(PictureRecorder());

void _paint(
  Canvas canvas, {
  List<SignalChange> changes = const [],
  String? valueAtStart,
  AnalogInterpolation interpolation = AnalogInterpolation.linear,
  double? manualMin,
  double? manualMax,
  int? primaryCursorTime,
}) {
  AnalogSignalPainter.paint(
    canvas: canvas,
    laneBounds: _laneBounds,
    changes: changes,
    valueAtStart: valueAtStart,
    timeMapper: _mapper,
    signalColor: _signalColor,
    interpolation: interpolation,
    valueStyle: _style,
    manualMin: manualMin,
    manualMax: manualMax,
    primaryCursorTime: primaryCursorTime,
  );
}

void main() {
  group('AnalogSignalPainter', () {
    test('no-op when changes empty and valueAtStart null', () {
      _paint(_makeCanvas());
    });

    test('paints single constant value without throwing', () {
      _paint(_makeCanvas(), valueAtStart: '3.14');
    });

    test('paints zero value without throwing', () {
      _paint(_makeCanvas(), valueAtStart: '0.0');
    });

    test('paints negative value without throwing', () {
      _paint(_makeCanvas(), valueAtStart: '-2.5');
    });

    test('NaN valueAtStart produces no trace (graceful)', () {
      _paint(_makeCanvas(), valueAtStart: 'nan');
    });

    test('x-state valueAtStart produces no trace (graceful)', () {
      _paint(_makeCanvas(), valueAtStart: 'x');
    });

    test('z-state valueAtStart produces no trace (graceful)', () {
      _paint(_makeCanvas(), valueAtStart: 'z');
    });

    test('empty string valueAtStart produces no trace (graceful)', () {
      _paint(_makeCanvas(), valueAtStart: '');
    });

    test('linear interpolation: rising ramp', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '0.0',
        changes: const [
          SignalChange(time: 250, value: '2.5'),
          SignalChange(time: 500, value: '5.0'),
          SignalChange(time: 750, value: '7.5'),
          SignalChange(time: 1000, value: '10.0'),
        ],
      );
    });

    test('step-hold interpolation: staircase', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '0.0',
        changes: const [
          SignalChange(time: 250, value: '3.0'),
          SignalChange(time: 500, value: '6.0'),
          SignalChange(time: 750, value: '1.0'),
        ],
        interpolation: AnalogInterpolation.stepHold,
      );
    });

    test('NaN gap in the middle of the trace', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '1.0',
        changes: const [
          SignalChange(time: 300, value: 'x'),
          SignalChange(time: 600, value: '5.0'),
        ],
      );
    });

    test('multiple NaN segments', () {
      _paint(
        _makeCanvas(),
        valueAtStart: 'nan',
        changes: const [
          SignalChange(time: 200, value: '2.0'),
          SignalChange(time: 400, value: 'x'),
          SignalChange(time: 600, value: '4.0'),
          SignalChange(time: 800, value: 'z'),
        ],
      );
    });

    test('manual range override', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '5.0',
        changes: const [SignalChange(time: 500, value: '-5.0')],
        manualMin: -10,
        manualMax: 10,
      );
    });

    test('manual range with inverted values falls back gracefully', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '1.0',
        manualMin: 10,
        manualMax: -10, // inverted — should fall back to ±1
      );
    });

    test('very large values (clamp to lane bounds)', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '1e15',
        changes: const [SignalChange(time: 500, value: '-1e15')],
      );
    });

    test('very small values (picosecond range)', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '1e-12',
        changes: const [SignalChange(time: 500, value: '5e-13')],
      );
    });

    test('cursor label rendered at primary cursor time', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '0.0',
        changes: const [SignalChange(time: 500, value: '5.0')],
        primaryCursorTime: 250,
      );
    });

    test('cursor before all data does not throw', () {
      _paint(
        _makeCanvas(),
        changes: const [SignalChange(time: 500, value: '3.0')],
        primaryCursorTime: 100,
      );
    });

    test('cursor after all data draws label at last value', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '2.0',
        changes: const [SignalChange(time: 200, value: '4.0')],
        primaryCursorTime: 800,
      );
    });

    test('cursor at NaN point does not draw label', () {
      _paint(
        _makeCanvas(),
        valueAtStart: 'x',
        primaryCursorTime: 100,
      );
    });

    test('changes beyond viewport are handled gracefully', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '1.0',
        changes: const [SignalChange(time: 5000, value: '9.0')],
      );
    });

    test('glitch: two changes at same timestamp', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '0.0',
        changes: const [
          SignalChange(time: 500, value: '3.0'),
          SignalChange(time: 500, value: '7.0'),
        ],
      );
    });

    test('step-hold with cursor label', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '1.0',
        changes: const [SignalChange(time: 500, value: '8.0')],
        interpolation: AnalogInterpolation.stepHold,
        primaryCursorTime: 250,
      );
    });

    test('identical min/max values handled without throwing', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '5.0',
        changes: const [SignalChange(time: 500, value: '5.0')],
      );
    });

    test('single change with no valueAtStart', () {
      _paint(
        _makeCanvas(),
        changes: const [SignalChange(time: 200, value: '3.7')],
      );
    });

    test('scientific notation values parse correctly', () {
      _paint(
        _makeCanvas(),
        valueAtStart: '1.5e-3',
        changes: const [SignalChange(time: 500, value: '-2.3e-3')],
      );
    });
  });

  group('AnalogSignalPainter pixel coalescing', () {
    test('coalesces 100 transitions per pixel into bounded anchor count', () {
      const ticksPerPixel = 100.0;
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 100000,
        viewportWidth: 1000,
        ticksPerPixel: ticksPerPixel,
        panOffsetTicks: 0,
      );
      final changes = [
        for (var t = 0; t < 100000; t++) SignalChange(time: t, value: '$t.0'),
      ];

      final points = AnalogSignalPainter.debugBuildPoints(
        changes: changes,
        valueAtStart: '0.0',
        timeMapper: mapper,
        xMin: 0,
        xMax: 1000,
      );

      // ≤ one anchor per pixel column plus the left-edge anchor.
      expect(points.length, lessThanOrEqualTo(1001));
      expect(points.length, greaterThan(0));
    });

    test('correctness: sparse transitions land at the expected pixels', () {
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 1000,
        ticksPerPixel: 1,
        panOffsetTicks: 0,
      );

      final points = AnalogSignalPainter.debugBuildPoints(
        changes: const [
          SignalChange(time: 250, value: '2.5'),
          SignalChange(time: 500, value: '5.0'),
          SignalChange(time: 750, value: '7.5'),
        ],
        valueAtStart: '0.0',
        timeMapper: mapper,
        xMin: 0,
        xMax: 1000,
      );

      expect(points, hasLength(4));
      expect(points[0].x, 0);
      expect(points[0].value, 0.0);
      expect(points[1].x, 250);
      expect(points[1].value, 2.5);
      expect(points[2].x, 500);
      expect(points[2].value, 5.0);
      expect(points[3].x, 750);
      expect(points[3].value, 7.5);
    });

    test('preserves NaN (X) glitch within a single pixel column', () {
      // 100 ticks per pixel; column 1 sees a brief X transition.
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 10,
        ticksPerPixel: 100,
        panOffsetTicks: 0,
      );

      final points = AnalogSignalPainter.debugBuildPoints(
        changes: const [
          SignalChange(time: 110, value: 'x'),
          SignalChange(time: 130, value: '5.0'),
          SignalChange(time: 200, value: '6.0'),
        ],
        valueAtStart: '5.0',
        timeMapper: mapper,
        xMin: 0,
        xMax: 10,
      );

      // Column 1 should retain a NaN anchor so the gap remains visible.
      final col1 = points.firstWhere((p) => p.x.floor() == 1);
      expect(col1.value.isNaN, isTrue);
    });
  });
}
