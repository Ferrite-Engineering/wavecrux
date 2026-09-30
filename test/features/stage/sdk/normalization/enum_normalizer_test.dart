// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/sdk/normalization/enum_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';
import 'package:wavecrux/features/stage/sdk/normalization/value_normalizer.dart';

void main() {
  group('EnumNormalizer', () {
    final normalizer = EnumNormalizer(
      labels: const {0: 'IDLE', 1: 'RUNNING', 2: 'ERROR'},
    );

    test('matches in-range values', () {
      expect(
        normalizer.normalize(
          const RawSignalSample(rawValue: '00', bitWidth: 2),
        ),
        equals(const NormalizedString('IDLE')),
      );
      expect(
        normalizer.normalize(
          const RawSignalSample(rawValue: '01', bitWidth: 2),
        ),
        equals(const NormalizedString('RUNNING')),
      );
      expect(
        normalizer.normalize(
          const RawSignalSample(rawValue: '10', bitWidth: 2),
        ),
        equals(const NormalizedString('ERROR')),
      );
    });

    test('unmatched value with no defaultLabel emits NormalizedXZ', () {
      // value = 3 isn't in the labels map.
      expect(
        normalizer.normalize(
          const RawSignalSample(rawValue: '11', bitWidth: 2),
        ),
        equals(const NormalizedXZ(isX: false)),
      );
    });

    test('defaultLabel applies to unmatched and X under asDefault policy', () {
      final withDefault = EnumNormalizer(
        labels: const {0: 'IDLE'},
        defaultLabel: 'UNKNOWN',
        xzPolicy: XZPolicy.asDefault,
      );
      // unmatched value
      expect(
        withDefault.normalize(
          const RawSignalSample(rawValue: '11', bitWidth: 2),
        ),
        equals(const NormalizedString('UNKNOWN')),
      );
      // X bits
      expect(
        withDefault.normalize(
          const RawSignalSample(rawValue: 'xx', bitWidth: 2),
        ),
        equals(const NormalizedString('UNKNOWN')),
      );
    });

    test('propagate policy yields NormalizedXZ on X bits', () {
      expect(
        normalizer.normalize(
          const RawSignalSample(rawValue: 'xx', bitWidth: 2),
        ),
        equals(const NormalizedXZ(isX: true)),
      );
    });

    test('throws on analog samples', () {
      expect(
        () => normalizer.normalize(
          const RawSignalSample(
            rawValue: '1.5',
            bitWidth: 0,
            isAnalog: true,
          ),
        ),
        throwsStateError,
      );
    });

    test('64-bit keys survive via BigInt coercion', () {
      final wide = EnumNormalizer(
        labels: {
          BigInt.parse('18446744073709551615'): 'MAX',
          0: 'ZERO',
        },
      );
      final raw = '1' * 64;
      expect(
        wide.normalize(RawSignalSample(rawValue: raw, bitWidth: 64)),
        equals(const NormalizedString('MAX')),
      );
    });

    test('1-bit edge case maps as expected', () {
      final scalar = EnumNormalizer(
        labels: const {0: 'OFF', 1: 'ON'},
      );
      expect(
        scalar.normalize(
          const RawSignalSample(rawValue: '0', bitWidth: 1),
        ),
        equals(const NormalizedString('OFF')),
      );
      expect(
        scalar.normalize(
          const RawSignalSample(rawValue: '1', bitWidth: 1),
        ),
        equals(const NormalizedString('ON')),
      );
    });
  });
}
