// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';

void main() {
  group('RawSignalSample', () {
    test('hasX detects upper- and lower-case unknown bits', () {
      expect(
        const RawSignalSample(rawValue: '101x', bitWidth: 4).hasX,
        isTrue,
      );
      expect(
        const RawSignalSample(rawValue: '1X10', bitWidth: 4).hasX,
        isTrue,
      );
      expect(
        const RawSignalSample(rawValue: '1010', bitWidth: 4).hasX,
        isFalse,
      );
    });

    test('hasZ detects high-impedance bits, X dominates', () {
      expect(
        const RawSignalSample(rawValue: 'z', bitWidth: 1).hasZ,
        isTrue,
      );
      expect(
        const RawSignalSample(rawValue: 'Z', bitWidth: 1).hasZ,
        isTrue,
      );
      // X dominates Z so hasZ is false when an X is present.
      expect(
        const RawSignalSample(rawValue: '1xz0', bitWidth: 4).hasZ,
        isFalse,
      );
    });

    test('copyWith preserves untouched fields', () {
      const original = RawSignalSample(
        rawValue: '1010',
        bitWidth: 4,
        timeTicks: 100,
      );
      final copy = original.copyWith(rawValue: '1111');
      expect(copy.rawValue, '1111');
      expect(copy.bitWidth, 4);
      expect(copy.timeTicks, 100);
      expect(copy.isAnalog, isFalse);
    });

    test('equality and hashCode match on all fields', () {
      const a = RawSignalSample(rawValue: '1', bitWidth: 1, timeTicks: 5);
      const b = RawSignalSample(rawValue: '1', bitWidth: 1, timeTicks: 5);
      const c = RawSignalSample(rawValue: '0', bitWidth: 1, timeTicks: 5);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });
}
