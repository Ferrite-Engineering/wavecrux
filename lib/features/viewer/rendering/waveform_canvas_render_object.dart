// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:wavecrux/core/theme/wavecrux_theme_accessors.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/domain/models/time_selection.dart';
import 'package:wavecrux/features/viewer/rendering/analog_signal_painter.dart';
import 'package:wavecrux/features/viewer/rendering/canvas_draw_command.dart';
import 'package:wavecrux/features/viewer/rendering/scalar_signal_painter.dart';
import 'package:wavecrux/features/viewer/rendering/transaction_painter.dart';
import 'package:wavecrux/features/viewer/rendering/vector_signal_painter.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_lane_data.dart';
import 'package:wavecrux/features/viewer/widgets/render_stats_collector.dart';
import 'package:wavecrux/services/value_format/analog_value_extractor.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// Internal [LeafRenderObjectWidget] that wires [WaveformCanvasRenderObject]
/// into the widget tree.
///
/// Callers should use [WaveformCanvas] (the public ConsumerStatefulWidget)
/// rather than this widget directly.
class WaveformCanvasView extends LeafRenderObjectWidget {
  const WaveformCanvasView({
    required this.lanes,
    required this.timeMapper,
    required this.cursorState,
    required this.colorTheme,
    this.fontSize = 12.0,
    this.lineWidthScale = 1.0,
    this.selectionRange,
    this.selectedTransaction,
    this.divergenceRegions = const [],
    this.patternMatchRegions = const [],
    this.xOriginTime,
    this.xOriginSignalRefs = const {},
    this.selectedRowPaths = const {},
    this.selectionColor = const Color(0xFF2196F3),
    this.statsCollector,
    this.viewportTop,
    this.viewportBottom,
    this.recordPaintCommands = false,
    super.key,
  });

  /// Pixel font size for the in-canvas value labels and group-header labels.
  /// Driven by `AppSettings.waveformFontSize` from the Settings → Display
  /// section; clamped 8–24 px by the slider.
  final double fontSize;

  /// Multiplier applied to every trace / lane-divider stroke width (1.0 =
  /// default). Driven by the Settings → Appearance "Boost legibility for XR /
  /// large displays" toggle: when enabled the host passes a value > 1 so
  /// traces stay readable at the low angular resolution of XR/AR glasses.
  final double lineWidthScale;

  final List<WaveformLaneData> lanes;
  final TimeMapper timeMapper;

  /// Primary/secondary cursor times.
  ///
  /// The render object no longer paints the cursor *line* or delta chip —
  /// those live in a sibling [CursorOverlay] layer wrapped in its own
  /// [RepaintBoundary] so cursor scrubbing does not invalidate the lane
  /// painting. This field is retained because [AnalogSignalPainter] draws
  /// an inline value dot + label at the primary cursor position on each
  /// analog lane, which is per-lane content that must be redrawn alongside
  /// the trace itself.
  ///
  /// The render object's [WaveformCanvasRenderObject.cursorState] setter
  /// is analog-aware: it skips [markNeedsPaint] when no analog lanes are
  /// present, so digital-only canvases (the typical case) pay zero repaint
  /// cost for cursor changes.
  final CursorState cursorState;
  final CruxColorTheme colorTheme;
  final TimeSelection? selectionRange;

  /// The currently selected transaction (from the transaction table or a canvas
  /// tap). Passed to [TransactionPainter] to highlight the matching block.
  final DecodedTransaction? selectedTransaction;

  /// Divergence regions from an active waveform diff. Painted as semi-transparent
  /// amber bands spanning the full canvas height.
  final List<TimeRange> divergenceRegions;

  /// Pattern match regions from an active pattern search. Painted as
  /// semi-transparent green bands spanning the full canvas height.
  final List<TimeRange> patternMatchRegions;

  /// The simulation tick at which the X-origin was found, or `null` when no
  /// X-trace is active. Passed to [WaveformCanvasRenderObject] to paint
  /// per-lane X-origin markers.
  final int? xOriginTime;

  /// Signal refs (VCD idcodes) whose lanes should receive an X-origin marker.
  /// Empty when no X-trace is active.
  final Set<String> xOriginSignalRefs;

  /// Row paths of the currently selected signal lanes — the per-tab
  /// `selectedVariablesProvider` as it stands, keyed by full path. A lane whose
  /// [WaveformLaneData.rowPath] is in this set (or its signalRef, for a lane
  /// built without a path) gets a full-lane tint + left accent bar. Empty when
  /// nothing is selected.
  final Set<String> selectedRowPaths;

  /// Accent color for the selected-lane treatment — the host passes
  /// `Theme.of(context).colorScheme.primary` so the canvas highlight matches
  /// the signal-name and value panes.
  final Color selectionColor;

  /// Optional stats collector populated during [WaveformCanvasRenderObject.paint].
  ///
  /// Set by [WaveformCanvas] from its pane's `renderStatsCollectorProvider`,
  /// so every paint feeds that pane's statistics strip and render-stats
  /// popover. Null only when the render object is built without one; it then
  /// skips all instrumentation.
  final RenderStatsCollector? statsCollector;

  /// Top y of the visible scroll viewport in canvas-local coordinates.
  ///
  /// When both [viewportTop] and [viewportBottom] are non-null, the render
  /// object skips painting lanes entirely outside the visible region — the
  /// dominant optimization for canvases with hundreds or thousands of signals.
  /// Null disables viewport culling (every lane is painted).
  final double? viewportTop;

  /// Bottom y of the visible scroll viewport in canvas-local coordinates.
  /// See [viewportTop].
  final double? viewportBottom;

  /// When `true`, [WaveformCanvasRenderObject.lastPaintCommands] is populated
  /// at the end of each paint call with a structured snapshot of draw commands.
  ///
  /// Set to `true` in widget tests to assert on rendered content (transaction
  /// colors, XOR lane presence, selection overlays) without comparing pixel
  /// images. Leave `false` in production — there is no capture overhead when
  /// this flag is off.
  final bool recordPaintCommands;

