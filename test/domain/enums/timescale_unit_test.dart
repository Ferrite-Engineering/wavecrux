// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';

void main() {
  group('TimescaleUnit', () {
    test('has exactly 7 values', () {
      expect(TimescaleUnit.values.length, 7);
    });

    group('exponent', () {
      test('femtoSeconds → -15', () {
        expect(TimescaleUnit.femtoSeconds.exponent, -15);
      });
      test('picoSeconds → -12', () {
        expect(TimescaleUnit.picoSeconds.exponent, -12);
      });
      test('nanoSeconds → -9', () {
        expect(TimescaleUnit.nanoSeconds.exponent, -9);
      });
      test('microSeconds → -6', () {
        expect(TimescaleUnit.microSeconds.exponent, -6);
      });
      test('milliSeconds → -3', () {
        expect(TimescaleUnit.milliSeconds.exponent, -3);
      });
      test('seconds → 0', () {
        expect(TimescaleUnit.seconds.exponent, 0);
      });
      test('unknown → null', () {
        expect(TimescaleUnit.unknown.exponent, isNull);
      });
    });

    group('symbol', () {
      test('femtoSeconds → "fs"', () {
        expect(TimescaleUnit.femtoSeconds.symbol, 'fs');
      });
      test('picoSeconds → "ps"', () {
        expect(TimescaleUnit.picoSeconds.symbol, 'ps');
      });
      test('nanoSeconds → "ns"', () {
        expect(TimescaleUnit.nanoSeconds.symbol, 'ns');
      });
      test('microSeconds → "µs"', () {
        expect(TimescaleUnit.microSeconds.symbol, 'µs');
      });
      test('milliSeconds → "ms"', () {
        expect(TimescaleUnit.milliSeconds.symbol, 'ms');
      });
      test('seconds → "s"', () {
        expect(TimescaleUnit.seconds.symbol, 's');
      });
      test('unknown → "?"', () {
        expect(TimescaleUnit.unknown.symbol, '?');
      });
    });

    test('exponent ordering is strictly decreasing fs→s', () {
      final units = [
        TimescaleUnit.femtoSeconds,
        TimescaleUnit.picoSeconds,
        TimescaleUnit.nanoSeconds,
        TimescaleUnit.microSeconds,
        TimescaleUnit.milliSeconds,
        TimescaleUnit.seconds,
      ];
      for (var i = 0; i < units.length - 1; i++) {
        expect(units[i].exponent! < units[i + 1].exponent!, isTrue);
      }
    });
  });
}
