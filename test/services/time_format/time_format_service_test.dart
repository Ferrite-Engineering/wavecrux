// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';

void main() {
  group('TimeFormatService', () {
    // ── no timescale ──────────────────────────────────────────────────────────

    group('format — no timescale', () {
      const svc = TimeFormatService();

      test('positive ticks returns "{n} ticks"', () {
        expect(svc.format(100), equals('100 ticks'));
        expect(svc.format(1), equals('1 ticks'));
      });

      test('zero ticks returns "0 ticks"', () {
        expect(svc.format(0), equals('0 ticks'));
      });

      test('large tick count formats without modification', () {
        expect(svc.format(999999), equals('999999 ticks'));
      });
    });

    // ── unknown unit falls back to ticks ──────────────────────────────────────

    group('format — unknown unit', () {
      const svc = TimeFormatService(
        timescale: Timescale(factor: 1, unit: TimescaleUnit.unknown),
      );

      test('returns ticks string when unit is unknown', () {
        expect(svc.format(50), equals('50 ticks'));
      });
    });

    // ── zero ticks ────────────────────────────────────────────────────────────

    group('format — zero ticks with known timescale', () {
      test('displays 0 with ns symbol for 1 ns timescale', () {
        const svc = TimeFormatService(
          timescale: Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds),
        );
        expect(svc.format(0), equals('0 ns'));
      });

      test('displays 0 with ps symbol for 1 ps timescale', () {
        const svc = TimeFormatService(
          timescale: Timescale(factor: 1, unit: TimescaleUnit.picoSeconds),
        );
        expect(svc.format(0), equals('0 ps'));
      });

      test('displays 0 with µs symbol for 1 µs timescale', () {
        const svc = TimeFormatService(
          timescale: Timescale(factor: 1, unit: TimescaleUnit.microSeconds),
        );
        expect(svc.format(0), equals('0 µs'));
      });

      test('displays 0 with ms symbol for 1 ms timescale', () {
        const svc = TimeFormatService(
          timescale: Timescale(factor: 1, unit: TimescaleUnit.milliSeconds),
        );
        expect(svc.format(0), equals('0 ms'));
      });

      test('displays 0 with s symbol for 1 s timescale', () {
        const svc = TimeFormatService(
          timescale: Timescale(factor: 1, unit: TimescaleUnit.seconds),
        );
        expect(svc.format(0), equals('0 s'));
      });
    });

    // ── auto-scaling: nanoseconds timescale ───────────────────────────────────

    group('format — 1 ns timescale', () {
      const svc = TimeFormatService(
        timescale: Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds),
      );

      test('1 tick → "1 ns"', () => expect(svc.format(1), equals('1 ns')));
      test('10 ticks → "10 ns"', () => expect(svc.format(10), equals('10 ns')));
      test(
        '100 ticks → "100 ns"',
        () => expect(svc.format(100), equals('100 ns')),
      );
      test(
        '999 ticks → "999 ns"',
        () => expect(svc.format(999), equals('999 ns')),
      );
      test(
        '1000 ticks → "1 µs"',
        () => expect(svc.format(1000), equals('1 µs')),
      );
      test(
        '1500 ticks → "1.5 µs"',
        () => expect(svc.format(1500), equals('1.5 µs')),
      );
      test(
        '1000000 ticks → "1 ms"',
        () => expect(svc.format(1000000), equals('1 ms')),
      );
      test(
        '1500000 ticks → "1.5 ms"',
        () => expect(svc.format(1500000), equals('1.5 ms')),
      );
      test(
        '1000000000 ticks → "1 s"',
        () => expect(svc.format(1000000000), equals('1 s')),
      );
    });

    // ── auto-scaling: picoseconds timescale ───────────────────────────────────

    group('format — 1 ps timescale', () {
      const svc = TimeFormatService(
        timescale: Timescale(factor: 1, unit: TimescaleUnit.picoSeconds),
      );

      test('1 tick → "1 ps"', () => expect(svc.format(1), equals('1 ps')));
      test(
        '1000 ticks → "1 ns"',
        () => expect(svc.format(1000), equals('1 ns')),
      );
      test(
        '1500 ticks → "1.5 ns"',
        () => expect(svc.format(1500), equals('1.5 ns')),
      );
      test(
        '1000000 ticks → "1 µs"',
        () => expect(svc.format(1000000), equals('1 µs')),
      );
      test(
        '1000000000 ticks → "1 ms"',
        () => expect(svc.format(1000000000), equals('1 ms')),
      );
    });

    // ── auto-scaling: femtoseconds timescale ──────────────────────────────────

    group('format — 1 fs timescale', () {
      const svc = TimeFormatService(
        timescale: Timescale(factor: 1, unit: TimescaleUnit.femtoSeconds),
      );

      test('1 tick → "1 fs"', () => expect(svc.format(1), equals('1 fs')));
      test(
        '1000 ticks → "1 ps"',
        () => expect(svc.format(1000), equals('1 ps')),
      );
      test(
        '1000000 ticks → "1 ns"',
        () => expect(svc.format(1000000), equals('1 ns')),
      );
    });

    // ── auto-scaling: factor-10 timescale ─────────────────────────────────────

    group('format — 10 ns timescale', () {
      const svc = TimeFormatService(
        timescale: Timescale(factor: 10, unit: TimescaleUnit.nanoSeconds),
      );

      test(
        '1 tick (= 10 ns) → "10 ns"',
        () => expect(svc.format(1), equals('10 ns')),
      );
      test(
        '150 ticks (= 1500 ns) → "1.5 µs"',
        () => expect(svc.format(150), equals('1.5 µs')),
      );
      test(
        '100000000 ticks (= 1 s) → "1 s"',
        () => expect(svc.format(100000000), equals('1 s')),
      );
    });

    // ── other SI units ────────────────────────────────────────────────────────

    group('format — µs and ms timescales', () {
      test('1 µs timescale: 1 tick → "1 µs", 1000 → "1 ms"', () {
        const svc = TimeFormatService(
          timescale: Timescale(factor: 1, unit: TimescaleUnit.microSeconds),
        );
        expect(svc.format(1), equals('1 µs'));
        expect(svc.format(1000), equals('1 ms'));
      });

      test('1 ms timescale: 1 tick → "1 ms", 1000 → "1 s"', () {
        const svc = TimeFormatService(
          timescale: Timescale(factor: 1, unit: TimescaleUnit.milliSeconds),
        );
        expect(svc.format(1), equals('1 ms'));
        expect(svc.format(1000), equals('1 s'));
      });

      test('1 s timescale: 1 tick → "1 s"', () {
        const svc = TimeFormatService(
          timescale: Timescale(factor: 1, unit: TimescaleUnit.seconds),
        );
        expect(svc.format(1), equals('1 s'));
      });
    });

    // ── precision and trailing-zero stripping ─────────────────────────────────

    group('format — value precision', () {
      const svc = TimeFormatService(
        timescale: Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds),
      );

      test('trailing zeros stripped: 1500 → "1.5 µs" not "1.50 µs"', () {
        expect(svc.format(1500), equals('1.5 µs'));
      });

      test('integer value has no decimal point: 100 → "100 ns"', () {
        expect(svc.format(100), equals('100 ns'));
      });

      test('two decimal places when value < 10: 1230 → "1.23 µs"', () {
        expect(svc.format(1230), equals('1.23 µs'));
      });

      test('one decimal place when 10 ≤ value < 100: 15500 → "15.5 µs"', () {
        // 15500 ns = 15.5 µs
        expect(svc.format(15500), equals('15.5 µs'));
      });

      test('zero decimal places when value ≥ 100: 500 → "500 ns"', () {
        expect(svc.format(500), equals('500 ns'));
      });

      test(
        'trailing zeros after decimal stripped completely: "1.00 µs" → "1 µs"',
        () {
          expect(svc.format(1000), equals('1 µs'));
        },
      );
    });

    // ── formatDelta ───────────────────────────────────────────────────────────

    group('formatDelta — 1 ns timescale', () {
      const svc = TimeFormatService(
        timescale: Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds),
      );

      test('a < b and b < a produce the same result (symmetric)', () {
        expect(svc.formatDelta(100, 1600), equals(svc.formatDelta(1600, 100)));
      });

      test('1600 − 100 = 1500 ns → "1.5 µs"', () {
        expect(svc.formatDelta(100, 1600), equals('1.5 µs'));
      });

      test('zero delta returns "0 ns"', () {
        expect(svc.formatDelta(500, 500), equals('0 ns'));
      });

      test('single-argument equivalent: formatDelta(0, n) == format(n)', () {
        expect(svc.formatDelta(0, 500), equals(svc.format(500)));
        expect(svc.formatDelta(0, 1500), equals(svc.format(1500)));
      });
    });

    group('formatDelta — no timescale', () {
      const svc = TimeFormatService();

      test('returns the delta as ticks string', () {
        expect(svc.formatDelta(100, 600), equals('500 ticks'));
      });

      test('is symmetric', () {
        expect(svc.formatDelta(600, 100), equals('500 ticks'));
      });

      test('zero delta returns "0 ticks"', () {
        expect(svc.formatDelta(50, 50), equals('0 ticks'));
      });
    });
  });
}
