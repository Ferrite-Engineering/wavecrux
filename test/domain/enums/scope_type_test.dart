// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';

void main() {
  group('ScopeType', () {
    test('has the expected number of values', () {
      expect(ScopeType.values.length, 24);
    });

    test('values support equality', () {
      expect(ScopeType.module, equals(ScopeType.module));
      expect(ScopeType.module, isNot(equals(ScopeType.task)));
    });

    test('values are distinct', () {
      final set = ScopeType.values.toSet();
      expect(set.length, ScopeType.values.length);
    });
  });
}
