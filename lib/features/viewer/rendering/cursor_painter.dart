// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// Paints the cursor and named-marker overlays onto the waveform canvas.
///
/// Bottom to top:
/// - Delta region: a band between the two cursors, when [paint]'s
///   `deltaRegionColor` is not fully transparent.
/// - Marker lines: a vertical line at each named marker, when
///   `markerLineColor` is not fully transparent.
/// - Secondary cursor: dashed vertical line (used for delta measurement).
/// - Primary cursor: solid vertical line spanning all lanes.
/// - Delta label: rendered between the two cursors when both are visible.
abstract final class CursorPainter {
  // Reusable Paint objects.
  static final Paint _primaryPaint = Paint()
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;
  static final Paint _dashedPaint = Paint()
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.butt;
  static final Paint _labelChipPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _deltaRegionPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _markerLinePaint = Paint()
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;

  static const Color _transparent = Color(0x00000000);

  // ── public API ───────────────────────────────────────────────────────────────

  /// Paints cursor overlays within [bounds].
  ///
  /// [deltaLabel] is the formatted delta-time string shown between the two
  /// cursors; pass null to suppress the label.
  ///
  /// [deltaRegionColor] fills the band between the two cursors and
  /// [markerLineColor] draws a line at each of [markerTimes]. Both default to
  /// fully transparent, and a fully transparent color draws nothing at all —
  /// no canvas call is made.
  static void paint({
    required Canvas canvas,
    required Rect bounds,
    required CursorState cursorState,
    required TimeMapper timeMapper,
    required Color primaryColor,
    required Color secondaryColor,
    Color deltaRegionColor = _transparent,
    Iterable<int> markerTimes = const [],
    Color markerLineColor = _transparent,
    String? deltaLabel,
    TextStyle? labelStyle,
  }) {
    final primaryTime = cursorState.primaryCursorTime;
    final secondaryTime = cursorState.secondaryCursorTime;
    if (deltaRegionColor.a > 0 &&
        primaryTime != null &&
        secondaryTime != null) {
      final x1 = timeMapper.timeToPixel(primaryTime);
      final x2 = timeMapper.timeToPixel(secondaryTime);
      final left = math.max(math.min(x1, x2), bounds.left);
      final right = math.min(math.max(x1, x2), bounds.right);
      if (right > left) {
        _deltaRegionPaint.color = deltaRegionColor;
        canvas.drawRect(
          Rect.fromLTRB(left, bounds.top, right, bounds.bottom),
          _deltaRegionPaint,
        );
      }
    }

    if (markerLineColor.a > 0) {
      _markerLinePaint.color = markerLineColor;
      for (final time in markerTimes) {
        final x = timeMapper.timeToPixel(time);
        if (x < bounds.left || x > bounds.right) continue;
        canvas.drawLine(
          Offset(x, bounds.top),
          Offset(x, bounds.bottom),
          _markerLinePaint,
        );
      }
    }

    // Secondary cursor first so primary renders on top.
    if (cursorState.secondaryCursorTime != null) {
      final x = timeMapper.timeToPixel(cursorState.secondaryCursorTime!);
      if (x >= bounds.left && x <= bounds.right) {
        _paintDashedLine(
          canvas,
          Offset(x, bounds.top),
          Offset(x, bounds.bottom),
          secondaryColor,
        );
      }
    }

    if (cursorState.primaryCursorTime != null) {
      final x = timeMapper.timeToPixel(cursorState.primaryCursorTime!);
      if (x >= bounds.left && x <= bounds.right) {
        _primaryPaint.color = primaryColor;
        canvas.drawLine(
          Offset(x, bounds.top),
          Offset(x, bounds.bottom),
          _primaryPaint,
        );
      }
    }

    if (deltaLabel != null &&
        deltaLabel.isNotEmpty &&
        cursorState.primaryCursorTime != null &&
        cursorState.secondaryCursorTime != null &&
        labelStyle != null) {
      _paintDeltaLabel(
        canvas,
        bounds,
        cursorState,
        timeMapper,
        deltaLabel,
        labelStyle,
        primaryColor,
        secondaryColor,
      );
    }
  }

  // ── internal helpers ─────────────────────────────────────────────────────────

  static void _paintDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
  ) {
    const dashLen = 6.0;
    const gapLen = 4.0;

    final paint = _dashedPaint..color = color;

    final total = (end - start).distance;
    final dir = (end - start) / total;
    var dist = 0.0;
    while (dist < total) {
      final segEnd = math.min(dist + dashLen, total);
      canvas.drawLine(start + dir * dist, start + dir * segEnd, paint);
      dist += dashLen + gapLen;
    }
  }

  static void _paintDeltaLabel(
    Canvas canvas,
    Rect bounds,
    CursorState cursorState,
    TimeMapper timeMapper,
    String label,
    TextStyle style,
    Color primaryColor,
    Color secondaryColor,
  ) {
    final x1 = timeMapper.timeToPixel(cursorState.primaryCursorTime!);
    final x2 = timeMapper.timeToPixel(cursorState.secondaryCursorTime!);
    final xLeft = math.min(x1, x2);
    final xRight = math.max(x1, x2);
    final midX = (xLeft + xRight) / 2.0;

    const padding = 4.0;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: style.copyWith(color: primaryColor),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final labelW = tp.width + padding * 2;
    final labelH = tp.height + padding * 2;
    // Bounds may be narrower than the label mid-resize (the canvas can drop to
    // a few pixels wide for a frame). `num.clamp` throws when min > max, so
    // skip the label entirely instead of crashing the paint.
    if (bounds.width < labelW) return;
    final labelX = (midX - labelW / 2.0).clamp(
      bounds.left,
      bounds.right - labelW,
    );
    final labelY = bounds.top + 4.0;

    // Background chip.
    _labelChipPaint.color = secondaryColor.withValues(alpha: 0.15);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(labelX, labelY, labelW, labelH),
        const Radius.circular(3),
      ),
      _labelChipPaint,
    );

    tp.paint(canvas, Offset(labelX + padding, labelY + padding));
  }
}