  @override
  WaveformCanvasRenderObject createRenderObject(BuildContext context) {
    final theme = Theme.of(context);
    final valueBase =
        theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    final labelBase =
        theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11);
    return WaveformCanvasRenderObject(
        lanes: lanes,
        timeMapper: timeMapper,
        cursorState: cursorState,
        colorTheme: colorTheme,
        valueTextStyle: valueBase.copyWith(fontSize: fontSize),
        groupLabelStyle: labelBase.copyWith(fontSize: fontSize),
        lineWidthScale: lineWidthScale,
        selectionRange: selectionRange,
        selectedTransaction: selectedTransaction,
        divergenceRegions: divergenceRegions,
        patternMatchRegions: patternMatchRegions,
        xOriginTime: xOriginTime,
        xOriginSignalRefs: xOriginSignalRefs,
        statsCollector: statsCollector,
        recordPaintCommands: recordPaintCommands,
      )
      ..selectedRowPaths = selectedRowPaths
      ..selectionColor = selectionColor
      ..viewportTop = viewportTop
      ..viewportBottom = viewportBottom;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    WaveformCanvasRenderObject renderObject,
  ) {
    final theme = Theme.of(context);
    final valueBase =
        theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    final labelBase =
        theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11);
    renderObject
      ..lanes = lanes
      ..timeMapper = timeMapper
      ..cursorState = cursorState
      ..colorTheme = colorTheme
      ..valueTextStyle = valueBase.copyWith(fontSize: fontSize)
      ..groupLabelStyle = labelBase.copyWith(fontSize: fontSize)
      ..lineWidthScale = lineWidthScale
      ..selectionRange = selectionRange
      ..selectedTransaction = selectedTransaction
      ..divergenceRegions = divergenceRegions
      ..patternMatchRegions = patternMatchRegions
      ..xOriginTime = xOriginTime
      ..xOriginSignalRefs = xOriginSignalRefs
      ..selectedRowPaths = selectedRowPaths
      ..selectionColor = selectionColor
      ..statsCollector = statsCollector
      ..viewportTop = viewportTop
      ..viewportBottom = viewportBottom
      ..recordPaintCommands = recordPaintCommands;
  }
}

// ── RenderObject ──────────────────────────────────────────────────────────────

/// Custom [RenderBox] that paints all visible waveform signal lanes and cursor
/// overlays.
///
/// Each lane is rendered by a dedicated painter ([ScalarSignalPainter] for
/// 1-bit signals, [VectorSignalPainter] for buses) and clipped to its row
/// bounds.  Cursor and secondary-cursor overlays are composited on top.
///
/// The render object sizes itself to the total lane stack height (unbounded
/// in the scroll axis) so that a [SingleChildScrollView] parent provides
/// vertical scrolling.
class WaveformCanvasRenderObject extends RenderBox {
  WaveformCanvasRenderObject({
    required List<WaveformLaneData> lanes,
    required TimeMapper timeMapper,
    required CursorState cursorState,
    required CruxColorTheme colorTheme,
    required TextStyle valueTextStyle,
    required TextStyle groupLabelStyle,
    double lineWidthScale = 1.0,
    TimeSelection? selectionRange,
    DecodedTransaction? selectedTransaction,
    List<TimeRange> divergenceRegions = const [],
    List<TimeRange> patternMatchRegions = const [],
    int? xOriginTime,
    Set<String> xOriginSignalRefs = const {},
    this.statsCollector,
    this.recordPaintCommands = false,
  }) : _lanes = lanes,
       _hasAnalogLanes = lanes.any((l) => l.isAnalog),
       _timeMapper = timeMapper,
       _cursorState = cursorState,
       _colorTheme = colorTheme,
       _valueTextStyle = valueTextStyle,
       _groupLabelStyle = groupLabelStyle,
       _lineWidthScale = lineWidthScale,
       _selectionRange = selectionRange,
       _selectedTransaction = selectedTransaction,
       _divergenceRegions = divergenceRegions,
       _patternMatchRegions = patternMatchRegions,
       _xOriginTime = xOriginTime,
       _xOriginSignalRefs = xOriginSignalRefs;

  // ── test-recording fields ─────────────────────────────────────────────────

  /// Whether to capture [CanvasDrawCommand] entries at the end of each [paint].
  ///
  /// Set via [WaveformCanvasView.recordPaintCommands]. Production code leaves
  /// this `false`; widget and integration tests flip it `true` to inspect
  /// rendered content without golden-image comparisons.
  bool recordPaintCommands;

  /// Snapshot of draw commands captured during the most recent [paint] call.
  ///
  /// Only populated when [recordPaintCommands] is `true`. Tests read
  /// `.value` after pumping a frame to assert on transaction colors, XOR lane
  /// presence, lane-divider count, and selection overlays.
  final ValueNotifier<List<CanvasDrawCommand>> lastPaintCommands =
      ValueNotifier(const []);

  // ── mutable properties (setters trigger repaint) ──────────────────────────

  List<WaveformLaneData> get lanes => _lanes;
  List<WaveformLaneData> _lanes;
  set lanes(List<WaveformLaneData> value) {
    if (value == _lanes) return;
    _lanes = value;
    _hasAnalogLanes = value.any((l) => l.isAnalog);
    markNeedsLayout();
  }

  /// True when at least one lane in [_lanes] renders an analog trace.
  ///
  /// Cached so the [cursorState] setter can decide in O(1) whether a cursor
  /// change actually affects rendering. The only paint output that depends
  /// on cursor position inside the render object is the inline value dot +
  /// label that [AnalogSignalPainter] draws on each analog lane (see
  /// [WaveformCanvasView.cursorState] for the architectural rationale).
  /// When no analog lane is present the cursor lines and delta chip are
  /// painted entirely by the sibling cursor-overlay layer, so a cursor
  /// scrub on a digital-only canvas (the typical case — 1000+ logic
  /// signals) skips the lane repaint completely.
  bool _hasAnalogLanes;

