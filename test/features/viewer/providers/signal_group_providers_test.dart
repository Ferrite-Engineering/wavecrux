// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';

Variable _v(String name) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'ref_$name',
  scopePath: 'top',
);

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('SignalGroupsNotifier — initial state', () {
    test('starts empty', () {
      final c = _container();
      expect(c.read(signalGroupsProvider).entries, isEmpty);
    });
  });

  // ── addSignal ──────────────────────────────────────────────────────────────

  group('addSignal', () {
    test('appends a signal entry', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
      final entries = c.read(signalGroupsProvider).entries;
      expect(entries, hasLength(1));
      expect(entries.first.kind, SignalEntryKind.signal);
      expect(entries.first.signalRef, 'ref_clk');
      expect(entries.first.displayName, 'clk');
    });

    test('auto-assigns palette color', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('a'));
      final color = Color(
        c.read(signalGroupsProvider).entries.first.argbColor!,
      );
      expect(WavecruxColors.signalPalette, contains(color));
    });

    test('insertIndex places signal at correct position', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('a'))
        ..addSignal(_v('b'))
        ..addSignal(_v('mid'), insertIndex: 1);
      final entries = c.read(signalGroupsProvider).entries;
      expect(entries[0].signalRef, 'ref_a');
      expect(entries[1].signalRef, 'ref_mid');
      expect(entries[2].signalRef, 'ref_b');
    });

    test('insertIndex 0 prepends', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('a'))
        ..addSignal(_v('first'), insertIndex: 0);
      expect(
        c.read(signalGroupsProvider).entries.first.signalRef,
        'ref_first',
      );
    });

    test('out-of-bounds insertIndex clamps to end', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('a'))
        ..addSignal(_v('b'), insertIndex: 99);
      expect(
        c.read(signalGroupsProvider).entries.last.signalRef,
        'ref_b',
      );
    });
  });

  // ── addSignals ─────────────────────────────────────────────────────────────

  group('addSignals', () {
    test('appends multiple signals', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignals([
        _v('a'),
        _v('b'),
        _v('c'),
      ]);
      expect(c.read(signalGroupsProvider).entries, hasLength(3));
    });

    test('empty list is no-op', () {
      final c = _container();
      final before = c.read(signalGroupsProvider);
      c.read(signalGroupsProvider.notifier).addSignals([]);
      expect(c.read(signalGroupsProvider), equals(before));
    });

    test('assigns sequential palette colors', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignals([_v('a'), _v('b')]);
      final entries = c.read(signalGroupsProvider).entries;
      expect(
        Color(entries[0].argbColor!),
        WavecruxColors.signalPalette[0],
      );
      expect(
        Color(entries[1].argbColor!),
        WavecruxColors.signalPalette[1],
      );
    });

    test('bulk-added entries all get unique ids', () {
      final c = _container();
      final vars = [for (var i = 0; i < 10000; i++) _v('s$i')];
      c.read(signalGroupsProvider.notifier).addSignals(vars);
      final ids = c.read(signalGroupsProvider).entries.map((e) => e.id).toSet();
      expect(ids, hasLength(vars.length));
      expect(ids, isNot(contains('')));
    });
  });

  // ── addSignalsChunked ────────────────────────────────────────────────────────

  group('addSignalsChunked', () {
    test('produces the same entries as the synchronous add', () async {
      final vars = [for (var i = 0; i < 2500; i++) _v('s$i')];
      final sync = _container();
      final chunked = _container();
      sync.read(signalGroupsProvider.notifier).addSignals(vars);
      final ok = await chunked
          .read(signalGroupsProvider.notifier)
          .addSignalsChunked(vars, chunkSize: 1000);

      expect(ok, isTrue);
      final syncEntries = sync.read(signalGroupsProvider).entries;
      final chunkedEntries = chunked.read(signalGroupsProvider).entries;
      expect(chunkedEntries, hasLength(syncEntries.length));
      for (var i = 0; i < syncEntries.length; i++) {
        expect(chunkedEntries[i].signalRef, syncEntries[i].signalRef);
        expect(chunkedEntries[i].displayName, syncEntries[i].displayName);
        expect(chunkedEntries[i].argbColor, syncEntries[i].argbColor);
      }
    });

    test('sets state exactly once (no per-chunk listener churn)', () async {
      final c = _container();
      var changes = 0;
      c.listen(signalGroupsProvider, (_, _) => changes++);
      final vars = [for (var i = 0; i < 2500; i++) _v('s$i')];
      await c
          .read(signalGroupsProvider.notifier)
          .addSignalsChunked(vars, chunkSize: 100);
      expect(changes, 1);
    });

    test('reports monotonic progress reaching the total', () async {
      final c = _container();
      final vars = [for (var i = 0; i < 2500; i++) _v('s$i')];
      final reports = <int>[];
      await c
          .read(signalGroupsProvider.notifier)
          .addSignalsChunked(
            vars,
            chunkSize: 1000,
            onProgress: (built, total) {
              expect(total, vars.length);
              reports.add(built);
            },
          );
      expect(reports, [1000, 2000, 2500]);
    });

    test('cancellation abandons the add with nothing applied', () async {
      final c = _container();
      final vars = [for (var i = 0; i < 2500; i++) _v('s$i')];
      var calls = 0;
      final ok = await c
          .read(signalGroupsProvider.notifier)
          .addSignalsChunked(
            vars,
            chunkSize: 1000,
            // Cancel after the first chunk has been built.
            isCancelled: () => calls++ >= 1,
          );
      expect(ok, isFalse);
      expect(c.read(signalGroupsProvider).entries, isEmpty);
    });

    test('empty list is a no-op returning true', () async {
      final c = _container();
      final ok = await c
          .read(signalGroupsProvider.notifier)
          .addSignalsChunked(const []);
      expect(ok, isTrue);
      expect(c.read(signalGroupsProvider).entries, isEmpty);
    });
  });

  // ── removeSignal ───────────────────────────────────────────────────────────

  group('removeSignal', () {
    test('removes entry at index', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('a'))
        ..addSignal(_v('b'))
        ..removeSignal(0);
      final entries = c.read(signalGroupsProvider).entries;
      expect(entries, hasLength(1));
      expect(entries.first.signalRef, 'ref_b');
    });

    test('negative index is no-op', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('a'))
        ..removeSignal(-1);
      expect(c.read(signalGroupsProvider).entries, hasLength(1));
    });

    test('out-of-bounds index is no-op', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('a'))
        ..removeSignal(5);
      expect(c.read(signalGroupsProvider).entries, hasLength(1));
    });
  });

  // ── reorderSignal ──────────────────────────────────────────────────────────

  group('reorderSignal', () {
    test('moves entry downward', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignals([_v('a'), _v('b'), _v('c')])
        // Move index 0 (a) past index 2 (c). Under the onReorderItem
        // convention, newIndex is the post-removal insertion index, so
        // appending after the last remaining entry means newIndex = 2.
        ..reorderSignal(0, 2);
      final refs = c
          .read(signalGroupsProvider)
          .entries
          .map((e) => e.signalRef)
          .toList();
      expect(refs, ['ref_b', 'ref_c', 'ref_a']);
    });

    test('moves entry upward', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignals([_v('a'), _v('b'), _v('c')])
        // Move index 2 (c) to position 0
        ..reorderSignal(2, 0);
      final refs = c
          .read(signalGroupsProvider)
          .entries
          .map((e) => e.signalRef)
          .toList();
      expect(refs, ['ref_c', 'ref_a', 'ref_b']);
    });

    test('out-of-bounds oldIndex is no-op', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('a'))
        ..reorderSignal(5, 0);
      expect(c.read(signalGroupsProvider).entries, hasLength(1));
    });
  });

  // ── addGroup ───────────────────────────────────────────────────────────────

  group('addGroup', () {
    test('appends a group entry', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addGroup('Control');
      final entries = c.read(signalGroupsProvider).entries;
      expect(entries, hasLength(1));
      expect(entries.first.kind, SignalEntryKind.group);
      expect(entries.first.groupName, 'Control');
    });

    test('insertIndex works for group', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('a'))
        ..addSignal(_v('b'))
        ..addGroup('G', insertIndex: 1);
      expect(
        c.read(signalGroupsProvider).entries[1].kind,
        SignalEntryKind.group,
      );
    });
  });

  // ── addSeparator ───────────────────────────────────────────────────────────

  group('addSeparator', () {
    test('adds blank separator', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSeparator();
      expect(
        c.read(signalGroupsProvider).entries.first.kind,
        SignalEntryKind.separator,
      );
    });

    test('adds comment when text is provided', () {
      final c = _container();
      c
          .read(signalGroupsProvider.notifier)
          .addSeparator(comment: 'AXI bus signals');
      final entry = c.read(signalGroupsProvider).entries.first;
      expect(entry.kind, SignalEntryKind.comment);
      expect(entry.text, 'AXI bus signals');
    });
  });

  // ── toggleGroupCollapsed ───────────────────────────────────────────────────

  group('toggleGroupCollapsed', () {
    test('collapses an expanded group', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addGroup('G')
        ..toggleGroupCollapsed(0);
      expect(
        c.read(signalGroupsProvider).entries.first.collapsed,
        isTrue,
      );
    });

    test('expands a collapsed group', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addGroup('G')
        ..toggleGroupCollapsed(0)
        ..toggleGroupCollapsed(0);
      expect(
        c.read(signalGroupsProvider).entries.first.collapsed,
        isFalse,
      );
    });

    test('no-op on non-group entry', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..toggleGroupCollapsed(0); // signal, not group — no-op
      expect(c.read(signalGroupsProvider).entries, hasLength(1));
    });

    test('no-op on out-of-bounds index', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addGroup('G')
        ..toggleGroupCollapsed(5);
      expect(c.read(signalGroupsProvider).entries, hasLength(1));
    });
  });

  // ── setSignalColor ─────────────────────────────────────────────────────────

  group('setSignalColor', () {
    test('updates the argbColor of a signal entry', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..setSignalColor(0, WavecruxColors.signalCyan);
      expect(
        c.read(signalGroupsProvider).entries.first.argbColor,
        WavecruxColors.signalCyan.toARGB32(),
      );
    });

    test('no-op on non-signal entry', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addGroup('G')
        ..setSignalColor(0, WavecruxColors.signalCyan);
      expect(
        c.read(signalGroupsProvider).entries.first.argbColor,
        isNull,
      );
    });
  });

  // ── setSignalAlias ─────────────────────────────────────────────────────────

  group('setSignalAlias', () {
    test('updates displayName', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('data'))
        ..setSignalAlias(0, 'RX Data');
      expect(
        c.read(signalGroupsProvider).entries.first.displayName,
        'RX Data',
      );
    });

    test('no-op on out-of-bounds index', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('a'))
        ..setSignalAlias(5, 'X');
      expect(
        c.read(signalGroupsProvider).entries.first.displayName,
        'a',
      );
    });
  });

  // ── setSignalFormat ────────────────────────────────────────────────────────

  group('setSignalFormat', () {
    test('updates display format', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('bus'))
        ..setSignalFormat(0, DisplayFormat.binary);
      expect(
        c.read(signalGroupsProvider).entries.first.format,
        DisplayFormat.binary,
      );
    });

    test('no-op on non-signal entry', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addGroup('G')
        ..setSignalFormat(0, DisplayFormat.binary);
      // group entry format field remains at default
      expect(
        c.read(signalGroupsProvider).entries.first.format,
        DisplayFormat.hexadecimal,
      );
    });
  });

  // ── setLaneHeight ──────────────────────────────────────────────────────────

  group('setLaneHeight', () {
    test('updates lane height within valid range', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..setLaneHeight(0, 50);
      expect(
        c.read(signalGroupsProvider).entries.first.laneHeight,
        50,
      );
    });

    test('clamps height below 16 to 16', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..setLaneHeight(0, 5);
      expect(
        c.read(signalGroupsProvider).entries.first.laneHeight,
        16,
      );
    });

    test('clamps height above 200 to 200', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..setLaneHeight(0, 999);
      expect(
        c.read(signalGroupsProvider).entries.first.laneHeight,
        200,
      );
    });

    test('no-op on non-signal entry', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSeparator()
        ..setLaneHeight(0, 50);
      expect(
        c.read(signalGroupsProvider).entries.first.laneHeight,
        10,
      );
    });

    // Touch callers (signal_list_panel resize handler) pass
    // `minHeight: MobileMetrics.minLaneHeight` (44) so a small shrink drag
    // past the visual floor doesn't leave a tiny stored value below 44 dp
    // that would surface as an unreadably thin lane on desktop.
    test('respects minHeight parameter when clamping lower bound', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..setLaneHeight(0, 30, minHeight: 44);
      expect(
        c.read(signalGroupsProvider).entries.first.laneHeight,
        44,
      );
    });

    test('minHeight defaults to 16 when omitted', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..setLaneHeight(0, 5);
      expect(
        c.read(signalGroupsProvider).entries.first.laneHeight,
        16,
      );
    });

    test('values above minHeight pass through unchanged', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..setLaneHeight(0, 60, minHeight: 44);
      expect(
        c.read(signalGroupsProvider).entries.first.laneHeight,
        60,
      );
    });
  });

  // ── setCommentText ─────────────────────────────────────────────────────────

  group('setCommentText', () {
    test('updates comment text', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSeparator(comment: 'old')
        ..setCommentText(0, 'new comment');
      expect(
        c.read(signalGroupsProvider).entries.first.text,
        'new comment',
      );
    });

    test('no-op on non-comment entry', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..setCommentText(0, 'ignored');
      expect(
        c.read(signalGroupsProvider).entries.first.text,
        isNull,
      );
    });
  });

  // ── clear ──────────────────────────────────────────────────────────────────

  group('clear', () {
    test('removes all entries', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignals([_v('a'), _v('b'), _v('c')])
        ..clear();
      expect(c.read(signalGroupsProvider).entries, isEmpty);
    });
  });

  // ── renameGroup ────────────────────────────────────────────────────────────

  group('renameGroup', () {
    test('renames group at given index', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addGroup('Old');
      c.read(signalGroupsProvider.notifier).renameGroup(0, 'New');
      expect(
        c.read(signalGroupsProvider).entries.first.groupName,
        'New',
      );
    });

    test('trims whitespace', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addGroup('G');
      c.read(signalGroupsProvider.notifier).renameGroup(0, '  Trimmed  ');
      expect(
        c.read(signalGroupsProvider).entries.first.groupName,
        'Trimmed',
      );
    });

    test('no-op on empty name', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addGroup('G');
      c.read(signalGroupsProvider.notifier).renameGroup(0, '   ');
      expect(
        c.read(signalGroupsProvider).entries.first.groupName,
        'G',
      );
    });

    test('no-op on non-group entry', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
      c.read(signalGroupsProvider.notifier).renameGroup(0, 'Oops');
      expect(
        c.read(signalGroupsProvider).entries.first.groupName,
        isNull,
      );
    });

    test('no-op on out-of-bounds index', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addGroup('G');
      c.read(signalGroupsProvider.notifier).renameGroup(5, 'Bad');
      expect(
        c.read(signalGroupsProvider).entries.first.groupName,
        'G',
      );
    });
  });

  // ── moveSignalIntoGroup ────────────────────────────────────────────────────

  group('moveSignalIntoGroup', () {
    test('moves signal into group as last child', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addGroup('G') // index 0
        ..addSignal(_v('clk')); // index 1
      c.read(signalGroupsProvider.notifier).moveSignalIntoGroup(1, 0);
      final entries = c.read(signalGroupsProvider).entries;
      expect(entries.length, 1);
      expect(entries.first.kind, SignalEntryKind.group);
      expect(entries.first.children.length, 1);
      expect(entries.first.children.first.signalRef, 'ref_clk');
    });

    test('signal before group: group index adjusted correctly', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('a')) // index 0
        ..addGroup('G'); // index 1
      c.read(signalGroupsProvider.notifier).moveSignalIntoGroup(0, 1);
      final entries = c.read(signalGroupsProvider).entries;
      expect(entries.length, 1);
      expect(entries.first.children.first.signalRef, 'ref_a');
    });

    test('appends to existing children', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addGroup('G')
        ..addSignal(_v('a'))
        ..moveSignalIntoGroup(1, 0) // 'a' into group
        ..addSignal(_v('b'))
        ..moveSignalIntoGroup(1, 0); // 'b' into group
      final group = c.read(signalGroupsProvider).entries.first;
      expect(group.children.map((e) => e.signalRef), ['ref_a', 'ref_b']);
    });

    test('no-op when signalIndex == groupIndex', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addGroup('G');
      c.read(signalGroupsProvider.notifier).moveSignalIntoGroup(0, 0);
      final entries = c.read(signalGroupsProvider).entries;
      expect(entries.length, 1);
      expect(entries.first.children, isEmpty);
    });

    test('no-op on out-of-bounds indices', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..addGroup('G');
      c.read(signalGroupsProvider.notifier).moveSignalIntoGroup(5, 1);
      expect(c.read(signalGroupsProvider).entries.length, 2);
    });
  });

  // ── removeChildFromGroup ───────────────────────────────────────────────────

  group('removeChildFromGroup', () {
    test('promotes child to top-level after the group', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addGroup('G')
        ..addSignal(_v('clk'))
        ..moveSignalIntoGroup(1, 0)
        ..removeChildFromGroup(0, 0);
      final entries = c.read(signalGroupsProvider).entries;
      expect(entries.length, 2);
      expect(entries[0].kind, SignalEntryKind.group);
      expect(entries[0].children, isEmpty);
      expect(entries[1].signalRef, 'ref_clk');
    });

    test('maintains order when group has multiple children', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addGroup('G')
        ..addSignal(_v('a'))
        ..addSignal(_v('b'))
        ..moveSignalIntoGroup(1, 0)
        ..moveSignalIntoGroup(1, 0)
        ..removeChildFromGroup(0, 0); // remove 'a'
      final entries = c.read(signalGroupsProvider).entries;
      expect(entries[0].children.map((e) => e.signalRef), ['ref_b']);
      expect(entries[1].signalRef, 'ref_a');
    });

    test('no-op on out-of-bounds childIndex', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addGroup('G')
        ..addSignal(_v('clk'))
        ..moveSignalIntoGroup(1, 0)
        ..removeChildFromGroup(0, 5);
      expect(c.read(signalGroupsProvider).entries.first.children.length, 1);
    });

    test('no-op on non-group entry', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
      c.read(signalGroupsProvider.notifier).removeChildFromGroup(0, 0);
      expect(c.read(signalGroupsProvider).entries.length, 1);
    });
  });

  // ── dissolveGroup ─────────────────────────────────────────────────────────

  group('dissolveGroup', () {
    test('removes group and promotes children to top level', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addGroup('G')
        ..addSignal(_v('a'))
        ..addSignal(_v('b'))
        ..moveSignalIntoGroup(1, 0)
        ..moveSignalIntoGroup(1, 0)
        ..dissolveGroup(0);
      final entries = c.read(signalGroupsProvider).entries;
      expect(entries.length, 2);
      expect(entries[0].signalRef, 'ref_a');
      expect(entries[1].signalRef, 'ref_b');
    });

    test('dissolving empty group just removes it', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..addGroup('G')
        ..addSignal(_v('rst'));
      c.read(signalGroupsProvider.notifier).dissolveGroup(1);
      final entries = c.read(signalGroupsProvider).entries;
      expect(entries.length, 2);
      expect(entries.map((e) => e.signalRef), ['ref_clk', 'ref_rst']);
    });

    test(
      'children are inserted at group position, preserving surrounding entries',
      () {
        final c = _container();
        c.read(signalGroupsProvider.notifier)
          ..addSignal(_v('before'))
          ..addGroup('G')
          ..addSignal(_v('child'))
          ..moveSignalIntoGroup(2, 1)
          ..addSignal(_v('after'))
          ..dissolveGroup(1);
        final entries = c.read(signalGroupsProvider).entries;
        expect(entries.map((e) => e.signalRef), [
          'ref_before',
          'ref_child',
          'ref_after',
        ]);
      },
    );

    test('no-op on non-group entry', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
      c.read(signalGroupsProvider.notifier).dissolveGroup(0);
      expect(c.read(signalGroupsProvider).entries.length, 1);
    });

    test('no-op on out-of-bounds index', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addGroup('G');
      c.read(signalGroupsProvider.notifier).dissolveGroup(5);
      expect(c.read(signalGroupsProvider).entries.length, 1);
    });
  });

  // ── setSignalFormatByRef ───────────────────────────────────────────────────

  group('setSignalFormatByRef', () {
    test('updates format on a top-level signal', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('bus'));
      c
          .read(signalGroupsProvider.notifier)
          .setSignalFormatByRef('ref_bus', DisplayFormat.binary);
      expect(
        c.read(signalGroupsProvider).entries.first.format,
        DisplayFormat.binary,
      );
    });

    test('updates format on a signal nested inside a group', () {
      final c = _container();
      // index 0 = group 'G', index 1 = signal 'inner' → move 1 into group 0
      c.read(signalGroupsProvider.notifier)
        ..addGroup('G')
        ..addSignal(_v('inner'))
        ..moveSignalIntoGroup(1, 0);
      c
          .read(signalGroupsProvider.notifier)
          .setSignalFormatByRef('ref_inner', DisplayFormat.octal);
      final group = c.read(signalGroupsProvider).entries.first;
      expect(group.children.first.format, DisplayFormat.octal);
    });

    test('no-op when signalRef not found', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('a'));
      final before = c.read(signalGroupsProvider);
      c
          .read(signalGroupsProvider.notifier)
          .setSignalFormatByRef('ref_missing', DisplayFormat.ascii);
      expect(identical(c.read(signalGroupsProvider), before), isTrue);
    });

    test('state is a new map instance — original unaffected', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('a'));
      final before = c.read(signalGroupsProvider);
      c
          .read(signalGroupsProvider.notifier)
          .setSignalFormatByRef('ref_a', DisplayFormat.binary);
      expect(
        identical(c.read(signalGroupsProvider), before),
        isFalse,
      );
    });
  });

  // ── setSignalFormatById ───────────────────────────────────────────────────

  group('setSignalFormatById', () {
    test('sets format on a top-level signal by id', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
      final entry = c.read(signalGroupsProvider).entries.first;
      c
          .read(signalGroupsProvider.notifier)
          .setSignalFormatById(entry.id, DisplayFormat.binary);
      expect(
        c.read(signalGroupsProvider).entries.first.format,
        DisplayFormat.binary,
      );
    });

    test('sets format on a signal nested inside a group', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addGroup('G')
        ..addSignal(_v('inner'))
        ..moveSignalIntoGroup(1, 0);
      final innerEntry = c
          .read(signalGroupsProvider)
          .entries
          .first
          .children
          .first;
      c
          .read(signalGroupsProvider.notifier)
          .setSignalFormatById(innerEntry.id, DisplayFormat.octal);
      final group = c.read(signalGroupsProvider).entries.first;
      expect(group.children.first.format, DisplayFormat.octal);
    });

    test('no-op when id not found — state reference unchanged', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('a'));
      final before = c.read(signalGroupsProvider);
      c
          .read(signalGroupsProvider.notifier)
          .setSignalFormatById('nonexistent-id', DisplayFormat.binary);
      expect(identical(c.read(signalGroupsProvider), before), isTrue);
    });

    test(
      'targets only the entry with the matching id (two same-ref signals)',
      () {
        final c = _container();
        // Add the same signal ref twice — two distinct entries with different ids.
        c.read(signalGroupsProvider.notifier)
          ..addSignal(_v('clk'))
          ..addSignal(_v('clk'));
        final entries = c.read(signalGroupsProvider).entries;
        final firstId = entries[0].id;
        c
            .read(signalGroupsProvider.notifier)
            .setSignalFormatById(firstId, DisplayFormat.binary);
        final updated = c.read(signalGroupsProvider).entries;
        expect(updated[0].format, DisplayFormat.binary);
        expect(updated[1].format, DisplayFormat.hexadecimal); // unchanged
      },
    );

    test('state is a new instance after update', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('a'));
      final entry = c.read(signalGroupsProvider).entries.first;
      final before = c.read(signalGroupsProvider);
      c
          .read(signalGroupsProvider.notifier)
          .setSignalFormatById(entry.id, DisplayFormat.binary);
      expect(
        identical(c.read(signalGroupsProvider), before),
        isFalse,
      );
    });
  });

  // ── setSignalTranslatorConfigByRef ─────────────────────────────────────────

  group('reresolveSignalRefs', () {
    test("rewrites stale refs to the active backend's value, by path", () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..addSignal(_v('rst'))
        // Simulate a cross-backend reopen: same paths, different refs.
        ..reresolveSignalRefs(
          _FakeSource([
            const Variable(
              name: 'clk',
              varType: VarType.wire,
              direction: VarDirection.unknown,
              signalRef: 'fresh_clk',
              scopePath: 'top',
            ),
            const Variable(
              name: 'rst',
              varType: VarType.wire,
              direction: VarDirection.unknown,
              signalRef: 'fresh_rst',
              scopePath: 'top',
            ),
          ]),
        );
      final entries = c.read(signalGroupsProvider).entries;
      expect(entries, hasLength(2));
      expect(entries[0].signalRef, 'fresh_clk');
      expect(entries[0].signalPath, 'top.clk');
      expect(entries[1].signalRef, 'fresh_rst');
      expect(entries[1].signalPath, 'top.rst');
    });

    test('drops entries whose path no longer exists in the active source', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..addSignal(_v('removed'))
        ..addSignal(_v('rst'))
        ..reresolveSignalRefs(
          _FakeSource([
            const Variable(
              name: 'clk',
              varType: VarType.wire,
              direction: VarDirection.unknown,
              signalRef: '0',
              scopePath: 'top',
            ),
            const Variable(
              name: 'rst',
              varType: VarType.wire,
              direction: VarDirection.unknown,
              signalRef: '1',
              scopePath: 'top',
            ),
          ]),
        );
      final paths = c
          .read(signalGroupsProvider)
          .entries
          .map((e) => e.signalPath)
          .toList();
      expect(paths, ['top.clk', 'top.rst']);
    });

    test('leaves legacy entries (signalPath == null) untouched', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        // Restore a manually constructed entry that mimics a pre-path session.
        ..restoreFromSession(
          SignalGroup(
            entries: [
              SignalEntry.signal(
                signalRef: '!', // DartVcd-flavored ref; no path
                displayName: 'clk',
              ),
            ],
          ),
        )
        ..reresolveSignalRefs(
          _FakeSource([
            const Variable(
              name: 'clk',
              varType: VarType.wire,
              direction: VarDirection.unknown,
              signalRef: '0',
              scopePath: 'top',
            ),
          ]),
        );
      // Untouched: still has the stale ref (the canvas's defensive
      // try/catch is responsible for skipping it at paint time).
      final entries = c.read(signalGroupsProvider).entries;
      expect(entries, hasLength(1));
      expect(entries[0].signalRef, '!');
      expect(entries[0].signalPath, isNull);
    });

    test('no-op when all refs already match (idempotent)', () {
      final c = _container();
      final notifier = c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'));
      final before = c.read(signalGroupsProvider);
      notifier.reresolveSignalRefs(_FakeSource([_v('clk')]));
      final after = c.read(signalGroupsProvider);
      expect(identical(before, after), isTrue);
    });

    test('recurses into groups', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..restoreFromSession(
          SignalGroup(
            entries: [
              SignalEntry.group(
                groupName: 'bus',
                children: [
                  SignalEntry.signal(
                    signalRef: 'stale',
                    signalPath: 'top.bus.req',
                    displayName: 'req',
                  ),
                ],
              ),
            ],
          ),
        )
        ..reresolveSignalRefs(
          _FakeSource([
            const Variable(
              name: 'req',
              varType: VarType.wire,
              direction: VarDirection.unknown,
              signalRef: 'fresh',
              scopePath: 'top.bus',
            ),
          ]),
        );
      final root = c.read(signalGroupsProvider).entries.single;
      expect(root.kind, SignalEntryKind.group);
      expect(root.children.single.signalRef, 'fresh');
    });
  });

  group('setSignalTranslatorConfigByRef', () {
    const kConfig = <String, Object?>{'m': 4, 'n': 12, 'signed': true};

    test('sets a translator config on a top-level signal', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('data'));
      c
          .read(signalGroupsProvider.notifier)
          .setSignalTranslatorConfigByRef('ref_data', kConfig);
      expect(
        c.read(signalGroupsProvider).entries.first.translatorConfig,
        kConfig,
      );
    });

    test('clears a translator config when null is passed', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('data'))
        ..setSignalTranslatorConfigByRef('ref_data', kConfig);
      // Verify it was set first.
      expect(
        c.read(signalGroupsProvider).entries.first.translatorConfig,
        isNotNull,
      );
      // Now clear it.
      c
          .read(signalGroupsProvider.notifier)
          .setSignalTranslatorConfigByRef('ref_data', null);
      expect(
        c.read(signalGroupsProvider).entries.first.translatorConfig,
        isNull,
      );
    });

    test('sets config on a signal nested inside a group', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addGroup('G')
        ..addSignal(_v('inner'))
        ..moveSignalIntoGroup(1, 0);
      c
          .read(signalGroupsProvider.notifier)
          .setSignalTranslatorConfigByRef('ref_inner', kConfig);
      final group = c.read(signalGroupsProvider).entries.first;
      expect(group.children.first.translatorConfig, kConfig);
    });

    test('no-op when signalRef not found', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('a'));
      final before = c.read(signalGroupsProvider);
      c
          .read(signalGroupsProvider.notifier)
          .setSignalTranslatorConfigByRef('ref_missing', kConfig);
      expect(identical(c.read(signalGroupsProvider), before), isTrue);
    });

    test('state is a new map instance — original unaffected', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('a'));
      final before = c.read(signalGroupsProvider);
      c
          .read(signalGroupsProvider.notifier)
          .setSignalTranslatorConfigByRef('ref_a', kConfig);
      expect(
        identical(c.read(signalGroupsProvider), before),
        isFalse,
      );
    });
  });

  group('setSignalTranslatorConfigById (issue #39 — per-instance)', () {
    const kConfig = <String, Object?>{'m': 4, 'n': 12, 'signed': true};
    const kOther = <String, Object?>{'m': 8, 'n': 8, 'signed': false};

    test('sets a translator config on the row with the matching id', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('data'));
      final entry = c.read(signalGroupsProvider).entries.first;
      c
          .read(signalGroupsProvider.notifier)
          .setSignalTranslatorConfigById(entry.id, kConfig);
      expect(
        c.read(signalGroupsProvider).entries.first.translatorConfig,
        kConfig,
      );
    });

    test('clears a translator config when null is passed', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('data'));
      final id = c.read(signalGroupsProvider).entries.first.id;
      c.read(signalGroupsProvider.notifier)
        ..setSignalTranslatorConfigById(id, kConfig)
        ..setSignalTranslatorConfigById(id, null);
      expect(
        c.read(signalGroupsProvider).entries.first.translatorConfig,
        isNull,
      );
    });

    test('sets config on a signal nested inside a group', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addGroup('G')
        ..addSignal(_v('inner'))
        ..moveSignalIntoGroup(1, 0);
      final innerId = c
          .read(signalGroupsProvider)
          .entries
          .first
          .children
          .first
          .id;
      c
          .read(signalGroupsProvider.notifier)
          .setSignalTranslatorConfigById(innerId, kConfig);
      final group = c.read(signalGroupsProvider).entries.first;
      expect(group.children.first.translatorConfig, kConfig);
    });

    test(
      'targets only the row with the matching id (two same-ref signals)',
      () {
        final c = _container();
        // Add the same signal ref twice — two distinct rows with different ids.
        c.read(signalGroupsProvider.notifier)
          ..addSignal(_v('bus'))
          ..addSignal(_v('bus'));
        final entries = c.read(signalGroupsProvider).entries;
        expect(entries[0].signalRef, entries[1].signalRef); // same signal

        // Configure each row differently — impossible under the old byRef path.
        c.read(signalGroupsProvider.notifier)
          ..setSignalTranslatorConfigById(entries[0].id, kConfig)
          ..setSignalTranslatorConfigById(entries[1].id, kOther);

        final after = c.read(signalGroupsProvider).entries;
        expect(after[0].translatorConfig, kConfig);
        expect(after[1].translatorConfig, kOther);
      },
    );

    test('byRef still fans out to every row (apply-to-all path intact)', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addSignal(_v('bus'))
        ..addSignal(_v('bus'))
        ..setSignalTranslatorConfigByRef('ref_bus', kConfig);
      final after = c.read(signalGroupsProvider).entries;
      expect(after[0].translatorConfig, kConfig);
      expect(after[1].translatorConfig, kConfig);
    });

    test('no-op when id not found — state reference unchanged', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('a'));
      final before = c.read(signalGroupsProvider);
      c
          .read(signalGroupsProvider.notifier)
          .setSignalTranslatorConfigById('nonexistent-id', kConfig);
      expect(identical(c.read(signalGroupsProvider), before), isTrue);
    });
  });

  group('clearSignalTranslatorById (issue #41 — also resets format)', () {
    const kBinding = <String, Object?>{kTranslatorIdConfigKey: 'custom.x'};

    test('clears the translator config on the row with the matching id', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('data'));
      final id = c.read(signalGroupsProvider).entries.first.id;
      c.read(signalGroupsProvider.notifier)
        ..setSignalTranslatorConfigById(id, kBinding)
        ..clearSignalTranslatorById(id);
      expect(
        c.read(signalGroupsProvider).entries.first.translatorConfig,
        isNull,
      );
    });

    test('also resets a non-default format back to the default hex', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('data'));
      final id = c.read(signalGroupsProvider).entries.first.id;
      // Reproduce issue #41: a non-default format set before the translator was
      // bound must not survive the clear.
      c.read(signalGroupsProvider.notifier)
        ..setSignalFormatById(id, DisplayFormat.ieee754Single)
        ..setSignalTranslatorConfigById(id, kBinding)
        ..clearSignalTranslatorById(id);
      final after = c.read(signalGroupsProvider).entries.first;
      expect(after.format, DisplayFormat.hexadecimal);
      expect(after.translatorConfig, isNull);
    });

    test('clears a binding on a signal nested inside a group', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier)
        ..addGroup('G')
        ..addSignal(_v('inner'))
        ..moveSignalIntoGroup(1, 0);
      final innerId = c
          .read(signalGroupsProvider)
          .entries
          .first
          .children
          .first
          .id;
      c.read(signalGroupsProvider.notifier)
        ..setSignalFormatById(innerId, DisplayFormat.ieee754Single)
        ..setSignalTranslatorConfigById(innerId, kBinding)
        ..clearSignalTranslatorById(innerId);
      final inner = c.read(signalGroupsProvider).entries.first.children.first;
      expect(inner.format, DisplayFormat.hexadecimal);
      expect(inner.translatorConfig, isNull);
    });

    test(
      'targets only the row with the matching id (two same-ref signals)',
      () {
        final c = _container();
        c.read(signalGroupsProvider.notifier)
          ..addSignal(_v('bus'))
          ..addSignal(_v('bus'));
        final entries = c.read(signalGroupsProvider).entries;
        c.read(signalGroupsProvider.notifier)
          ..setSignalFormatById(entries[0].id, DisplayFormat.ieee754Single)
          ..setSignalTranslatorConfigById(entries[0].id, kBinding)
          ..setSignalFormatById(entries[1].id, DisplayFormat.ieee754Single)
          ..setSignalTranslatorConfigById(entries[1].id, kBinding)
          ..clearSignalTranslatorById(entries[0].id);
        final after = c.read(signalGroupsProvider).entries;
        // Cleared row reverts; the sibling row keeps its format and binding.
        expect(after[0].format, DisplayFormat.hexadecimal);
        expect(after[0].translatorConfig, isNull);
        expect(after[1].format, DisplayFormat.ieee754Single);
        expect(after[1].translatorConfig, kBinding);
      },
    );

    test('no-op when id not found — state reference unchanged', () {
      final c = _container();
      c.read(signalGroupsProvider.notifier).addSignal(_v('a'));
      final before = c.read(signalGroupsProvider);
      c
          .read(signalGroupsProvider.notifier)
          .clearSignalTranslatorById('nonexistent-id');
      expect(identical(c.read(signalGroupsProvider), before), isTrue);
    });
  });
}

