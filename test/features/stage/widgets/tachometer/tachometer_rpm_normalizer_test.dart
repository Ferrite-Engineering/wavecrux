// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/sdk/normalization/linear_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';
import 'package:wavecrux/features/stage/sdk/normalization/value_normalizer.dart';

/// Returns a binary string of [bits] zero-padded to [width]. Used to
/// construct VCD-style raw values at exact bit boundaries the rpm
/// normalizer is expected to handle.
String _vcdBits(int value, int width) {
  return value.toRadixString(2).padLeft(width, '0');
}

/// Convenience constructor mirroring the rpm-binding normalizer the
/// tachometer manifest declares. Default range is the manifest's static
/// 0..8192 mapping; tests override for per-instance config scenarios.
LinearNormalizer _rpmNormalizer({double inputMin = 0, double inputMax = 8192}) {
  return LinearNormalizer(
    inputMin: inputMin,
    inputMax: inputMax,
  );
}

void main() {
  group('Tachometer rpm normalizer — manifest defaults (0..8192)', () {
    final n = _rpmNormalizer();

    // The binding contract demands the normalizer accept any
    // RPM bus width the user binds — see the contract's "Type routing"
    // table. We sweep 12, 13, 14, 16-bit widths because those are the
    // typical hardware counter widths on a tachometer counter chain.
    for (final width in const [12, 13, 14, 16]) {
      group('bit-width $width', () {
        test('zero raw value maps to outputMin (0.0)', () {
          final sample = RawSignalSample(
            rawValue: _vcdBits(0, width),
            bitWidth: width,
          );
          final result = n.normalize(sample);
          expect(result, isA<NormalizedDouble>());
          expect((result as NormalizedDouble).value, 0.0);
        });

        test(
          'mid-range raw value 4096 maps to outputMid (0.5)',
          () {
            final sample = RawSignalSample(
              rawValue: _vcdBits(4096, width),
              bitWidth: width,
            );
            final result = n.normalize(sample);
            expect(result, isA<NormalizedDouble>());
            expect((result as NormalizedDouble).value, closeTo(0.5, 1e-12));
          },
        );

        test('raw value 8192 maps to outputMax (1.0) — boundary', () {
          // 8192 needs at least 14 bits to express; for narrower widths
          // the binding cannot represent it and the test is meaningless.
          if (width < 14) return;
          final sample = RawSignalSample(
            rawValue: _vcdBits(8192, width),
            bitWidth: width,
          );
          final result = n.normalize(sample);
          expect(result, isA<NormalizedDouble>());
          expect((result as NormalizedDouble).value, closeTo(1.0, 1e-12));
        });

        test('value just below upper boundary stays in [0, 1)', () {
          if (width < 14) return;
          final sample = RawSignalSample(
            rawValue: _vcdBits(8191, width),
            bitWidth: width,
          );
          final result = n.normalize(sample);
          expect(result, isA<NormalizedDouble>());
          final v = (result as NormalizedDouble).value;
          expect(v, greaterThan(0.0));
          expect(v, lessThan(1.0));
          expect(v, closeTo(8191 / 8192, 1e-12));
        });

        test(
          'over-range value clamps to outputMax (default clamp: true)',
          () {
            // Pick a value that fits in the bit width but exceeds the
            // 0..8192 input range — for 16-bit that's 0xFFFF (65535).
            final maxForWidth = (1 << width) - 1;
            if (maxForWidth <= 8192) return;
            final sample = RawSignalSample(
              rawValue: _vcdBits(maxForWidth, width),
              bitWidth: width,
            );
            final result = n.normalize(sample);
            expect(result, isA<NormalizedDouble>());
            expect((result as NormalizedDouble).value, 1.0);
          },
        );
      });
    }
  });

  group('Tachometer rpm normalizer — per-instance config override', () {
    test(
      'minRpm=1000, maxRpm=12000 — value 6500 maps to ~0.5',
      () {
        final n = _rpmNormalizer(inputMin: 1000, inputMax: 12000);
        final sample = RawSignalSample(
          rawValue: _vcdBits(6500, 14),
          bitWidth: 14,
        );
        final result = n.normalize(sample);
        expect(result, isA<NormalizedDouble>());
        expect(
          (result as NormalizedDouble).value,
          closeTo((6500 - 1000) / (12000 - 1000), 1e-12),
        );
      },
    );

    test('values below minRpm clamp to 0.0', () {
      final n = _rpmNormalizer(inputMin: 800, inputMax: 12000);
      final sample = RawSignalSample(
        rawValue: _vcdBits(500, 14),
        bitWidth: 14,
      );
      final result = n.normalize(sample);
      expect(result, isA<NormalizedDouble>());
      expect((result as NormalizedDouble).value, 0.0);
    });
  });

  group('Tachometer rpm normalizer — X/Z propagation', () {
    test('all-X sample produces NormalizedXZ(isX: true)', () {
      final n = _rpmNormalizer();
      const sample = RawSignalSample(rawValue: 'xxxxxxxxxxxxxx', bitWidth: 14);
      final result = n.normalize(sample);
      expect(result, isA<NormalizedXZ>());
      expect((result as NormalizedXZ).isX, isTrue);
    });

    test('all-Z sample produces NormalizedXZ(isX: false)', () {
      final n = _rpmNormalizer();
      const sample = RawSignalSample(rawValue: 'zzzzzzzzzzzzzz', bitWidth: 14);
      final result = n.normalize(sample);
      expect(result, isA<NormalizedXZ>());
      expect((result as NormalizedXZ).isX, isFalse);
    });

    test(
      'mixed X / known bits propagate as NormalizedXZ(isX: true) under '
      'default propagate policy — the renderer holds the previous '
      'NumberInput value',
      () {
        final n = _rpmNormalizer();
        const sample = RawSignalSample(
          rawValue: '0010x010101010',
          bitWidth: 14,
        );
        final result = n.normalize(sample);
        expect(result, isA<NormalizedXZ>());
        expect((result as NormalizedXZ).isX, isTrue);
      },
    );

    test(
      'asDefault X/Z policy emits the configured defaultValue instead '
      'of NormalizedXZ',
      () {
        const n = LinearNormalizer(
          inputMin: 0,
          inputMax: 8192,
          xzPolicy: XZPolicy.asDefault,
          defaultValue: 0.5,
        );
        final result = n.normalize(
          const RawSignalSample(rawValue: 'xxxxxxxxxxxxxx', bitWidth: 14),
        );
        expect(result, isA<NormalizedDouble>());
        expect((result as NormalizedDouble).value, 0.5);
      },
    );
  });

  group('Tachometer rpm normalizer — extra widths (1-bit, narrow vectors)', () {
    test('1-bit signal binding still passes through normalize() without '
        'crashing even though the rpm binding rejects it at the manifest '
        'level (manifest min bit_width = 1)', () {
      // Defensive: the manifest's per-binding min=1 lets a 1-bit signal
      // bind, even though it's a degenerate gauge. Normalizer must still
      // produce a sensible NormalizedDouble.
      final n = _rpmNormalizer();
      const s0 = RawSignalSample(rawValue: '0', bitWidth: 1);
      const s1 = RawSignalSample(rawValue: '1', bitWidth: 1);
      expect(n.normalize(s0), isA<NormalizedDouble>());
      expect(n.normalize(s1), isA<NormalizedDouble>());
    });

    test('4-bit nibble walks 0..15 monotonically', () {
      final n = _rpmNormalizer(inputMax: 15);
      var prev = -1.0;
      for (var v = 0; v <= 15; v++) {
        final r =
            n.normalize(
                  RawSignalSample(rawValue: _vcdBits(v, 4), bitWidth: 4),
                )
                as NormalizedDouble;
        expect(r.value, greaterThanOrEqualTo(prev));
        prev = r.value;
      }
      // Endpoints exact.
      expect(
        (n.normalize(const RawSignalSample(rawValue: '0000', bitWidth: 4))
                as NormalizedDouble)
            .value,
        0.0,
      );
      expect(
        (n.normalize(const RawSignalSample(rawValue: '1111', bitWidth: 4))
                as NormalizedDouble)
            .value,
        1.0,
      );
    });
  });

  group('Tachometer rpm normalizer — equality + kind discriminator', () {
    test('two normalizers with identical config compare equal', () {
      const a = LinearNormalizer(inputMin: 0, inputMax: 8192);
      const b = LinearNormalizer(inputMin: 0, inputMax: 8192);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('kind == "linear" — the manifest-format discriminator', () {
      const n = LinearNormalizer(inputMin: 0, inputMax: 8192);
      expect(n.kind, 'linear');
    });
  });
}