  TimeMapper get timeMapper => _timeMapper;
  TimeMapper _timeMapper;
  set timeMapper(TimeMapper value) {
    if (value == _timeMapper) return;
    _timeMapper = value;
    markNeedsPaint();
  }

  CursorState get cursorState => _cursorState;
  CursorState _cursorState;
  set cursorState(CursorState value) {
    if (value == _cursorState) return;
    _cursorState = value;
    if (_hasAnalogLanes) {
      markNeedsPaint();
    }
  }

  CruxColorTheme get colorTheme => _colorTheme;
  CruxColorTheme _colorTheme;
  set colorTheme(CruxColorTheme value) {
    if (value == _colorTheme) return;
    _colorTheme = value;
    markNeedsPaint();
  }

  /// Trace / lane-divider stroke-width multiplier (1.0 = default). See
  /// [WaveformCanvasView.lineWidthScale].
  double get lineWidthScale => _lineWidthScale;
  double _lineWidthScale;
  set lineWidthScale(double value) {
    if (value == _lineWidthScale) return;
    _lineWidthScale = value;
    markNeedsPaint();
  }

  TimeSelection? get selectionRange => _selectionRange;
  TimeSelection? _selectionRange;
  set selectionRange(TimeSelection? value) {
    if (value == _selectionRange) return;
    _selectionRange = value;
    markNeedsPaint();
  }

  DecodedTransaction? get selectedTransaction => _selectedTransaction;
  DecodedTransaction? _selectedTransaction;
  set selectedTransaction(DecodedTransaction? value) {
    if (value == _selectedTransaction) return;
    _selectedTransaction = value;
    markNeedsPaint();
  }

  List<TimeRange> get divergenceRegions => _divergenceRegions;
  List<TimeRange> _divergenceRegions;
  set divergenceRegions(List<TimeRange> value) {
    if (value == _divergenceRegions) return;
    _divergenceRegions = value;
    markNeedsPaint();
  }

  List<TimeRange> get patternMatchRegions => _patternMatchRegions;
  List<TimeRange> _patternMatchRegions;
  set patternMatchRegions(List<TimeRange> value) {
    if (value == _patternMatchRegions) return;
    _patternMatchRegions = value;
    markNeedsPaint();
  }

  int? get xOriginTime => _xOriginTime;
  int? _xOriginTime;
  set xOriginTime(int? value) {
    if (value == _xOriginTime) return;
    _xOriginTime = value;
    markNeedsPaint();
  }

  Set<String> get xOriginSignalRefs => _xOriginSignalRefs;
  Set<String> _xOriginSignalRefs;
  set xOriginSignalRefs(Set<String> value) {
    if (value == _xOriginSignalRefs) return;
    _xOriginSignalRefs = value;
    markNeedsPaint();
  }

  /// Row paths of the currently-selected signal lanes.
  ///
  /// The per-tab selection lives in `selectedVariablesProvider` keyed by
  /// fullPath; [WaveformCanvas] hands that set here unchanged and each lane is
  /// matched by its own [WaveformLaneData.rowPath]. Not by signalRef: aliased
  /// variables share a ref, so selecting `up.clk` would also tint `down.clk`
  /// and every other alias of the net. A selected signal's lane gets a
  /// full-lane tint + left accent bar — the canvas-side counterpart of the
  /// signal-name/value panes' row highlight. A cross-probe from a sibling
  /// product selects the signal here, so this is what makes the inbound
  /// highlight visible on the trace itself, not just in the side panes.
  Set<String> get selectedRowPaths => _selectedRowPaths;
  Set<String> _selectedRowPaths = const {};
  set selectedRowPaths(Set<String> value) {
    if (value == _selectedRowPaths) return;
    _selectedRowPaths = value;
    markNeedsPaint();
  }

  /// Base accent color for the selected-lane treatment. Passed from
  /// [WaveformCanvas] as `Theme.of(context).colorScheme.primary` so the canvas
  /// highlight matches the tint the signal-name and value panes already use
  /// (see [value_column_row]).
  Color get selectionColor => _selectionColor;
  Color _selectionColor = const Color(0xFF2196F3);
  set selectionColor(Color value) {
    if (value == _selectionColor) return;
    _selectionColor = value;
    markNeedsPaint();
  }

  /// Optional stats collector populated during [paint].
  ///
  /// When null (diagnostics panel closed) all instrumentation is skipped.
  /// Updating this field never triggers a repaint — it is purely additive
  /// instrumentation with no visual effect.
  RenderStatsCollector? statsCollector;

  /// Top y of the visible scroll viewport (canvas-local coords). When null,
  /// every lane is painted regardless of scroll position.
  ///
  /// Set by [WaveformCanvas] from its scroll controller so the render object
  /// can skip lanes outside the visible region — the dominant optimization
  /// for waveforms with hundreds or thousands of signals where only a few
  /// dozen lanes are on screen at a time.
  double? get viewportTop => _viewportTop;
  double? _viewportTop;
  set viewportTop(double? value) {
    if (value == _viewportTop) return;
    _viewportTop = value;
    markNeedsPaint();
  }

  /// Bottom y of the visible scroll viewport (canvas-local coords). See
  /// [viewportTop].
  double? get viewportBottom => _viewportBottom;
  double? _viewportBottom;
  set viewportBottom(double? value) {
    if (value == _viewportBottom) return;
    _viewportBottom = value;
    markNeedsPaint();
  }

  TextStyle _valueTextStyle;
  TextStyle _groupLabelStyle;

  TextStyle get valueTextStyle => _valueTextStyle;
  set valueTextStyle(TextStyle value) {
    if (value == _valueTextStyle) return;
    _valueTextStyle = value;
    markNeedsPaint();
  }

