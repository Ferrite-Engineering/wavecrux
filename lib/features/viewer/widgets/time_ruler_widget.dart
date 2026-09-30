// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:math' as math;

import 'package:crux_theme/crux_theme.dart' show cruxColorThemeProvider;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/core/theme/wavecrux_theme.dart';
import 'package:wavecrux/core/theme/wavecrux_theme_accessors.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';
import 'package:wavecrux/services/waveform_geom/time_ruler_data.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

// ── public constants ──────────────────────────────────────────────────────────

/// Fixed height of the time ruler bar in logical pixels.
const double timeRulerHeight = 36;

// ── internal layout constants ─────────────────────────────────────────────────

// Layout within the 36 px height (all y values from top):
//
//   y=0..14  indicator zone  — delta chip + cursor/marker downward triangles
//   y=14..27 label zone      — time-label text (10 pt ≈ 12 px)
//   y=27..35 tick zone       — major ticks 9 px; minor ticks 4 px
//   y=35     bottom border

const double _indicatorZoneBottom = 14;
const double _tickBottom = 35; // bottom of tick marks
const double _majorTickH = 9;
const double _minorTickH = 4;
const double _majorTickTop = _tickBottom - _majorTickH; // 26.0
const double _minorTickTop = _tickBottom - _minorTickH; // 31.0
const double _borderY = 35.5;

// Cursor / marker indicator geometry is now driven by [MobileMetrics] —
// see [_TimeRulerPainter.cursorHalfW] / [_TimeRulerPainter.markerHalfW].
//
// Hit-test tolerance for grabbing a cursor with the mouse on desktop:
// 9 dp from cursor centre (matches the historical 5 dp half-width + 4 dp
// padding). Touch device classes use 22 dp via the metric — see
// [_TimeRulerWidgetState._hitTest] and ARCHITECTURE.md §3.1.8.9.
const double _cursorHitRadius = 9;

// Minimum desktop horizontal grab radius for a named marker flag (the flag is
// narrower than a cursor, so the hit zone is widened to this floor).
const double _markerHitMinRadius = 8;

// How far below the triangle tip the grab zone extends.
const double _cursorHitYPad = 4;

// ── drag-target enum ──────────────────────────────────────────────────────────

enum _DragTarget { none, primary, secondary }

/// Horizontal time ruler bar shown above the waveform canvas.
///
/// Renders:
/// - Major tick marks with auto-scaled time labels (via [TimeRulerData]).
/// - Minor tick marks (no labels).
/// - Downward-pointing triangle at the top for each cursor position:
///   primary (filled) and secondary (outlined), in the canvas theme's
///   `cursor.primary` / `cursor.secondary` colors.
/// - Colored triangular marker flags with letter labels for each named
///   marker (a–z) set in [MarkerStateNotifier].
///
/// Every color but the major ticks and the bottom border comes from the
/// active canvas theme (`ruler.*`, `cursor.*`, `marker.flag*`).
///
/// **Tap** places the primary cursor; **Shift+tap** or **right-click**
/// places the secondary cursor.
///
/// **Click-and-drag on a cursor triangle** moves that cursor. The mouse cursor
/// changes to [SystemMouseCursors.resizeLeftRight] when hovering over a
/// draggable cursor indicator.
class TimeRulerWidget extends ConsumerStatefulWidget {
  const TimeRulerWidget({super.key});

  @override
  ConsumerState<TimeRulerWidget> createState() => _TimeRulerWidgetState();
}

class _TimeRulerWidgetState extends ConsumerState<TimeRulerWidget> {
  _DragTarget _dragTarget = _DragTarget.none;

  // Button that was pressed on the last pointer-down (kPrimaryMouseButton or
  // kSecondaryMouseButton). Tracked so pointer-up knows which button caused it.
  int _downButton = 0;

  // True when the pointer is hovering (no button held) over a cursor triangle.
  bool _hoveringCursor = false;

  // Double-click tracking: record the last tap time and which cursor was hit.
  // A second tap on the same cursor within _doubleTapWindow removes that cursor.
  static const Duration _doubleTapWindow = Duration(milliseconds: 400);
  DateTime? _lastTapTime;
  _DragTarget _lastTapTarget = _DragTarget.none;

