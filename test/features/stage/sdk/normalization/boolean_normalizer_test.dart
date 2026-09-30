// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/sdk/normalization/boolean_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';
import 'package:wavecrux/features/stage/sdk/normalization/value_normalizer.dart';

void main() {
  group('BooleanNormalizer', () {
    test('default reduction is LSB', () {
      const n = BooleanNormalizer();
      expect(
        n.normalize(const RawSignalSample(rawValue: '1010', bitWidth: 4)),
        equals(const NormalizedBool(value: false)),
      );
      expect(
        n.normalize(const RawSignalSample(rawValue: '1011', bitWidth: 4)),
        equals(const NormalizedBool(value: true)),
      );
    });

    test('anyHigh fires on any 1 bit', () {
      const n = BooleanNormalizer(reduction: BooleanReduction.anyHigh);
      expect(
        n.normalize(const RawSignalSample(rawValue: '0000', bitWidth: 4)),
        equals(const NormalizedBool(value: false)),
      );
      expect(
        n.normalize(const RawSignalSample(rawValue: '0001', bitWidth: 4)),
        equals(const NormalizedBool(value: true)),
      );
      // anyHigh remains true even with X bits when at least one '1' exists.
      expect(
        n.normalize(const RawSignalSample(rawValue: 'x1xx', bitWidth: 4)),
        equals(const NormalizedBool(value: true)),
      );
    });

    test('allHigh requires every bit to be 1', () {
      const n = BooleanNormalizer(reduction: BooleanReduction.allHigh);
      expect(
        n.normalize(const RawSignalSample(rawValue: '1111', bitWidth: 4)),
        equals(const NormalizedBool(value: true)),
      );
      expect(
        n.normalize(const RawSignalSample(rawValue: '1110', bitWidth: 4)),
        equals(const NormalizedBool(value: false)),
      );
    });

    test('X bit on LSB propagates per default policy', () {
      const n = BooleanNormalizer();
      expect(
        n.normalize(const RawSignalSample(rawValue: '111x', bitWidth: 4)),
        equals(const NormalizedXZ(isX: true)),
      );
    });

    test('XZPolicy.asDefault returns defaultValue for X bits', () {
      const n = BooleanNormalizer(
        xzPolicy: XZPolicy.asDefault,
        defaultValue: true,
      );
      expect(
        n.normalize(const RawSignalSample(rawValue: 'x', bitWidth: 1)),
        equals(const NormalizedBool(value: true)),
      );
    });

    test('1-bit edge case', () {
      const n = BooleanNormalizer();
      expect(
        n.normalize(const RawSignalSample(rawValue: '1', bitWidth: 1)),
        equals(const NormalizedBool(value: true)),
      );
      expect(
        n.normalize(const RawSignalSample(rawValue: '0', bitWidth: 1)),
        equals(const NormalizedBool(value: false)),
      );
    });

    test('64-bit edge case anyHigh = true on a single bit set', () {
      const n = BooleanNormalizer(reduction: BooleanReduction.anyHigh);
      final raw = '${'0' * 63}1';
      expect(
        n.normalize(RawSignalSample(rawValue: raw, bitWidth: 64)),
        equals(const NormalizedBool(value: true)),
      );
    });

    test('analog samples coerce non-zero ⇒ true, NaN ⇒ X', () {
      const n = BooleanNormalizer();
      expect(
        n.normalize(
          const RawSignalSample(
            rawValue: '0.0',
            bitWidth: 0,
            isAnalog: true,
          ),
        ),
        equals(const NormalizedBool(value: false)),
      );
      expect(
        n.normalize(
          const RawSignalSample(
            rawValue: '1.5',
            bitWidth: 0,
            isAnalog: true,
          ),
        ),
        equals(const NormalizedBool(value: true)),
      );
      expect(
        n.normalize(
          const RawSignalSample(
            rawValue: 'not-a-number',
            bitWidth: 0,
            isAnalog: true,
          ),
        ),
        equals(const NormalizedXZ(isX: true)),
      );
    });
  });
}