  TextStyle get groupLabelStyle => _groupLabelStyle;
  set groupLabelStyle(TextStyle value) {
    if (value == _groupLabelStyle) return;
    _groupLabelStyle = value;
    markNeedsPaint();
  }

  // ── reusable Paint objects ──────────────────────────────────────────────────
  //
  // Paint objects allocated once and mutated as needed before each draw. Avoids
  // hundreds of allocations per frame on canvases with many signal lanes.

  final Paint _laneDividerPaint = Paint()
    ..strokeWidth = 0.5
    ..style = PaintingStyle.stroke;

  final Paint _selectionFillPaint = Paint()..style = PaintingStyle.fill;

  final Paint _selectionStrokePaint = Paint()
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;

  final Paint _patternFillPaint = Paint()
    ..color =
        const Color(0x2256AB4E) // green @ ~13%
    ..style = PaintingStyle.fill;

  final Paint _patternStrokePaint = Paint()
    ..color =
        const Color(0x5056AB4E) // green @ ~31%
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;

  final Paint _divergenceFillPaint = Paint()
    ..color =
        const Color(0x33FF9800) // amber @ ~20%
    ..style = PaintingStyle.fill;

  final Paint _divergenceStrokePaint = Paint()
    ..color =
        const Color(0x66FF9800) // amber @ ~40%
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;

  final Paint _xOriginLinePaint = Paint()
    ..color =
        const Color(0xFFEF5350) // red-400
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;

  final Paint _xOriginBgPaint = Paint()
    ..color =
        const Color(0x15EF5350) // red ~8% opacity
    ..style = PaintingStyle.fill;

  final Paint _xOriginDiamondPaint = Paint()
    ..color =
        const Color(0xFFEF5350) // red-400
    ..style = PaintingStyle.fill;

  final Paint _groupHeaderPaint = Paint()..style = PaintingStyle.fill;

  /// Full-lane tint painted behind a selected signal's trace.
  final Paint _selectionLaneBgPaint = Paint()..style = PaintingStyle.fill;

  /// Left accent bar drawn at the leading edge of a selected signal's lane.
  final Paint _selectionAccentPaint = Paint()..style = PaintingStyle.fill;

  /// Width (logical px) of the selected-lane left accent bar. Widened from the
  /// original 3 px so an inbound cross-probe selection reads clearly against a
  /// dense trace.
  static const double _selectionAccentWidth = 5;

  final Paint _xorBgPaint = Paint()
    ..color =
        const Color(0x1AFF9800) // amber ~10% opacity
    ..style = PaintingStyle.fill;

  final Paint _transactionBgPaint = Paint()..style = PaintingStyle.fill;

  // ── layout ────────────────────────────────────────────────────────────────

  double get _totalHeight => _lanes.fold(0, (sum, lane) => sum + lane.height);

  @override
  void performLayout() {
    size = constraints.constrain(Size(constraints.maxWidth, _totalHeight));
  }

  @override
  void dispose() {
    lastPaintCommands.dispose();
    super.dispose();
  }

  @override
  double computeMinIntrinsicHeight(double width) => _totalHeight;

  @override
  double computeMaxIntrinsicHeight(double width) => _totalHeight;

  // ── painting ──────────────────────────────────────────────────────────────

