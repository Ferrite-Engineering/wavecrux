// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stage_widget_slot.dart';

void main() {
  group('StageWidgetSlot', () {
    test('stores all positional fields', () {
      const s = StageWidgetSlot(
        name: 'led0',
        childWidgetId: 'led',
        x: 0.1,
        y: 0.2,
        width: 0.05,
        height: 0.05,
        label: 'LD0',
      );
      expect(s.name, 'led0');
      expect(s.childWidgetId, 'led');
      expect(s.x, 0.1);
      expect(s.y, 0.2);
      expect(s.width, 0.05);
      expect(s.height, 0.05);
      expect(s.label, 'LD0');
    });

    test('label defaults to null', () {
      const s = StageWidgetSlot(
        name: 'sw0',
        childWidgetId: 'switch',
        x: 0,
        y: 0,
        width: 0.1,
        height: 0.1,
      );
      expect(s.label, isNull);
    });

    test('copyWith no-args returns equal slot', () {
      const s = StageWidgetSlot(
        name: 'led0',
        childWidgetId: 'led',
        x: 0.1,
        y: 0.2,
        width: 0.05,
        height: 0.05,
      );
      expect(s.copyWith(), equals(s));
    });

    test('copyWith updates label', () {
      const s = StageWidgetSlot(
        name: 'led0',
        childWidgetId: 'led',
        x: 0,
        y: 0,
        width: 0.1,
        height: 0.1,
      );
      final updated = s.copyWith(label: 'L1');
      expect(updated.label, 'L1');
      expect(updated.name, s.name);
    });

    test('copyWith(clearLabel: true) drops the label', () {
      const s = StageWidgetSlot(
        name: 'led0',
        childWidgetId: 'led',
        x: 0,
        y: 0,
        width: 0.1,
        height: 0.1,
        label: 'LD0',
      );
      final cleared = s.copyWith(clearLabel: true);
      expect(cleared.label, isNull);
    });

    test('equality matches by all fields', () {
      const a = StageWidgetSlot(
        name: 'led0',
        childWidgetId: 'led',
        x: 0,
        y: 0,
        width: 0.1,
        height: 0.1,
      );
      const b = StageWidgetSlot(
        name: 'led0',
        childWidgetId: 'led',
        x: 0,
        y: 0,
        width: 0.1,
        height: 0.1,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when childWidgetId differs', () {
      const a = StageWidgetSlot(
        name: 'led0',
        childWidgetId: 'led',
        x: 0,
        y: 0,
        width: 0.1,
        height: 0.1,
      );
      const b = StageWidgetSlot(
        name: 'led0',
        childWidgetId: 'switch',
        x: 0,
        y: 0,
        width: 0.1,
        height: 0.1,
      );
      expect(a, isNot(equals(b)));
    });

    test('toString contains identifying fields', () {
      const s = StageWidgetSlot(
        name: 'led3',
        childWidgetId: 'led',
        x: 0,
        y: 0,
        width: 0.1,
        height: 0.1,
      );
      expect(s.toString(), allOf(contains('led3'), contains('led')));
    });
  });

  group('StageWidgetSlot — pinBindings (multi-pin slots)', () {
    test('pinBindings defaults to null and isMultiPin returns false', () {
      const s = StageWidgetSlot(
        name: 'led0',
        childWidgetId: 'led',
        x: 0,
        y: 0,
        width: 0.1,
        height: 0.1,
      );
      expect(s.pinBindings, isNull);
      expect(s.isMultiPin, isFalse);
    });

    test('isMultiPin is true when pinBindings has entries', () {
      const s = StageWidgetSlot(
        name: 'hdmi_in',
        childWidgetId: 'wavecrux.pro.framebuffer',
        x: 0,
        y: 0,
        width: 0.3,
        height: 0.3,
        pinBindings: {
          'pixelClk': 'hdmi_in_pixel_clk',
          'data': 'hdmi_in_data',
          'hSync': 'hdmi_in_hsync',
        },
      );
      expect(s.isMultiPin, isTrue);
      expect(s.pinBindings, hasLength(3));
      expect(s.pinBindings!['data'], 'hdmi_in_data');
    });

    test('isMultiPin is false for an empty pinBindings map', () {
      const s = StageWidgetSlot(
        name: 'hdmi_in',
        childWidgetId: 'wavecrux.pro.framebuffer',
        x: 0,
        y: 0,
        width: 0.3,
        height: 0.3,
        pinBindings: {},
      );
      expect(s.isMultiPin, isFalse);
    });

    test('equality includes pinBindings', () {
      const a = StageWidgetSlot(
        name: 'hdmi_in',
        childWidgetId: 'wavecrux.pro.framebuffer',
        x: 0,
        y: 0,
        width: 0.3,
        height: 0.3,
        pinBindings: {'data': 'hdmi_in_data'},
      );
      const b = StageWidgetSlot(
        name: 'hdmi_in',
        childWidgetId: 'wavecrux.pro.framebuffer',
        x: 0,
        y: 0,
        width: 0.3,
        height: 0.3,
        pinBindings: {'data': 'hdmi_in_data'},
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when pinBindings entries differ', () {
      const a = StageWidgetSlot(
        name: 'hdmi_in',
        childWidgetId: 'wavecrux.pro.framebuffer',
        x: 0,
        y: 0,
        width: 0.3,
        height: 0.3,
        pinBindings: {'data': 'hdmi_in_data'},
      );
      const b = StageWidgetSlot(
        name: 'hdmi_in',
        childWidgetId: 'wavecrux.pro.framebuffer',
        x: 0,
        y: 0,
        width: 0.3,
        height: 0.3,
        pinBindings: {'data': 'other_slot'},
      );
      expect(a, isNot(equals(b)));
    });

    test('copyWith preserves pinBindings by default', () {
      const s = StageWidgetSlot(
        name: 'hdmi_in',
        childWidgetId: 'wavecrux.pro.framebuffer',
        x: 0,
        y: 0,
        width: 0.3,
        height: 0.3,
        pinBindings: {'data': 'hdmi_in_data'},
      );
      expect(s.copyWith().pinBindings, s.pinBindings);
    });

    test('copyWith(pinBindings: ...) replaces the map', () {
      const s = StageWidgetSlot(
        name: 'hdmi_in',
        childWidgetId: 'wavecrux.pro.framebuffer',
        x: 0,
        y: 0,
        width: 0.3,
        height: 0.3,
        pinBindings: {'data': 'a'},
      );
      final updated = s.copyWith(
        pinBindings: const {'data': 'b', 'pixelClk': 'c'},
      );
      expect(updated.pinBindings, {'data': 'b', 'pixelClk': 'c'});
    });

    test('copyWith(clearPinBindings: true) drops the map', () {
      const s = StageWidgetSlot(
        name: 'hdmi_in',
        childWidgetId: 'wavecrux.pro.framebuffer',
        x: 0,
        y: 0,
        width: 0.3,
        height: 0.3,
        pinBindings: {'data': 'hdmi_in_data'},
      );
      final cleared = s.copyWith(clearPinBindings: true);
      expect(cleared.pinBindings, isNull);
      expect(cleared.isMultiPin, isFalse);
    });
  });
}
