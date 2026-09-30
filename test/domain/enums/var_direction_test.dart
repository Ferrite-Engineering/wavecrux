// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';

void main() {
  group('VarDirection', () {
    test('has exactly 7 values', () {
      expect(VarDirection.values.length, 7);
    });

    test('all expected values are present', () {
      expect(
        VarDirection.values,
        containsAll([
          VarDirection.unknown,
          VarDirection.implicit,
          VarDirection.input,
          VarDirection.output,
          VarDirection.inout,
          VarDirection.buffer,
          VarDirection.linkage,
        ]),
      );
    });

    test('values are distinct', () {
      expect(VarDirection.values.toSet().length, VarDirection.values.length);
    });

    test('values support equality', () {
      expect(VarDirection.input, equals(VarDirection.input));
      expect(VarDirection.input, isNot(equals(VarDirection.output)));
    });
  });
}
