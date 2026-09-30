// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stage_widget_slot.dart';
import 'package:wavecrux/services/stage/stage_slot_family.dart';

StageWidgetSlot _slot(String name) => StageWidgetSlot(
  name: name,
  childWidgetId: 'led',
  x: 0,
  y: 0,
  width: 0.05,
  height: 0.05,
);

void main() {
  group('StageSlotFamilyResolver.parseName', () {
    test('parses trailing-digit form', () {
      final r = StageSlotFamilyResolver.parseName('led15');
      expect(r?.prefix, 'led');
      expect(r?.index, 15);
    });

    test('parses bracketed form', () {
      final r = StageSlotFamilyResolver.parseName('led[7]');
      expect(r?.prefix, 'led');
      expect(r?.index, 7);
    });

    test('returns null for non-numeric suffix', () {
      expect(StageSlotFamilyResolver.parseName('btnC'), isNull);
      expect(StageSlotFamilyResolver.parseName('JA'), isNull);
      expect(StageSlotFamilyResolver.parseName('clk'), isNull);
    });

    test('returns null for entirely numeric names', () {
      expect(StageSlotFamilyResolver.parseName('123'), isNull);
    });

    test('handles underscored prefixes', () {
      final r = StageSlotFamilyResolver.parseName('rgb_led4');
      expect(r?.prefix, 'rgb_led');
      expect(r?.index, 4);
    });
  });

  group('StageSlotFamilyResolver.groupFamilies', () {
    test('groups led and sw families separately', () {
      final slots = [
        _slot('led0'),
        _slot('led1'),
        _slot('led2'),
        _slot('sw0'),
        _slot('sw1'),
        _slot('btnC'), // unparseable — dropped
      ];
      final families = StageSlotFamilyResolver.groupFamilies(slots);
      expect(families.keys.toSet(), {'led', 'sw'});
      expect(families['led']!.size, 3);
      expect(families['sw']!.size, 2);
    });

    test('orders members by ascending index', () {
      final slots = [
        _slot('led15'),
        _slot('led3'),
        _slot('led0'),
        _slot('led9'),
      ];
      final f = StageSlotFamilyResolver.groupFamilies(slots)['led']!;
      expect(f.members.map((m) => m.index), [0, 3, 9, 15]);
      expect(f.minIndex, 0);
      expect(f.maxIndex, 15);
    });
  });

  group('StageSlotFamilyResolver.familyOf', () {
    test('returns the matching family for a slot in a family', () {
      final slots = [
        _slot('led0'),
        _slot('led1'),
        _slot('led2'),
      ];
      final f = StageSlotFamilyResolver.familyOf(slots, 'led1');
      expect(f, isNotNull);
      expect(f!.prefix, 'led');
      expect(f.size, 3);
    });

    test('returns null for a singleton family', () {
      final slots = [_slot('led0')];
      expect(StageSlotFamilyResolver.familyOf(slots, 'led0'), isNull);
    });

    test('returns null when slot has no numeric suffix', () {
      final slots = [_slot('btnC'), _slot('btnL')];
      expect(StageSlotFamilyResolver.familyOf(slots, 'btnC'), isNull);
    });
  });
}
