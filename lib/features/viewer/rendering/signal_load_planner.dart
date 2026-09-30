// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/viewer/rendering/lane_geometry_index.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_lane_data.dart';

/// Pure planning helpers for the canvas's viewport-gated signal loading and
/// LRU eviction. Kept free of widget/render state so the gating and eviction
/// contracts are unit-testable in isolation (see
/// `test/features/viewer/rendering/signal_load_planner_test.dart`).
abstract final class SignalLoadPlanner {
  /// Signal refs whose lane intersects the visible vertical window expanded by
  /// [overscanPx] above and below. Derived purely from the lane [geometry]
  /// index — which is data-independent and covers ALL lanes (the canvas
  /// materializes rich lane objects only for the viewport, so the geometry
  /// index, not the materialized lanes, is the full coordinate system).
  ///
  /// Order is top-to-bottom and duplicates are removed, so the caller loads
  /// on-screen signals in the order the user sees them.
  ///
  /// An empty [geometry] loads nothing — the refresh runs post-frame, so the
  /// index always reflects the current signal list; empty means there is
  /// genuinely nothing to load. (This replaced an all-refs fallback that
  /// required the caller to flatten every entry — an O(all-entries) pass per
  /// scroll tick at gate-level scale.)
  ///
  /// [viewportTop] / [viewportBottom] are the scroll-derived bounds; either may
  /// be null before the first layout, in which case the window is taken as
  /// `[0, initialViewportHeight]` (a bounded first-screen estimate) rather than
  /// the whole content.
  static List<String> viewportVisibleRefs({
    required LaneGeometryIndex geometry,
    required double? viewportTop,
    required double? viewportBottom,
    required double viewportHeight,
    required double overscanPx,
    required double initialViewportHeight,
  }) {
    final result = <String>[];
    final seen = <String>{};
    for (final entry in viewportVisibleEntries(
      geometry: geometry,
      viewportTop: viewportTop,
      viewportBottom: viewportBottom,
      viewportHeight: viewportHeight,
      overscanPx: overscanPx,
      initialViewportHeight: initialViewportHeight,
    )) {
      if (seen.add(entry.signalRef!)) result.add(entry.signalRef!);
    }
    return result;
  }

  /// The signal entries behind [viewportVisibleRefs], one per lane, top to
  /// bottom and not de-duplicated: the same ref can sit in two lanes drawn
  /// differently (one as a bus, one as an analog curve), and a caller that
  /// needs to know how a ref is drawn needs every lane. Only entries with a
  /// non-null [SignalEntry.signalRef] are returned.
  static List<SignalEntry> viewportVisibleEntries({
    required LaneGeometryIndex geometry,
    required double? viewportTop,
    required double? viewportBottom,
    required double viewportHeight,
    required double overscanPx,
    required double initialViewportHeight,
  }) {
    if (geometry.length == 0) return const <SignalEntry>[];
    final top0 = viewportTop ?? 0;
    final height = viewportHeight > 0 ? viewportHeight : initialViewportHeight;
    final bottom0 = viewportBottom ?? (top0 + height);
    final (first, lastExclusive) = geometry.visibleRange(
      top0 - overscanPx,
      bottom0 + overscanPx,
    );

    final result = <SignalEntry>[];
    for (var i = first; i < lastExclusive; i++) {
      if (geometry.kindAt(i) != WaveformLaneKind.signal) continue;
      final entry = geometry.payloads[i]! as SignalEntry;
      if (entry.signalRef == null) continue;
      result.add(entry);
    }
    return result;
  }

  /// Budget for how many decompressed signals to retain before evicting: at
  /// least [minBudget], otherwise a multiple of the currently-visible count so
  /// a few screens of scroll-back stay warm.
  static int budgetFor({required int visibleCount, required int minBudget}) =>
      math.max(minBudget, visibleCount * 3);

  /// The off-screen signals to unload so the loaded set drops back to [budget].
  ///
  /// [lruOrder] is oldest-(least-recently-visible)-first; [isLoaded] reports
  /// whether a ref currently holds decompressed data; [visible] are the
  /// currently on-screen refs, which are never evicted. Returns the refs to
  /// unload, oldest first, or an empty list when within budget.
  static List<String> evictionPlan({
    required List<String> lruOrder,
    required bool Function(String) isLoaded,
    required Set<String> visible,
    required int budget,
  }) {
    final loaded = lruOrder.where(isLoaded).toList();
    final overflow = loaded.length - budget;
    if (overflow <= 0) return const <String>[];
    final plan = <String>[];
    for (final ref in loaded) {
      if (plan.length >= overflow) break;
      if (visible.contains(ref)) continue;
      plan.add(ref);
    }
    return plan;
  }
}
