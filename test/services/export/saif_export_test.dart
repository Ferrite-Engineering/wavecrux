// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/services/export/saif_statistics.dart';
import 'package:wavecrux/services/export/saif_writer.dart';

import '../../helpers/fake_waveform_data_source.dart';

/// SAIF export: the switching-activity numbers a power tool ingests.
///
/// SAIF export is deliberately the only "power analysis" WaveCrux does.
/// Nothing here computes watts, so these
/// tests are about one thing: are the durations and toggle counts *true*.
///
/// The invariant that catches almost everything is that `T0 + T1 + TX + TZ`
/// must equal the analysis window exactly, per bit. A consuming tool notices a
/// violation immediately, and every off-by-one in an accumulation loop breaks
/// it.
void main() {
  const stats = SaifStatisticsService();
  const writer = SaifWriter();

  /// Analyzes one signal. [initial] is expressed as a change at the window's
  /// start, which is how a VCD's `$dumpvars` block actually appears — the fake
  /// source derives `valueAt` from the change list, and so does the real one.
  SaifSignalActivity analyze(
    List<SignalChange> changes, {
    required String path,
    required int width,
    int start = 0,
    int end = 100,
    String? initial,
  }) => stats.analyze(
    signalPath: path,
    name: path.split('.').last,
    width: width,
    source: FakeWaveformDataSource(
      signals: {
        path: [
          if (initial != null) SignalChange(time: start, value: initial),
          ...changes,
        ],
      },
      endTime: end,
    ),
    startTime: start,
    endTime: end,
  );

  group('dwell times partition the window exactly', () {
    test('a scalar toggling once', () {
      final a = analyze(
        const [SignalChange(time: 40, value: '1')],
        path: 'top.clk',
        width: 1,
        initial: '0',
      );
      final bit = a.bits.single;
      expect(bit.t0, 40);
      expect(bit.t1, 60);
      expect(bit.total, 100, reason: 'T0+T1+TX+TZ must equal the window');
      expect(bit.toggleCount, 1);
    });

    test('a signal that never changes holds for the whole window', () {
      final a = analyze(
        const <SignalChange>[],
        path: 'top.tie',
        width: 1,
        initial: '1',
      );
      expect(a.bits.single.t1, 100);
      expect(a.bits.single.toggleCount, 0);
      expect(a.bits.single.total, 100);
    });

    test('unknown before the first value is TX, not T0', () {
      // Reporting it as 0 would invent a full window of settled-low time — a
      // power tool would then under-report activity on a net that was simply
      // never driven.
      final a = analyze(
        const [SignalChange(time: 60, value: '1')],
        path: 'top.late',
        width: 1,
      );
      expect(a.bits.single.tx, 60);
      expect(a.bits.single.t1, 40);
      expect(a.bits.single.total, 100);
    });

    test('x and z stretches are reported, not flattened', () {
      final a = analyze(
        const [
          SignalChange(time: 20, value: 'x'),
          SignalChange(time: 50, value: 'z'),
          SignalChange(time: 80, value: '1'),
        ],
        path: 'top.n',
        width: 1,
        initial: '0',
      );
      final b = a.bits.single;
      expect(b.t0, 20);
      expect(b.tx, 30);
      expect(b.tz, 30);
      expect(b.t1, 20);
      expect(b.total, 100);
    });
  });

  group('toggle counting', () {
    test('only 0 to 1 and 1 to 0 count', () {
      // A settle out of x is not a physical toggle. Counting it would inflate
      // an energy estimate, which is the direction that misleads.
      final a = analyze(
        const [
          SignalChange(time: 20, value: 'x'),
          SignalChange(time: 40, value: '1'),
          SignalChange(time: 60, value: '0'),
          SignalChange(time: 80, value: 'z'),
        ],
        path: 'top.n',
        width: 1,
        initial: '0',
      );
      // 0→x (no), x→1 (no), 1→0 (yes), 0→z (no).
      expect(a.bits.single.toggleCount, 1);
    });

    test('a same-value change record is not a toggle', () {
      final a = analyze(
        const [
          SignalChange(time: 0, value: '0'),
          SignalChange(time: 50, value: '0'),
        ],
        path: 'top.n',
        width: 1,
        initial: '0',
      );
      expect(a.bits.single.toggleCount, 0);
    });
  });

  group('buses are per bit', () {
    test('each bit accumulates independently', () {
      // 0b0000 → 0b0011 at t=50. Bits 0,1 toggle; bits 2,3 never do.
      final a = analyze(
        const [SignalChange(time: 50, value: '0011')],
        path: 'top.bus',
        width: 4,
        initial: '0000',
      );
      expect(a.bits, hasLength(4));
      // Index 0 is the LSB.
      expect(a.bits[0].t1, 50);
      expect(a.bits[1].t1, 50);
      expect(a.bits[2].t1, 0);
      expect(a.bits[3].t1, 0);
      expect(a.bits[0].toggleCount, 1);
      expect(a.bits[3].toggleCount, 0);
      for (final b in a.bits) {
        expect(b.total, 100, reason: 'every bit must cover the window');
      }
    });

    test('a short bit string is zero-extended, per the VCD rule', () {
      final a = analyze(
        const [SignalChange(time: 50, value: '11')],
        path: 'top.bus',
        width: 4,
        initial: '0',
      );
      expect(a.bits[2].t1, 0);
      expect(a.bits[3].t1, 0);
      expect(a.bits[0].t1, 50);
    });

    test('a partially-unknown bus splits per bit', () {
      final a = analyze(
        const [SignalChange(time: 50, value: '01x1')],
        path: 'top.bus',
        width: 4,
        initial: '0000',
      );
      expect(a.bits[1].tx, 50, reason: 'only the x bit is unknown');
      expect(a.bits[0].t1, 50);
      expect(a.bits[3].t0, 100);
    });
  });

  group('degenerate windows', () {
    test('a zero-length window yields all zeros, not a crash', () {
      final a = analyze(
        const <SignalChange>[],
        path: 'top.n',
        width: 1,
        start: 50,
        end: 50,
        initial: '1',
      );
      expect(a.bits.single.total, 0);
    });
  });

  group('the rendered document', () {
    List<SaifSignalActivity> sample() => [
      analyze(
        const [SignalChange(time: 50, value: '1')],
        path: 'top.clk',
        width: 1,
        initial: '0',
      ),
      analyze(
        const [SignalChange(time: 50, value: '10')],
        path: 'top.dsp.bus',
        width: 2,
        initial: '00',
      ),
    ];

    test('carries the header a reader keys off', () {
      final out = writer.render(
        signals: sample(),
        duration: 100,
        timescale: const Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds),
      );
      expect(out, contains('(SAIFILE'));
      expect(out, contains('(SAIFVERSION "2.0")'));
      expect(out, contains('(DIRECTION "backward")'));
      expect(out, contains('(TIMESCALE 1ns)'));
      expect(out, contains('(DURATION 100)'));
    });

    test('nests INSTANCE scopes from the signal paths', () {
      final out = writer.render(signals: sample(), duration: 100);
      expect(out, contains('(INSTANCE top'));
      expect(out, contains('(INSTANCE dsp'));
      // dsp must be nested inside top, not a sibling.
      expect(
        out.indexOf('(INSTANCE top'),
        lessThan(out.indexOf('(INSTANCE dsp')),
      );
    });

    test('scalars carry no index, buses carry escaped per-bit indices', () {
      final out = writer.render(signals: sample(), duration: 100);
      expect(out, contains('(clk (T0 '));
      expect(out, contains(r'(bus\[0\] (T0 '));
      expect(out, contains(r'(bus\[1\] (T0 '));
    });

    test('reports real TX and TZ rather than hardcoding zero', () {
      // Verilator's own writer hardcodes these because it has two-value logic.
      // Reading four-state data is the one place this exporter can do better,
      // and a test is the only thing that keeps it that way.
      final withUnknown = [
        analyze(
          const [SignalChange(time: 30, value: '1')],
          path: 'top.n',
          width: 1,
        ),
      ];
      final out = writer.render(signals: withUnknown, duration: 100);
      expect(out, contains('(TX 30)'));
      expect(out, isNot(contains('(TX 0) (TB 0) (TC 0))')));
    });

    test('balances its parentheses', () {
      final out = writer.render(signals: sample(), duration: 100);
      final opens = '('.allMatches(out).length;
      final closes = ')'.allMatches(out).length;
      expect(opens, closes, reason: 'SAIF is an s-expression; it must balance');
    });

    test('an empty signal set still produces a valid document', () {
      final out = writer.render(signals: const [], duration: 0);
      expect(out, contains('(SAIFILE'));
      expect('('.allMatches(out).length, ')'.allMatches(out).length);
    });

    test('the timescale falls back to 1ns for an untimed trace', () {
      expect(writer.render(signals: const [], duration: 0), contains('1ns'));
    });
  });
}
