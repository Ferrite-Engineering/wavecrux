// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/analog_interpolation.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/features/viewer/rendering/visible_changes.dart';
import 'package:wavecrux/services/value_format/analog_value_extractor.dart';
import 'package:wavecrux/services/waveform_geom/analog_scale_service.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// Paints an analog signal lane onto a [Canvas].
///
/// "Analog" here is a *rendering* mode, not a signal type. It covers both
/// real-valued signals, which are analog by nature, and digital buses the user
/// has asked to see drawn as a curve. The only difference between the two is
/// how a raw value string becomes a number, and that is entirely the caller's
/// choice of [valueExtractor] — everything below this line is value-agnostic.
///
/// Rendering conventions:
/// - A continuous line trace connecting recorded data points.
/// - [AnalogInterpolation.linear]: straight lines between points.
/// - [AnalogInterpolation.stepHold]: horizontal hold then instant jump.
/// - NaN / unparseable values produce a gap in the trace.
/// - Faint horizontal gridlines at computed nice tick values.
/// - Zero line is slightly brighter when zero is within the visible range.
/// - A small dot + value label is drawn at the primary cursor intersection.
abstract final class AnalogSignalPainter {
  static const double _vMargin = 4;

  // Trace line width.
  static const double _traceWidth = 1.5;

  // Grid line opacity (multiplied with signal color).
  static const double _gridAlpha = 0.18;
  static const double _zeroGridAlpha = 0.35;

  // Cursor dot radius.
  static const double _cursorDotRadius = 3;

  // Reusable Paint objects mutated per call.
  static final Paint _gridPaint = Paint()..style = PaintingStyle.stroke;
  static final Paint _tracePaint = Paint()
    ..strokeWidth = _traceWidth
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  static final Paint _cursorDotPaint = Paint()..style = PaintingStyle.fill;

  // ── public API ────────────────────────────────────────────────────────────────

  /// Paints an analog signal into [laneBounds].
  ///
  /// [changes] must be ordered by ascending time and may start before the
  /// viewport. [valueAtStart] is the signal's value just before the first of
  /// [changes].
  ///
  /// [manualMin] / [manualMax] override auto-ranging when both are supplied.
  /// [primaryCursorTime] draws a value dot + label at the cursor position.
  ///
  /// [valueExtractor] converts a raw value string to a plottable number and
  /// defaults to [AnalogValueExtractors.real], preserving the historical
  /// behaviour for real-valued signals exactly. A digital bus rendered as
  /// analog passes [AnalogValueExtractors.forDigitalLane] instead, so its bits
  /// are read through the lane's own numeric format.
  static void paint({
    required Canvas canvas,
    required Rect laneBounds,
    required List<SignalChange> changes,
    required String? valueAtStart,
    required TimeMapper timeMapper,
    required Color signalColor,
    required AnalogInterpolation interpolation,
    required TextStyle valueStyle,
    double? manualMin,
    double? manualMax,
    int? primaryCursorTime,
    double lineWidthScale = 1.0,
    AnalogValueExtractor valueExtractor = AnalogValueExtractors.real,
  }) {
    if (changes.isEmpty && valueAtStart == null) return;

    // Legibility scale (1.0 = default). Thickens the analog trace so it stays
    // readable on far-viewed / XR displays. Set per call (shared static Paint).
    _tracePaint.strokeWidth = _traceWidth * lineWidthScale;

    canvas
      ..save()
      ..clipRect(laneBounds);

    final top = laneBounds.top + _vMargin;
    final bottom = laneBounds.bottom - _vMargin;

    // Build pixel-space data points from the visible changes.
    final extents = <_ColumnExtent>[];
    final points = _buildPoints(
      changes,
      valueAtStart,
      timeMapper,
      laneBounds.left,
      laneBounds.right,
      valueExtractor,
      extents,
    );

    if (points.isEmpty) {
      canvas.restore();
      return;
    }

    // Compute Y-axis scale. A column's swing counts: a spike narrower than a
    // pixel is still part of the range the lane has to show.
    final AnalogScale scale;
    if (manualMin != null && manualMax != null) {
      scale = AnalogScaleService.computeManualScale(manualMin, manualMax);
    } else {
      final finite = <double>[
        for (final p in points)
          if (p.value.isFinite) p.value,
        for (final e in extents) ...[e.min, e.max],
      ];
      scale = AnalogScaleService.computeAutoScale(finite);
    }

    // Draw background grid lines.
    _paintGrid(canvas, laneBounds, scale, top, bottom, signalColor);

    // Draw the signal trace.
    _paintTrace(
      canvas,
      points,
      scale,
      top,
      bottom,
      signalColor,
      interpolation,
      laneBounds.right,
    );

    // Min/max per pixel column: the full swing of a column the trace
    // coalesced to one point, drawn as a vertical bar through it.
    final tracePaint = _tracePaint..color = signalColor;
    for (final e in extents) {
      canvas.drawLine(
        Offset(e.x, scale.valueToY(e.min, top, bottom)),
        Offset(e.x, scale.valueToY(e.max, top, bottom)),
        tracePaint,
      );
    }

    // Draw cursor intersection indicator.
    if (primaryCursorTime != null) {
      _paintCursorLabel(
        canvas,
        points,
        scale,
        top,
        bottom,
        timeMapper,
        primaryCursorTime,
        signalColor,
        valueStyle,
        interpolation,
        laneBounds,
      );
    }

    canvas.restore();
  }