  // True if the pointer actually moved while a cursor was grabbed. Distinguishes
  // a cursor drag (move) from a cursor tap (click without moving).
  bool _cursorDragged = false;

  // ── edge auto-scroll ────────────────────────────────────────────────────────

  static const double _edgeScrollZone = 40;
  static const double _edgeScrollMaxSpeed = 8;

  Timer? _edgeScrollTimer;
  Offset? _lastPointerPosition;

  void _startEdgeScroll() {
    _edgeScrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _tickEdgeScroll(),
    );
  }

  void _stopEdgeScroll() {
    _edgeScrollTimer?.cancel();
    _edgeScrollTimer = null;
  }

  void _tickEdgeScroll() {
    if (!mounted) {
      _stopEdgeScroll();
      return;
    }
    final pos = _lastPointerPosition;
    if (pos == null || _dragTarget == _DragTarget.none) {
      _stopEdgeScroll();
      return;
    }
    final mapper = ref.read(timeMapperProvider);
    final vw = mapper.viewportWidth;

    double panDelta = 0;
    if (pos.dx > vw - _edgeScrollZone) {
      panDelta =
          ((pos.dx - (vw - _edgeScrollZone)) / _edgeScrollZone) *
          _edgeScrollMaxSpeed;
    } else if (pos.dx < _edgeScrollZone) {
      panDelta =
          -((_edgeScrollZone - pos.dx) / _edgeScrollZone) * _edgeScrollMaxSpeed;
    }
    if (panDelta == 0) {
      _stopEdgeScroll();
      return;
    }

    ref.read(timeMapperProvider.notifier).pan(panDelta);
    final newMapper = ref.read(timeMapperProvider);
    final time = newMapper.pixelToTime(pos.dx);
    final notifier = ref.read(cursorStateProvider.notifier);
    if (_dragTarget == _DragTarget.primary) {
      notifier.placePrimary(time);
    } else {
      notifier.placeSecondary(time);
    }
  }

  @override
  void dispose() {
    _stopEdgeScroll();
    super.dispose();
  }

  // ── hit-testing ─────────────────────────────────────────────────────────────

  _DragTarget _hitTest(
    Offset localPosition,
    TimeMapper timeMapper,
    CursorState cursorState,
  ) {
    final x = localPosition.dx;
    final y = localPosition.dy;

    // Per ARCHITECTURE.md §3.1.8.9: on touch device classes the horizontal
    // grab zone widens to 22 dp on each side (44 dp total) so a finger can
    // grab the cursor reliably. Desktop keeps the historical ~9 dp radius.
    final metrics = MobileMetrics.of(
      context,
      ref.read(deviceClassProvider),
    );
    final hitRadius = metrics.isTouch ? 22.0 : _cursorHitRadius;
    final tipY = metrics.cursorMarkerSize / 2 * 1.4;

    // Restrict grab zone to the indicator zone (triangles live here).
    if (y > tipY + _cursorHitYPad) return _DragTarget.none;

    // Primary cursor is drawn on top so it wins hit priority.
    final primTime = cursorState.primaryCursorTime;
    if (primTime != null) {
      final primX = timeMapper.timeToPixel(primTime);
      if ((x - primX).abs() <= hitRadius) return _DragTarget.primary;
    }

    final secTime = cursorState.secondaryCursorTime;
    if (secTime != null) {
      final secX = timeMapper.timeToPixel(secTime);
      if ((x - secX).abs() <= hitRadius) return _DragTarget.secondary;
    }

    return _DragTarget.none;
  }

  // ── marker hit-testing ────────────────────────────────────────────────────

  /// Returns the letter of the named marker under [localPosition], or null.
  ///
  /// Mirrors the flag geometry painted by [_TimeRulerPainter._paintMarkerFlag]:
  /// a downward triangle plus letter in the indicator zone. Used by the
  /// right-click handler so a marker can be removed from the ruler.
  String? _markerHitTest(Offset localPosition, TimeMapper timeMapper) {
    if (localPosition.dy > _indicatorZoneBottom + 2) return null;
    final markers = ref.read(markerStateProvider).getAllMarkers();
    if (markers.isEmpty) return null;
    final metrics = MobileMetrics.of(context, ref.read(deviceClassProvider));
    final markerHalfW = metrics.namedMarkerFlag / 2;
    final hitRadius = metrics.isTouch
        ? 22.0
        : math.max(markerHalfW, _markerHitMinRadius);
    String? best;
    var bestDist = double.infinity;
    for (final entry in markers) {
      final mx = timeMapper.timeToPixel(entry.value);
      final dist = (localPosition.dx - mx).abs();
      if (dist <= hitRadius && dist < bestDist) {
        bestDist = dist;
        best = entry.key;
      }
    }
    return best;
  }

  Future<void> _showMarkerContextMenu(
    Offset globalPosition,
    String letter,
  ) async {
    final l10n = L10N.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'remove',
          child: Text(l10n.markerRemoveMenuItem(letter)),
        ),
      ],
    );
    if (selected == 'remove' && mounted) {
      ref.read(markerStateProvider.notifier).removeMarker(letter);
    }
  }

  // ── pointer handlers ─────────────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    _downButton = event.buttons;
    final timeMapper = ref.read(timeMapperProvider);

    // Right-click: remove a marker if one is under the pointer, otherwise
    // place the secondary cursor (no drag).
    if (event.buttons == kSecondaryMouseButton) {
      final markerLetter = _markerHitTest(event.localPosition, timeMapper);
      if (markerLetter != null) {
        unawaited(_showMarkerContextMenu(event.position, markerLetter));
        return;
      }
      final time = timeMapper.pixelToTime(event.localPosition.dx);
      ref.read(cursorStateProvider.notifier).placeSecondary(time);
      return;
    }

    // Left-click: try to grab a cursor triangle.
    if (event.buttons == kPrimaryMouseButton) {
      final cursorState = ref.read(cursorStateProvider);
      final target = _hitTest(event.localPosition, timeMapper, cursorState);
      if (target != _DragTarget.none) {
        setState(() {
          _dragTarget = target;
          _cursorDragged = false;
        });
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_dragTarget == _DragTarget.none) return;
    _cursorDragged = true;
    _lastPointerPosition = event.localPosition;
    final timeMapper = ref.read(timeMapperProvider);
    final time = timeMapper.pixelToTime(event.localPosition.dx);
    final notifier = ref.read(cursorStateProvider.notifier);
    if (_dragTarget == _DragTarget.primary) {
      notifier.placePrimary(time);
    } else {
      notifier.placeSecondary(time);
    }
    final vw = timeMapper.viewportWidth;
    if (event.localPosition.dx > vw - _edgeScrollZone ||
        event.localPosition.dx < _edgeScrollZone) {
      _startEdgeScroll();
    } else {
      _stopEdgeScroll();
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _lastPointerPosition = null;
    _stopEdgeScroll();

    if (_dragTarget != _DragTarget.none && !_cursorDragged) {
      // Tap on a cursor triangle (no drag): check for double-click to remove.
      final now = DateTime.now();
      final lastTime = _lastTapTime;
      final tappedTarget = _dragTarget;
      if (lastTime != null &&
          now.difference(lastTime) <= _doubleTapWindow &&
          _lastTapTarget == tappedTarget) {
        // Double-click confirmed — remove the cursor.
        final notifier = ref.read(cursorStateProvider.notifier);
        if (tappedTarget == _DragTarget.primary) {
          notifier.clearAll();
        } else {
          notifier.clearSecondary();
        }
        _lastTapTime = null;
        _lastTapTarget = _DragTarget.none;
      } else {
        _lastTapTime = now;
        _lastTapTarget = tappedTarget;
      }
    } else if (_dragTarget == _DragTarget.none &&
        _downButton == kPrimaryMouseButton) {
      // Plain tap on the ruler (not on a cursor) — place a cursor.
      final isSecondary = HardwareKeyboard.instance.isShiftPressed;
      final timeMapper = ref.read(timeMapperProvider);
      final time = timeMapper.pixelToTime(event.localPosition.dx);
      final notifier = ref.read(cursorStateProvider.notifier);
      if (isSecondary) {
        notifier.placeSecondary(time);
      } else {
        notifier.placePrimary(time);
      }
      // A plain ruler tap resets the double-click state.
      _lastTapTime = null;
      _lastTapTarget = _DragTarget.none;
    }

    setState(() {
      _dragTarget = _DragTarget.none;
      _cursorDragged = false;
      _downButton = 0;
    });
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _lastPointerPosition = null;
    _stopEdgeScroll();
    setState(() {
      _dragTarget = _DragTarget.none;
      _downButton = 0;
    });
  }

  void _onHover(PointerHoverEvent event) {
    final timeMapper = ref.read(timeMapperProvider);
    final cursorState = ref.read(cursorStateProvider);
    final target = _hitTest(event.localPosition, timeMapper, cursorState);
    final hovering = target != _DragTarget.none;
    if (hovering != _hoveringCursor) setState(() => _hoveringCursor = hovering);
  }

  // ── build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final timeMapper = ref.watch(timeMapperProvider);
    final timescale = ref.watch(currentTimescaleProvider);
    final cursorState = ref.watch(cursorStateProvider);
    final markerState = ref.watch(markerStateProvider);
    final cursorDelta = ref.watch(cursorDeltaProvider);
    final patternMatchRanges = ref.watch(
      patternSearchProvider.select((s) => s.matchRanges),
    );
    final deltaLabel = cursorDelta.deltaDisplay != null
        ? '${l10n.cursorDeltaLabel} ${cursorDelta.deltaDisplay}'
        : null;
    // The ruler reads the canvas theme through the same accessors as the lane
    // render object and the cursor layer, so a preset switch, a theme pack or
    // a token edit in Settings ▸ Appearance repaints it.
    final colorTheme = ref.watch(cruxColorThemeProvider);
    final extension =
        Theme.of(context).extension<WavecruxColorExtension>() ??
        const WavecruxColorExtension.dark();
    final colorScheme = Theme.of(context).colorScheme;
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);

    final palette = _RulerPalette(
      background: colorTheme.canvasRulerBackground,
      minorTick: colorTheme.canvasRulerTick,
      // Not `ruler.tickMajor`: that token already colors the canvas's
      // group-header and comment text, in a different shade from these ticks
      // in every built-in preset, so one token cannot drive both without
      // repainting one of them. The major ticks keep the per-brightness
      // palette they have always used.
      majorTick: extension.timeRulerMajorTick,
      label: colorTheme.canvasRulerLabel,
      primaryCursor: colorTheme.canvasCursorPrimary,
      secondaryCursor: colorTheme.canvasCursorSecondary,
      cursorTime: colorTheme.canvasRulerCursorTime,
      markerFlag: colorTheme.canvasMarkerFlag,
      markerFlagText: colorTheme.canvasMarkerFlagText,
    );

    final labelStyle = TextStyle(
      fontFamily: WavecruxColors.monoFontFamily,
      fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
      fontSize: 10,
      letterSpacing: 0,
      color: palette.label,
    );

    // Show resize cursor while hovering over a cursor triangle or mid-drag.
    final mouseCursor = (_hoveringCursor || _dragTarget != _DragTarget.none)
        ? SystemMouseCursors.resizeLeftRight
        : MouseCursor.defer;

    return SizedBox(
      height: timeRulerHeight,
      child: MouseRegion(
        cursor: mouseCursor,
        onHover: _onHover,
        onExit: (_) {
          if (_hoveringCursor) setState(() => _hoveringCursor = false);
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final rulerWidth = constraints.maxWidth;
              final rulerData = TimeRulerData.compute(
                timeMapper,
                rulerWidth,
                timescale: timescale,
              );
              return RepaintBoundary(
                child: CustomPaint(
                  size: Size(rulerWidth, timeRulerHeight),
                  painter: _TimeRulerPainter(
                    rulerData: rulerData,
                    timeMapper: timeMapper,
                    cursorState: cursorState,
                    markerState: markerState,
                    palette: palette,
                    labelStyle: labelStyle,
                    borderColor: colorScheme.outline,
                    cursorHalfW: metrics.cursorMarkerSize / 2,
                    markerHalfW: metrics.namedMarkerFlag / 2,
                    deltaLabel: deltaLabel,
                    patternMatchRanges: patternMatchRanges,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── palette ───────────────────────────────────────────────────────────────────

/// Every color the ruler paints except its bottom border, resolved once per
/// build. Value equality lets [_TimeRulerPainter.shouldRepaint] repaint on
/// exactly the theme changes that alter the picture.
@immutable
class _RulerPalette {
  const _RulerPalette({
    required this.background,
    required this.minorTick,
    required this.majorTick,
    required this.label,
    required this.primaryCursor,
    required this.secondaryCursor,
    required this.cursorTime,
    required this.markerFlag,
    required this.markerFlagText,
  });

  /// `ruler.background`.
  final Color background;

  /// `ruler.tick`.
  final Color minorTick;

  /// The per-brightness major-tick color; see the build method.
  final Color majorTick;

  /// `ruler.label` — the tick labels.
  final Color label;

  /// `cursor.primary` — the filled triangle.
  final Color primaryCursor;

  /// `cursor.secondary` — the outlined triangle and the delta chip's tint.
  final Color secondaryCursor;

  /// `ruler.cursorTime` — the delta chip's text.
  final Color cursorTime;

  /// `marker.flag` — a named marker's triangle.
  final Color markerFlag;

  /// `marker.flagText` — a named marker's letter.
  final Color markerFlagText;

  @override
  bool operator ==(Object other) =>
      other is _RulerPalette &&
      other.background == background &&
      other.minorTick == minorTick &&
      other.majorTick == majorTick &&
      other.label == label &&
      other.primaryCursor == primaryCursor &&
      other.secondaryCursor == secondaryCursor &&
      other.cursorTime == cursorTime &&
      other.markerFlag == markerFlag &&
      other.markerFlagText == markerFlagText;

  @override
  int get hashCode => Object.hash(
    background,
    minorTick,
    majorTick,
    label,
    primaryCursor,
    secondaryCursor,
    cursorTime,
    markerFlag,
    markerFlagText,
  );
}

// ── private CustomPainter ─────────────────────────────────────────────────────

class _TimeRulerPainter extends CustomPainter {
  const _TimeRulerPainter({
    required this.rulerData,
    required this.timeMapper,
    required this.cursorState,
    required this.markerState,
    required this.palette,
    required this.labelStyle,
    required this.borderColor,
    required this.cursorHalfW,
    required this.markerHalfW,
    this.deltaLabel,
    this.patternMatchRanges = const [],
  });

  final TimeRulerData rulerData;
  final TimeMapper timeMapper;
  final CursorState cursorState;
  final MarkerState markerState;
  final _RulerPalette palette;
  final TextStyle labelStyle;
  final Color borderColor;
  final String? deltaLabel;
  final List<TimeRange> patternMatchRanges;

  /// Half-width of the primary/secondary cursor downward triangle.
  /// Scales with [MobileMetrics.cursorMarkerSize] (5 dp on desktop, 9 dp
  /// on touch device classes).
  final double cursorHalfW;

  /// Half-width of named marker (a–z) downward triangles. Scales with
  /// [MobileMetrics.namedMarkerFlag] (4 dp on desktop, 8 dp on touch).
  final double markerHalfW;

  @override
  bool shouldRepaint(_TimeRulerPainter old) =>
      old.rulerData != rulerData ||
      old.timeMapper != timeMapper ||
      old.cursorState != cursorState ||
      old.markerState != markerState ||
      old.palette != palette ||
      old.labelStyle != labelStyle ||
      old.borderColor != borderColor ||
      old.cursorHalfW != cursorHalfW ||
      old.markerHalfW != markerHalfW ||
      old.deltaLabel != deltaLabel ||
      old.patternMatchRanges != patternMatchRanges;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;

    // 1. Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, timeRulerHeight),
      Paint()..color = palette.background,
    );

    // 2. Pattern match bands in the tick zone (behind ticks).
    if (patternMatchRanges.isNotEmpty && !timeMapper.isEmpty) {
      _paintPatternMatchBands(canvas, w);
    }

    // 3. Tick marks and time labels
    _paintTicks(canvas, w);

    // 4. Bottom border line
    canvas.drawLine(
      const Offset(0, _borderY),
      Offset(w, _borderY),
      Paint()
        ..color = borderColor
        ..strokeWidth = 1.0,
    );

    // 5. Named marker flags (below cursors so cursors render on top)
    for (final entry in markerState.getAllMarkers()) {
      final x = timeMapper.timeToPixel(entry.value);
      if (x >= -1 && x <= w + 1) {
        _paintMarkerFlag(canvas, w, x, entry.key);
      }
    }

    // 6. Delta chip — painted before cursor triangles so the triangles
    //    appear on top at each endpoint.
    final primTime = cursorState.primaryCursorTime;
    final secTime = cursorState.secondaryCursorTime;
    if (deltaLabel != null && primTime != null && secTime != null) {
      _paintDeltaChip(canvas, size, primTime, secTime, deltaLabel!);
    }

    // 7. Secondary cursor indicator (painted before primary so primary wins)
    if (secTime != null) {
      final x = timeMapper.timeToPixel(secTime);
      if (x >= -1 && x <= w + 1) {
        _paintCursorTriangle(canvas, x, palette.secondaryCursor, filled: false);
      }
    }

    // 8. Primary cursor indicator
    if (primTime != null) {
      final x = timeMapper.timeToPixel(primTime);
      if (x >= -1 && x <= w + 1) {
        _paintCursorTriangle(canvas, x, palette.primaryCursor, filled: true);
      }
    }
  }

  // ── delta chip ──────────────────────────────────────────────────────────────

  // Vertical bounds of the chip inside the indicator zone (y=0..14).
  // Cursor triangles (y=0..7) are painted on top, so the chip sits behind them
  // at the endpoints and is clearly readable between them.
  static const double _chipTop = 1.5;
  static const double _chipBottom = _indicatorZoneBottom - 1.5; // 12.5
  static const double _chipH = _chipBottom - _chipTop; // 11.0
  static const double _chipHPad = 4;

  void _paintDeltaChip(
    Canvas canvas,
    Size size,
    int primTime,
    int secTime,
    String label,
  ) {
    final x1 = timeMapper.timeToPixel(primTime);
    final x2 = timeMapper.timeToPixel(secTime);
    final xLeft = math.min(x1, x2);
    final xRight = math.max(x1, x2);
    final midX = (xLeft + xRight) / 2;

    final chipStyle = labelStyle.copyWith(color: palette.cursorTime);
    final tp = TextPainter(
      text: TextSpan(text: label, style: chipStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final chipW = tp.width + _chipHPad * 2;
    final chipX = (midX - chipW / 2)
        .clamp(0.0, math.max(0.0, size.width - chipW))
        .toDouble();
    final textY = _chipTop + (_chipH - tp.height) / 2;
    const lineY = _chipTop + _chipH / 2;

    // Semi-transparent background pill.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(chipX, _chipTop, chipW, _chipH),
        const Radius.circular(3),
      ),
      Paint()..color = palette.secondaryCursor.withValues(alpha: 0.18),
    );

    // Bracket lines from each cursor to the chip edges (only when there's a gap).
    final bp = Paint()
      ..color = palette.secondaryCursor.withValues(alpha: 0.35)
      ..strokeWidth = 1.0;
    if (xLeft < chipX - 2) {
      canvas.drawLine(Offset(xLeft, lineY), Offset(chipX, lineY), bp);
    }
    if (xRight > chipX + chipW + 2) {
      canvas.drawLine(Offset(xRight, lineY), Offset(chipX + chipW, lineY), bp);
    }

    tp.paint(canvas, Offset(chipX + _chipHPad, textY));
  }

  // ── pattern match bands ─────────────────────────────────────────────────────

  void _paintPatternMatchBands(Canvas canvas, double width) {
    final paint = Paint()
      ..color =
          const Color(0x4056AB4E) // green @ ~25%
      ..style = PaintingStyle.fill;
    for (final region in patternMatchRanges) {
      final x1 = timeMapper.timeToPixel(region.start).clamp(0.0, width);
      final x2 = timeMapper.timeToPixel(region.end).clamp(0.0, width);
      if (x2 <= x1) continue;
      canvas.drawRect(
        Rect.fromLTWH(x1, _majorTickTop, x2 - x1, _majorTickH),
        paint,
      );
    }
  }

  // ── tick rendering ──────────────────────────────────────────────────────────

  void _paintTicks(Canvas canvas, double width) {
    final majorPaint = Paint()
      ..color = palette.majorTick
      ..strokeWidth = 1.0;
    final minorPaint = Paint()
      ..color = palette.minorTick
      ..strokeWidth = 1.0;

    for (final tick in rulerData.ticks) {
      final x = tick.x;
      if (x < -1 || x > width + 1) continue;

      if (tick.isMajor) {
        canvas.drawLine(
          Offset(x, _majorTickTop),
          Offset(x, _tickBottom),
          majorPaint,
        );
        if (tick.label != null) {
          _paintLabel(canvas, width, x, tick.label!);
        }
      } else {
        canvas.drawLine(
          Offset(x, _minorTickTop),
          Offset(x, _tickBottom),
          minorPaint,
        );
      }
    }
  }

  void _paintLabel(Canvas canvas, double width, double x, String label) {
    final tp = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    // Skip the label when the ruler is narrower than the label itself.
    // Without this guard, `clamp(2.0, width - tp.width - 2.0)` throws
    // ArgumentError because the upper bound becomes less than the lower —
    // reproducible at iPad split-screen widths where the canvas can shrink
    // below ~50 dp during the resize transition. Tick marks still draw;
    // only the textual time label is suppressed.
    final maxLx = width - tp.width - 2.0;
    if (maxLx < 2.0) return;
    // Center label on tick; clamp to ruler bounds with a 2 px margin.
    final lx = (x - tp.width / 2.0).clamp(2.0, maxLx);
    // Top of label just above the major tick, but not above the indicator zone.
    final ly = math.max(
      _indicatorZoneBottom,
      _majorTickTop - tp.height - 1.0,
    );
    tp.paint(canvas, Offset(lx, ly));
  }

  // ── cursor indicator ────────────────────────────────────────────────────────

  void _paintCursorTriangle(
    Canvas canvas,
    double x,
    Color color, {
    required bool filled,
  }) {
    // Triangle tip y scales with width so it stays visually proportional
    // (an isoceles triangle ~1:1.4 wide-to-tall ratio reads naturally).
    final tipY = cursorHalfW * 1.4;
    final path = Path()
      ..moveTo(x - cursorHalfW, 0)
      ..lineTo(x + cursorHalfW, 0)
      ..lineTo(x, tipY)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  // ── marker flag ─────────────────────────────────────────────────────────────

  void _paintMarkerFlag(Canvas canvas, double width, double x, String letter) {
    // Downward-pointing filled triangle in marker color.
    final tipY = markerHalfW * 1.5;
    final path = Path()
      ..moveTo(x - markerHalfW, 0)
      ..lineTo(x + markerHalfW, 0)
      ..lineTo(x, tipY)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = palette.markerFlag
        ..style = PaintingStyle.fill,
    );

    // Letter label just below the triangle tip, centered on x.
    final markerLabelStyle = labelStyle.copyWith(
      color: palette.markerFlagText,
      fontSize: 9,
      fontWeight: FontWeight.bold,
    );
    final tp = TextPainter(
      text: TextSpan(text: letter, style: markerLabelStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    // Skip the marker letter when the ruler is narrower than the label;
    // otherwise the clamp would throw at narrow widths (same defensive
    // guard as `_paintLabel`).
    final maxLx = width - tp.width - 1.0;
    if (maxLx < 1.0) return;
    final lx = (x - tp.width / 2.0).clamp(1.0, maxLx);
    tp.paint(canvas, Offset(lx, markerHalfW * 1.5 + 1.0));
  }
}
