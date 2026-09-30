// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Regression for P46: an HDL-sim UART decodes to nothing under a baud-rate
// decoder.
//
// Found running scenario 04. The design was `always #5 clk` (10 ns period,
// 1 ns timescale) with `CLKS_PER_BIT = 8`, so 80 ns per bit — 12.5 Mbaud. The
// decoder defaulted to `baud_rate = 9600`, computed a 104 166-tick bit period
// against an 80-tick reality, and returned **no transactions at all**. No
// error, no warning, no hint about which of a dozen settings was wrong.
//
// The user's reaction was the design input: they expected a clocks-per-bit
// knob, because `CLKS_PER_BIT` is right there in the design. Nobody writing an
// HDL testbench picks a baud number; they pick a clock and a divisor.
//
// These tests use the scenario's real numbers so the fixture and the bug stay
// tied together.

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/services/decoders/uart_decoder.dart';

import 'uart_decoder_test.dart'
    show buildUartFrames, makeChangesQuery, makeQuery;

/// The scenario-04 timing: `always #5 clk` at a 1 ns timescale.
const int _clockHalfPeriodTicks = 5;
const int _clocksPerBit = 8;
const int _bitPeriodTicks = _clocksPerBit * _clockHalfPeriodTicks * 2; // 80

const _timescale = Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);

/// A free-running clock across [endTime], toggling every half period.
List<(int, String)> buildClock(int endTime, {required int halfPeriod}) {
  final changes = <(int, String)>[];
  var level = '0';
  for (var t = 0; t < endTime; t += halfPeriod) {
    changes.add((t, level));
    level = level == '0' ? '1' : '0';
  }
  return changes;
}

UartDecoder decoderWith(Map<String, dynamic> params, {bool withClock = true}) =>
    UartDecoder(
      DecoderConfig(
        signalBindings: {
          'tx': 'tb.tx',
          if (withClock) 'clk': 'tb.clk',
        },
        parameters: {
          'data_bits': 8,
          'parity': 'none',
          'stop_bits': '1',
          'bit_order': 'lsb',
          'group_gap_bits': 10,
          ...params,
        },
      ),
    );

