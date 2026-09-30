// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart' show cruxColorThemeProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/theme/wavecrux_theme_accessors.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/diagnostics/providers/render_pipeline_stats_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/rendering/cursor_painter.dart';
import 'package:wavecrux/features/viewer/widgets/render_stats_collector.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// Repaint-isolated cursor layer drawn above the waveform canvas.
///
/// The waveform [WaveformCanvasRenderObject] paints all signal lanes and
/// per-lane decorations. Without this overlay, every cursor move (mouse
/// scrub, keyboard nudge, programmatic jump) would call `markNeedsPaint`
/// on the lane render object and trigger a full repaint of every signal
/// lane — visibly janky once the canvas hosts hundreds or thousands of
/// signals.
///
/// This widget paints only the primary cursor line, the secondary cursor
/// dashed line, the delta-time chip, and — when the active theme gives
/// `cursor.delta` / `marker.line` a color — the band between the cursors
/// and a line at each named marker. It is wrapped in a
/// [RepaintBoundary] so cursor changes invalidate only this layer's
/// recorded picture; the lane layer stays cached on the GPU.
///
/// Mobile note: the overlay wraps its [CustomPaint] in [IgnorePointer] so
/// pinch-zoom, two-finger pan, and long-press context menus dispatched by
/// [WaveformGestureHandler] underneath continue to work unchanged on iOS,
/// iPadOS, and Android.
///
/// The overlay sizes itself to the visible viewport (it is not embedded
/// in the scrolling content), so the cursor lines visually span the
/// portion of the canvas the user can see — identical to the previous
/// in-render-object behaviour where `clipRect(offset & size)` clipped
/// the cursor to the same region.
class CursorOverlay extends ConsumerWidget {
  const CursorOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cursorState = ref.watch(cursorStateProvider);
    final timeMapper = ref.watch(timeMapperProvider);
    final delta = ref.watch(cursorDeltaProvider);
    // Cursor and marker colors come from the active canvas theme, through the
    // same accessors the lane render object uses, so a preset switch, a
    // theme pack, or a token edit in Settings ▸ Appearance repaints them.
    final colorTheme = ref.watch(cruxColorThemeProvider);
    final markerState = ref.watch(markerStateProvider);
    final labelStyle =
        Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 11);
    final statsCollector = ref.watch(renderStatsCollectorProvider);

    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _CursorOverlayPainter(
            cursorState: cursorState,
            timeMapper: timeMapper,
            primaryColor: colorTheme.canvasCursorPrimary,
            secondaryColor: colorTheme.canvasCursorSecondary,
            deltaRegionColor: colorTheme.canvasCursorDelta,
            markerLineColor: colorTheme.canvasMarkerLine,
            markerState: markerState,
            deltaLabel: delta.deltaDisplay,
            labelStyle: labelStyle,
            statsCollector: statsCollector,
          ),
          // Fill the parent — usually the visible viewport area.
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _CursorOverlayPainter extends CustomPainter {
  _CursorOverlayPainter({
    required this.cursorState,
    required this.timeMapper,
    required this.primaryColor,
    required this.secondaryColor,
    required this.deltaRegionColor,
    required this.markerLineColor,
    required this.markerState,
    required this.deltaLabel,
    required this.labelStyle,
    required this.statsCollector,
  });

  final CursorState cursorState;
  final TimeMapper timeMapper;
  final Color primaryColor;
  final Color secondaryColor;
  final Color deltaRegionColor;
  final Color markerLineColor;
  final MarkerState markerState;
  final String? deltaLabel;
  final TextStyle labelStyle;
  final RenderStatsCollector statsCollector;

  /// True when marker lines are drawn, so a marker edit changes the picture.
  bool get _drawsMarkerLines => markerLineColor.a > 0;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final sc = statsCollector;
    final sw = Stopwatch()..start();
    CursorPainter.paint(
      canvas: canvas,
      bounds: bounds,
      cursorState: cursorState,
      timeMapper: timeMapper,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      deltaRegionColor: deltaRegionColor,
      markerTimes: _drawsMarkerLines ? markerState.markers.values : const [],
      markerLineColor: markerLineColor,
      deltaLabel: deltaLabel,
      labelStyle: labelStyle,
    );
    sw.stop();
    sc.recordCursorPaint(sw.elapsedMicroseconds);
  }

  @override
  bool shouldRepaint(covariant _CursorOverlayPainter old) {
    return old.cursorState != cursorState ||
        old.timeMapper != timeMapper ||
        old.primaryColor != primaryColor ||
        old.secondaryColor != secondaryColor ||
        old.deltaRegionColor != deltaRegionColor ||
        old.markerLineColor != markerLineColor ||
        (_drawsMarkerLines && old.markerState != markerState) ||
        old.deltaLabel != deltaLabel ||
        old.labelStyle != labelStyle;
  }
}
