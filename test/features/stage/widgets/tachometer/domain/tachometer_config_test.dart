// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/widgets/tachometer/domain/tachometer_config.dart';

void main() {
  group('TachometerConfig — defaults', () {
    test('matches the documented automotive-engine modal defaults', () {
      const c = TachometerConfig();
      expect(c.minRpm, 0);
      expect(c.maxRpm, 8000);
      expect(c.warningRpm, 6500);
      expect(c.redlineRpm, 7500);
    });

    test('asserts maintain min < max and zone ordering', () {
      // minRpm must be strictly less than maxRpm.
      expect(
        () => TachometerConfig(minRpm: 1000, maxRpm: 1000),
        throwsA(isA<AssertionError>()),
      );
      // warningRpm must sit inside [min, max] — default maxRpm is
      // 8000, so warningRpm: 9000 trips the upper-bound assertion.
      expect(
        () => TachometerConfig(warningRpm: 9000),
        throwsA(isA<AssertionError>()),
      );
      // redlineRpm must sit at or above warningRpm. Default min/max
      // (0/8000) bracket both values cleanly so this test isolates the
      // ordering invariant.
      expect(
        () => TachometerConfig(warningRpm: 7000, redlineRpm: 6500),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('TachometerConfig — copyWith / equality / hashCode / toString', () {
    test('copyWith updates only the named fields', () {
      const base = TachometerConfig();
      final updated = base.copyWith(maxRpm: 10000, redlineRpm: 9500);
      expect(updated.minRpm, base.minRpm);
      expect(updated.maxRpm, 10000);
      expect(updated.warningRpm, base.warningRpm);
      expect(updated.redlineRpm, 9500);
    });

    test('equality + hashCode honor every field', () {
      const a = TachometerConfig();
      final b = a.copyWith();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      final c = a.copyWith(minRpm: 500);
      expect(a, isNot(equals(c)));
    });

    test('toString surfaces every field for debug logs', () {
      const c = TachometerConfig();
      final s = c.toString();
      expect(s, contains('minRpm: 0'));
      expect(s, contains('maxRpm: 8000'));
      expect(s, contains('warningRpm: 6500'));
      expect(s, contains('redlineRpm: 7500'));
    });
  });

  group('TachometerConfig — fromMap / toMap round-trip', () {
    test('default config round-trips losslessly', () {
      const c = TachometerConfig();
      final reparsed = TachometerConfig.fromMap(c.toMap());
      expect(reparsed, equals(c));
    });

    test('custom config round-trips losslessly', () {
      const c = TachometerConfig(
        minRpm: 800,
        maxRpm: 12000,
        warningRpm: 9000,
        redlineRpm: 11000,
      );
      final reparsed = TachometerConfig.fromMap(c.toMap());
      expect(reparsed, equals(c));
    });

    test('toMap omits no field — every config knob is persistable', () {
      const c = TachometerConfig();
      final map = c.toMap();
      expect(
        map.keys,
        containsAll(['minRpm', 'maxRpm', 'warningRpm', 'redlineRpm']),
      );
    });
  });

  group('TachometerConfig — fromMap fallback policy', () {
    test('empty map returns defaults', () {
      final c = TachometerConfig.fromMap(const <String, Object?>{});
      expect(c, equals(const TachometerConfig()));
    });

    test('partial map fills missing keys with defaults', () {
      final c = TachometerConfig.fromMap(const <String, Object?>{
        'maxRpm': 10000,
      });
      expect(c.minRpm, 0);
      expect(c.maxRpm, 10000);
      expect(c.warningRpm, 6500);
      expect(c.redlineRpm, 7500);
    });

    test('non-numeric / wrong-type values fall back to defaults', () {
      // The loader silently falls back rather than crashing
      // on a corrupt session.
      final c = TachometerConfig.fromMap(const <String, Object?>{
        'minRpm': 'not a number',
        'maxRpm': true,
      });
      expect(c, equals(const TachometerConfig()));
    });

    test('coerces double values to int via round()', () {
      final c = TachometerConfig.fromMap(const <String, Object?>{
        'minRpm': 0.0,
        'maxRpm': 8500.4,
        'warningRpm': 6800.6,
        'redlineRpm': 7600.0,
      });
      expect(c.minRpm, 0);
      expect(c.maxRpm, 8500);
      expect(c.warningRpm, 6801);
      expect(c.redlineRpm, 7600);
    });

    test('coerces numeric strings via int.tryParse', () {
      final c = TachometerConfig.fromMap(const <String, Object?>{
        'minRpm': '0',
        'maxRpm': '9000',
        'warningRpm': '7200',
        'redlineRpm': '8000',
      });
      expect(c.minRpm, 0);
      expect(c.maxRpm, 9000);
      expect(c.warningRpm, 7200);
      expect(c.redlineRpm, 8000);
    });

    test(
      'lowering maxRpm below the default zones keeps maxRpm (regression)',
      () {
        // The user lowers only maxRpm; warning/redline stay at their
        // defaults (6500 / 7500). Pre-fix this tripped warning > max and
        // reverted the *whole* config to maxRpm 8000, so the gauge
        // ignored the range knob. Now the zones clamp into [0, 200] and
        // the user's maxRpm survives.
        final c = TachometerConfig.fromMap(const <String, Object?>{
          'maxRpm': 200,
        });
        expect(c.minRpm, 0);
        expect(c.maxRpm, 200);
        expect(c.warningRpm, 200);
        expect(c.redlineRpm, 200);
      },
    );

    test(
      'out-of-range zones are clamped into [minRpm, maxRpm], not dropped',
      () {
        // warningRpm below minRpm → clamped up to minRpm; everything else
        // in range is preserved.
        var c = TachometerConfig.fromMap(const <String, Object?>{
          'minRpm': 1000,
          'maxRpm': 8000,
          'warningRpm': 500,
          'redlineRpm': 7500,
        });
        expect(c.minRpm, 1000);
        expect(c.maxRpm, 8000);
        expect(c.warningRpm, 1000);
        expect(c.redlineRpm, 7500);

        // redlineRpm below warningRpm → clamped up to warningRpm.
        c = TachometerConfig.fromMap(const <String, Object?>{
          'minRpm': 0,
          'maxRpm': 8000,
          'warningRpm': 7500,
          'redlineRpm': 6500,
        });
        expect(c.warningRpm, 7500);
        expect(c.redlineRpm, 7500);

        // warningRpm/redlineRpm above maxRpm → both clamped down to maxRpm.
        c = TachometerConfig.fromMap(const <String, Object?>{
          'minRpm': 0,
          'maxRpm': 8000,
          'warningRpm': 9000,
          'redlineRpm': 9500,
        });
        expect(c.warningRpm, 8000);
        expect(c.redlineRpm, 8000);
      },
    );

    test('degenerate range (minRpm >= maxRpm) falls the range to defaults', () {
      // No needle mapping exists for an inverted range, so the range
      // itself reverts to 0..8000; the zones then clamp into that range.
      final c = TachometerConfig.fromMap(const <String, Object?>{
        'minRpm': 5000,
        'maxRpm': 4000,
        'warningRpm': 3500,
        'redlineRpm': 3800,
      });
      expect(c.minRpm, 0);
      expect(c.maxRpm, 8000);
      expect(c.warningRpm, 3500);
      expect(c.redlineRpm, 3800);
    });
  });
}