void main() {
  // One frame per byte at the scenario's 80-tick bit period.
  final tx = buildUartFrames(
    const [0x41, 0x42],
    startTime: 1000,
    bitPeriod: _bitPeriodTicks,
  );
  final signals = {
    'tx': tx,
    'clk': buildClock(4000, halfPeriod: _clockHalfPeriodTicks),
  };
  final query = makeQuery(signals);
  final changesQuery = makeChangesQuery(signals);

  /// The decoded payload as a flat hex string, e.g. `'0x41 0x42'`.
  String decodeData(UartDecoder d) {
    final txs = d.decode(0, 4000, query, changesQuery, timescale: _timescale);
    return [for (final t in txs) t.fields['data'] ?? ''].join(' ');
  }

  group('P46 — the reported failure', () {
    test('the default baud decoder finds nothing on this trace', () {
      // Not an assertion that this is *desirable* — it is the reproduction.
      // 9600 baud at 1 ns/tick is a 104 166-tick bit period against an
      // 80-tick reality.
      final d = decoderWith({'baud_rate': 9600}, withClock: false);
      expect(
        d.decode(0, 4000, query, changesQuery, timescale: _timescale),
        isEmpty,
      );
    });

    test('clocks-per-bit decodes the same trace correctly', () {
      final d = decoderWith({
        'timing_mode': 'clocks_per_bit',
        'clocks_per_bit': _clocksPerBit,
      });
      expect(decodeData(d), contains('41'));
    });

    test('the equivalent baud also works — the modes agree', () {
      // 1 / (80 ticks x 1 ns) = 12.5 Mbaud. Proves clocks-per-bit is a
      // restatement of the same timing, not a different decode path.
      final d = decoderWith({'baud_rate': 12500000}, withClock: false);
      expect(decodeData(d), contains('41'));
    });
  });

  group('clocks-per-bit mode', () {
    test('measures the clock period from the clock itself', () {
      // Halving the clock rate doubles the bit period, so the same 80-tick
      // trace samples at the wrong instants and yields a different byte. Note
      // it does NOT go silent — a wrong bit period produces wrong data, which
      // is precisely why guessing the timing is worse than stating it, and
      // why P46 was reported as "no transactions" only because 9600 baud was
      // wrong by four orders of magnitude rather than by two.
      final slowSignals = {
        'tx': tx,
        'clk': buildClock(4000, halfPeriod: _clockHalfPeriodTicks * 2),
      };
      final d = decoderWith({
        'timing_mode': 'clocks_per_bit',
        'clocks_per_bit': _clocksPerBit,
      });
      final out = d.decode(
        0,
        4000,
        makeQuery(slowSignals),
        makeChangesQuery(slowSignals),
        timescale: _timescale,
      );
      final data = [for (final t in out) t.fields['data']].join(' ');
      expect(
        data,
        isNot(contains('41')),
        reason:
            'the measured clock period must reach the bit period — if this '
            'still decodes 0x41 the measurement is being ignored',
      );
    });

    test('a gated clock does not skew the measurement', () {
      // The median gap is used rather than the mean precisely so a long idle
      // stretch cannot drag the period upward.
      final gated = [
        ...buildClock(1000, halfPeriod: _clockHalfPeriodTicks),
        (3000, '1'), // a 2 000-tick gap: the clock was gated off
        ...buildClock(
          4000,
          halfPeriod: _clockHalfPeriodTicks,
        ).where((c) => c.$1 > 3000),
      ];
      final signalsGated = {'tx': tx, 'clk': gated};
      final d = decoderWith({
        'timing_mode': 'clocks_per_bit',
        'clocks_per_bit': _clocksPerBit,
      });
      final out = d.decode(
        0,
        4000,
        makeQuery(signalsGated),
        makeChangesQuery(signalsGated),
        timescale: _timescale,
      );
      expect([for (final t in out) t.fields['data']].join(' '), contains('41'));
    });

    test('decodes nothing when the clk signal is not bound', () {
      // Silent-and-empty rather than wrong. The mode asks for a clock; without
      // one there is no honest bit period to invent.
      final d = decoderWith({
        'timing_mode': 'clocks_per_bit',
        'clocks_per_bit': _clocksPerBit,
      }, withClock: false);
      expect(
        d.decode(0, 4000, query, changesQuery, timescale: _timescale),
        isEmpty,
      );
    });

    test('rejects a non-positive clocks-per-bit', () {
      final d = decoderWith({
        'timing_mode': 'clocks_per_bit',
        'clocks_per_bit': 0,
      });
      expect(
        d.decode(0, 4000, query, changesQuery, timescale: _timescale),
        isEmpty,
      );
    });

    test('is independent of the timescale', () {
      // Clocks-per-bit is measured in ticks throughout, so a trace with no
      // timescale at all still decodes — unlike baud, which cannot work
      // without one.
      final d = decoderWith({
        'timing_mode': 'clocks_per_bit',
        'clocks_per_bit': _clocksPerBit,
      });
      final out = d.decode(0, 4000, query, changesQuery);
      expect([for (final t in out) t.fields['data']].join(' '), contains('41'));
    });
  });

  group('auto-detect mode', () {
    test('recovers the bit period from the data line', () {
      final d = decoderWith({'timing_mode': 'auto'}, withClock: false);
      expect(decodeData(d), contains('41'));
    });

    test('works at a different bit period without being told', () {
      final wide = buildUartFrames(
        const [0x55],
        startTime: 1000,
        bitPeriod: 250,
      );
      final s = {'tx': wide};
      final d = decoderWith({'timing_mode': 'auto'}, withClock: false);
      final out = d.decode(
        0,
        8000,
        makeQuery(s),
        makeChangesQuery(s),
        timescale: _timescale,
      );
      expect([for (final t in out) t.fields['data']].join(' '), contains('55'));
    });

    test('decodes nothing on a line with no transitions', () {
      final s = {
        'tx': <(int, String)>[(0, '1')],
      };
      final d = decoderWith({'timing_mode': 'auto'}, withClock: false);
      expect(
        d.decode(0, 4000, makeQuery(s), makeChangesQuery(s)),
        isEmpty,
      );
    });
  });

  group('backward compatibility', () {
    test('an unset timing_mode behaves exactly as baud did', () {
      // Every session and every decoder config already in the wild omits the
      // parameter. It must keep meaning what it always meant.
      final withoutMode = decoderWith({
        'baud_rate': 12500000,
      }, withClock: false);
      final explicitBaud = decoderWith({
        'timing_mode': 'baud',
        'baud_rate': 12500000,
      }, withClock: false);
      expect(decodeData(withoutMode), decodeData(explicitBaud));
      expect(decodeData(withoutMode), contains('41'));
    });

    test('an unrecognized timing_mode falls back to baud', () {
      final d = decoderWith({
        'timing_mode': 'something_new',
        'baud_rate': 12500000,
      }, withClock: false);
      expect(decodeData(d), contains('41'));
    });

    test('the clk binding is optional, not required', () {
      expect(
        UartDecoder.decoderDefinition.requiredSignals.map((s) => s.name),
        isNot(contains('clk')),
      );
      expect(
        UartDecoder.decoderDefinition.optionalSignals.map((s) => s.name),
        contains('clk'),
      );
    });
  });
}
