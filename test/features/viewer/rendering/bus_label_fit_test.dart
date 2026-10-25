// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Issue #49: a bus label too wide for its lane drew its leading digits, with
// no ellipsis, so a narrow lane could read as a different number.

import 'dart:ui';

import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/features/viewer/rendering/vector_signal_painter.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// Monospace stand-in: every character, `…` included, is 10 px wide.
double _mono(String s) => s.runes.length * 10.0;

void main() {
  group('fitBusLabel', () {
    test('a label that fits is drawn whole', () {
      expect(fitBusLabel('12345678', maxWidth: 80, measure: _mono), '12345678');
      expect(
        fitBusLabel(
          '00000200',
          maxWidth: 80,
          measure: _mono,
          stripLeadingZeros: true,
        ),
        '00000200',
        reason: 'leading zeros are only dropped when the label overflows',
      );
    });

    test('an empty label draws nothing', () {
      expect(fitBusLabel('', maxWidth: 80, measure: _mono), isNull);
    });

    test('keeps the trailing digits behind a leading ellipsis', () {
      expect(fitBusLabel('12345678', maxWidth: 50, measure: _mono), '…5678');
      expect(fitBusLabel('12345678', maxWidth: 59, measure: _mono), '…5678');
      expect(fitBusLabel('12345678', maxWidth: 79, measure: _mono), '…345678');
    });

    test('drops leading zeros before truncating a radix numeral', () {
      // The issue's 32-bit rd_wdata, previously shown as `0000200`.
      expect(
        fitBusLabel(
          '00000200',
          maxWidth: 30,
          measure: _mono,
          stripLeadingZeros: true,
        ),
        '200',
      );
      // The issue's 64-bit order, previously shown as fifteen zeros.
      expect(
        fitBusLabel(
          '0000000000000000',
          maxWidth: 20,
          measure: _mono,
          stripLeadingZeros: true,
        ),
        '0',
      );
    });

    test('truncates the stripped numeral when it still overflows', () {
      expect(
        fitBusLabel(
          '0012345678',
          maxWidth: 50,
          measure: _mono,
          stripLeadingZeros: true,
        ),
        '…5678',
      );
    });

    test('keeps leading zeros when stripping is not allowed', () {
      expect(fitBusLabel('00000200', maxWidth: 30, measure: _mono), '…00');
    });

    test('draws nothing when not even the ellipsis and one digit fit', () {
      expect(fitBusLabel('12345678', maxWidth: 20, measure: _mono), '…8');
      expect(fitBusLabel('12345678', maxWidth: 19, measure: _mono), isNull);
      expect(fitBusLabel('7', maxWidth: 5, measure: _mono), isNull);
      expect(
        fitBusLabel(
          '00',
          maxWidth: 5,
          measure: _mono,
          stripLeadingZeros: true,
        ),
        isNull,
      );
    });

    test('a proportional font still gets the longest tail that fits', () {
      // `1` is narrow, `…` is wide: the per-character estimate is off, and
      // the search must correct it in both directions.
      double proportional(String s) {
        var w = 0.0;
        for (final r in s.runes) {
          w += switch (r) {
            0x31 => 4.0, // '1'
            0x2026 => 14.0, // '…'
            _ => 9.0,
          };
        }
        return w;
      }

      const label = '9911119911119999';
      for (var maxWidth = 1.0; maxWidth < 160; maxWidth += 1) {
        final fitted = fitBusLabel(
          label,
          maxWidth: maxWidth,
          measure: proportional,
        );
        // Reference: the longest tail that fits, found by brute force.
        String? expected;
        if (proportional(label) <= maxWidth) {
          expected = label;
        } else {
          for (var keep = label.length - 1; keep >= 1; keep--) {
            final c = '…${label.substring(label.length - keep)}';
            if (proportional(c) <= maxWidth) {
              expected = c;
              break;
            }
          }
        }
        expect(fitted, expected, reason: 'maxWidth $maxWidth');
      }
    });

    test('costs a handful of measurements, not one per digit', () {
      var calls = 0;
      double counting(String s) {
        calls++;
        return _mono(s);
      }

      final fitted = fitBusLabel(
        '1' * 64,
        maxWidth: 200,
        measure: counting,
      );
      expect(fitted, '…${'1' * 19}');
      expect(calls, lessThanOrEqualTo(4));
    });
  });

  group('VectorSignalPainter.isRadixNumeral', () {
    test('bare numerals in the format radix', () {
      expect(
        VectorSignalPainter.isRadixNumeral(
          '00ff',
          DisplayFormat.hexadecimal,
        ),
        isTrue,
      );
      expect(
        VectorSignalPainter.isRadixNumeral(
          '00FF',
          DisplayFormat.hexadecimal,
        ),
        isTrue,
      );
      expect(
        VectorSignalPainter.isRadixNumeral('0010', DisplayFormat.binary),
        isTrue,
      );
      expect(
        VectorSignalPainter.isRadixNumeral('0017', DisplayFormat.octal),
        isTrue,
      );
    });

    test('anything else is left whole', () {
      // A radix prefix keeps its `0`.
      expect(
        VectorSignalPainter.isRadixNumeral(
          '0x00ff',
          DisplayFormat.hexadecimal,
        ),
        isFalse,
      );
      expect(
        VectorSignalPainter.isRadixNumeral('0012', DisplayFormat.binary),
        isFalse,
      );
      expect(
        VectorSignalPainter.isRadixNumeral('0018', DisplayFormat.octal),
        isFalse,
      );
      expect(
        VectorSignalPainter.isRadixNumeral(
          '00012',
          DisplayFormat.unsignedDecimal,
        ),
        isFalse,
      );
      expect(
        VectorSignalPainter.isRadixNumeral('00', DisplayFormat.namedEnum),
        isFalse,
      );
      expect(
        VectorSignalPainter.isRadixNumeral('', DisplayFormat.hexadecimal),
        isFalse,
      );
    });
  });

  group('VectorSignalPainter label painting', () {
    // The test font draws every glyph 1 em wide: 11 px at this size.
    const style = TextStyle(fontSize: 11);
    const glyph = 11.0;

    /// Paints a bus whose first segment spans `[0, segmentWidth)` px and
    /// returns the unconstrained width of the label drawn for that segment,
    /// or null if none was drawn.
    ///
    /// The segment's label area is `segmentWidth - 14` px: a 5 px slant on
    /// each side plus 4 px of padding.
    double? firstLabel({
      required String value,
      required double segmentWidth,
      int bitWidth = 32,
    }) {
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 1000,
        ticksPerPixel: 1,
        panOffsetTicks: 0,
      );
      final canvas = _RecordingCanvas();
      VectorSignalPainter.paint(
        canvas: canvas,
        laneBounds: const Rect.fromLTWH(0, 0, 1000, 30),
        changes: [
          SignalChange(time: segmentWidth.toInt(), value: 'b${'1' * bitWidth}'),
        ],
        valueAtStart: value,
        timeMapper: mapper,
        signalColor: const Color(0xFF00FF00),
        xColor: const Color(0xFFFF0000),
        xHatchColor: const Color(0x80FF0000),
        zColor: const Color(0xFF0000FF),
        format: DisplayFormat.hexadecimal,
        bitWidth: bitWidth,
        valueStyle: style,
      );
      final first = canvas.paragraphs.where(
        (p) => p.offset.dx < segmentWidth,
      );
      return first.isEmpty ? null : first.single.width;
    }

    String bits(int value, int width) =>
        'b${value.toRadixString(2).padLeft(width, '0')}';

    test('a label that fits is drawn whole', () {
      final width = firstLabel(
        value: bits(0x12345678, 32),
        segmentWidth: 8 * glyph + 14 + 2,
      );
      expect(width, 8 * glyph);
    });

    test('an overflowing label never draws wider than its area', () {
      const segmentWidth = 74.0; // 60 px label area
      final width = firstLabel(
        value: bits(0x12345678, 32),
        segmentWidth: segmentWidth,
      );
      expect(width, isNotNull);
      // Unconstrained width of what is drawn: the old code laid out at
      // `maxWidth`, so all eight digits sat in the paragraph and only the
      // leading ones showed.
      expect(width, lessThanOrEqualTo(segmentWidth - 14));
      // The ellipsis plus at least the four least significant digits.
      expect(width, greaterThanOrEqualTo(4 * glyph));
    });

    test('a hex value drops its leading zeros before truncating', () {
      final width = firstLabel(
        value: bits(0x200, 32), // `00000200`
        segmentWidth: 74, // 60 px: room for 5 glyphs, not 8
      );
      expect(width, 3 * glyph, reason: 'draws `200`');
    });

    test('no label when not even the ellipsis and one digit fit', () {
      final width = firstLabel(
        value: bits(0x12345678, 32),
        segmentWidth: 35, // 21 px: above the 18 px minimum, under 2 glyphs
      );
      expect(width, isNull);
    });
  });
}

/// Records `drawParagraph`; every other canvas call is accepted and ignored.
///
/// The paragraph's unconstrained width is read at draw time: the painter
/// reuses one `TextPainter`, which disposes the paragraph on its next layout.
class _RecordingCanvas implements Canvas {
  final List<({double width, Offset offset})> paragraphs = [];

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    paragraphs.add((width: paragraph.maxIntrinsicWidth, offset: offset));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
