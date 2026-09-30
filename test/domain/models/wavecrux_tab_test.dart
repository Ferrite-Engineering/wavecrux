// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/pane_id.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/domain/models/wavecrux_tab.dart';

void main() {
  group('WavecruxTab', () {
    late TabId id;

    setUp(() {
      id = TabId.fromString('aaaabbbb-cccc-dddd-eeee-ffffffffffff');
    });

    test('placeholder() factory produces a placeholder tab', () {
      final tab = WavecruxTab.placeholder();
      expect(tab.displayName, equals('Welcome'));
      expect(tab.filePath, isNull);
      expect(tab.sessionFilePath, isNull);
      expect(tab.isDetached, isFalse);
      expect(tab.isPlaceholder, isTrue);
      expect(tab.paneId, equals(PaneId.primary));
    });

    test('placeholder() honors custom displayName', () {
      final tab = WavecruxTab.placeholder(displayName: 'Untitled');
      expect(tab.displayName, equals('Untitled'));
      expect(tab.isPlaceholder, isTrue);
    });

    test('placeholder() honors custom paneId', () {
      final pane = PaneId.generate();
      final tab = WavecruxTab.placeholder(paneId: pane);
      expect(tab.paneId, equals(pane));
    });

    test('construction stores all fields', () {
      final pane = PaneId.generate();
      final tab = WavecruxTab(
        id: id,
        displayName: 'test.vcd',
        filePath: '/tmp/test.vcd',
        sessionFilePath: '/tmp/test.wavecrux',
        paneId: pane,
      );
      expect(tab.id, equals(id));
      expect(tab.displayName, equals('test.vcd'));
      expect(tab.filePath, equals('/tmp/test.vcd'));
      expect(tab.sessionFilePath, equals('/tmp/test.wavecrux'));
      expect(tab.isDetached, isFalse);
      expect(tab.isPlaceholder, isFalse);
      expect(tab.paneId, equals(pane));
    });

    test('isPlaceholder is false once a sessionFilePath is set', () {
      final tab = WavecruxTab(
        id: id,
        displayName: 'session.wavecrux',
        sessionFilePath: '/tmp/x.wavecrux',
      );
      expect(tab.isPlaceholder, isFalse);
    });

    test('paneId defaults to PaneId.primary when not provided', () {
      final tab = WavecruxTab(id: id, displayName: 'test.vcd');
      expect(tab.paneId, equals(PaneId.primary));
    });

    test('copyWith isDetached', () {
      final tab = WavecruxTab(id: id, displayName: 'test.vcd');
      final detached = tab.copyWith(isDetached: true);
      expect(detached.isDetached, isTrue);
      expect(detached.id, equals(tab.id));
    });

    test('copyWith paneId', () {
      final pane = PaneId.generate();
      final tab = WavecruxTab(id: id, displayName: 'test.vcd');
      final moved = tab.copyWith(paneId: pane);
      expect(moved.paneId, equals(pane));
      expect(moved.id, equals(tab.id));
      expect(moved.displayName, equals(tab.displayName));
    });

    test('equality is value-based', () {
      final a = WavecruxTab(id: id, displayName: 'same');
      final b = WavecruxTab(id: id, displayName: 'same');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality when id differs', () {
      final a = WavecruxTab(id: id, displayName: 'same');
      final b = WavecruxTab(id: TabId.generate(), displayName: 'same');
      expect(a, isNot(equals(b)));
    });

    test('inequality when displayName differs', () {
      final a = WavecruxTab(id: id, displayName: 'aaa');
      final b = WavecruxTab(id: id, displayName: 'bbb');
      expect(a, isNot(equals(b)));
    });

    test('inequality when paneId differs', () {
      final a = WavecruxTab(id: id, displayName: 'same');
      final b = WavecruxTab(
        id: id,
        displayName: 'same',
        paneId: PaneId.generate(),
      );
      expect(a, isNot(equals(b)));
    });
  });
}
