// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:wavecrux/features/viewer/rendering/waveform_lane_data.dart';

/// Compact geometry for **every** lane the canvas would render, kept separate
/// from the rich [WaveformLaneData] objects the painter consumes.
///
/// At gate-level scale ("Add All in Scope" on a 1.3M-variable netlist) the
/// canvas cannot afford to construct one [WaveformLaneData] per entry — the
/// per-lane map lookups, strings, and object churn cost seconds per pass on
/// slow targets (web/DDC most visibly; a 17 s frozen frame in the beta
/// recording that motivated this split). This index stores only what every
/// consumer of *all* lanes actually needs — position, size, kind, and a
/// pointer to the source object — in typed arrays plus one pointer slot per
/// lane. Rich lanes are then materialized **only for the viewport window**
/// (`WaveformCanvas._materializeLanes`), which is O(visible), not O(total).
///
/// Payload contract by [WaveformLaneKind]:
/// - `signal` / `group` / `separator` / `comment` — the source `SignalEntry`.
/// - `xorDiff` — the *parent signal's* `SignalEntry` (the diff trace is keyed
///   by its signalRef; content is re-derived from `DiffState` on
///   materialization).
/// - `transaction` — the `ActiveDecoder` the lane belongs to.
///
/// Lanes are top-to-bottom: [tops] is strictly increasing and, because lanes
/// never overlap, lane bottoms (`tops[i] + heights[i]`) are non-decreasing —
/// the invariant [visibleRange]'s binary search relies on. Gaps between
/// lanes are legal (reserved translator child-row space).
class LaneGeometryIndex {
  LaneGeometryIndex({
    required this.tops,
    required this.heights,
    required this.kinds,
    required this.payloads,
    required this.bottom,
    required this.signalLaneCount,
  }) : assert(
         tops.length == heights.length &&
             tops.length == kinds.length &&
             tops.length == payloads.length,
         'parallel arrays must have equal length',
       );

  /// The empty index (no file / no lanes).
  static final LaneGeometryIndex empty = LaneGeometryIndex(
    tops: Float64List(0),
    heights: Float64List(0),
    kinds: Uint8List(0),
    payloads: const [],
    bottom: 0,
    signalLaneCount: 0,
  );

  /// Lane top y-coordinates, strictly increasing.
  final Float64List tops;

  /// Lane heights, parallel to [tops].
  final Float64List heights;

  /// [WaveformLaneKind] indices, parallel to [tops].
  final Uint8List kinds;

  /// Source object per lane — see the payload contract in the class doc.
  final List<Object?> payloads;

  /// The y-coordinate just past the last lane *including* trailing reserved
  /// child-row space — the canvas content extent (see issue #43).
  final double bottom;

  /// Number of `signal`-kind lanes (drives e.g. the accessibility label
  /// without an O(N) recount per build).
  final int signalLaneCount;

  /// Total lane count.
  int get length => tops.length;

  /// The [WaveformLaneKind] of lane [i].
  WaveformLaneKind kindAt(int i) => WaveformLaneKind.values[kinds[i]];

  /// Index range `[first, lastExclusive)` of lanes intersecting the vertical
  /// window `[top, bottom]`. Binary-searched — O(log n).
  (int, int) visibleRange(double top, double bottom) {
    final n = length;
    if (n == 0 || bottom < top) return (0, 0);

    // First lane whose bottom edge reaches the window: lane bottoms are
    // non-decreasing, so lower-bound on (tops[i] + heights[i] >= top).
    var lo = 0;
    var hi = n;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (tops[mid] + heights[mid] < top) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final first = lo;

    // First lane starting past the window: lower-bound on (tops[i] > bottom).
    lo = first;
    hi = n;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (tops[mid] <= bottom) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return (first, lo);
  }
}
