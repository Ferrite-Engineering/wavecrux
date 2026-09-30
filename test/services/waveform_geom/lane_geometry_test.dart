// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';

// Desktop (16) and touch (44) min-lane floors, matching MobileMetrics.
const _desktop = LaneMetrics(minLaneHeight: 16);
const _touch = LaneMetrics(minLaneHeight: 44);

SignalEntry _sig(String ref, double laneHeight) => SignalEntry.signal(
  signalRef: ref,
  displayName: ref,
  laneHeight: laneHeight,
);

void main() {
  group('LaneMetrics', () {
    test('structural heights default to the canonical constants', () {
      const m = LaneMetrics(minLaneHeight: 44);
      expect(m.groupHeaderHeight, kGroupHeaderHeight);
      expect(m.separatorHeight, kSeparatorHeight);
      expect(m.commentHeight, kCommentHeight);
    });

    test('value equality so it can key a Riverpod family', () {
      expect(
        const LaneMetrics(minLaneHeight: 44),
        const LaneMetrics(minLaneHeight: 44),
      );
      expect(
        const LaneMetrics(minLaneHeight: 44).hashCode,
        const LaneMetrics(minLaneHeight: 44).hashCode,
      );
      expect(
        const LaneMetrics(minLaneHeight: 44),
        isNot(const LaneMetrics(minLaneHeight: 16)),
      );
    });
  });

  group('LaneGeometry.heightForEntry', () {
    test('signal row clamps stored laneHeight UP to minLaneHeight only', () {
      // Stored above the floor → passes through unchanged.
      expect(LaneGeometry.heightForEntry(_sig('a', 30), _desktop), 30);
      // Stored below the touch floor → clamped up at render.
      expect(LaneGeometry.heightForEntry(_sig('a', 30), _touch), 44);
    });

    test(
      'store raw, render clamped: a sub-min stored height is not flattened',
      () {
        final entry = _sig('a', 8);
        // The model renders the floor…
        expect(LaneGeometry.heightForEntry(entry, _touch), 44);
        expect(LaneGeometry.heightForEntry(entry, _desktop), 16);
        // …but never mutates the stored value, so the same entry re-opened on a
        // lower-floor (desktop) session keeps its raw height intact.
        expect(entry.laneHeight, 8);
      },
    );

    test(
      'model imposes no upper bound — the writer enforces the 200 dp cap',
      () {
        // setLaneHeight() clamps to [min, 200]; the geometry model trusts the
        // stored value and never re-clamps the top end.
        expect(LaneGeometry.heightForEntry(_sig('a', 200), _touch), 200);
        expect(LaneGeometry.heightForEntry(_sig('a', 250), _touch), 250);
      },
    );

    test('structural rows render at fixed heights on every device class', () {
      const group = SignalEntry.group(groupName: 'g');
      const sep = SignalEntry.separator();
      const comment = SignalEntry.comment(text: 'c');
      for (final m in [_desktop, _touch]) {
        expect(LaneGeometry.heightForEntry(group, m), kGroupHeaderHeight);
        expect(LaneGeometry.heightForEntry(sep, m), kSeparatorHeight);
        expect(LaneGeometry.heightForEntry(comment, m), kCommentHeight);
      }
    });
  });

  group('LaneGeometry — cumulative offsets', () {
    test('stacks heights into cumulative tops and a total', () {
      final geometry = LaneGeometry(
        entries: [
          _sig('a', 30),
          const SignalEntry.separator(),
          _sig('b', 50),
          const SignalEntry.comment(text: 'c'),
        ],
        metrics: _desktop,
      );

      expect(geometry.rows.map((r) => r.height).toList(), [30, 10, 50, 22]);
      expect(geometry.rows.map((r) => r.top).toList(), [0, 30, 40, 90]);
      expect(geometry.totalHeight, 112);
      expect(geometry.topAt(2), 40);
      expect(geometry.heightAt(2), 50);
      expect(geometry.rows[2].bottom, 90);
    });

    test('flattens an expanded group: header then its children inline', () {
      final geometry = LaneGeometry(
        entries: [
          SignalEntry.group(
            groupName: 'cpu',
            children: [_sig('clk', 30), _sig('rst', 30)],
          ),
          _sig('top', 30),
        ],
        metrics: _desktop,
      );

      // group header (22), clk (30), rst (30), top (30).
      expect(geometry.rows.map((r) => r.entry.kind).toList(), [
        SignalEntryKind.group,
        SignalEntryKind.signal,
        SignalEntryKind.signal,
        SignalEntryKind.signal,
      ]);
      expect(geometry.rows.map((r) => r.top).toList(), [0, 22, 52, 82]);
      expect(geometry.totalHeight, 112);
    });

    test('a collapsed group contributes only its header row', () {
      final geometry = LaneGeometry(
        entries: [
          SignalEntry.group(
            groupName: 'cpu',
            collapsed: true,
            children: [_sig('clk', 30), _sig('rst', 30)],
          ),
          _sig('top', 30),
        ],
        metrics: _desktop,
      );

      expect(geometry.rows.length, 2); // header + top, no children
      expect(geometry.rows[0].entry.kind, SignalEntryKind.group);
      expect(geometry.rows[1].entry.signalRef, 'top');
      expect(geometry.rows[1].top, kGroupHeaderHeight);
    });

    test(
      'grouped signals are clamped on touch (the grouped-row alignment bug)',
      () {
        final geometry = LaneGeometry(
          entries: [
            SignalEntry.group(
              groupName: 'cpu',
              children: [_sig('clk', 30)],
            ),
          ],
          metrics: _touch,
        );
        // Group header is the fixed 22; the CHILD signal clamps up to 44.
        expect(geometry.rows[0].height, kGroupHeaderHeight);
        expect(geometry.rows[1].height, 44);
        expect(geometry.rows[1].top, kGroupHeaderHeight);
      },
    );

    test('empty entry list has zero total height', () {
      final geometry = LaneGeometry(entries: const [], metrics: _desktop);
      expect(geometry.rows, isEmpty);
      expect(geometry.totalHeight, 0);
    });
  });
}
