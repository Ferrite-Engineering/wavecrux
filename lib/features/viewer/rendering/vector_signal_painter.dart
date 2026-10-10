// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/features/viewer/rendering/visible_changes.dart';
import 'package:wavecrux/services/translate/translate_filter_service.dart';
import 'package:wavecrux/services/value_format/builtin_value_translator.dart';
import 'package:wavecrux/services/waveform/display_changes.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// Paints a multi-bit bus signal lane onto a [Canvas].
///
/// Each stable-value period is rendered as a parallelogram (angled left and
/// right edges) with the formatted value label centred inside.  Value states:
///
/// - Normal binary value: semi-transparent fill + full-opacity outline + text.
/// - Unknown ('x'): red hatched fill.
/// - High-impedance ('z'): dashed outline, no fill.
///
/// Very narrow periods (< [_minLabelWidth]) still render the shape but omit
/// the text label.
abstract final class VectorSignalPainter {
  /// Minimum segment pixel width at which a value label is attempted.
  static const double _minLabelWidth = 18;

  /// Horizontal slant amount for the parallelogram edges, in logical pixels.
  static const double _slant = 5;

  /// Vertical margin from the lane top/bottom to the waveform shape.
  static const double _vMargin = 3;

  // Reusable Paint objects mutated per call. Avoids ~5 Paint allocations per
  // bus segment per frame on canvases with many bus signals.
  static final Paint _normalFillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _normalStrokePaint = Paint()
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;
  static final Paint _xFillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _xStrokePaint = Paint()
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;
  static final Paint _hatchPaint = Paint()
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;
  static final Paint _zPaint = Paint()
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;

  // ── public API ───────────────────────────────────────────────────────────────

  /// Paints the bus waveform for a multi-bit signal into [laneBounds].
  ///
  /// [bitWidth] is used by the [Translator] to correctly format values.
  /// [valueStyle] should use a monospace font (e.g. JetBrains Mono).
  ///
  /// [translator] resolves raw values to display text. Defaults to the built-in
  /// translator (byte-identical to the legacy `ValueFormatService`); callers
  /// that have a per-signal translator binding (Stage 1+) pass the resolved
  /// translator from the registry. This is a parameter — not a Riverpod read —
  /// because the painter runs inside a `RenderObject`.
  static void paint({
    required Canvas canvas,
    required Rect laneBounds,
    required List<SignalChange> changes,
    required String? valueAtStart,
    required TimeMapper timeMapper,
    required Color signalColor,
    required Color xColor,
    required Color xHatchColor,
    required Color zColor,
    required DisplayFormat format,
    required int bitWidth,
    required TextStyle valueStyle,
    TranslateFilter? translateFilter,
    Map<String, Object?>? translatorConfig,
    Translator? translator,
    double lineWidthScale = 1.0,
  }) {
    if (changes.isEmpty && valueAtStart == null) return;

    // Legibility scale (1.0 = default). Thickens the bus-segment outlines,
    // x-hatch, and z-line so buses stay readable on far-viewed / XR displays.
    // Set per call because the Paint objects are shared statics.
    _normalStrokePaint.strokeWidth = 1.0 * lineWidthScale;
    _xStrokePaint.strokeWidth = 1.0 * lineWidthScale;
    _hatchPaint.strokeWidth = 1.0 * lineWidthScale;
    _zPaint.strokeWidth = 1.5 * lineWidthScale;

    final segments = _buildSegments(
      changes,
      valueAtStart,
      timeMapper,
      laneBounds.left,
      laneBounds.right,
    );
    if (segments.isEmpty) return;

    final yTop = laneBounds.top + _vMargin;
    final yBot = laneBounds.bottom - _vMargin;
    final yMid = (yTop + yBot) / 2.0;

    final activeTranslator = translator ?? const BuiltinValueTranslator();

    canvas
      ..save()
      ..clipRect(laneBounds);

    for (final seg in segments) {
      final x0 = seg.xStart;
      final x1 = seg.xEnd;
      final width = x1 - x0;
      if (width <= 0) continue;

      // Strip leading 'b' / 'B' from the VCD raw value without allocating a
      // new RegExp per segment. lowercase() is required for x/z detection
      // since VCD permits 'X', 'Z' as well as 'x', 'z'.
      final lowered = seg.value.toLowerCase();
      final normalised = (lowered.isNotEmpty && lowered.codeUnitAt(0) == 0x62)
          ? lowered.substring(1)
          : lowered;
      final isX = normalised.isNotEmpty && normalised.contains('x');
      final isZ = !isX && normalised.isNotEmpty && normalised.contains('z');

      final slant = math.min(_slant, width / 4.0);

      if (isX) {
        _paintXSegment(canvas, x0, x1, yTop, yBot, slant, xColor, xHatchColor);
      } else if (isZ) {
        _paintZSegment(canvas, x0, x1, yTop, yBot, yMid, slant, zColor);
      } else {
        // Try translate filter before falling back to numeric format.
        final label =
            translateFilter?.translate(normalised) ??
            (bitWidth > 0
                ? activeTranslator
                      .translate(
                        TranslationRequest(
                          rawValue: seg.value,
                          bitWidth: bitWidth,
                          format: format,
                          config: translatorConfig,
                        ),
                      )
                      .text
                : seg.value);
        _paintNormalSegment(
          canvas,
          x0,
          x1,
          yTop,
          yBot,
          yMid,
          slant,
          signalColor,
          label,
          valueStyle,
        );
      }
    }

    canvas.restore();
  }

