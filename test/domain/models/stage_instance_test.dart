// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';

void main() {
  group('StageInstance', () {
    test('default field values', () {
      const i = StageInstance(id: 'i0', widgetId: 'led');
      expect(i.id, 'i0');
      expect(i.widgetId, 'led');
      expect(i.signalBindings, isEmpty);
      expect(i.x, 0);
      expect(i.y, 0);
      expect(i.width, 160);
      expect(i.height, 100);
      expect(i.label, isNull);
    });

    test('stores explicit fields', () {
      const i = StageInstance(
        id: 'i7',
        widgetId: 'sevenSeg',
        signalBindings: {
          'value': StageSignalBinding(signalRef: 'top.cnt'),
          'enable': StageSignalBinding(signalRef: 'top.en'),
        },
        x: 50,
        y: 60,
        width: 200,
        height: 80,
        label: 'Counter',
      );
      expect(i.id, 'i7');
      expect(i.widgetId, 'sevenSeg');
      expect(
        i.signalBindings,
        const {
          'value': StageSignalBinding(signalRef: 'top.cnt'),
          'enable': StageSignalBinding(signalRef: 'top.en'),
        },
      );
      expect(i.x, 50);
      expect(i.y, 60);
      expect(i.width, 200);
      expect(i.height, 80);
      expect(i.label, 'Counter');
    });

    test('copyWith no-args returns equal instance', () {
      const i = StageInstance(
        id: 'i0',
        widgetId: 'led',
        signalBindings: {'in': StageSignalBinding(signalRef: 'top.clk')},
      );
      expect(i.copyWith(), equals(i));
    });

    test('copyWith updates bindings only', () {
      const i = StageInstance(id: 'i0', widgetId: 'led');
      final updated = i.copyWith(
        signalBindings: const {
          'in': StageSignalBinding(signalRef: 'top.clk'),
        },
      );
      expect(
        updated.signalBindings,
        const {'in': StageSignalBinding(signalRef: 'top.clk')},
      );
      expect(updated.widgetId, 'led');
    });

    test('copyWith updates layout fields', () {
      const i = StageInstance(id: 'i0', widgetId: 'led');
      final updated = i.copyWith(x: 100, y: 50, width: 200, height: 80);
      expect(updated.x, 100);
      expect(updated.y, 50);
      expect(updated.width, 200);
      expect(updated.height, 80);
    });

    test('copyWith(clearLabel: true) drops the label', () {
      const i = StageInstance(id: 'i0', widgetId: 'led', label: 'L');
      expect(i.copyWith(clearLabel: true).label, isNull);
    });

    test('equality compares bindings map by content', () {
      const a = StageInstance(
        id: 'i0',
        widgetId: 'led',
        signalBindings: {'in': StageSignalBinding(signalRef: 'top.clk')},
      );
      const b = StageInstance(
        id: 'i0',
        widgetId: 'led',
        signalBindings: {'in': StageSignalBinding(signalRef: 'top.clk')},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when bindings differ', () {
      const a = StageInstance(
        id: 'i0',
        widgetId: 'led',
        signalBindings: {'in': StageSignalBinding(signalRef: 'top.clk')},
      );
      const b = StageInstance(
        id: 'i0',
        widgetId: 'led',
        signalBindings: {'in': StageSignalBinding(signalRef: 'top.rst')},
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when bindings size differs', () {
      const a = StageInstance(
        id: 'i0',
        widgetId: 'led',
        signalBindings: {'in': StageSignalBinding(signalRef: 'top.clk')},
      );
      const b = StageInstance(
        id: 'i0',
        widgetId: 'led',
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when layout differs', () {
      const a = StageInstance(id: 'i0', widgetId: 'led');
      const b = StageInstance(id: 'i0', widgetId: 'led', x: 50);
      expect(a, isNot(equals(b)));
    });

    test('toString contains id and widgetId', () {
      const i = StageInstance(id: 'i9', widgetId: 'gauge');
      expect(i.toString(), allOf(contains('i9'), contains('gauge')));
    });
  });

  group('StageInstance.configuration', () {
    test('defaults to an empty map', () {
      const i = StageInstance(id: 'i0', widgetId: 'led');
      expect(i.configuration, isEmpty);
    });

    test('stores scalar values verbatim', () {
      const i = StageInstance(
        id: 'i1',
        widgetId: 'audio',
        configuration: {
          'fftSize': 2048,
          'showFft': true,
          'fftFloorDb': -60.0,
          'fftWindow': 'hamming',
        },
      );
      expect(i.configuration['fftSize'], 2048);
      expect(i.configuration['showFft'], true);
      expect(i.configuration['fftFloorDb'], -60.0);
      expect(i.configuration['fftWindow'], 'hamming');
    });

    test('copyWith updates configuration only', () {
      const a = StageInstance(id: 'i0', widgetId: 'audio');
      final b = a.copyWith(configuration: const {'fftSize': 512});
      expect(a.configuration, isEmpty);
      expect(b.configuration['fftSize'], 512);
      expect(b.id, a.id);
      expect(b.widgetId, a.widgetId);
    });

    test('equality compares configuration map by content', () {
      const a = StageInstance(
        id: 'i0',
        widgetId: 'audio',
        configuration: {'fftSize': 1024, 'showFft': true},
      );
      const b = StageInstance(
        id: 'i0',
        widgetId: 'audio',
        configuration: {'showFft': true, 'fftSize': 1024},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when configuration differs', () {
      const a = StageInstance(
        id: 'i0',
        widgetId: 'audio',
        configuration: {'fftSize': 1024},
      );
      const b = StageInstance(
        id: 'i0',
        widgetId: 'audio',
        configuration: {'fftSize': 2048},
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when configuration size differs', () {
      const a = StageInstance(id: 'i0', widgetId: 'audio');
      const b = StageInstance(
        id: 'i0',
        widgetId: 'audio',
        configuration: {'fftSize': 1024},
      );
      expect(a, isNot(equals(b)));
    });

    test('explicit null value is distinct from missing key', () {
      const a = StageInstance(id: 'i0', widgetId: 'audio');
      const b = StageInstance(
        id: 'i0',
        widgetId: 'audio',
        configuration: {'fftSize': null},
      );
      expect(a, isNot(equals(b)));
    });

    test('toString includes the configuration size', () {
      const i = StageInstance(
        id: 'i0',
        widgetId: 'audio',
        configuration: {'fftSize': 1024, 'showFft': true},
      );
      expect(i.toString(), contains('config: 2'));
    });
  });
}
