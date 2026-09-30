// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// How close, in logical pixels, a click must fall to a transition for the
/// anchor to snap onto it.
///
/// Eight pixels is roughly a comfortable pointer-accuracy radius without being
/// so wide that a deliberate mid-plateau anchor gets yanked to an edge.
const double kAnnotationSnapRadiusPx = 8;

/// The result of hit-testing a canvas position against the waveform.
@immutable
final class ResolvedAnchor {
  const ResolvedAnchor({
    required this.time,
    required this.rowId,
    required this.signalRef,
    required this.snapped,
  });

  /// The tick the anchor lands on — snapped to a transition when one was in
  /// range and snapping is enabled.
  final int time;

  /// Stable row identity (`SignalEntry.signalPath`).
  final String rowId;

  /// Backend-local ref for the same row, so the caller can read a value
  /// without re-resolving.
  final String signalRef;

  /// Whether [time] was moved onto a transition.
  final bool snapped;

  PointAnchor toAnchor() => PointAnchor(time: time, rowId: rowId);
}

/// Turns a canvas position into an [Annotation] anchor.
///
/// **Edge snapping is on by default, and that is a correctness decision rather
/// than a convenience.** People annotate *edges*. An unsnapped pixel→tick
/// mapping hands back 1247 when the user meant 1250, and the witness value is
/// then captured on the wrong side of the transition — so the note records the
/// value the signal held *before* the event it is describing, and a later
/// reload compares against that. The feature would be quietly wrong in the one
/// case it exists to serve.
class AnnotationAnchorResolver {
  const AnnotationAnchorResolver();

  /// Resolves a canvas-local [position] to an anchor, or `null` when the
  /// position does not land on an annotatable signal row.
  ///
  /// [scrollOffset] is the canvas's vertical scroll offset, so content-space
  /// row tops map into the viewport the click was measured in.
  ///
  /// Rows without a `signalPath` — groups, separators, comments — are not
  /// annotatable: there is no stable identity to anchor to and no value to
  /// witness.
  ResolvedAnchor? resolve({
    required Offsetish position,
    required TimeMapper mapper,
    required LaneGeometry geometry,
    required double scrollOffset,
    WaveformDataSource? source,
    bool snapToEdges = true,
    double snapRadiusPx = kAnnotationSnapRadiusPx,
  }) {
    final row = _rowAt(geometry, position.dy + scrollOffset);
    if (row == null) return null;

    final rowId = row.entry.signalPath;
    final signalRef = row.entry.signalRef;
    if (rowId == null || rowId.isEmpty || signalRef == null) return null;

    final rawTime = mapper.pixelToTime(position.dx);
    if (!snapToEdges || source == null) {
      return ResolvedAnchor(
        time: rawTime,
        rowId: rowId,
        signalRef: signalRef,
        snapped: false,
      );
    }

    final snappedTime = _snapToNearestEdge(
      source: source,
      signalRef: signalRef,
      mapper: mapper,
      rawTime: rawTime,
      rawPixel: position.dx,
      snapRadiusPx: snapRadiusPx,
    );
    return ResolvedAnchor(
      time: snappedTime ?? rawTime,
      rowId: rowId,
      signalRef: signalRef,
      snapped: snappedTime != null,
    );
  }

  /// The nearest transition to [rawTime] within [snapRadiusPx], or `null`.
  ///
  /// Distance is measured in **pixels, not ticks**, so the snap feels the same
  /// at every zoom level. At a coarse zoom a tick-radius would snap across
  /// hundreds of nanoseconds; at a fine one it would never engage.
  int? _snapToNearestEdge({
    required WaveformDataSource source,
    required String signalRef,
    required TimeMapper mapper,
    required int rawTime,
    required double rawPixel,
    required double snapRadiusPx,
  }) {
    final candidates = <int>[
      ?source.prevTransition(signalRef, rawTime)?.time,
      ?source.nextTransition(signalRef, rawTime)?.time,
    ];
    // `prevTransition` is strictly-before and `nextTransition` strictly-after,
    // so a click landing exactly ON an edge would otherwise miss it. Probe the
    // half-open tick window instead of asking `valueAt`, which answers
    // non-null at every time after the first transition and would make every
    // click "snap" to itself.
    if (source.changesInRange(signalRef, rawTime, rawTime + 1).isNotEmpty) {
      candidates.add(rawTime);
    }

    int? best;
    var bestDistance = double.infinity;
    for (final time in candidates) {
      final distance = (mapper.timeToPixel(time) - rawPixel).abs();
      if (distance <= snapRadiusPx && distance < bestDistance) {
        best = time;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// The row whose vertical band contains [contentY] (content space).
  LaneRow? _rowAt(LaneGeometry geometry, double contentY) {
    for (final row in geometry.rows) {
      if (contentY >= row.top && contentY < row.bottom) return row;
    }
    return null;
  }
}

/// Minimal x/y pair, so this service stays free of `dart:ui` like the rest of
/// the domain and can be exercised without a binding.
@immutable
class Offsetish {
  const Offsetish(this.dx, this.dy);

  final double dx;
  final double dy;
}
