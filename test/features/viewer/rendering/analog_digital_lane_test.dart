// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/features/viewer/rendering/analog_signal_painter.dart';
import 'package:wavecrux/services/value_format/analog_value_extractor.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// The painter half of "render a digital bus as an analog trace".
///
/// [AnalogSignalPainter] is deliberately value-agnostic: it knows how to turn a
/// list of `(x, number)` anchors into a curve and nothing about where the
/// numbers came from. These tests drive it with the digital-lane extractor and
/// assert the anchors it builds, which is the seam where the feature either
/// works or silently plots the wrong magnitudes.
void main() {
  TimeMapper mapper({int endTime = 1000, double width = 1000}) => TimeMapper(
    startTime: 0,
    endTime: endTime,
    viewportWidth: width,
    ticksPerPixel: endTime / width,
    panOffsetTicks: 0,
  );

  group('digital bus rendered as analog', () {
    test('a hex-formatted bus plots its magnitude, not its digits', () {
      final points = AnalogSignalPainter.debugBuildPoints(
        changes: const [
          SignalChange(time: 250, value: '00001111'), // 15
          SignalChange(time: 500, value: '11111111'), // 255
          SignalChange(time: 750, value: '10000000'), // 128
        ],
        valueAtStart: '00000000',
        timeMapper: mapper(),
        xMin: 0,
        xMax: 1000,
        valueExtractor: AnalogValueExtractors.forDigitalLane(
          bitWidth: 8,
          format: DisplayFormat.hexadecimal,
        ),
      );

      expect(points.map((p) => p.value).toList(), [0, 15, 255, 128]);
    });

    test('the same bits under Q4.12 plot a different curve', () {
      // This is the whole reason the toggle is orthogonal to the format: the
      // shape of the curve depends on how the bits are read as a number.
      const changes = [
        SignalChange(time: 250, value: '0001100000000000'), // 6144 raw
        SignalChange(time: 500, value: '1110100000000000'), // -6144 raw
      ];

      final asHex = AnalogSignalPainter.debugBuildPoints(
        changes: changes,
        valueAtStart: null,
        timeMapper: mapper(),
        xMin: 0,
        xMax: 1000,
        valueExtractor: AnalogValueExtractors.forDigitalLane(
          bitWidth: 16,
          format: DisplayFormat.hexadecimal,
        ),
      );
      final asQ = AnalogSignalPainter.debugBuildPoints(
        changes: changes,
        valueAtStart: null,
        timeMapper: mapper(),
        xMin: 0,
        xMax: 1000,
        valueExtractor: AnalogValueExtractors.forDigitalLane(
          bitWidth: 16,
          format: DisplayFormat.fixedPointQ,
          config: const {'m': 4, 'n': 12, 'signed': true},
        ),
      );

      expect(asHex.map((p) => p.value).toList(), [6144, 59392]);
      expect(asQ.map((p) => p.value).toList(), [1.5, -1.5]);
    });

    test('x and z runs become gaps, never zeros', () {
      final points = AnalogSignalPainter.debugBuildPoints(
        changes: const [
          SignalChange(time: 250, value: 'xxxxxxxx'),
          SignalChange(time: 500, value: 'zzzzzzzz'),
          SignalChange(time: 750, value: '00000001'),
        ],
        valueAtStart: '11111111',
        timeMapper: mapper(),
        xMin: 0,
        xMax: 1000,
        valueExtractor: AnalogValueExtractors.forDigitalLane(
          bitWidth: 8,
          format: DisplayFormat.unsignedDecimal,
        ),
      );

      expect(points[0].value, 255);
      expect(points[1].value, isNaN);
      expect(points[2].value, isNaN);
      expect(points[3].value, 1);
      // The failure this guards: a gap rendered as 0 sits on the axis and is
      // indistinguishable from a real zero sample.
      expect(points.where((p) => p.value == 0), isEmpty);
    });

    test('signed buses cross zero rather than wrapping to a huge positive', () {
      final points = AnalogSignalPainter.debugBuildPoints(
        changes: const [
          SignalChange(time: 250, value: '111111111111'), // -1
          SignalChange(time: 500, value: '100000000000'), // -2048
          SignalChange(time: 750, value: '011111111111'), // +2047
        ],
        valueAtStart: '000000000000',
        timeMapper: mapper(),
        xMin: 0,
        xMax: 1000,
        valueExtractor: AnalogValueExtractors.forDigitalLane(
          bitWidth: 12,
          format: DisplayFormat.signedDecimal,
        ),
      );

      expect(points.map((p) => p.value).toList(), [0, -1, -2048, 2047]);
    });
  });

  group('real-valued signals are unaffected', () {
    test('the default extractor is still the real parse', () {
      // No valueExtractor passed — exactly how every existing call site looks.
      final points = AnalogSignalPainter.debugBuildPoints(
        changes: const [
          SignalChange(time: 250, value: '2.5'),
          SignalChange(time: 500, value: '-1.25'),
          SignalChange(time: 750, value: 'x'),
        ],
        valueAtStart: '0.0',
        timeMapper: mapper(),
        xMin: 0,
        xMax: 1000,
      );

      expect(points[0].value, 0.0);
      expect(points[1].value, 2.5);
      expect(points[2].value, -1.25);
      expect(points[3].value, isNaN);
    });

    test('a real signal read through the digital extractor still works', () {
      // Belt and braces: `renderAsAnalog` on a real signal is documented as a
      // no-op, but if a caller ever did build a digital extractor for one, the
      // real literal must still parse rather than being read as bits.
      final extract = AnalogValueExtractors.forDigitalLane(
        bitWidth: 0,
        format: DisplayFormat.hexadecimal,
      );
      expect(extract('3.14'), closeTo(3.14, 1e-9));
    });
  });
}
