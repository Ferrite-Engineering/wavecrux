// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/rendering/lane_geometry_index.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_lane_data.dart';

/// Stacks [heights] from y = 0 downward with optional [gapAfter] blank space
/// after each lane (translator child-row reservations).
LaneGeometryIndex _stack(List<double> heights, {double gapAfter = 0}) {
  final tops = Float64List(heights.length);
  final hs = Float64List(heights.length);
  final kinds = Uint8List(heights.length);
  var y = 0.0;
  for (var i = 0; i < heights.length; i++) {
    tops[i] = y;
    hs[i] = heights[i];
    kinds[i] = WaveformLaneKind.signal.index;
    y += heights[i] + gapAfter;
  }
  return LaneGeometryIndex(
    tops: tops,
    heights: hs,
    kinds: kinds,
    payloads: List<Object?>.filled(heights.length, null),
    bottom: y,
    signalLaneCount: heights.length,
  );
}

void main() {
  group('LaneGeometryIndex.visibleRange', () {
    test('empty index yields an empty range', () {
      expect(LaneGeometryIndex.empty.visibleRange(0, 1000), (0, 0));
      expect(LaneGeometryIndex.empty.length, 0);
    });

    test('window covering everything returns the full range', () {
      final g = _stack(List.filled(10, 20));
      expect(g.visibleRange(0, 1000), (0, 10));
    });

    test('interior window returns only intersecting lanes', () {
      // Lane i occupies [i*20, i*20+20).
      final g = _stack(List.filled(100, 20));
      final (first, last) = g.visibleRange(200, 400);
      // Lane 9 ends at 200 (bottom == top of window → intersects);
      // lane 20 starts at 400 (top == bottom of window → intersects).
      expect(first, 9);
      expect(last, 21);
    });

    test('window above all lanes is empty', () {
      final g = _stack(List.filled(10, 20));
      expect(g.visibleRange(-500, -100), (0, 0));
    });

    test('window below all lanes is empty', () {
      final g = _stack(List.filled(10, 20));
      final (first, last) = g.visibleRange(5000, 6000);
      expect(first, last);
    });

    test('inverted window is empty', () {
      final g = _stack(List.filled(10, 20));
      expect(g.visibleRange(400, 200), (0, 0));
    });

    test('handles gaps between lanes (child-row reservations)', () {
      // Lanes at [0,20), [50,70), [100,120) with 30px gaps.
      final g = _stack(List.filled(3, 20), gapAfter: 30);
      // A window entirely inside the first gap intersects nothing.
      final (first, last) = g.visibleRange(25, 45);
      expect(first, last);
      // A window straddling the gap picks up the neighbors.
      expect(g.visibleRange(15, 55), (0, 2));
      // Bottom includes the trailing gap.
      expect(g.bottom, 150);
    });

    test('varying lane heights keep the search correct', () {
      // Lanes: [0,10), [10,110), [110,140).
      final g = _stack([10, 100, 30]);
      expect(g.visibleRange(50, 60), (1, 2));
      expect(g.visibleRange(0, 5), (0, 1));
      expect(g.visibleRange(139, 139), (2, 3));
    });

    test('kindAt maps back to the lane kind enum', () {
      final g = _stack([20]);
      expect(g.kindAt(0), WaveformLaneKind.signal);
    });
  });
}
