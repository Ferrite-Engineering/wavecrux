// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';

void main() {
  group('StagePanelConfig', () {
    test('default fields', () {
      const p = StagePanelConfig(id: 'p0', name: 'Main');
      expect(p.id, 'p0');
      expect(p.name, 'Main');
      expect(p.instances, isEmpty);
    });

    test('stores instances list', () {
      const p = StagePanelConfig(
        id: 'p0',
        name: 'Main',
        instances: [
          StageInstance(id: 'i0', widgetId: 'led'),
          StageInstance(id: 'i1', widgetId: 'sevenSeg'),
        ],
      );
      expect(p.instances, hasLength(2));
      expect(p.instances.first.id, 'i0');
    });

    test('copyWith no-args returns equal panel', () {
      const p = StagePanelConfig(id: 'p0', name: 'Main');
      expect(p.copyWith(), equals(p));
    });

    test('copyWith updates name only', () {
      const p = StagePanelConfig(id: 'p0', name: 'Main');
      final r = p.copyWith(name: 'Renamed');
      expect(r.name, 'Renamed');
      expect(r.id, p.id);
    });

    test('copyWith replaces instances', () {
      const p = StagePanelConfig(id: 'p0', name: 'Main');
      final r = p.copyWith(
        instances: const [StageInstance(id: 'x', widgetId: 'led')],
      );
      expect(r.instances, hasLength(1));
      expect(r.instances.first.id, 'x');
    });

    test('equality compares by id, name, and instances ordering', () {
      const a = StagePanelConfig(
        id: 'p0',
        name: 'A',
        instances: [
          StageInstance(id: 'i0', widgetId: 'led'),
          StageInstance(id: 'i1', widgetId: 'sevenSeg'),
        ],
      );
      const b = StagePanelConfig(
        id: 'p0',
        name: 'A',
        instances: [
          StageInstance(id: 'i0', widgetId: 'led'),
          StageInstance(id: 'i1', widgetId: 'sevenSeg'),
        ],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when instances ordering differs', () {
      const a = StagePanelConfig(
        id: 'p0',
        name: 'A',
        instances: [
          StageInstance(id: 'i0', widgetId: 'led'),
          StageInstance(id: 'i1', widgetId: 'sevenSeg'),
        ],
      );
      const b = StagePanelConfig(
        id: 'p0',
        name: 'A',
        instances: [
          StageInstance(id: 'i1', widgetId: 'sevenSeg'),
          StageInstance(id: 'i0', widgetId: 'led'),
        ],
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when instances length differs', () {
      const a = StagePanelConfig(id: 'p0', name: 'A');
      const b = StagePanelConfig(
        id: 'p0',
        name: 'A',
        instances: [StageInstance(id: 'i0', widgetId: 'led')],
      );
      expect(a, isNot(equals(b)));
    });

    test('toString contains id and name', () {
      const p = StagePanelConfig(id: 'p9', name: 'Bus Monitor');
      expect(p.toString(), allOf(contains('p9'), contains('Bus Monitor')));
    });
  });
}
