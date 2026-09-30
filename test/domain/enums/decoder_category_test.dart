// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/decoder_category.dart';

void main() {
  group('DecoderCategory', () {
    test('has exactly nine values in fixed display order', () {
      expect(DecoderCategory.values, hasLength(9));
      expect(DecoderCategory.values, [
        DecoderCategory.serial,
        DecoderCategory.automotive,
        DecoderCategory.amba,
        DecoderCategory.highSpeed,
        DecoderCategory.testManagement,
        DecoderCategory.ethernet,
        DecoderCategory.instructionTrace,
        DecoderCategory.userPlugin,
        DecoderCategory.custom,
      ]);
    });

    test('declaration order is locale-independent and groups protocols by '
        'family', () {
      // Cognitive grouping: low-pin-count serial → automotive → AMBA →
      // high-speed serial → test/management → Ethernet → instruction trace
      // → user plugins → custom escape hatch.
      expect(DecoderCategory.serial.index, 0);
      expect(DecoderCategory.automotive.index, 1);
      expect(DecoderCategory.amba.index, 2);
      expect(DecoderCategory.highSpeed.index, 3);
      expect(DecoderCategory.testManagement.index, 4);
      expect(DecoderCategory.ethernet.index, 5);
      expect(DecoderCategory.instructionTrace.index, 6);
      expect(DecoderCategory.userPlugin.index, 7);
      expect(DecoderCategory.custom.index, 8);
    });

    test('every value has a stable name() — used for ValueKey in pickers', () {
      // The picker UI builds widget keys from `category.name` so a rename
      // would break test/widget identity. Pin the names here.
      expect(DecoderCategory.serial.name, 'serial');
      expect(DecoderCategory.automotive.name, 'automotive');
      expect(DecoderCategory.amba.name, 'amba');
      expect(DecoderCategory.highSpeed.name, 'highSpeed');
      expect(DecoderCategory.testManagement.name, 'testManagement');
      expect(DecoderCategory.ethernet.name, 'ethernet');
      expect(DecoderCategory.instructionTrace.name, 'instructionTrace');
      expect(DecoderCategory.userPlugin.name, 'userPlugin');
      expect(DecoderCategory.custom.name, 'custom');
    });
  });
}