  // ── grid ──────────────────────────────────────────────────────────────────────

  static void _paintGrid(
    Canvas canvas,
    Rect laneBounds,
    AnalogScale scale,
    double top,
    double bottom,
    Color signalColor,
  ) {
    for (final tick in scale.ticks) {
      final y = scale.valueToY(tick, top, bottom);
      final isZero = tick == 0.0;
      final alpha = isZero ? _zeroGridAlpha : _gridAlpha;
      _gridPaint
        ..color = signalColor.withValues(alpha: alpha)
        ..strokeWidth = isZero ? 1.0 : 0.5;
      canvas.drawLine(
        Offset(laneBounds.left, y),
        Offset(laneBounds.right, y),
        _gridPaint,
      );
    }
  }

  // ── trace ─────────────────────────────────────────────────────────────────────

  static void _paintTrace(
    Canvas canvas,
    List<_DataPoint> points,
    AnalogScale scale,
    double top,
    double bottom,
    Color signalColor,
    AnalogInterpolation interpolation,
    double xMax,
  ) {
    final tracePaint = _tracePaint..color = signalColor;

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (!p.value.isFinite) continue; // gap

      final x1 = p.x;
      final y1 = scale.valueToY(p.value, top, bottom);

      // Determine where this segment ends.
      final double x2;
      final double y2;
      if (i + 1 < points.length) {
        final next = points[i + 1];
        x2 = next.x;
        if (!next.value.isFinite) {
          // Next point is a gap — extend to its x but no line there.
          canvas.drawLine(Offset(x1, y1), Offset(x2, y1), tracePaint);
          continue;
        }
        y2 = scale.valueToY(next.value, top, bottom);
      } else {
        // Last point — hold to the right edge.
        x2 = xMax;
        y2 = y1;
        canvas.drawLine(Offset(x1, y1), Offset(x2, y1), tracePaint);
        continue;
      }

      switch (interpolation) {
        case AnalogInterpolation.linear:
          canvas.drawLine(Offset(x1, y1), Offset(x2, y2), tracePaint);

        case AnalogInterpolation.stepHold:
          // Horizontal hold from x1 to x2 at old y, then vertical drop.
          canvas.drawLine(Offset(x1, y1), Offset(x2, y1), tracePaint);
          if (y1 != y2) {
            canvas.drawLine(Offset(x2, y1), Offset(x2, y2), tracePaint);
          }
      }
    }
  }

  // ── cursor label ──────────────────────────────────────────────────────────────

  static void _paintCursorLabel(
    Canvas canvas,
    List<_DataPoint> points,
    AnalogScale scale,
    double top,
    double bottom,
    TimeMapper timeMapper,
    int cursorTime,
    Color signalColor,
    TextStyle valueStyle,
    AnalogInterpolation interpolation,
    Rect laneBounds,
  ) {
    final cx = timeMapper.timeToPixel(cursorTime);
    if (cx < laneBounds.left || cx > laneBounds.right) return;

    final cursorValue = _interpolateAt(points, cx, interpolation);
    if (cursorValue == null || !cursorValue.isFinite) return;

    final cy = scale.valueToY(cursorValue, top, bottom);

    // Draw dot.
    _cursorDotPaint.color = signalColor;
    canvas.drawCircle(Offset(cx, cy), _cursorDotRadius, _cursorDotPaint);

    // Draw value label to the right of the dot (flip left if near right edge).
    final label = _formatValue(cursorValue);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: valueStyle.copyWith(
          color: signalColor,
          fontSize: (valueStyle.fontSize ?? 11) - 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: laneBounds.width / 2);

    const hPad = 5.0;
    final labelX = (cx + _cursorDotRadius + hPad + tp.width > laneBounds.right)
        ? cx - _cursorDotRadius - hPad - tp.width
        : cx + _cursorDotRadius + hPad;
    final labelY = (cy - tp.height / 2).clamp(
      laneBounds.top,
      laneBounds.bottom - tp.height,
    );

    tp.paint(canvas, Offset(labelX, labelY));
  }

  // ── helpers ───────────────────────────────────────────────────────────────────

  /// Builds pixel-space anchor points from [changes] and [valueAtStart].
  ///
  /// Anchor points falling within the same integer pixel column are coalesced
  /// to a single point, bounding the trace cost by viewport width rather than
  /// transition count. NaN values are sticky — if either the prior anchor or
  /// the new change is NaN (X / Z / unparseable) the column renders as a gap
  /// so brief X glitches remain visible.
  ///
  /// Coalescing keeps the column's last value, so a column that swung
  /// between values also reports its min and max to [extents]: a spike
  /// narrower than a pixel is drawn at its full height rather than lost.
  ///
  /// [changes] may start before the viewport; see
  /// [firstChangeAtOrAfterPixel].
  static List<_DataPoint> _buildPoints(
    List<SignalChange> changes,
    String? valueAtStart,
    TimeMapper timeMapper,
    double xMin,
    double xMax,
    AnalogValueExtractor extract,
    List<_ColumnExtent> extents,
  ) {
    final points = <_DataPoint>[];
    final first = firstChangeAtOrAfterPixel(changes, timeMapper, xMin);
    final entering = first > 0 ? changes[first - 1].value : valueAtStart;

    // Left-edge anchor.
    if (entering != null) {
      points.add(_DataPoint(x: xMin, value: extract(entering)));
    }
    var lastCol = points.isNotEmpty ? points.last.x.floor() : xMin.floor() - 1;
    // Finite range the current column has held, once it holds two values.
    var colMin = double.infinity;
    var colMax = double.negativeInfinity;

    void closeColumn() {
      if (colMin < colMax && points.isNotEmpty && points.last.value.isFinite) {
        extents.add(_ColumnExtent(x: points.last.x, min: colMin, max: colMax));
      }
      colMin = double.infinity;
      colMax = double.negativeInfinity;
    }

    for (var i = first; i < changes.length; i++) {
      final change = changes[i];
      final x = timeMapper.timeToPixel(change.time).clamp(xMin, xMax);
      final col = x.floor();
      final v = extract(change.value);

      if (points.isNotEmpty && col <= lastCol) {
        // Same pixel column — coalesce. NaN is sticky: any NaN within the
        // column renders the column as a gap.
        final last = points.last;
        if (last.value.isFinite) {
          if (last.value < colMin) colMin = last.value;
          if (last.value > colMax) colMax = last.value;
        }
        if (v.isFinite) {
          if (v < colMin) colMin = v;
          if (v > colMax) colMax = v;
        }
        final coalesced = (!last.value.isFinite || !v.isFinite)
            ? double.nan
            : v;
        points[points.length - 1] = _DataPoint(x: last.x, value: coalesced);
        continue;
      }

      closeColumn();
      points.add(_DataPoint(x: x, value: v));
      lastCol = col;
      if (x >= xMax) break;
    }
    closeColumn();

    return points;
  }

  // ── test seam ────────────────────────────────────────────────────────────────

  /// Test-only window onto [_buildPoints]. Returns each anchor as a
  /// `(x, value)` record so tests can assert pixel-column coalescing without
  /// taking a dependency on the private `_DataPoint` type.
  @visibleForTesting
  static List<({double x, double value})> debugBuildPoints({
    required List<SignalChange> changes,
    required String? valueAtStart,
    required TimeMapper timeMapper,
    required double xMin,
    required double xMax,
    AnalogValueExtractor valueExtractor = AnalogValueExtractors.real,
  }) {
    final raw = _buildPoints(
      changes,
      valueAtStart,
      timeMapper,
      xMin,
      xMax,
      valueExtractor,
      <_ColumnExtent>[],
    );
    return [for (final p in raw) (x: p.x, value: p.value)];
  }

  /// Test-only window onto the per-column swings [_buildPoints] reports: one
  /// `(x, min, max)` per pixel column that held more than one value.
  @visibleForTesting
  static List<({double x, double min, double max})> debugColumnExtents({
    required List<SignalChange> changes,
    required String? valueAtStart,
    required TimeMapper timeMapper,
    required double xMin,
    required double xMax,
    AnalogValueExtractor valueExtractor = AnalogValueExtractors.real,
  }) {
    final extents = <_ColumnExtent>[];
    _buildPoints(
      changes,
      valueAtStart,
      timeMapper,
      xMin,
      xMax,
      valueExtractor,
      extents,
    );
    return [for (final e in extents) (x: e.x, min: e.min, max: e.max)];
  }

  /// Interpolates the signal value at pixel x [cx] using [interpolation].
  ///
  /// Returns null when [cx] is before the first data point.
  static double? _interpolateAt(
    List<_DataPoint> points,
    double cx,
    AnalogInterpolation interpolation,
  ) {
    _DataPoint? before;
    _DataPoint? after;

    for (final p in points) {
      if (p.x <= cx) {
        before = p;
      } else {
        after = p;
        break;
      }
    }

    if (before == null) return null;
    if (!before.value.isFinite) return null;

    if (interpolation == AnalogInterpolation.stepHold || after == null) {
      return before.value;
    }

    if (!after.value.isFinite) return before.value;

    // Linear interpolation between before and after.
    final t = (cx - before.x) / (after.x - before.x);
    return before.value + t * (after.value - before.value);
  }

  /// Formats a finite value for the cursor label (3 significant figures).
  static String _formatValue(double v) {
    if (!v.isFinite) return '?';
    if (v == 0.0) return '0';
    final abs = v.abs();
    if (abs >= 1e4 || abs < 1e-3) {
      // Scientific notation: e.g. "1.23e-6".
      final exp = (math.log(abs) / math.ln10).floor();
      final mantissa = v / math.pow(10, exp).toDouble();
      return '${mantissa.toStringAsFixed(2)}e$exp';
    }
    if (abs >= 100) return v.toStringAsFixed(1);
    if (abs >= 10) return v.toStringAsFixed(2);
    if (abs >= 1) return v.toStringAsFixed(3);
    return v.toStringAsFixed(4);
  }
}

/// A pixel-space anchor point for the analog trace.
final class _DataPoint {
  const _DataPoint({required this.x, required this.value});

  final double x;

  /// Signal value; [double.nan] represents a gap in the trace.
  final double value;
}

/// The finite range one pixel column held, for a column whose changes were
/// coalesced into a single [_DataPoint].
final class _ColumnExtent {
  const _ColumnExtent({required this.x, required this.min, required this.max});

  final double x;
  final double min;
  final double max;
}
