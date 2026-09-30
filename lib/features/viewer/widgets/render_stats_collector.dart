// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:wavecrux/domain/models/render_pipeline_stats.dart';

/// Accumulates per-frame waveform paint metrics from [WaveformCanvasRenderObject].
///
/// The render object holds an optional reference to this collector and calls
/// [beginFrame] at the start of each [paint] call, then records each paint
/// phase via the `record*` methods, and finally calls [endFrame] to publish
/// a [RenderPipelineStats] snapshot and notify listeners.
///
/// When [WaveformCanvasRenderObject.statsCollector] is null (the default when
/// the diagnostics panel is closed) there is zero overhead — no collector
/// instance exists and no code paths are exercised.
class RenderStatsCollector extends ChangeNotifier {
  RenderPipelineStats? _stats;

  /// The latest published stats snapshot, or null before [endFrame] has been
  /// called for the first time.
  RenderPipelineStats? get stats => _stats;

  // Frame durations are not collected here. They are an app-wide signal, not a
  // per-pane one, and their one reader — the App Diagnostics dialog —
  // registers its own `SchedulerBinding` timings callback for as long as it is
  // open, so nothing pays for them while it is closed.

  // ── per-frame accumulators ────────────────────────────────────────────────

  int _layoutTimeUs = 0;
  int _scalarPaintTimeUs = 0;
  int _vectorPaintTimeUs = 0;
  int _analogPaintTimeUs = 0;
  int _cursorPaintTimeUs = 0;
  int _transactionPaintTimeUs = 0;
  int _visibleSignalRows = 0;
  int _visibleTransitions = 0;
  int _lineSegmentsDrawn = 0;
  double _canvasWidth = 0;
  double _canvasHeight = 0;

  // ── frame lifecycle ───────────────────────────────────────────────────────

  /// Resets all accumulators. Called at the very start of each paint pass.
  void beginFrame() {
    _layoutTimeUs = 0;
    _scalarPaintTimeUs = 0;
    _vectorPaintTimeUs = 0;
    _analogPaintTimeUs = 0;
    _cursorPaintTimeUs = 0;
    _transactionPaintTimeUs = 0;
    _visibleSignalRows = 0;
    _visibleTransitions = 0;
    _lineSegmentsDrawn = 0;
    _canvasWidth = 0;
    _canvasHeight = 0;
  }

  // ── record methods ────────────────────────────────────────────────────────

  /// Records the time spent computing lane geometry before the paint loop.
  void recordLayout(int timeUs) => _layoutTimeUs += timeUs;

  /// Records time and segment count for one scalar (1-bit) signal lane.
  void recordScalarPaint(int timeUs, int segmentCount) {
    _scalarPaintTimeUs += timeUs;
    _lineSegmentsDrawn += segmentCount;
  }

  /// Records time and segment count for one vector (multi-bit) signal lane.
  void recordVectorPaint(int timeUs, int segmentCount) {
    _vectorPaintTimeUs += timeUs;
    _lineSegmentsDrawn += segmentCount;
  }

  /// Records time and segment count for one analog (real-valued) signal lane.
  void recordAnalogPaint(int timeUs, int segmentCount) {
    _analogPaintTimeUs += timeUs;
    _lineSegmentsDrawn += segmentCount;
  }

  /// Records time spent painting the cursor overlay.
  void recordCursorPaint(int timeUs) => _cursorPaintTimeUs += timeUs;

  /// Records time spent painting protocol-decoder transaction lanes.
  void recordTransactionPaint(int timeUs) => _transactionPaintTimeUs += timeUs;

  /// Records viewport dimensions and signal/transition counts.
  void recordViewportInfo(
    int visibleRows,
    int visibleTransitions,
    Size canvasSize,
  ) {
    _visibleSignalRows = visibleRows;
    _visibleTransitions = visibleTransitions;
    _canvasWidth = canvasSize.width;
    _canvasHeight = canvasSize.height;
  }

  /// Builds a [RenderPipelineStats] snapshot from accumulated data and
  /// notifies listeners. Called at the end of each paint pass.
  void endFrame() {
    final totalPaintTimeUs =
        _layoutTimeUs +
        _scalarPaintTimeUs +
        _vectorPaintTimeUs +
        _analogPaintTimeUs +
        _cursorPaintTimeUs +
        _transactionPaintTimeUs;

    _stats = RenderPipelineStats(
      visibleSignalRows: _visibleSignalRows,
      visibleTransitions: _visibleTransitions,
      lineSegmentsDrawn: _lineSegmentsDrawn,
      layoutTimeUs: _layoutTimeUs,
      scalarPaintTimeUs: _scalarPaintTimeUs,
      vectorPaintTimeUs: _vectorPaintTimeUs,
      analogPaintTimeUs: _analogPaintTimeUs,
      cursorPaintTimeUs: _cursorPaintTimeUs,
      transactionPaintTimeUs: _transactionPaintTimeUs,
      totalPaintTimeUs: totalPaintTimeUs,
      canvasWidth: _canvasWidth,
      canvasHeight: _canvasHeight,
    );
    notifyListeners();
  }
}