  // ── segment builder ──────────────────────────────────────────────────────────

  /// Builds an ordered list of constant-value segments across the visible lane.
  ///
  /// Transitions falling within the same integer pixel column are coalesced:
  /// the segment count is bounded by viewport width, not transition count.
  /// X states are sticky — any sub-pixel X within a column promotes the column
  /// to render as X so brief X glitches remain visible. A same-value
  /// sub-pixel burst (A→B→A inside a column) still starts a fresh segment at
  /// that column, so its slanted edges mark where the bus moved.
  ///
  /// [changes] may start before the viewport; see
  /// [firstChangeAtOrAfterPixel].
  static List<_Segment> _buildSegments(
    List<SignalChange> changes,
    String? initialValue,
    TimeMapper timeMapper,
    double xMin,
    double xMax,
  ) {
    final segments = <_Segment>[];
    final view = DisplayChanges.of(changes);
    final first = firstChangeAtOrAfterPixel(view, timeMapper, xMin);
    var currentValue = first > 0 ? view.valueAt(first - 1) : initialValue;
    var currentX = xMin;
    var currentCol = xMin.floor();

    for (var i = first; i < view.length; i++) {
      final value = view.valueAt(i);
      final x = timeMapper.timeToPixel(view.timeAt(i)).clamp(xMin, xMax);
      final col = x.floor();
      if (col <= currentCol) {
        // Same pixel column — coalesce. Promote to X if seen.
        if (_hasXState(value)) {
          currentValue = value;
        } else if (currentValue == null || !_hasXState(currentValue)) {
          currentValue = value;
        }
        continue;
      }
      if (currentValue != null) {
        segments.add(_Segment(xStart: currentX, xEnd: x, value: currentValue));
      }
      currentValue = value;
      currentX = x;
      currentCol = col;
      if (currentX >= xMax) break;
    }

    if (currentValue != null && currentX < xMax) {
      segments.add(_Segment(xStart: currentX, xEnd: xMax, value: currentValue));
    }

    return segments;
  }

