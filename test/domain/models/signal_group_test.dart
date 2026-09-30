// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/signal_group.dart';

void main() {
  // ── SignalEntry ─────────────────────────────────────────────────────────────

  group('SignalEntry.signal', () {
    final entry = SignalEntry.signal(
      signalRef: 'ref1',
      displayName: 'clk',
      argbColor: 0xFF4CAF50,
      format: DisplayFormat.binary,
    );

    test('stores all fields', () {
      expect(entry.kind, SignalEntryKind.signal);
      expect(entry.signalRef, 'ref1');
      expect(entry.displayName, 'clk');
      expect(entry.argbColor, 0xFF4CAF50);
      expect(entry.format, DisplayFormat.binary);
    });

    test('group/separator/comment fields are null/default', () {
      expect(entry.groupName, isNull);
      expect(entry.collapsed, isFalse);
      expect(entry.children, isEmpty);
      expect(entry.text, isNull);
    });

    test('copyWith(displayName:) updates only displayName', () {
      final copy = entry.copyWith(displayName: 'clock');
      expect(copy.displayName, 'clock');
      expect(copy.signalRef, 'ref1');
      expect(copy.format, DisplayFormat.binary);
    });

    test('copyWith(format:) updates only format', () {
      final copy = entry.copyWith(format: DisplayFormat.hexadecimal);
      expect(copy.format, DisplayFormat.hexadecimal);
      expect(copy.displayName, 'clk');
    });

    test('copyWith(clearArgbColor: true) sets argbColor to null', () {
      final copy = entry.copyWith(clearArgbColor: true);
      expect(copy.argbColor, isNull);
    });

    test('default laneHeight is 30', () {
      final e = SignalEntry.signal(signalRef: 'r', displayName: 'x');
      expect(e.laneHeight, 30);
    });

    test('copyWith(laneHeight:) updates laneHeight', () {
      final e = SignalEntry.signal(signalRef: 'r', displayName: 'x');
      final copy = e.copyWith(laneHeight: 50);
      expect(copy.laneHeight, 50);
      expect(copy.signalRef, 'r');
    });

    test('equality considers laneHeight', () {
      final a = SignalEntry.signal(signalRef: 'r', displayName: 'x');
      final b = a.copyWith(laneHeight: 60);
      expect(a, isNot(equals(b)));
    });

    test('hashCode differs when laneHeight differs', () {
      final a = SignalEntry.signal(signalRef: 'r', displayName: 'x');
      final b = a.copyWith(laneHeight: 60);
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    test('copyWith preserves identity — equal to itself', () {
      final a = SignalEntry.signal(signalRef: 'r', displayName: 'x');
      expect(a.copyWith(), equals(a));
    });

    test('two distinct instances are not equal (unique ids)', () {
      final a = SignalEntry.signal(signalRef: 'r', displayName: 'x');
      final b = SignalEntry.signal(signalRef: 'r', displayName: 'x');
      expect(a, isNot(equals(b)));
    });

    test('id is preserved through copyWith', () {
      final a = SignalEntry.signal(signalRef: 'r', displayName: 'x');
      final b = a.copyWith(displayName: 'y');
      expect(b.id, equals(a.id));
    });

    test('equality — different signalRef are not equal', () {
      final a = SignalEntry.signal(signalRef: 'r1', displayName: 'x');
      final b = SignalEntry.signal(signalRef: 'r2', displayName: 'x');
      expect(a, isNot(equals(b)));
    });

    test('hashCode matches for same instance after copyWith', () {
      final a = SignalEntry.signal(signalRef: 'r', displayName: 'x');
      expect(a.copyWith().hashCode, equals(a.hashCode));
    });

    test('toString contains signalRef', () {
      expect(entry.toString(), contains('ref1'));
    });
  });

  group('SignalEntry.group', () {
    final child = SignalEntry.signal(signalRef: 'c1', displayName: 'data');
    late SignalEntry group;
    setUp(() {
      group = SignalEntry.group(
        groupName: 'AXI',
        collapsed: true,
        children: [child],
      );
    });

    test('stores all fields', () {
      expect(group.kind, SignalEntryKind.group);
      expect(group.groupName, 'AXI');
      expect(group.collapsed, isTrue);
      expect(group.children, hasLength(1));
    });

    test('default collapsed is false', () {
      const g = SignalEntry.group(groupName: 'Test');
      expect(g.collapsed, isFalse);
      expect(g.children, isEmpty);
    });

    test('copyWith(collapsed:) toggles collapsed', () {
      final copy = group.copyWith(collapsed: false);
      expect(copy.collapsed, isFalse);
      expect(copy.groupName, 'AXI');
    });

    test('copyWith(children:) replaces children', () {
      final copy = group.copyWith(children: []);
      expect(copy.children, isEmpty);
    });

    test('equality — same group', () {
      const a = SignalEntry.group(groupName: 'G');
      const b = SignalEntry.group(groupName: 'G');
      expect(a, equals(b));
    });

    test('equality — different groupName', () {
      const a = SignalEntry.group(groupName: 'G1');
      const b = SignalEntry.group(groupName: 'G2');
      expect(a, isNot(equals(b)));
    });
  });

  group('SignalEntry.separator', () {
    test('kind is separator', () {
      const sep = SignalEntry.separator();
      expect(sep.kind, SignalEntryKind.separator);
    });

    test('all separators are equal', () {
      const a = SignalEntry.separator();
      const b = SignalEntry.separator();
      expect(a, equals(b));
    });

    test('copyWith returns a separator', () {
      const sep = SignalEntry.separator();
      expect(sep.copyWith().kind, SignalEntryKind.separator);
    });
  });

  group('SignalEntry.comment', () {
    test('stores text', () {
      const c = SignalEntry.comment(text: 'Clock domain');
      expect(c.kind, SignalEntryKind.comment);
      expect(c.text, 'Clock domain');
    });

    test('equality — same text', () {
      const a = SignalEntry.comment(text: 'x');
      const b = SignalEntry.comment(text: 'x');
      expect(a, equals(b));
    });

    test('equality — different text', () {
      const a = SignalEntry.comment(text: 'x');
      const b = SignalEntry.comment(text: 'y');
      expect(a, isNot(equals(b)));
    });

    test('copyWith(text:) updates text', () {
      const c = SignalEntry.comment(text: 'old');
      final copy = c.copyWith(text: 'new');
      expect(copy.text, 'new');
    });
  });

  // ── SignalGroup ─────────────────────────────────────────────────────────────

  group('SignalGroup', () {
    late SignalEntry clk;
    late SignalEntry data;
    const sep = SignalEntry.separator();
    late SignalEntry group;

    setUp(() {
      clk = SignalEntry.signal(signalRef: 'r1', displayName: 'clk');
      data = SignalEntry.signal(signalRef: 'r2', displayName: 'data');
      group = SignalEntry.group(groupName: 'G', children: [clk]);
    });

    test('default is empty', () {
      const sg = SignalGroup();
      expect(sg.entries, isEmpty);
      expect(sg.signalCount, 0);
    });

    test('signalCount counts top-level signals', () {
      final sg = SignalGroup(entries: [clk, data, sep]);
      expect(sg.signalCount, 2);
    });

    test('signalCount recurses into groups', () {
      final sg = SignalGroup(entries: [group, data]);
      // group has 1 child signal + data = 2
      expect(sg.signalCount, 2);
    });

    test('displayedSignalRefs is empty for an empty panel', () {
      expect(const SignalGroup().displayedSignalRefs, isEmpty);
    });

    test('displayedSignalRefs collects top-level signal refs', () {
      final sg = SignalGroup(entries: [clk, data, sep]);
      expect(sg.displayedSignalRefs, {'r1', 'r2'});
    });

    test('displayedSignalRefs recurses into groups', () {
      final sg = SignalGroup(entries: [group, data]);
      expect(sg.displayedSignalRefs, {'r1', 'r2'});
    });

    test('displayedSignalRefs ignores separators and comments', () {
      final sg = SignalGroup(
        entries: [
          sep,
          const SignalEntry.comment(text: 'note'),
          clk,
        ],
      );
      expect(sg.displayedSignalRefs, {'r1'});
    });

    test('displayedSignalRefs holds one ref for a duplicated signal', () {
      final dup = SignalEntry.signal(signalRef: 'r1', displayName: 'clk2');
      final sg = SignalGroup(entries: [clk, dup]);
      expect(sg.displayedSignalRefs, {'r1'});
    });

    test('addEntry appends one entry', () {
      const sg = SignalGroup();
      final sg2 = sg.addEntry(clk);
      expect(sg2.entries, hasLength(1));
      expect(sg2.entries.first, clk);
    });

    test('addEntries appends multiple entries', () {
      const sg = SignalGroup();
      final sg2 = sg.addEntries([clk, data]);
      expect(sg2.entries, hasLength(2));
    });

    test('copyWith replaces entries', () {
      final sg = SignalGroup(entries: [clk]);
      final sg2 = sg.copyWith(entries: [data]);
      expect(sg2.entries, [data]);
    });

    test('copyWith with no args returns equal object', () {
      final sg = SignalGroup(entries: [clk, data]);
      expect(sg.copyWith(), equals(sg));
    });

    test('equality — same entries (same instance)', () {
      final a = SignalGroup(entries: [clk, sep]);
      final b = SignalGroup(entries: [clk, sep]);
      expect(a, equals(b));
    });

    test('equality — different entries', () {
      final a = SignalGroup(entries: [clk]);
      final b = SignalGroup(entries: [data]);
      expect(a, isNot(equals(b)));
    });

    test('equality — different length', () {
      final a = SignalGroup(entries: [clk]);
      final b = SignalGroup(entries: [clk, data]);
      expect(a, isNot(equals(b)));
    });

    test('hashCode matches for equal instances', () {
      final a = SignalGroup(entries: [clk]);
      final b = SignalGroup(entries: [clk]);
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toString mentions entry count', () {
      final sg = SignalGroup(entries: [clk, data]);
      expect(sg.toString(), contains('2'));
    });

    test('original is not mutated by addEntry', () {
      const original = SignalGroup();
      final _ = original.addEntry(clk);
      expect(original.entries, isEmpty);
    });
  });
}
