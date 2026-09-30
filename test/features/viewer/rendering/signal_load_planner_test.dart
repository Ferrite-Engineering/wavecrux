// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/viewer/rendering/lane_geometry_index.dart';
import 'package:wavecrux/features/viewer/rendering/signal_load_planner.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_lane_data.dart';

/// One geometry slot: kind + optional signal ref, laid out top-to-bottom.
typedef _Slot = ({WaveformLaneKind kind, String? ref, double height});

_Slot _signal(String ref, {double height = 20}) =>
    (kind: WaveformLaneKind.signal, ref: ref, height: height);

_Slot _group({double height = 20}) =>
    (kind: WaveformLaneKind.group, ref: null, height: height);

/// Builds a [LaneGeometryIndex] by stacking [slots] from y = 0 downward —
/// the same shape the canvas's geometry builder produces.
LaneGeometryIndex _geometry(List<_Slot> slots) {
  final tops = Float64List(slots.length);
  final heights = Float64List(slots.length);
  final kinds = Uint8List(slots.length);
  final payloads = List<Object?>.filled(slots.length, null);
  var y = 0.0;
  var signals = 0;
  for (var i = 0; i < slots.length; i++) {
    final slot = slots[i];
    tops[i] = y;
    heights[i] = slot.height;
    kinds[i] = slot.kind.index;
    payloads[i] = switch (slot.kind) {
      WaveformLaneKind.signal => SignalEntry.signal(
        signalRef: slot.ref,
        displayName: slot.ref ?? '',
      ),
      _ => const SignalEntry.separator(),
    };
    if (slot.kind == WaveformLaneKind.signal) signals++;
    y += slot.height;
  }
  return LaneGeometryIndex(
    tops: tops,
    heights: heights,
    kinds: kinds,
    payloads: payloads,
    bottom: y,
    signalLaneCount: signals,
  );
}

void main() {
  group('SignalLoadPlanner.viewportVisibleRefs', () {
    // 100 signal lanes, 20px tall, stacked 0..2000.
    final geometry = _geometry([for (var i = 0; i < 100; i++) _signal('$i')]);
    final allRefs = [for (var i = 0; i < 100; i++) '$i'];

    test('empty geometry loads nothing (nothing to paint)', () {
      final refs = SignalLoadPlanner.viewportVisibleRefs(
        geometry: LaneGeometryIndex.empty,
        viewportTop: 0,
        viewportBottom: 400,
        viewportHeight: 400,
        overscanPx: 0,
        initialViewportHeight: 900,
      );
      expect(refs, isEmpty);
    });

    test('returns only lanes intersecting the window (no overscan)', () {
      // Window [200, 400) → lanes at y in [180, 400] given 20px height.
      final refs = SignalLoadPlanner.viewportVisibleRefs(
        geometry: geometry,
        viewportTop: 200,
        viewportBottom: 400,
        viewportHeight: 200,
        overscanPx: 0,
        initialViewportHeight: 900,
      );
      // Lane i occupies [i*20, i*20+20]. Intersects [200,400]: i=9..20.
      expect(refs.first, '9');
      expect(refs.last, '20');
      expect(refs.length, lessThan(allRefs.length));
    });

    test('overscan widens the window above and below', () {
      final tight = SignalLoadPlanner.viewportVisibleRefs(
        geometry: geometry,
        viewportTop: 1000,
        viewportBottom: 1200,
        viewportHeight: 200,
        overscanPx: 0,
        initialViewportHeight: 900,
      );
      final wide = SignalLoadPlanner.viewportVisibleRefs(
        geometry: geometry,
        viewportTop: 1000,
        viewportBottom: 1200,
        viewportHeight: 200,
        overscanPx: 200,
        initialViewportHeight: 900,
      );
      expect(wide.length, greaterThan(tight.length));
      // Overscan never balloons to the whole file.
      expect(wide.length, lessThan(allRefs.length));
    });

    test('skips non-signal lanes and de-duplicates', () {
      final mixed = _geometry([
        _group(),
        _signal('a'),
        _signal('a'), // duplicate ref (e.g. same signal in two groups)
        _signal('b'),
      ]);
      final refs = SignalLoadPlanner.viewportVisibleRefs(
        geometry: mixed,
        viewportTop: 0,
        viewportBottom: 100,
        viewportHeight: 100,
        overscanPx: 0,
        initialViewportHeight: 900,
      );
      expect(refs, equals(['a', 'b']));
    });

    test('uses the initial-height estimate when viewport is unknown', () {
      // Null bounds → window [0, initialViewportHeight]. With 200px it should
      // include only the first ~10 lanes, NOT all 100 (the key scalability win:
      // an initial Add-All does not eagerly load every signal).
      final refs = SignalLoadPlanner.viewportVisibleRefs(
        geometry: geometry,
        viewportTop: null,
        viewportBottom: null,
        viewportHeight: 0,
        overscanPx: 0,
        initialViewportHeight: 200,
      );
      expect(refs, isNotEmpty);
      expect(refs.length, lessThan(20));
      expect(refs.first, '0');
    });
  });

  group('SignalLoadPlanner.budgetFor', () {
    test('floors at minBudget for small visible counts', () {
      expect(
        SignalLoadPlanner.budgetFor(visibleCount: 10, minBudget: 256),
        256,
      );
    });
    test('scales with visible count past the floor', () {
      expect(
        SignalLoadPlanner.budgetFor(visibleCount: 200, minBudget: 256),
        600,
      );
    });
  });

  group('SignalLoadPlanner.evictionPlan', () {
    bool allLoaded(String _) => true;

    test('evicts nothing while within budget', () {
      final plan = SignalLoadPlanner.evictionPlan(
        lruOrder: ['a', 'b', 'c'],
        isLoaded: allLoaded,
        visible: {'c'},
        budget: 10,
      );
      expect(plan, isEmpty);
    });

    test('evicts oldest-first down to budget, never the visible set', () {
      // 6 loaded, budget 3 → evict 3, but skip currently-visible 'a'/'f'.
      final plan = SignalLoadPlanner.evictionPlan(
        lruOrder: ['a', 'b', 'c', 'd', 'e', 'f'],
        isLoaded: allLoaded,
        visible: {'a', 'f'},
        budget: 3,
      );
      // overflow = 6 - 3 = 3; oldest non-visible first: b, c, d.
      expect(plan, equals(['b', 'c', 'd']));
      expect(plan, isNot(contains('a')));
      expect(plan, isNot(contains('f')));
    });

    test('ignores refs that are no longer loaded', () {
      final plan = SignalLoadPlanner.evictionPlan(
        lruOrder: ['a', 'b', 'c', 'd'],
        isLoaded: (r) => r != 'b', // 'b' already unloaded elsewhere
        visible: const {},
        budget: 2,
      );
      // loaded = [a, c, d]; overflow = 1; oldest non-visible = a.
      expect(plan, equals(['a']));
    });
  });
}