  @override
  void paint(PaintingContext context, Offset offset) {
    final sc = statsCollector;
    sc?.beginFrame();

    // When there are no lanes, zero the paint metrics and skip all painting
    // so the diagnostics panel does not show values from a previous non-empty
    // frame. Issue 26: pre-fix this reset recorded `Size.zero` for the
    // canvas extent, which surfaced as a misleading "0×0 px" in the Pane
    // Render Stats popover; report the render object's actual `size`
    // instead so the popover reflects the real on-screen canvas
    // dimensions even when nothing is being painted.
    if (_lanes.isEmpty) {
      sc
        ?..recordViewportInfo(0, 0, size)
        ..endFrame();
      return;
    }

    final canvas = context.canvas;
    final canvasWidth = size.width;

    canvas
      ..save()
      ..clipRect(offset & size)
      ..drawRect(offset & size, Paint()..color = _colorTheme.canvasBackground);

    // Viewport culling: when the wrapper provided scroll bounds, skip lanes
    // entirely above or below the visible region. Drops paint cost from O(N
    // lanes) to O(N visible lanes) — the dominant win for files with hundreds
    // or thousands of signals.
    final vTop = _viewportTop;
    final vBottom = _viewportBottom;
    final cullEnabled = vTop != null && vBottom != null && vBottom > vTop;

    // Refresh theme-derived paint colors (may have changed when colorTheme updates).
    _laneDividerPaint.color = _colorTheme.canvasLaneDivider;
    // Scale the lane divider with the legibility multiplier (default 0.5 px).
    _laneDividerPaint.strokeWidth = 0.5 * _lineWidthScale;
    final selection = _colorTheme.canvasSelection;
    _selectionFillPaint.color = selection;
    final selArgb = selection.toARGB32();
    final selAlpha = (selArgb >> 24) & 0xFF;
    final selRgb = selArgb & 0x00FFFFFF;
    _selectionStrokePaint.color = Color(
      ((selAlpha * 3).clamp(0, 0xFF) << 24) | selRgb,
    );
    final laneBgOddPaint = Paint()..color = _colorTheme.canvasLaneBackgroundOdd;
    final laneBgEvenPaint = Paint()
      ..color = _colorTheme.canvasLaneBackgroundEven;

    // Selected-lane treatment colors, refreshed from the accent passed by the
    // host (Theme primary) so the canvas highlight tracks light/dark and any
    // theme pack. The tint alpha is raised from the original 0.18 so an inbound
    // cross-probe selection is unmistakable behind a dense waveform, while
    // staying translucent enough to read the trace on top.
    _selectionLaneBgPaint.color = _selectionColor.withValues(alpha: 0.30);
    _selectionAccentPaint.color = _selectionColor;

    var visibleSignalRows = 0;
    var visibleTransitions = 0;

    var laneIndex = 0;
    for (final lane in _lanes) {
      final laneTop = lane.y;
      final laneBottom = lane.y + lane.height;

      if (cullEnabled && (laneBottom < vTop || laneTop > vBottom)) {
        laneIndex++;
        continue;
      }

      final laneRect = Rect.fromLTWH(
        offset.dx,
        offset.dy + lane.y,
        canvasWidth,
        lane.height,
      );

      // Alternating lane background (skipped for group headers and separators —
      // those paint their own surface).
      if (lane.kind == WaveformLaneKind.signal ||
          lane.kind == WaveformLaneKind.transaction ||
          lane.kind == WaveformLaneKind.xorDiff ||
          lane.kind == WaveformLaneKind.comment) {
        canvas.drawRect(
          laneRect,
          laneIndex.isOdd ? laneBgOddPaint : laneBgEvenPaint,
        );
      }
      laneIndex++;

      // Selected-signal treatment: full-lane tint painted UNDER the trace
      // (drawn next) so the highlight reads as a lane background, plus a left
      // accent bar painted after. Matches the row highlight the signal-name
      // and value panes show, and is the on-canvas cue an inbound cross-probe
      // selection was previously missing.
      final isSelectedLane =
          lane.kind == WaveformLaneKind.signal &&
          lane.signalRef != null &&
          _selectedRowPaths.contains(lane.rowPath ?? lane.signalRef);
      if (isSelectedLane) {
        canvas.drawRect(laneRect, _selectionLaneBgPaint);
      }

      switch (lane.kind) {
        case WaveformLaneKind.signal:
          _paintSignalLane(canvas, laneRect, lane, sc);
          visibleSignalRows++;
          visibleTransitions += lane.changes.length;
        case WaveformLaneKind.group:
          _paintGroupHeader(canvas, laneRect, lane);
        case WaveformLaneKind.separator:
          _paintSeparator(canvas, laneRect);
        case WaveformLaneKind.comment:
          _paintComment(canvas, laneRect, lane);
        case WaveformLaneKind.transaction:
          if (sc != null) {
            final sw = Stopwatch()..start();
            _paintTransactionLane(canvas, laneRect, lane);
            sw.stop();
            sc.recordTransactionPaint(sw.elapsedMicroseconds);
          } else {
            _paintTransactionLane(canvas, laneRect, lane);
          }
        case WaveformLaneKind.xorDiff:
          _paintXorDiffLane(canvas, laneRect, lane);
      }

      // Subtle lane divider line — uses the cached paint object.
      canvas.drawLine(
        Offset(laneRect.left, laneRect.bottom),
        Offset(laneRect.right, laneRect.bottom),
        _laneDividerPaint,
      );

      // Left accent bar for a selected lane, painted last so it stays crisp
      // over the trace and the alternating background.
      if (isSelectedLane) {
        canvas.drawRect(
          Rect.fromLTWH(
            laneRect.left,
            laneRect.top,
            _selectionAccentWidth,
            laneRect.height,
          ),
          _selectionAccentPaint,
        );
      }
    }

    // Selection range overlay (semi-transparent blue fill + border).
    final sel = _selectionRange?.normalized();
    if (sel != null && !sel.isEmpty && !_timeMapper.isEmpty) {
      final x1 = _timeMapper.timeToPixel(sel.startTime).clamp(0.0, size.width);
      final x2 = _timeMapper.timeToPixel(sel.endTime).clamp(0.0, size.width);
      if (x2 > x1) {
        final selRect = Rect.fromLTWH(
          offset.dx + x1,
          offset.dy,
          x2 - x1,
          size.height,
        );
        canvas
          ..drawRect(selRect, _selectionFillPaint)
          ..drawRect(selRect, _selectionStrokePaint);
      }
    }

    // Pattern match overlays drawn above signal lanes, below divergence/cursor.
    _paintPatternMatchOverlays(canvas, offset);

    // Divergence overlays drawn above signal lanes, below cursor.
    _paintDivergenceOverlays(canvas, offset);

    // X-origin markers drawn per-lane.
    //
    // Cursor lines and the delta chip are painted by the sibling
    // [CursorOverlay] layer (a separate [RepaintBoundary]) so cursor
    // scrubbing does not invalidate this lane painting. Inline analog
    // cursor labels are still drawn per-lane by [AnalogSignalPainter] above.
    _paintXOriginMarkers(canvas, offset);

    canvas.restore();

    if (sc != null) {
      sc
        ..recordViewportInfo(visibleSignalRows, visibleTransitions, size)
        ..endFrame();
    }

    if (recordPaintCommands) {
      lastPaintCommands.value = _buildDrawCommands(offset);
    }
  }

