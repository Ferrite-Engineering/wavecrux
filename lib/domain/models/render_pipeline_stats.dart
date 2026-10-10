// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Per-frame paint statistics collected from the waveform canvas render object.
@immutable
class RenderPipelineStats {
  const RenderPipelineStats({
    required this.visibleSignalRows,
    required this.visibleTransitions,
    required this.lineSegmentsDrawn,
    required this.layoutTimeUs,
    required this.scalarPaintTimeUs,
    required this.vectorPaintTimeUs,
    required this.analogPaintTimeUs,
    required this.cursorPaintTimeUs,
    required this.transactionPaintTimeUs,
    required this.totalPaintTimeUs,
    required this.canvasWidth,
    required this.canvasHeight,
  });

  /// Number of signal lanes currently visible in the viewport.
  final int visibleSignalRows;

  /// Value changes the signal lanes hold inside the visible time range, as
  /// drawn: after reduction to pixel columns, and without the off-screen band
  /// either side that the canvas caches for panning.
  final int visibleTransitions;

  /// Number of line segments drawn during the last paint call.
  final int lineSegmentsDrawn;

  final int layoutTimeUs;
  final int scalarPaintTimeUs;
  final int vectorPaintTimeUs;
  final int analogPaintTimeUs;
  final int cursorPaintTimeUs;
  final int transactionPaintTimeUs;

  /// Wall-clock microseconds for the entire paint() call.
  final int totalPaintTimeUs;

  final double canvasWidth;
  final double canvasHeight;

  RenderPipelineStats copyWith({
    int? visibleSignalRows,
    int? visibleTransitions,
    int? lineSegmentsDrawn,
    int? layoutTimeUs,
    int? scalarPaintTimeUs,
    int? vectorPaintTimeUs,
    int? analogPaintTimeUs,
    int? cursorPaintTimeUs,
    int? transactionPaintTimeUs,
    int? totalPaintTimeUs,
    double? canvasWidth,
    double? canvasHeight,
  }) => RenderPipelineStats(
    visibleSignalRows: visibleSignalRows ?? this.visibleSignalRows,
    visibleTransitions: visibleTransitions ?? this.visibleTransitions,
    lineSegmentsDrawn: lineSegmentsDrawn ?? this.lineSegmentsDrawn,
    layoutTimeUs: layoutTimeUs ?? this.layoutTimeUs,
    scalarPaintTimeUs: scalarPaintTimeUs ?? this.scalarPaintTimeUs,
    vectorPaintTimeUs: vectorPaintTimeUs ?? this.vectorPaintTimeUs,
    analogPaintTimeUs: analogPaintTimeUs ?? this.analogPaintTimeUs,
    cursorPaintTimeUs: cursorPaintTimeUs ?? this.cursorPaintTimeUs,
    transactionPaintTimeUs:
        transactionPaintTimeUs ?? this.transactionPaintTimeUs,
    totalPaintTimeUs: totalPaintTimeUs ?? this.totalPaintTimeUs,
    canvasWidth: canvasWidth ?? this.canvasWidth,
    canvasHeight: canvasHeight ?? this.canvasHeight,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RenderPipelineStats &&
          runtimeType == other.runtimeType &&
          visibleSignalRows == other.visibleSignalRows &&
          visibleTransitions == other.visibleTransitions &&
          lineSegmentsDrawn == other.lineSegmentsDrawn &&
          layoutTimeUs == other.layoutTimeUs &&
          scalarPaintTimeUs == other.scalarPaintTimeUs &&
          vectorPaintTimeUs == other.vectorPaintTimeUs &&
          analogPaintTimeUs == other.analogPaintTimeUs &&
          cursorPaintTimeUs == other.cursorPaintTimeUs &&
          transactionPaintTimeUs == other.transactionPaintTimeUs &&
          totalPaintTimeUs == other.totalPaintTimeUs &&
          canvasWidth == other.canvasWidth &&
          canvasHeight == other.canvasHeight;

  @override
  int get hashCode => Object.hashAll([
    visibleSignalRows,
    visibleTransitions,
    lineSegmentsDrawn,
    layoutTimeUs,
    scalarPaintTimeUs,
    vectorPaintTimeUs,
    analogPaintTimeUs,
    cursorPaintTimeUs,
    transactionPaintTimeUs,
    totalPaintTimeUs,
    canvasWidth,
    canvasHeight,
  ]);

  @override
  String toString() =>
      'RenderPipelineStats('
      'visibleRows: $visibleSignalRows, '
      'visibleTransitions: $visibleTransitions, '
      'segments: $lineSegmentsDrawn, '
      'totalPaintUs: $totalPaintTimeUs, '
      'canvas: ${canvasWidth}x$canvasHeight'
      ')';
}
