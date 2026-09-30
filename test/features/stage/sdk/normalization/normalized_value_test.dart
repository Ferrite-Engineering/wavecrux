// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';

void main() {
  group('NormalizedValue subtypes', () {
    test('NormalizedDouble equality / hash', () {
      expect(const NormalizedDouble(0.5), equals(const NormalizedDouble(0.5)));
      expect(
        const NormalizedDouble(0.5).hashCode,
        const NormalizedDouble(0.5).hashCode,
      );
      expect(
        const NormalizedDouble(0.5),
        isNot(equals(const NormalizedDouble(0.6))),
      );
    });

    test('NormalizedBool equality and toString', () {
      expect(
        const NormalizedBool(value: true),
        equals(const NormalizedBool(value: true)),
      );
      expect(
        const NormalizedBool(value: false).toString(),
        contains('false'),
      );
    });

    test('NormalizedString round-trips simple values', () {
      expect(
        const NormalizedString('IDLE'),
        equals(const NormalizedString('IDLE')),
      );
    });

    test('NormalizedNumList equality is element-wise', () {
      expect(
        NormalizedNumList(const [0, 1, 2]),
        equals(NormalizedNumList(const [0, 1, 2])),
      );
      expect(
        NormalizedNumList(const [0, 1, 2]),
        isNot(equals(NormalizedNumList(const [0, 1]))),
      );
    });

    test('NormalizedXZ distinguishes X from Z', () {
      expect(
        const NormalizedXZ(isX: true),
        isNot(equals(const NormalizedXZ(isX: false))),
      );
    });

    test('exhaustive switch covers every variant', () {
      // Compile-time exhaustiveness check — if a new variant is added the
      // switch below stops being exhaustive and the test fails to build.
      const values = <NormalizedValue>[
        NormalizedDouble(0),
        NormalizedBool(value: true),
        NormalizedString(''),
        NormalizedXZ(isX: true),
      ];
      for (final v in values) {
        final tag = switch (v) {
          NormalizedDouble() => 'double',
          NormalizedBool() => 'bool',
          NormalizedString() => 'string',
          NormalizedNumList() => 'numList',
          NormalizedXZ() => 'xz',
        };
        expect(tag, isNotEmpty);
      }
      // NormalizedNumList is non-const, exercise it separately.
      final numList = NormalizedNumList(const [0, 1]);
      expect(
        switch (numList as NormalizedValue) {
          NormalizedDouble() => 'double',
          NormalizedBool() => 'bool',
          NormalizedString() => 'string',
          NormalizedNumList() => 'numList',
          NormalizedXZ() => 'xz',
        },
        'numList',
      );
    });
  });
}
