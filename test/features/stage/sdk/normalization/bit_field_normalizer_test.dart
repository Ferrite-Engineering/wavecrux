// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/sdk/normalization/bit_field_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/linear_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';

void main() {
  group('BitFieldNormalizer', () {
    test('extracts upper byte of 16-bit bus', () {
      const n = BitFieldNormalizer(highBit: 15, lowBit: 8);
      // 0xAB55 → upper 0xAB = 171
      final out =
          n.normalize(
                const RawSignalSample(
                  rawValue: '1010101101010101',
                  bitWidth: 16,
                ),
              )
              as NormalizedDouble;
      expect(out.value, 0xAB.toDouble());
    });

    test('extracts a single bit (LSB)', () {
      const n = BitFieldNormalizer(highBit: 0, lowBit: 0);
      expect(
        (n.normalize(const RawSignalSample(rawValue: '1010', bitWidth: 4))
                as NormalizedDouble)
            .value,
        0.0,
      );
      expect(
        (n.normalize(const RawSignalSample(rawValue: '1011', bitWidth: 4))
                as NormalizedDouble)
            .value,
        1.0,
      );
    });

    test('extracts 64-bit slice (MSB byte from a 64-bit bus)', () {
      const n = BitFieldNormalizer(highBit: 63, lowBit: 56);
      final raw = '11111111${'0' * 56}';
      final out =
          n.normalize(
                RawSignalSample(rawValue: raw, bitWidth: 64),
              )
              as NormalizedDouble;
      expect(out.value, 0xFF.toDouble());
    });

    test('chains a linear sub-normalizer', () {
      const n = BitFieldNormalizer(
        highBit: 7,
        lowBit: 0,
        sub: LinearNormalizer(inputMin: 0, inputMax: 255),
      );
      // upper byte ignored, lower byte = 0x80 = 128 ⇒ 128/255
      final out =
          n.normalize(
                const RawSignalSample(
                  rawValue: '1111111110000000',
                  bitWidth: 16,
                ),
              )
              as NormalizedDouble;
      expect(out.value, closeTo(128 / 255, 1e-9));
    });

    test('all-X within slice propagates', () {
      const n = BitFieldNormalizer(highBit: 3, lowBit: 0);
      final out = n.normalize(
        const RawSignalSample(rawValue: '0000xxxx', bitWidth: 8),
      );
      expect(out, equals(const NormalizedXZ(isX: true)));
    });

    test('mixed-X within slice propagates as X', () {
      const n = BitFieldNormalizer(highBit: 3, lowBit: 0);
      final out = n.normalize(
        const RawSignalSample(rawValue: '00001x10', bitWidth: 8),
      );
      expect(out, equals(const NormalizedXZ(isX: true)));
    });

    test('throws StateError on analog samples', () {
      const n = BitFieldNormalizer(highBit: 3, lowBit: 0);
      expect(
        () => n.normalize(
          const RawSignalSample(
            rawValue: '1.5',
            bitWidth: 0,
            isAnalog: true,
          ),
        ),
        throwsStateError,
      );
    });

    test('out-of-range high_bit returns NormalizedXZ', () {
      const n = BitFieldNormalizer(highBit: 31, lowBit: 0);
      final out = n.normalize(
        const RawSignalSample(rawValue: '1010', bitWidth: 4),
      );
      expect(out, equals(const NormalizedXZ(isX: true)));
    });
  });
}
