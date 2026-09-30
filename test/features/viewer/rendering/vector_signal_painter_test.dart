// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/features/viewer/rendering/vector_signal_painter.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

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

const _style = TextStyle(fontSize: 11);

Canvas _makeCanvas() => Canvas(PictureRecorder());

void _paint(
  Canvas canvas, {
  List<SignalChange> changes = const [],
  String? valueAtStart,
  int bitWidth = 8,
  DisplayFormat format = DisplayFormat.hexadecimal,
}) {
  VectorSignalPainter.paint(
    canvas: canvas,
    laneBounds: _laneBounds,
    changes: changes,
    valueAtStart: valueAtStart,
    timeMapper: _mapper,
    signalColor: _signalColor,
    xColor: _xColor,
    xHatchColor: _xHatchColor,
    zColor: _zColor,
    format: format,
    bitWidth: bitWidth,
    valueStyle: _style,
  );
}

void main() {
  group('VectorSignalPainter', () {
    test('no-op when no data', () {
      _paint(_makeCanvas());
    });

    test('paints normal segment from valueAtStart', () {
      _paint(_makeCanvas(), valueAtStart: 'b10101010');
    });

    test('paints x segment', () {
      _paint(_makeCanvas(), valueAtStart: 'bxxxxxxxx');
    });

    test('paints z segment', () {
      _paint(_makeCanvas(), valueAtStart: 'bzzzzzzzz');
    });

    test('paints multiple changing segments', () {
      _paint(
        _makeCanvas(),
        valueAtStart: 'b00000000',
        changes: const [
          SignalChange(time: 250, value: 'b11111111'),
          SignalChange(time: 500, value: 'bxxxxxxxx'),
          SignalChange(time: 750, value: 'bzzzzzzzz'),
        ],
      );
    });

    test('very narrow segments skip label but draw shape', () {
      _paint(
        _makeCanvas(),
        valueAtStart: 'b00000000',
        changes: const [
          SignalChange(time: 5, value: 'b11111111'),
          SignalChange(time: 10, value: 'b00000000'),
          SignalChange(time: 15, value: 'b11111111'),
        ],
      );
    });

    test('uses binary format', () {
      _paint(
        _makeCanvas(),
        valueAtStart: 'b10101010',
        format: DisplayFormat.binary,
      );
    });

    test('uses unsigned decimal format', () {
      _paint(
        _makeCanvas(),
        valueAtStart: 'b10101010',
        format: DisplayFormat.unsignedDecimal,
      );
    });

    test('4-bit bus', () {
      _paint(
        _makeCanvas(),
        valueAtStart: 'b1010',
        bitWidth: 4,
        changes: const [SignalChange(time: 500, value: 'b0101')],
      );
    });

    test('32-bit bus', () {
      _paint(
        _makeCanvas(),
        valueAtStart: 'b10000000000000000000000000000001',
        bitWidth: 32,
      );
    });

    test('partial x in segment', () {
      _paint(_makeCanvas(), valueAtStart: 'bxxxx1010');
    });

    test('changes beyond viewport are ignored', () {
      _paint(
        _makeCanvas(),
        valueAtStart: 'b00000000',
        changes: const [SignalChange(time: 2000, value: 'b11111111')],
      );
    });
  });

  group('VectorSignalPainter pixel coalescing', () {
    test('coalesces 100 transitions per pixel into bounded segment count', () {
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
          SignalChange(
            time: t,
            value: 'b${(t & 0xff).toRadixString(2).padLeft(8, '0')}',
          ),
      ];

      final segments = VectorSignalPainter.debugBuildSegments(
        changes: changes,
        valueAtStart: 'b00000000',
        timeMapper: mapper,
        xMin: 0,
        xMax: 1000,
      );

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

      final segments = VectorSignalPainter.debugBuildSegments(
        changes: const [SignalChange(time: 500, value: 'b11110000')],
        valueAtStart: 'b00001111',
        timeMapper: mapper,
        xMin: 0,
        xMax: 1000,
      );

      expect(segments, hasLength(2));
      expect(segments[0].xStart, 0);
      expect(segments[0].xEnd, 500);
      expect(segments[0].value, 'b00001111');
      expect(segments[1].xStart, 500);
      expect(segments[1].xEnd, 1000);
      expect(segments[1].value, 'b11110000');
    });

    test('preserves X glitch within a single pixel column', () {
      // 100 ticks per pixel; pack a normal→X→normal burst into pixel column 1.
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 10,
        ticksPerPixel: 100,
        panOffsetTicks: 0,
      );

      final segments = VectorSignalPainter.debugBuildSegments(
        changes: const [
          SignalChange(time: 110, value: 'bxxxx0000'),
          SignalChange(time: 130, value: 'b11110000'),
          SignalChange(time: 200, value: 'b00000000'),
        ],
        valueAtStart: 'b11110000',
        timeMapper: mapper,
        xMin: 0,
        xMax: 10,
      );

      final col1 = segments.firstWhere(
        (s) => s.xStart >= 1 && s.xStart < 2,
      );
      expect(col1.value, contains('x'));
    });
  });
}
