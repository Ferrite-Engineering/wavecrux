// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';

void main() {
  group('DisplayFormat', () {
    test('has exactly 12 values', () {
      expect(DisplayFormat.values.length, 12);
    });

    test('all expected values are present', () {
      expect(
        DisplayFormat.values,
        containsAll([
          DisplayFormat.binary,
          DisplayFormat.hexadecimal,
          DisplayFormat.octal,
          DisplayFormat.unsignedDecimal,
          DisplayFormat.signedDecimal,
          DisplayFormat.ascii,
          DisplayFormat.ieee754Single,
          DisplayFormat.ieee754Double,
          DisplayFormat.fixedPointQ,
          DisplayFormat.signedMagnitude,
          DisplayFormat.grayCode,
          DisplayFormat.namedEnum,
        ]),
      );
    });

    test('values are distinct', () {
      expect(DisplayFormat.values.toSet().length, DisplayFormat.values.length);
    });

    test('values support equality', () {
      expect(DisplayFormat.hexadecimal, equals(DisplayFormat.hexadecimal));
      expect(DisplayFormat.binary, isNot(equals(DisplayFormat.hexadecimal)));
    });
  });
}
