// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';

void main() {
  group('StageWidgetCategory', () {
    test('has exactly six values in fixed display order', () {
      expect(StageWidgetCategory.values, hasLength(6));
      expect(StageWidgetCategory.values, [
        StageWidgetCategory.primitive,
        StageWidgetCategory.peripheral,
        StageWidgetCategory.instrument,
        StageWidgetCategory.board,
        StageWidgetCategory.protocol,
        StageWidgetCategory.custom,
      ]);
    });

    test('declaration order is locale-independent and groups widgets by '
        'capability', () {
      // Cognitive grouping: simple primitives → richer peripherals →
      // instrument-style readouts → board emulations → protocol dashboards →
      // user-supplied widgets.
      expect(StageWidgetCategory.primitive.index, 0);
      expect(StageWidgetCategory.peripheral.index, 1);
      expect(StageWidgetCategory.instrument.index, 2);
      expect(StageWidgetCategory.board.index, 3);
      expect(StageWidgetCategory.protocol.index, 4);
      expect(StageWidgetCategory.custom.index, 5);
    });

    test('every value has a stable name() — used for ValueKey in pickers', () {
      // The Stage picker UI builds widget keys from `category.name`.
      expect(StageWidgetCategory.primitive.name, 'primitive');
      expect(StageWidgetCategory.peripheral.name, 'peripheral');
      expect(StageWidgetCategory.instrument.name, 'instrument');
      expect(StageWidgetCategory.board.name, 'board');
      expect(StageWidgetCategory.protocol.name, 'protocol');
      expect(StageWidgetCategory.custom.name, 'custom');
    });
  });
}