  /// True if [value] contains an `x`/`X` character — used to keep sub-pixel
  /// X glitches visible after coalescing.
  static bool _hasXState(String value) {
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (c == 0x78 || c == 0x58) return true;
    }
    return false;
  }

  // ── test seam ───────────────────────────────────────────────────────────────

  /// Test-only window onto [_buildSegments].
  @visibleForTesting
  static List<({double xStart, double xEnd, String value})> debugBuildSegments({
    required List<SignalChange> changes,
    required String? valueAtStart,
    required TimeMapper timeMapper,
    required double xMin,
    required double xMax,
  }) {
    final raw = _buildSegments(changes, valueAtStart, timeMapper, xMin, xMax);
    return [
      for (final s in raw) (xStart: s.xStart, xEnd: s.xEnd, value: s.value),
    ];
  }

  // ── per-segment painters ─────────────────────────────────────────────────────

  static void _paintNormalSegment(
    Canvas canvas,
    double x0,
    double x1,
    double yTop,
    double yBot,
    double yMid,
    double slant,
    Color color,
    String label,
    TextStyle valueStyle,
  ) {
    final path = _parallelogramPath(x0, x1, yTop, yBot, slant);

    _normalFillPaint.color = color.withValues(alpha: 0.18);
    _normalStrokePaint.color = color;

    canvas
      ..drawPath(path, _normalFillPaint)
      ..drawPath(path, _normalStrokePaint);

    final innerWidth = x1 - x0 - slant * 2 - 4;
    if (innerWidth > _minLabelWidth && label.isNotEmpty) {
      _paintLabel(canvas, label, x0, x1, yMid, innerWidth, valueStyle, color);
    }
  }

  static void _paintXSegment(
    Canvas canvas,
    double x0,
    double x1,
    double yTop,
    double yBot,
    double slant,
    Color xColor,
    Color xHatchColor,
  ) {
    final path = _parallelogramPath(x0, x1, yTop, yBot, slant);

    _xFillPaint.color = xColor.withValues(alpha: 0.25);
    _xStrokePaint.color = xColor;
    _hatchPaint.color = xHatchColor;

    canvas
      ..drawPath(path, _xFillPaint)
      ..save()
      ..clipPath(path);

    const spacing = 6.0;
    final h = yBot - yTop;
    var startX = x0 - slant - h;
    while (startX < x1 + slant) {
      canvas.drawLine(
        Offset(startX, yTop),
        Offset(startX + h, yBot),
        _hatchPaint,
      );
      startX += spacing;
    }

    canvas
      ..restore()
      ..drawPath(path, _xStrokePaint);
  }

  static void _paintZSegment(
    Canvas canvas,
    double x0,
    double x1,
    double yTop,
    double yBot,
    double yMid,
    double slant,
    Color zColor,
  ) {
    const dashLen = 6.0;
    const gapLen = 3.0;

    final paint = _zPaint..color = zColor;

    _drawDashedLine(
      canvas,
      Offset(x0 + slant, yTop),
      Offset(x1 - slant, yTop),
      dashLen,
      gapLen,
      paint,
    );
    _drawDashedLine(
      canvas,
      Offset(x0 - slant, yBot),
      Offset(x1 + slant, yBot),
      dashLen,
      gapLen,
      paint,
    );

    canvas
      ..drawLine(Offset(x0 + slant, yTop), Offset(x0 - slant, yBot), paint)
      ..drawLine(Offset(x1 - slant, yTop), Offset(x1 + slant, yBot), paint);

    _drawDashedLine(
      canvas,
      Offset(x0, yMid),
      Offset(x1, yMid),
      dashLen,
      gapLen,
      paint,
    );
  }

  // ── geometry helpers ─────────────────────────────────────────────────────────

  static Path _parallelogramPath(
    double x0,
    double x1,
    double yTop,
    double yBot,
    double slant,
  ) => Path()
    ..moveTo(x0 + slant, yTop)
    ..lineTo(x1 - slant, yTop)
    ..lineTo(x1 + slant, yBot)
    ..lineTo(x0 - slant, yBot)
    ..close();

  static void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    double dashLen,
    double gapLen,
    Paint paint,
  ) {
    final total = (end - start).distance;
    if (total <= 0) return;
    final dir = (end - start) / total;
    var dist = 0.0;
    while (dist < total) {
      final segEnd = math.min(dist + dashLen, total);
      canvas.drawLine(start + dir * dist, start + dir * segEnd, paint);
      dist += dashLen + gapLen;
    }
  }

  static void _paintLabel(
    Canvas canvas,
    String label,
    double x0,
    double x1,
    double yMid,
    double maxWidth,
    TextStyle style,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: style.copyWith(color: color),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);

    if (tp.width > maxWidth) return;

    final textX = (x0 + x1) / 2.0 - tp.width / 2.0;
    final textY = yMid - tp.height / 2.0;
    tp.paint(canvas, Offset(textX, textY));
  }
}

/// A constant-value time segment with pixel x-coordinates.
final class _Segment {
  const _Segment({
    required this.xStart,
    required this.xEnd,
    required this.value,
  });

  final double xStart;
  final double xEnd;
  final String value;
}