/// Minimal [WaveformDataSource] stub for [reresolveSignalRefs] tests. Only
/// `findVariables` is exercised; the rest throws to make accidental use loud.
class _FakeSource implements WaveformDataSource {
  _FakeSource(this._variables);

  final List<Variable> _variables;

  @override
  List<Variable> findVariables(SignalFilter filter) =>
      _variables.where(filter.matches).toList();

  // ── unused by these tests ─────────────────────────────────────────────────
  @override
  Future<void> openFile(String path) => throw UnimplementedError();
  @override
  void close() => throw UnimplementedError();
  @override
  List<Scope> get rootScopes => throw UnimplementedError();
  @override
  Future<void> loadSignal(String signalRef) => throw UnimplementedError();
  @override
  Future<void> unloadSignal(String signalRef) => throw UnimplementedError();
  @override
  bool isSignalLoaded(String signalRef) => throw UnimplementedError();
  @override
  String? valueAt(String signalRef, int time) => throw UnimplementedError();
  @override
  List<SignalChange> changesInRange(String signalRef, int start, int end) =>
      throw UnimplementedError();
  @override
  SignalChange? nextTransition(String signalRef, int afterTime) =>
      throw UnimplementedError();
  @override
  SignalChange? prevTransition(String signalRef, int beforeTime) =>
      throw UnimplementedError();
  @override
  int get startTime => throw UnimplementedError();
  @override
  int get endTime => throw UnimplementedError();
  @override
  Timescale? get timescale => throw UnimplementedError();
  @override
  String? get date => throw UnimplementedError();
  @override
  String? get version => throw UnimplementedError();
}
