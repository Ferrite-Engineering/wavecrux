// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/features/viewer/rendering/visible_changes.dart';
import 'package:wavecrux/services/waveform/display_changes.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// Paints a 1-bit digital signal lane onto a [Canvas].
///
/// Rendering conventions (GTKWave-compatible):
/// - High ('1'): horizontal line near the top of the lane.
/// - Low ('0'): horizontal line near the bottom of the lane.
/// - Unknown ('x'): red filled rectangle with diagonal hatch lines.
/// - High-impedance ('z'): dashed horizontal line at the lane centre.
/// - Vertical edges are drawn at every value transition.
abstract final class ScalarSignalPainter {
  // Reusable Paint objects — colors are mutated per call. Avoids ~3 Paint
  // allocations per signal lane per frame (a ~3000 alloc/frame win for a
  // 1000-signal canvas).
  static final Paint _linePaint = Paint()
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.butt;

  static final Paint _edgePaint = Paint()
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.butt;

  static final Paint _xFillPaint = Paint()..style = PaintingStyle.fill;

  static final Paint _hatchPaint = Paint()
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;

  static final Paint _zPaint = Paint()
    ..strokeWidth = 2.0
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.butt;

  // ── public API ───────────────────────────────────────────────────────────────

  /// Paints the waveform for a 1-bit signal into [laneBounds].
  ///
  /// [changes] must be ordered by ascending time and cover the visible range;
  /// they may start before it. [valueAtStart] is the signal's value just
  /// before the first of [changes] (from [WaveformDataSource.valueAt]); pass
  /// null if the signal has no value before the first change.
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
    double lineWidthScale = 1.0,
  }) {
    if (changes.isEmpty && valueAtStart == null) return;

    // Legibility scale (1.0 = default). Thickens the trace, transition edges,
    // and hatch so a 1-bit lane stays readable at the low angular resolution
    // of XR/AR glasses and other large, far-viewed displays. Set per call
    // because the Paint objects are shared statics.
    _linePaint.strokeWidth = 1.5 * lineWidthScale;
    _edgePaint.strokeWidth = 1.0 * lineWidthScale;
    _hatchPaint.strokeWidth = 1.0 * lineWidthScale;
    _zPaint.strokeWidth = 2.0 * lineWidthScale;

    final glitches = <double>[];
    final segments = _buildSegments(
      changes,
      valueAtStart,
      timeMapper,
      laneBounds.left,
      laneBounds.right,
      glitches,
    );
    if (segments.isEmpty) return;

    // Vertical margins keep high/low lines away from the lane border.
    const vMargin = 4.0;
    final yTop = laneBounds.top + vMargin;
    final yBot = laneBounds.bottom - vMargin;
    final yMid = (laneBounds.top + laneBounds.bottom) / 2.0;

    final linePaint = _linePaint..color = signalColor;
    final edgePaint = _edgePaint..color = signalColor;

    // Save and clip so painters can't bleed into adjacent lanes.
    canvas
      ..save()
      ..clipRect(laneBounds);

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final x0 = seg.xStart;
      final x1 = seg.xEnd;
      if (x1 <= x0) continue;

      switch (seg.value) {
        case '1':
          canvas.drawLine(Offset(x0, yTop), Offset(x1, yTop), linePaint);
        case '0':
          canvas.drawLine(Offset(x0, yBot), Offset(x1, yBot), linePaint);
        case 'z':
          _paintZState(canvas, x0, x1, yMid, zColor);
        default:
          // 'x' or any unrecognised value.
          _paintXState(
            canvas,
            Rect.fromLTRB(x0, laneBounds.top, x1, laneBounds.bottom),
            xColor,
            xHatchColor,
          );
      }

      // Vertical transition edge between this segment and the previous one.
      if (i > 0) {
        final prev = segments[i - 1];
        final transX = x0;
        final fromY = _yLevel(prev.value, yTop, yBot, yMid);
        final toY = _yLevel(seg.value, yTop, yBot, yMid);

        if (fromY != null && toY != null) {
          canvas.drawLine(
            Offset(transX, fromY),
            Offset(transX, toY),
            edgePaint,
          );
        } else {
          // Transition involves x state — draw a full-height edge.
          canvas.drawLine(
            Offset(transX, laneBounds.top),
            Offset(transX, laneBounds.bottom),
            edgePaint,
          );
        }
      }
    }

    // A column the value left and came back to inside one pixel: the segment
    // walk above coalesced it to a single level, so mark it full height. This
    // is what keeps a sub-pixel pulse on screen (at least one pixel wide)
    // instead of vanishing into the level it returned to.
    for (final x in glitches) {
      canvas.drawLine(Offset(x, yTop), Offset(x, yBot), edgePaint);
    }

    canvas.restore();
  }

  // ── test seam ───────────────────────────────────────────────────────────────

  /// Test-only window onto [_buildSegments]. Returns each segment as a record
  /// of `(xStart, xEnd, value)` so tests can assert pixel-column coalescing
  /// without taking a dependency on the private `_Segment` type.
  @visibleForTesting
  static List<({double xStart, double xEnd, String value})> debugBuildSegments({
    required List<SignalChange> changes,
    required String? valueAtStart,
    required TimeMapper timeMapper,
    required double xMin,
    required double xMax,
  }) {
    final raw = _buildSegments(
      changes,
      valueAtStart,
      timeMapper,
      xMin,
      xMax,
      <double>[],
    );
    return [
      for (final s in raw) (xStart: s.xStart, xEnd: s.xEnd, value: s.value),
    ];
  }

  /// Test-only window onto the glitch columns [_buildSegments] reports: the
  /// x of every pixel column in which the value changed more than once.
  @visibleForTesting
  static List<double> debugGlitchColumns({
    required List<SignalChange> changes,
    required String? valueAtStart,
    required TimeMapper timeMapper,
    required double xMin,
    required double xMax,
  }) {
    final glitches = <double>[];
    _buildSegments(changes, valueAtStart, timeMapper, xMin, xMax, glitches);
    return glitches;
  }

  // ── internal helpers ─────────────────────────────────────────────────────────

  /// Returns the y-coordinate for the horizontal line of [value], or null
  /// for 'x' (which spans the full lane height).
  static double? _yLevel(
    String value,
    double yTop,
    double yBot,
    double yMid,
  ) {
    return switch (value) {
      '0' => yBot,
      '1' => yTop,
      'z' => yMid,
      _ => null,
    };
  }

  /// Builds an ordered list of constant-value segments across the visible lane.
  ///
  /// Transitions falling within the same integer pixel column are coalesced:
  /// the segment count is bounded by viewport width, not transition count.
  /// X states are sticky — any sub-pixel X within a column promotes the
  /// column to render as X so brief X glitches remain visible.
  /// A column in which the value changed more than once (a 0→1→0 burst
  /// narrower than a pixel) coalesces to one level here, so its x is added
  /// to [glitches] and painted as a full-height mark: a sub-pixel pulse must
  /// still show as at least one pixel.
  ///
  /// [changes] may start before the viewport (the canvas caches a range
  /// wider than the view so a pan does not refetch): changes left of [xMin]
  /// only set the value entering the viewport, exactly as [initialValue]
  /// would have.
  static List<_Segment> _buildSegments(
    List<SignalChange> changes,
    String? initialValue,
    TimeMapper timeMapper,
    double xMin,
    double xMax,
    List<double> glitches,
  ) {
    final segments = <_Segment>[];
    final view = DisplayChanges.of(changes);
    final first = firstChangeAtOrAfterPixel(view, timeMapper, xMin);
    var currentValue = first > 0 ? view.valueAt(first - 1) : initialValue;
    var currentX = xMin;
    var currentCol = xMin.floor();
    // The previous change's value while it sits in the current column, and
    // whether the column has held two different values.
    String? columnLast;
    var columnGlitched = false;

    for (var i = first; i < view.length; i++) {
      final value = view.valueAt(i);
      final x = timeMapper.timeToPixel(view.timeAt(i)).clamp(xMin, xMax);
      final col = x.floor();
      if (col <= currentCol) {
        // Same pixel column — coalesce. Promote to X if seen.
        if (columnLast != null && columnLast != value) {
          columnGlitched = true;
        }
        columnLast = value;
        if (_hasXState(value)) {
          currentValue = value;
        } else if (currentValue == null || !_hasXState(currentValue)) {
          currentValue = value;
        }
        continue;
      }
      if (columnGlitched) glitches.add(currentX);
      columnGlitched = false;
      columnLast = value;
      if (currentValue != null) {
        segments.add(_Segment(xStart: currentX, xEnd: x, value: currentValue));
      }
      currentValue = value;
      currentX = x;
      currentCol = col;
      if (currentX >= xMax) break;
    }
    if (columnGlitched) glitches.add(currentX);

    // Final segment extends to the right canvas edge.
    if (currentValue != null && currentX < xMax) {
      segments.add(_Segment(xStart: currentX, xEnd: xMax, value: currentValue));
    }

    return segments;
  }

  /// True if [value] contains an `x`/`X` character anywhere — used to keep
  /// sub-pixel X glitches visible after coalescing.
  static bool _hasXState(String value) {
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (c == 0x78 || c == 0x58) return true;
    }
    return false;
  }

  /// Fills [rect] with a semi-transparent red and overlays diagonal hatch lines.
  static void _paintXState(
    Canvas canvas,
    Rect rect,
    Color xColor,
    Color xHatchColor,
  ) {
    _xFillPaint.color = xColor.withValues(alpha: 0.25);
    canvas.drawRect(rect, _xFillPaint);

    final hatchPaint = _hatchPaint..color = xHatchColor;

    const spacing = 6.0;
    final h = rect.height;

    // Diagonal lines running top-left to bottom-right.
    var startX = rect.left - h;
    while (startX < rect.right) {
      final x0 = math.max(startX, rect.left);
      final y0 = (startX >= rect.left)
          ? rect.top
          : rect.top + (rect.left - startX);
      final x1 = math.min(startX + h, rect.right);
      final y1 = (startX + h <= rect.right)
          ? rect.bottom
          : rect.bottom - (startX + h - rect.right);
      canvas.drawLine(Offset(x0, y0), Offset(x1, y1), hatchPaint);
      startX += spacing;
    }
  }

  /// Draws a dashed horizontal line at [y] from [xStart] to [xEnd].
  static void _paintZState(
    Canvas canvas,
    double xStart,
    double xEnd,
    double y,
    Color zColor,
  ) {
    const dashLen = 8.0;
    const gapLen = 4.0;

    final paint = _zPaint..color = zColor;

    var x = xStart;
    while (x < xEnd) {
      final end = math.min(x + dashLen, xEnd);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dashLen + gapLen;
    }
  }
}

/// A constant-value time segment with its pixel x-coordinates.
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