  /// Builds a structured list of [CanvasDrawCommand] entries from the most
  /// recent paint pass. Called only when [recordPaintCommands] is `true`.
  ///
  /// Captures: lane dividers, transaction blocks (with error vs. normal color),
  /// XOR diff lane backgrounds, and the selection range overlay. Does not
  /// attempt to replicate every raw canvas call — only the semantically
  /// meaningful commands that widget and integration tests assert on.
  List<CanvasDrawCommand> _buildDrawCommands(Offset offset) {
    final commands = <CanvasDrawCommand>[];
    final vTop = _viewportTop;
    final vBottom = _viewportBottom;
    final cullEnabled = vTop != null && vBottom != null && vBottom > vTop;

    for (final lane in _lanes) {
      if (cullEnabled && (lane.y + lane.height < vTop || lane.y > vBottom)) {
        continue;
      }

      final laneRect = Rect.fromLTWH(
        offset.dx,
        offset.dy + lane.y,
        size.width,
        lane.height,
      );

      // Lane divider line at bottom edge.
      commands.add(
        DrawLine(
          Offset(laneRect.left, laneRect.bottom),
          Offset(laneRect.right, laneRect.bottom),
          _laneDividerPaint,
        ),
      );

      // Selected-lane tint + left accent bar, so a widget test can assert the
      // canvas actually paints a selection cue on the selected signal's lane
      // (the P1 payoff — an inbound cross-probe selection is now visible on the
      // trace, not only in the side panes).
      if (lane.kind == WaveformLaneKind.signal &&
          lane.signalRef != null &&
          _selectedRowPaths.contains(lane.rowPath ?? lane.signalRef)) {
        commands
          ..add(
            DrawRect(
              laneRect,
              Paint()
                ..style = PaintingStyle.fill
                // Keep in lockstep with `_selectionLaneBgPaint` on the direct
                // canvas path — both raised from 0.18 for a clearer cross-probe
                // cue.
                ..color = _selectionColor.withValues(alpha: 0.30),
            ),
          )
          ..add(
            DrawRect(
              Rect.fromLTWH(
                laneRect.left,
                laneRect.top,
                _selectionAccentWidth,
                laneRect.height,
              ),
              Paint()
                ..style = PaintingStyle.fill
                ..color = _selectionColor,
            ),
          );
      }

      // Transaction blocks — one DrawRect per transaction with error vs. normal
      // fill color so tests can assert on isError coloring without pixel diffs.
      if (lane.kind == WaveformLaneKind.transaction && !_timeMapper.isEmpty) {
        for (final tx in lane.transactions) {
          final x1 = _timeMapper
              .timeToPixel(tx.startTime)
              .clamp(0.0, size.width);
          final x2 = _timeMapper.timeToPixel(tx.endTime).clamp(x1, size.width);
          if (x2 <= x1) continue;
          final txRect = Rect.fromLTRB(
            offset.dx + x1,
            laneRect.top + 2,
            offset.dx + x2,
            laneRect.bottom - 2,
          );
          final txPaint = Paint()
            ..style = PaintingStyle.fill
            ..color = tx.isError
                ? const Color(0xFFEF5350)
                : lane.transactionColor;
          commands.add(DrawRect(txRect, txPaint));
        }
      }

      // XOR diff lane — emit the background rect so tests can assert presence.
      if (lane.kind == WaveformLaneKind.xorDiff) {
        commands.add(DrawRect(laneRect, _xorBgPaint));
      }
    }

    // Selection range overlay.
    final sel = _selectionRange?.normalized();
    if (sel != null && !sel.isEmpty && !_timeMapper.isEmpty) {
      final x1 = _timeMapper.timeToPixel(sel.startTime).clamp(0.0, size.width);
      final x2 = _timeMapper.timeToPixel(sel.endTime).clamp(0.0, size.width);
      if (x2 > x1) {
        commands.add(
          DrawRect(
            Rect.fromLTWH(offset.dx + x1, offset.dy, x2 - x1, size.height),
            _selectionFillPaint,
          ),
        );
      }
    }

    // Divergence overlay rectangles (amber tint spanning full canvas height).
    if (!_timeMapper.isEmpty) {
      for (final region in _divergenceRegions) {
        final x1 = _timeMapper.timeToPixel(region.start).clamp(0.0, size.width);
        final x2 = _timeMapper.timeToPixel(region.end).clamp(0.0, size.width);
        if (x2 <= x1) continue;
        commands.add(
          DrawRect(
            Rect.fromLTWH(offset.dx + x1, offset.dy, x2 - x1, size.height),
            _divergenceFillPaint,
          ),
        );
      }
    }

    // Pattern match overlay rectangles (green tint spanning full canvas height).
    if (!_timeMapper.isEmpty) {
      for (final region in _patternMatchRegions) {
        final x1 = _timeMapper.timeToPixel(region.start).clamp(0.0, size.width);
        final x2 = _timeMapper.timeToPixel(region.end).clamp(0.0, size.width);
        if (x2 <= x1) continue;
        commands.add(
          DrawRect(
            Rect.fromLTWH(offset.dx + x1, offset.dy, x2 - x1, size.height),
            _patternFillPaint,
          ),
        );
      }
    }

    // X-origin markers — per involved lane: background tint, dashed line, diamond.
    final xOriginT = _xOriginTime;
    if (xOriginT != null &&
        _xOriginSignalRefs.isNotEmpty &&
        !_timeMapper.isEmpty) {
      final x = _timeMapper.timeToPixel(xOriginT);
      if (x >= 0 && x <= size.width) {
        const dashLen = 4.0;
        const gapLen = 3.0;
        for (final lane in _lanes) {
          if (lane.kind != WaveformLaneKind.signal) continue;
          if (!_xOriginSignalRefs.contains(lane.signalRef)) continue;
          if (cullEnabled &&
              (lane.y + lane.height < vTop || lane.y > vBottom)) {
            continue;
          }
          final laneTop = offset.dy + lane.y;
          final laneBottom = laneTop + lane.height;
          final laneRight = offset.dx + size.width;
          final cx = offset.dx + x;

          // Background tint from X-origin to right edge of lane.
          commands.add(
            DrawRect(
              Rect.fromLTRB(cx, laneTop, laneRight, laneBottom),
              _xOriginBgPaint,
            ),
          );

          // Dashed vertical line segments spanning the lane height.
          var y0 = laneTop;
          while (y0 < laneBottom) {
            final y1 = (y0 + dashLen).clamp(laneTop, laneBottom);
            commands.add(
              DrawLine(Offset(cx, y0), Offset(cx, y1), _xOriginLinePaint),
            );
            y0 += dashLen + gapLen;
          }

          // Diamond anchor path at the top of the lane.
          const half = 4.0;
          final path = Path()
            ..moveTo(cx, laneTop + 1)
            ..lineTo(cx + half, laneTop + 1 + half)
            ..lineTo(cx, laneTop + 1 + half * 2)
            ..lineTo(cx - half, laneTop + 1 + half)
            ..close();
          commands.add(DrawPath(path, _xOriginDiamondPaint));
        }
      }
    }

    return commands;
  }

