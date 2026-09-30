// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/sdk/normalization/linear_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';
import 'package:wavecrux/features/stage/sdk/normalization/value_normalizer.dart';

void main() {
  group('LinearNormalizer', () {
    test('maps in-range bit-string sample to expected fractional value', () {
      const n = LinearNormalizer(inputMin: 0, inputMax: 255);
      // 0x80 ⇒ 128 / 255 ≈ 0.5019...
      final out = n.normalize(
        const RawSignalSample(rawValue: '10000000', bitWidth: 8),
      );
      expect(out, isA<NormalizedDouble>());
      final value = (out as NormalizedDouble).value;
      expect(value, closeTo(128 / 255, 1e-9));
    });

    test('clamps over- and under-range inputs by default', () {
      const n = LinearNormalizer(inputMin: 16, inputMax: 32);
      // Below min ⇒ outputMin (default 0.0)
      expect(
        (n.normalize(const RawSignalSample(rawValue: '0', bitWidth: 6))
                as NormalizedDouble)
            .value,
        0.0,
      );
      // Above max ⇒ outputMax (default 1.0)
      expect(
        (n.normalize(const RawSignalSample(rawValue: '111111', bitWidth: 6))
                as NormalizedDouble)
            .value,
        1.0,
      );
    });

    test('does not clamp when clamp=false', () {
      const n = LinearNormalizer(inputMin: 0, inputMax: 10, clamp: false);
      final out =
          n.normalize(
                const RawSignalSample(rawValue: '10100', bitWidth: 5), // 20
              )
              as NormalizedDouble;
      expect(out.value, 2.0);
    });

    test('all-X / all-Z propagate by default', () {
      const n = LinearNormalizer(inputMin: 0, inputMax: 15);
      final x = n.normalize(
        const RawSignalSample(rawValue: 'xxxx', bitWidth: 4),
      );
      expect(x, equals(const NormalizedXZ(isX: true)));
      final z = n.normalize(
        const RawSignalSample(rawValue: 'zzzz', bitWidth: 4),
      );
      expect(z, equals(const NormalizedXZ(isX: false)));
    });

    test('XZPolicy.asDefault returns defaultValue for X', () {
      const n = LinearNormalizer(
        inputMin: 0,
        inputMax: 15,
        xzPolicy: XZPolicy.asDefault,
        defaultValue: 0.42,
      );
      final out = n.normalize(
        const RawSignalSample(rawValue: 'xxxx', bitWidth: 4),
      );
      expect(out, equals(const NormalizedDouble(0.42)));
    });

    test('XZPolicy.bestEffort coerces partial X to 0', () {
      const n = LinearNormalizer(
        inputMin: 0,
        inputMax: 15,
        xzPolicy: XZPolicy.bestEffort,
      );
      // 1x10 → 1010 = 10 ⇒ 10/15
      final out =
          n.normalize(
                const RawSignalSample(rawValue: '1x10', bitWidth: 4),
              )
              as NormalizedDouble;
      expect(out.value, closeTo(10 / 15, 1e-9));
    });

    test('analog samples parse as doubles', () {
      const n = LinearNormalizer(inputMin: -1, inputMax: 1);
      final out =
          n.normalize(
                const RawSignalSample(
                  rawValue: '0.0',
                  bitWidth: 0,
                  isAnalog: true,
                ),
              )
              as NormalizedDouble;
      expect(out.value, closeTo(0.5, 1e-9));
    });

    test('1-bit edge case: scalar maps onto 0.0/1.0', () {
      const n = LinearNormalizer(inputMin: 0, inputMax: 1);
      expect(
        (n.normalize(const RawSignalSample(rawValue: '1', bitWidth: 1))
                as NormalizedDouble)
            .value,
        1.0,
      );
      expect(
        (n.normalize(const RawSignalSample(rawValue: '0', bitWidth: 1))
                as NormalizedDouble)
            .value,
        0.0,
      );
    });

    test('64-bit edge case: very wide bus survives BigInt path', () {
      const n = LinearNormalizer(inputMin: 0, inputMax: 18446744073709551615.0);
      final raw = '1' * 64;
      final out =
          n.normalize(
                RawSignalSample(rawValue: raw, bitWidth: 64),
              )
              as NormalizedDouble;
      expect(out.value, closeTo(1.0, 1e-9));
    });
  });
}
