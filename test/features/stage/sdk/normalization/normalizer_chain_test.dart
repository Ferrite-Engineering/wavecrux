// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/sdk/normalization/bit_field_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/boolean_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/linear_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalizer_chain.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';

void main() {
  group('NormalizerChain', () {
    test('bit_field → linear composes as expected', () {
      final chain = NormalizerChain(const [
        BitFieldNormalizer(highBit: 7, lowBit: 0),
        LinearNormalizer(inputMin: 0, inputMax: 255),
      ]);
      // 16-bit value with 0xFF in the low byte ⇒ chain output 1.0
      final out =
          chain.normalize(
                const RawSignalSample(
                  rawValue: '0000000011111111',
                  bitWidth: 16,
                ),
              )
              as NormalizedDouble;
      expect(out.value, closeTo(1.0, 1e-9));
    });

    test('bit_field → linear with mid-range value', () {
      final chain = NormalizerChain(const [
        BitFieldNormalizer(highBit: 15, lowBit: 8),
        LinearNormalizer(inputMin: 0, inputMax: 255),
      ]);
      // upper byte = 0x80 = 128 ⇒ 128/255
      final out =
          chain.normalize(
                const RawSignalSample(
                  rawValue: '1000000000000000',
                  bitWidth: 16,
                ),
              )
              as NormalizedDouble;
      expect(out.value, closeTo(128 / 255, 1e-9));
    });

    test('NormalizedXZ short-circuits the chain', () {
      final chain = NormalizerChain(const [
        BitFieldNormalizer(highBit: 3, lowBit: 0),
        LinearNormalizer(inputMin: 0, inputMax: 15),
      ]);
      final out = chain.normalize(
        const RawSignalSample(rawValue: 'xxxx', bitWidth: 4),
      );
      expect(out, equals(const NormalizedXZ(isX: true)));
    });

    test('boolean → linear: bool ⇒ 0/1 sample ⇒ scaled', () {
      final chain = NormalizerChain(const [
        BooleanNormalizer(),
        LinearNormalizer(inputMin: 0, inputMax: 1, outputMax: 100),
      ]);
      final out =
          chain.normalize(
                const RawSignalSample(rawValue: '1', bitWidth: 1),
              )
              as NormalizedDouble;
      expect(out.value, closeTo(100, 1e-9));
    });

    test('single stage works', () {
      final chain = NormalizerChain(const [
        LinearNormalizer(inputMin: 0, inputMax: 1),
      ]);
      final out =
          chain.normalize(
                const RawSignalSample(rawValue: '1', bitWidth: 1),
              )
              as NormalizedDouble;
      expect(out.value, 1.0);
    });

    test('empty chain throws', () {
      expect(
        () => NormalizerChain(const []),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