  // ── per-lane painters ─────────────────────────────────────────────────────

  void _paintSignalLane(
    Canvas canvas,
    Rect bounds,
    WaveformLaneData lane,
    RenderStatsCollector? sc,
  ) {
    final segCount = sc != null ? lane.changes.length : 0;

    if (lane.isAnalog) {
      if (sc != null) {
        final sw = Stopwatch()..start();
        AnalogSignalPainter.paint(
          canvas: canvas,
          laneBounds: bounds,
          changes: lane.changes,
          valueAtStart: lane.valueAtStart,
          timeMapper: _timeMapper,
          signalColor: lane.signalColor,
          interpolation: lane.analogInterpolation,
          valueStyle: _valueTextStyle,
          manualMin: lane.analogRangeMin,
          manualMax: lane.analogRangeMax,
          primaryCursorTime: _cursorState.primaryCursorTime,
          lineWidthScale: _lineWidthScale,
          valueExtractor:
              lane.analogValueExtractor ?? AnalogValueExtractors.real,
        );
        sw.stop();
        sc.recordAnalogPaint(sw.elapsedMicroseconds, segCount);
      } else {
        AnalogSignalPainter.paint(
          canvas: canvas,
          laneBounds: bounds,
          changes: lane.changes,
          valueAtStart: lane.valueAtStart,
          timeMapper: _timeMapper,
          signalColor: lane.signalColor,
          interpolation: lane.analogInterpolation,
          valueStyle: _valueTextStyle,
          manualMin: lane.analogRangeMin,
          manualMax: lane.analogRangeMax,
          primaryCursorTime: _cursorState.primaryCursorTime,
          lineWidthScale: _lineWidthScale,
          valueExtractor:
              lane.analogValueExtractor ?? AnalogValueExtractors.real,
        );
      }
    } else if (lane.isScalar) {
      if (sc != null) {
        final sw = Stopwatch()..start();
        ScalarSignalPainter.paint(
          canvas: canvas,
          laneBounds: bounds,
          changes: lane.changes,
          valueAtStart: lane.valueAtStart,
          timeMapper: _timeMapper,
          signalColor: lane.signalColor,
          xColor: _colorTheme.canvasSignalXFill,
          xHatchColor: _colorTheme.canvasSignalXHatch,
          zColor: _colorTheme.canvasSignalZLine,
          lineWidthScale: _lineWidthScale,
        );
        sw.stop();
        sc.recordScalarPaint(sw.elapsedMicroseconds, segCount);
      } else {
        ScalarSignalPainter.paint(
          canvas: canvas,
          laneBounds: bounds,
          changes: lane.changes,
          valueAtStart: lane.valueAtStart,
          timeMapper: _timeMapper,
          signalColor: lane.signalColor,
          xColor: _colorTheme.canvasSignalXFill,
          xHatchColor: _colorTheme.canvasSignalXHatch,
          zColor: _colorTheme.canvasSignalZLine,
          lineWidthScale: _lineWidthScale,
        );
      }
    } else {
      if (sc != null) {
        final sw = Stopwatch()..start();
        VectorSignalPainter.paint(
          canvas: canvas,
          laneBounds: bounds,
          changes: lane.changes,
          valueAtStart: lane.valueAtStart,
          timeMapper: _timeMapper,
          signalColor: lane.signalColor,
          xColor: _colorTheme.canvasSignalXFill,
          xHatchColor: _colorTheme.canvasSignalXHatch,
          zColor: _colorTheme.canvasSignalZLine,
          format: lane.format,
          bitWidth: lane.bitWidth,
          valueStyle: _valueTextStyle,
          translateFilter: lane.translateFilter,
          translatorConfig: lane.translatorConfig,
          lineWidthScale: _lineWidthScale,
        );
        sw.stop();
        sc.recordVectorPaint(sw.elapsedMicroseconds, segCount);
      } else {
        VectorSignalPainter.paint(
          canvas: canvas,
          laneBounds: bounds,
          changes: lane.changes,
          valueAtStart: lane.valueAtStart,
          timeMapper: _timeMapper,
          signalColor: lane.signalColor,
          xColor: _colorTheme.canvasSignalXFill,
          xHatchColor: _colorTheme.canvasSignalXHatch,
          zColor: _colorTheme.canvasSignalZLine,
          format: lane.format,
          bitWidth: lane.bitWidth,
          valueStyle: _valueTextStyle,
          translateFilter: lane.translateFilter,
          translatorConfig: lane.translatorConfig,
          lineWidthScale: _lineWidthScale,
        );
      }
    }
  }

  void _paintGroupHeader(Canvas canvas, Rect bounds, WaveformLaneData lane) {
    _groupHeaderPaint.color = _colorTheme.canvasGroupHeader;
    canvas.drawRect(bounds, _groupHeaderPaint);

    if (lane.displayName.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: lane.displayName,
          style: _groupLabelStyle.copyWith(
            color: _colorTheme.canvasRulerTickMajor,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: bounds.width - 16);

      tp.paint(
        canvas,
        Offset(
          bounds.left + (bounds.width - tp.width) / 2,
          bounds.top + (bounds.height - tp.height) / 2,
        ),
      );
    }
  }

  void _paintSeparator(Canvas canvas, Rect bounds) {
    // Blank separator lane — no content.
  }

