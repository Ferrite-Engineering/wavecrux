// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_type.dart';

void main() {
  group('VarType', () {
    test('has the expected number of values', () {
      expect(VarType.values.length, 37);
    });

    test('values are distinct', () {
      expect(VarType.values.toSet().length, VarType.values.length);
    });

    test('values support equality', () {
      expect(VarType.wire, equals(VarType.wire));
      expect(VarType.wire, isNot(equals(VarType.reg)));
    });
  });
}
