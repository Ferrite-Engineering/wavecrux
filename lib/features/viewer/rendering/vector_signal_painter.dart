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
        final filtered = translateFilter?.translate(normalised);
        final label =
            filtered ??
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
          stripLeadingZeros: filtered == null && isRadixNumeral(label, format),
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
    TextStyle valueStyle, {
    required bool stripLeadingZeros,
  }) {
    final path = _parallelogramPath(x0, x1, yTop, yBot, slant);

    _normalFillPaint.color = color.withValues(alpha: 0.18);
    _normalStrokePaint.color = color;

    canvas
      ..drawPath(path, _normalFillPaint)
      ..drawPath(path, _normalStrokePaint);

    final innerWidth = x1 - x0 - slant * 2 - 4;
    if (innerWidth > _minLabelWidth && label.isNotEmpty) {
      _paintLabel(
        canvas,
        label,
        x0,
        x1,
        yMid,
        innerWidth,
        valueStyle,
        color,
        stripLeadingZeros: stripLeadingZeros,
      );
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

  /// Shared label painter, re-laid out per candidate rather than allocated
  /// per segment. Painting is single-threaded, so one instance is enough.
  static final TextPainter _labelPainter = TextPainter(
    textDirection: TextDirection.ltr,
  );

  static void _paintLabel(
    Canvas canvas,
    String label,
    double x0,
    double x1,
    double yMid,
    double maxWidth,
    TextStyle style,
    Color color, {
    required bool stripLeadingZeros,
  }) {
    final textStyle = style.copyWith(color: color);
    final tp = _labelPainter;
    String? laidOut;
    double measure(String text) {
      tp
        ..text = TextSpan(text: text, style: textStyle)
        ..layout();
      laidOut = text;
      return tp.width;
    }

    // Measured unconstrained: a `maxWidth` layout clips the text to fit and
    // reports the clipped width, which is how an overflowing label used to
    // draw its leading digits with nothing to say that any were missing.
    final fitted = fitBusLabel(
      label,
      maxWidth: maxWidth,
      measure: measure,
      stripLeadingZeros: stripLeadingZeros,
    );
    if (fitted == null) return;
    if (laidOut != fitted) measure(fitted);

    final textX = (x0 + x1) / 2.0 - tp.width / 2.0;
    final textY = yMid - tp.height / 2.0;
    tp.paint(canvas, Offset(textX, textY));
  }

  /// Whether [label] is a bare numeral in [format]'s radix — the only kind of
  /// label whose leading zeros [fitBusLabel] may drop.
  ///
  /// The built-in formatter renders binary, octal and hex without a radix
  /// prefix (`00000200`, not `0x00000200`). A label carrying a prefix, a sign,
  /// or anything else outside the radix's digits is left whole, so a
  /// translator that renders `0x…` never loses the `0` of its prefix.
  @visibleForTesting
  static bool isRadixNumeral(String label, DisplayFormat format) {
    if (label.isEmpty) return false;
    final isDigit = switch (format) {
      DisplayFormat.binary => _isBinaryDigit,
      DisplayFormat.octal => _isOctalDigit,
      DisplayFormat.hexadecimal => _isHexDigit,
      DisplayFormat.unsignedDecimal ||
      DisplayFormat.signedDecimal ||
      DisplayFormat.ascii ||
      DisplayFormat.ieee754Single ||
      DisplayFormat.ieee754Double ||
      DisplayFormat.fixedPointQ ||
      DisplayFormat.signedMagnitude ||
      DisplayFormat.grayCode ||
      DisplayFormat.namedEnum => null,
    };
    if (isDigit == null) return false;
    for (var i = 0; i < label.length; i++) {
      if (!isDigit(label.codeUnitAt(i))) return false;
    }
    return true;
  }

  static bool _isBinaryDigit(int c) => c == 0x30 || c == 0x31;

  static bool _isOctalDigit(int c) => c >= 0x30 && c <= 0x37;

  static bool _isHexDigit(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x61 && c <= 0x66) ||
      (c >= 0x41 && c <= 0x46);
}

/// The label text to draw for a bus segment whose label area is [maxWidth]
/// wide, or `null` when no truthful label fits.
///
/// A bus value that does not fit must never be drawn as a different number,
/// so this never drops a digit silently. In order, it tries:
///
/// 1. [label] as is.
/// 2. With [stripLeadingZeros] (set only for a bare binary, octal or hex
///    numeral), [label] without its leading zeros, keeping at least one
///    digit: `00000200` → `200`, `0000000000000000` → `0`.
/// 3. The least significant characters behind a leading `…`, as many as fit:
///    `12345678` → `…5678`. The trailing digits are the ones that change
///    from one value to the next, so they are the ones worth keeping.
/// 4. Nothing, when not even `…` and one character fit.
///
/// [measure] returns the rendered width of a string. The painter passes a
/// [TextPainter] layout; it is a parameter so this stays a pure function.
/// The `…` search starts from a per-character estimate and steps from there,
/// so a monospace label costs two or three measurements, not one per digit.
String? fitBusLabel(
  String label, {
  required double maxWidth,
  required double Function(String text) measure,
  bool stripLeadingZeros = false,
}) {
  if (label.isEmpty) return null;
  var width = measure(label);
  if (width <= maxWidth) return label;

  var text = label;
  if (stripLeadingZeros) {
    var i = 0;
    while (i < text.length - 1 && text.codeUnitAt(i) == 0x30) {
      i++;
    }
    if (i > 0) {
      text = text.substring(i);
      width = measure(text);
      if (width <= maxWidth) return text;
    }
  }

  // `…` plus every character is wider than [text], which did not fit, so at
  // most `length - 1` characters can follow the ellipsis.
  final maxKeep = text.length - 1;
  if (maxKeep < 1) return null;
  String truncated(int keep) =>
      '$_kEllipsis${text.substring(text.length - keep)}';

  // Estimate, treating the ellipsis as one character wide, then correct.
  final perChar = width / text.length;
  var keep = (maxWidth / perChar).floor() - 1;
  if (keep > maxKeep) keep = maxKeep;
  if (keep < 1) keep = 1;
  while (keep >= 1 && measure(truncated(keep)) > maxWidth) {
    keep--;
  }
  if (keep < 1) return null;
  while (keep < maxKeep && measure(truncated(keep + 1)) <= maxWidth) {
    keep++;
  }
  return truncated(keep);
}

const String _kEllipsis = '\u2026';

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