  void _paintComment(Canvas canvas, Rect bounds, WaveformLaneData lane) {
    if (lane.commentText == null || lane.commentText!.isEmpty) return;

    final tp = TextPainter(
      text: TextSpan(
        text: '// ${lane.commentText}',
        style: _groupLabelStyle.copyWith(
          color: _colorTheme.canvasRulerTickMajor,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: bounds.width - 16);

    tp.paint(
      canvas,
      Offset(bounds.left + 8, bounds.top + (bounds.height - tp.height) / 2),
    );
  }

  void _paintTransactionLane(
    Canvas canvas,
    Rect bounds,
    WaveformLaneData lane,
  ) {
    // Subtle background tint matching the [DecoderListEntry] row in the
    // signal list — the row owns the decoder name label, so the canvas
    // lane paints transactions only.  See ARCHITECTURE.md §6.5 for the
    // panel-alignment rationale and `decoder_list_entry.dart` for the
    // moved label.
    _transactionBgPaint.color = lane.transactionColor.withValues(alpha: 0.06);
    canvas.drawRect(bounds, _transactionBgPaint);

    TransactionPainter.paint(
      canvas: canvas,
      laneBounds: bounds,
      transactions: lane.transactions,
      timeMapper: _timeMapper,
      laneColor: lane.transactionColor,
      labelStyle: _valueTextStyle,
      selectedTransaction: _selectedTransaction,
    );
  }

  void _paintXorDiffLane(Canvas canvas, Rect bounds, WaveformLaneData lane) {
    // Subtle amber background so the XOR lane is visually distinct from signal lanes.
    canvas.drawRect(bounds, _xorBgPaint);

    // "⊕" label at left edge — matches the style used by _paintTransactionLane.
    final tp = TextPainter(
      text: TextSpan(
        text: '⊕',
        style: _groupLabelStyle.copyWith(
          color: const Color(0xB3FF9800), // amber 70% opacity
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 20);
    tp.paint(
      canvas,
      Offset(bounds.left + 4, bounds.top + (bounds.height - tp.height) / 2),
    );

    // Render the XOR trace as a scalar signal using full-opacity amber.
    ScalarSignalPainter.paint(
      canvas: canvas,
      laneBounds: bounds,
      changes: lane.xorChanges,
      valueAtStart: lane.xorValueAtStart,
      timeMapper: _timeMapper,
      signalColor: const Color(0xFFFF9800), // amber
      xColor: _colorTheme.canvasSignalXFill,
      xHatchColor: _colorTheme.canvasSignalXHatch,
      zColor: _colorTheme.canvasSignalZLine,
    );
  }

  void _paintPatternMatchOverlays(Canvas canvas, Offset offset) {
    if (_patternMatchRegions.isEmpty || _timeMapper.isEmpty) return;

    for (final region in _patternMatchRegions) {
      final x1 = _timeMapper.timeToPixel(region.start).clamp(0.0, size.width);
      final x2 = _timeMapper.timeToPixel(region.end).clamp(0.0, size.width);
      if (x2 <= x1) continue;
      final rect = Rect.fromLTWH(
        offset.dx + x1,
        offset.dy,
        x2 - x1,
        size.height,
      );
      canvas
        ..drawRect(rect, _patternFillPaint)
        ..drawRect(rect, _patternStrokePaint);
    }
  }

  void _paintDivergenceOverlays(Canvas canvas, Offset offset) {
    if (_divergenceRegions.isEmpty || _timeMapper.isEmpty) return;

    for (final region in _divergenceRegions) {
      final x1 = _timeMapper.timeToPixel(region.start).clamp(0.0, size.width);
      final x2 = _timeMapper.timeToPixel(region.end).clamp(0.0, size.width);
      if (x2 <= x1) continue;
      final rect = Rect.fromLTWH(
        offset.dx + x1,
        offset.dy,
        x2 - x1,
        size.height,
      );
      canvas
        ..drawRect(rect, _divergenceFillPaint)
        ..drawRect(rect, _divergenceStrokePaint);
    }
  }

  void _paintXOriginMarkers(Canvas canvas, Offset offset) {
    final t = _xOriginTime;
    if (t == null || _xOriginSignalRefs.isEmpty || _timeMapper.isEmpty) return;

    final x = _timeMapper.timeToPixel(t);
    if (x < 0 || x > size.width) return;

    // Dashes for the vertical line: 4px on, 3px off.
    const dashLen = 4.0;
    const gapLen = 3.0;

    final vTop = _viewportTop;
    final vBottom = _viewportBottom;
    final cullEnabled = vTop != null && vBottom != null && vBottom > vTop;

    for (final lane in _lanes) {
      if (lane.kind != WaveformLaneKind.signal) continue;
      if (!_xOriginSignalRefs.contains(lane.signalRef)) continue;
      if (cullEnabled && (lane.y + lane.height < vTop || lane.y > vBottom)) {
        continue;
      }

      final laneTop = offset.dy + lane.y;
      final laneBottom = laneTop + lane.height;
      final laneRight = offset.dx + size.width;
      final cx = offset.dx + x;

      // Background tint from X-origin to right edge of lane.
      canvas.drawRect(
        Rect.fromLTRB(cx, laneTop, laneRight, laneBottom),
        _xOriginBgPaint,
      );

      // Dashed vertical line spanning the lane height.
      var y0 = laneTop;
      while (y0 < laneBottom) {
        final y1 = (y0 + dashLen).clamp(laneTop, laneBottom);
        canvas.drawLine(Offset(cx, y0), Offset(cx, y1), _xOriginLinePaint);
        y0 += dashLen + gapLen;
      }

      // Diamond anchor at the top of the lane.
      const half = 4.0;
      final path = Path()
        ..moveTo(cx, laneTop + 1)
        ..lineTo(cx + half, laneTop + 1 + half)
        ..lineTo(cx, laneTop + 1 + half * 2)
        ..lineTo(cx - half, laneTop + 1 + half)
        ..close();
      canvas.drawPath(path, _xOriginDiamondPaint);
    }
  }

  // ── hit testing ──────────────────────────────────────────────────────────

  @override
  bool hitTestSelf(Offset position) => true;
}
