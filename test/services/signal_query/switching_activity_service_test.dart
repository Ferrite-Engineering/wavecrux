// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/activity_report.dart';
import 'package:wavecrux/domain/models/signal_activity.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/services/signal_query/switching_activity_service.dart';

class _MockDataSource extends Mock implements WaveformDataSource {}

void main() {
  late _MockDataSource source;
  late SwitchingActivityService service;

  const ref = 'top.clk';
  const start = 0;
  const end = 100;

  setUp(() {
    source = _MockDataSource();
    service = const SwitchingActivityService();
    when(() => source.timescale).thenReturn(null);
  });

  // ── analyzeSignal ───────────────────────────────────────────────────────────

  group('analyzeSignal', () {
    test('no transitions → count 0 and toggleRate 0', () {
      when(() => source.changesInRange(ref, start, end)).thenReturn([]);
      when(() => source.valueAt(ref, start)).thenReturn('0');

      final result = service.analyzeSignal(ref, source, start, end);

      expect(result.transitionCount, 0);
      expect(result.toggleRate, 0.0);
      expect(result.isClockCandidate, isFalse);
      expect(result.timeRange, const TimeRange(start: start, end: end));
    });

    test('counts all changes in range', () {
      when(() => source.changesInRange(ref, start, end)).thenReturn([
        const SignalChange(time: 10, value: '1'),
        const SignalChange(time: 20, value: '0'),
        const SignalChange(time: 30, value: '1'),
        const SignalChange(time: 40, value: '0'),
      ]);
      when(() => source.valueAt(ref, start)).thenReturn('0');

      final result = service.analyzeSignal(ref, source, start, end);

      expect(result.transitionCount, 4);
      expect(result.toggleRate, closeTo(4 / 100, 1e-10));
    });

    test('toggleRate is 0 when startTime == endTime', () {
      when(() => source.changesInRange(ref, 50, 50)).thenReturn([]);
      when(() => source.valueAt(ref, 50)).thenReturn('0');

      final result = service.analyzeSignal(ref, source, 50, 50);

      expect(result.toggleRate, 0.0);
    });

    test('single transition is counted', () {
      when(() => source.changesInRange(ref, start, end)).thenReturn([
        const SignalChange(time: 50, value: '1'),
      ]);
      when(() => source.valueAt(ref, start)).thenReturn('0');

      final result = service.analyzeSignal(ref, source, start, end);

      expect(result.transitionCount, 1);
    });

    test('X and Z value transitions are counted', () {
      when(() => source.changesInRange(ref, start, end)).thenReturn([
        const SignalChange(time: 10, value: 'x'),
        const SignalChange(time: 20, value: 'z'),
        const SignalChange(time: 30, value: '0'),
      ]);
      when(() => source.valueAt(ref, start)).thenReturn('1');

      final result = service.analyzeSignal(ref, source, start, end);

      expect(result.transitionCount, 3);
    });

    test(
      'constant signal with one initial-state record reports 0 transitions',
      () {
        // A signal that never changes value still has its initial-state
        // dump recorded at time 0 by `$dumpvars`. wellen surfaces that as a
        // single value-change record, but it is not a transition — the
        // value did not differ from the prior state because there was no
        // prior state.
        when(() => source.changesInRange(ref, start, end)).thenReturn([
          const SignalChange(time: 0, value: '0'),
        ]);
        when(() => source.valueAt(ref, start)).thenReturn('0');

        final result = service.analyzeSignal(ref, source, start, end);

        expect(result.transitionCount, 0);
        expect(result.toggleRate, 0.0);
      },
    );

    // ── duty cycle ────────────────────────────────────────────────────────────

    test('1-bit signal: duty cycle computed correctly', () {
      // High for 50 ticks out of 100.
      when(() => source.changesInRange(ref, start, end)).thenReturn([
        const SignalChange(time: 0, value: '1'),
        const SignalChange(time: 50, value: '0'),
      ]);
      when(() => source.valueAt(ref, start)).thenReturn('0');

      final result = service.analyzeSignal(ref, source, start, end);

      expect(result.dutyCycle, closeTo(0.5, 1e-10));
    });

    test('1-bit signal: initially high, never goes low → dutyCycle 1.0', () {
      when(() => source.changesInRange(ref, start, end)).thenReturn([]);
      when(() => source.valueAt(ref, start)).thenReturn('1');

      final result = service.analyzeSignal(ref, source, start, end);

      expect(result.dutyCycle, closeTo(1.0, 1e-10));
    });

    test('1-bit signal: always low → dutyCycle 0.0', () {
      when(() => source.changesInRange(ref, start, end)).thenReturn([]);
      when(() => source.valueAt(ref, start)).thenReturn('0');

      final result = service.analyzeSignal(ref, source, start, end);

      expect(result.dutyCycle, closeTo(0.0, 1e-10));
    });

    test('multi-bit signal → dutyCycle is null', () {
      when(() => source.changesInRange(ref, start, end)).thenReturn([
        const SignalChange(time: 10, value: 'b00'),
        const SignalChange(time: 20, value: 'b01'),
      ]);
      when(() => source.valueAt(ref, start)).thenReturn('b00');

      final result = service.analyzeSignal(ref, source, start, end);

      expect(result.dutyCycle, isNull);
    });

    test('multi-bit initial value → dutyCycle is null even if no changes', () {
      when(() => source.changesInRange(ref, start, end)).thenReturn([]);
      when(() => source.valueAt(ref, start)).thenReturn('b0000');

      final result = service.analyzeSignal(ref, source, start, end);

      expect(result.dutyCycle, isNull);
    });

    test('no changes and null initial value → dutyCycle is null', () {
      when(() => source.changesInRange(ref, start, end)).thenReturn([]);
      when(() => source.valueAt(ref, start)).thenReturn(null);

      final result = service.analyzeSignal(ref, source, start, end);

      expect(result.dutyCycle, isNull);
    });

    test('b-prefixed single-bit value → treated as 1-bit', () {
      when(() => source.changesInRange(ref, start, end)).thenReturn([
        const SignalChange(time: 50, value: 'b0'),
      ]);
      when(() => source.valueAt(ref, start)).thenReturn('b1');

      final result = service.analyzeSignal(ref, source, start, end);

      // High for first 50 ticks.
      expect(result.dutyCycle, closeTo(0.5, 1e-10));
    });

    test('duty cycle with irregular segments', () {
      // Pattern: low 20, high 30, low 10, high 40 = 70 high / 100 total.
      when(() => source.changesInRange(ref, start, end)).thenReturn([
        const SignalChange(time: 20, value: '1'),
        const SignalChange(time: 50, value: '0'),
        const SignalChange(time: 60, value: '1'),
      ]);
      when(() => source.valueAt(ref, start)).thenReturn('0');

      final result = service.analyzeSignal(ref, source, start, end);

      expect(result.dutyCycle, closeTo(0.7, 1e-10));
    });

    test('isClockCandidate is always false', () {
      when(() => source.changesInRange(ref, start, end)).thenReturn([
        const SignalChange(time: 10, value: '1'),
        const SignalChange(time: 20, value: '0'),
        const SignalChange(time: 30, value: '1'),
        const SignalChange(time: 40, value: '0'),
        const SignalChange(time: 50, value: '1'),
        const SignalChange(time: 60, value: '0'),
        const SignalChange(time: 70, value: '1'),
        const SignalChange(time: 80, value: '0'),
      ]);
      when(() => source.valueAt(ref, start)).thenReturn('0');

      expect(
        service.analyzeSignal(ref, source, start, end).isClockCandidate,
        isFalse,
      );
    });
  });

  // ── detectClock ─────────────────────────────────────────────────────────────

  group('detectClock', () {
    // Perfect 10-tick-period clock: 5 rising edges (4 measurable periods), 50% DC.
    // Rising at 5,15,25,35,45; falling at 10,20,30,40,50.
    List<SignalChange> perfectClock() => [
      const SignalChange(time: 5, value: '1'),
      const SignalChange(time: 10, value: '0'),
      const SignalChange(time: 15, value: '1'),
      const SignalChange(time: 20, value: '0'),
      const SignalChange(time: 25, value: '1'),
      const SignalChange(time: 30, value: '0'),
      const SignalChange(time: 35, value: '1'),
      const SignalChange(time: 40, value: '0'),
      const SignalChange(time: 45, value: '1'),
      const SignalChange(time: 50, value: '0'),
    ];

    test('perfect 50% clock → isClockCandidate true', () {
      when(() => source.changesInRange(ref, 0, 60)).thenReturn(perfectClock());
      when(() => source.valueAt(ref, 0)).thenReturn('0');

      final result = service.detectClock(ref, source, 0, 60);

      expect(result.isClockCandidate, isTrue);
    });

    test('perfect clock with 1 ns timescale → estimatedFrequency 100 MHz', () {
      when(() => source.changesInRange(ref, 0, 60)).thenReturn(perfectClock());
      when(() => source.valueAt(ref, 0)).thenReturn('0');
      when(() => source.timescale).thenReturn(
        const Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds),
      );

      final result = service.detectClock(ref, source, 0, 60);

      // Period = 10 ticks × 1 ns/tick = 10 ns → 100 MHz.
      expect(result.estimatedFrequency, closeTo(100e6, 1.0));
    });

    test('clock with null timescale → estimatedFrequency is null', () {
      when(() => source.changesInRange(ref, 0, 60)).thenReturn(perfectClock());
      when(() => source.valueAt(ref, 0)).thenReturn('0');
      // timescale stub returns null (set in setUp).

      final result = service.detectClock(ref, source, 0, 60);

      expect(result.isClockCandidate, isTrue);
      expect(result.estimatedFrequency, isNull);
    });

    test('fewer than 8 transitions → not a clock', () {
      when(() => source.changesInRange(ref, start, end)).thenReturn([
        const SignalChange(time: 10, value: '1'),
        const SignalChange(time: 20, value: '0'),
        const SignalChange(time: 30, value: '1'),
        const SignalChange(time: 40, value: '0'),
        const SignalChange(time: 50, value: '1'),
        const SignalChange(time: 60, value: '0'),
        const SignalChange(time: 70, value: '1'),
      ]);
      when(() => source.valueAt(ref, start)).thenReturn('0');

      expect(
        service.detectClock(ref, source, start, end).isClockCandidate,
        isFalse,
      );
    });

    test(
      'fewer than 5 rising edges → not a clock (cannot measure 4 periods)',
      () {
        // 8 transitions but only 4 rising edges → 3 measurable periods < 4 required.
        when(() => source.changesInRange(ref, start, end)).thenReturn([
          const SignalChange(time: 10, value: '1'),
          const SignalChange(time: 20, value: '0'),
          const SignalChange(time: 30, value: '1'),
          const SignalChange(time: 40, value: '0'),
          const SignalChange(time: 50, value: '1'),
          const SignalChange(time: 60, value: '0'),
          const SignalChange(time: 70, value: '1'),
          const SignalChange(time: 80, value: '0'),
        ]);
        when(() => source.valueAt(ref, start)).thenReturn('0');

        expect(
          service.detectClock(ref, source, start, end).isClockCandidate,
          isFalse,
        );
      },
    );

    test('inconsistent period (>5% variation) → not a clock', () {
      // 5 rising edges but periods 10,10,11,10 → 11/10-1 = 10% > 5%.
      when(() => source.changesInRange(ref, 0, 70)).thenReturn([
        const SignalChange(time: 5, value: '1'),
        const SignalChange(time: 10, value: '0'),
        const SignalChange(time: 15, value: '1'),
        const SignalChange(time: 20, value: '0'),
        const SignalChange(time: 25, value: '1'),
        const SignalChange(time: 30, value: '0'),
        const SignalChange(time: 36, value: '1'),
        const SignalChange(time: 41, value: '0'),
        const SignalChange(time: 46, value: '1'),
        const SignalChange(time: 51, value: '0'),
      ]);
      when(() => source.valueAt(ref, 0)).thenReturn('0');

      expect(
        service.detectClock(ref, source, 0, 70).isClockCandidate,
        isFalse,
      );
    });

    test('jitter > 2% of mean period → not a clock (fast_toggle scenario)', () {
      // 5 rising edges, periods [14, 14, 15, 14] → stddev/mean ≈ 3.3% > 2%.
      when(() => source.changesInRange(ref, 0, 100)).thenReturn([
        const SignalChange(time: 0, value: '1'),
        const SignalChange(time: 7, value: '0'),
        const SignalChange(time: 14, value: '1'),
        const SignalChange(time: 21, value: '0'),
        const SignalChange(time: 28, value: '1'),
        const SignalChange(time: 35, value: '0'),
        const SignalChange(time: 43, value: '1'),
        const SignalChange(time: 50, value: '0'),
        const SignalChange(time: 57, value: '1'),
        const SignalChange(time: 64, value: '0'),
      ]);
      when(() => source.valueAt(ref, 0)).thenReturn('0');

      expect(
        service.detectClock(ref, source, 0, 100).isClockCandidate,
        isFalse,
      );
    });

    test('duty cycle below 40% → not a clock', () {
      // 5 rising edges, high for 1 tick / low for 9 → 10% duty cycle.
      when(() => source.changesInRange(ref, 0, 50)).thenReturn([
        const SignalChange(time: 0, value: '1'),
        const SignalChange(time: 1, value: '0'),
        const SignalChange(time: 10, value: '1'),
        const SignalChange(time: 11, value: '0'),
        const SignalChange(time: 20, value: '1'),
        const SignalChange(time: 21, value: '0'),
        const SignalChange(time: 30, value: '1'),
        const SignalChange(time: 31, value: '0'),
        const SignalChange(time: 40, value: '1'),
        const SignalChange(time: 41, value: '0'),
      ]);
      when(() => source.valueAt(ref, 0)).thenReturn('0');

      expect(
        service.detectClock(ref, source, 0, 50).isClockCandidate,
        isFalse,
      );
    });

    test('duty cycle above 60% → not a clock', () {
      // 5 rising edges, high for 9 ticks / low for 1 → 90% duty cycle.
      when(() => source.changesInRange(ref, 0, 50)).thenReturn([
        const SignalChange(time: 0, value: '1'),
        const SignalChange(time: 9, value: '0'),
        const SignalChange(time: 10, value: '1'),
        const SignalChange(time: 19, value: '0'),
        const SignalChange(time: 20, value: '1'),
        const SignalChange(time: 29, value: '0'),
        const SignalChange(time: 30, value: '1'),
        const SignalChange(time: 39, value: '0'),
        const SignalChange(time: 40, value: '1'),
        const SignalChange(time: 49, value: '0'),
      ]);
      when(() => source.valueAt(ref, 0)).thenReturn('0');

      expect(
        service.detectClock(ref, source, 0, 50).isClockCandidate,
        isFalse,
      );
    });

    test('multi-bit signal → not a clock', () {
      when(() => source.changesInRange(ref, start, end)).thenReturn([
        const SignalChange(time: 10, value: 'b01'),
        const SignalChange(time: 20, value: 'b10'),
        const SignalChange(time: 30, value: 'b01'),
        const SignalChange(time: 40, value: 'b10'),
      ]);
      when(() => source.valueAt(ref, start)).thenReturn('b00');

      expect(
        service.detectClock(ref, source, start, end).isClockCandidate,
        isFalse,
      );
    });

    test('near-50% duty cycle within tolerance is accepted', () {
      // 5 rising edges, 10-tick period, high for 4 ticks (40% — exactly at boundary).
      when(() => source.changesInRange(ref, 0, 50)).thenReturn([
        const SignalChange(time: 0, value: '1'),
        const SignalChange(time: 4, value: '0'),
        const SignalChange(time: 10, value: '1'),
        const SignalChange(time: 14, value: '0'),
        const SignalChange(time: 20, value: '1'),
        const SignalChange(time: 24, value: '0'),
        const SignalChange(time: 30, value: '1'),
        const SignalChange(time: 34, value: '0'),
        const SignalChange(time: 40, value: '1'),
        const SignalChange(time: 44, value: '0'),
      ]);
      when(() => source.valueAt(ref, 0)).thenReturn('0');

      expect(
        service.detectClock(ref, source, 0, 50).isClockCandidate,
        isTrue,
      );
    });

    test('zero-jitter clock with 4 measurable periods is accepted', () {
      // Identical to perfectClock: periods all 10 → stddev 0 → passes jitter check.
      when(() => source.changesInRange(ref, 0, 60)).thenReturn(perfectClock());
      when(() => source.valueAt(ref, 0)).thenReturn('0');

      expect(
        service.detectClock(ref, source, 0, 60).isClockCandidate,
        isTrue,
      );
    });

    test('frequency uses average period', () {
      // Rising edges at 5,15,25,35,45 → avg period 10 ticks, 1 ns → 100 MHz.
      when(() => source.changesInRange(ref, 0, 60)).thenReturn(perfectClock());
      when(() => source.valueAt(ref, 0)).thenReturn('0');
      when(() => source.timescale).thenReturn(
        const Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds),
      );

      final freq = service.detectClock(ref, source, 0, 60).estimatedFrequency;
      expect(freq, isNotNull);
      expect(freq, closeTo(1e8, 1.0));
    });
  });

  // ── analyzeAll ──────────────────────────────────────────────────────────────

  group('analyzeAll', () {
    test('empty map → empty report', () {
      when(() => source.timescale).thenReturn(null);

      final report = service.analyzeAll({}, source, start, end);

      expect(report.signals, isEmpty);
      expect(report.topSwitchers, isEmpty);
      expect(report.totalTransitions, 0);
      expect(report.timeRange, const TimeRange(start: start, end: end));
    });

    test('totalTransitions is sum of all signal transition counts', () {
      const refA = 'top.a';
      const refB = 'top.b';

      when(() => source.changesInRange(refA, start, end)).thenReturn([
        const SignalChange(time: 10, value: '1'),
        const SignalChange(time: 20, value: '0'),
      ]);
      when(() => source.valueAt(refA, start)).thenReturn('0');

      when(() => source.changesInRange(refB, start, end)).thenReturn([
        const SignalChange(time: 15, value: '1'),
        const SignalChange(time: 25, value: '0'),
        const SignalChange(time: 35, value: '1'),
        const SignalChange(time: 45, value: '0'),
      ]);
      when(() => source.valueAt(refB, start)).thenReturn('0');

      final report = service.analyzeAll(
        {refA: refA, refB: refB},
        source,
        start,
        end,
      );

      expect(report.totalTransitions, 6);
    });

    test('topSwitchers is sorted by toggleRate descending', () {
      const refA = 'top.slow';
      const refB = 'top.fast';

      when(() => source.changesInRange(refA, start, end)).thenReturn([
        const SignalChange(time: 50, value: '1'),
      ]);
      when(() => source.valueAt(refA, start)).thenReturn('0');

      when(() => source.changesInRange(refB, start, end)).thenReturn([
        const SignalChange(time: 10, value: '1'),
        const SignalChange(time: 20, value: '0'),
        const SignalChange(time: 30, value: '1'),
        const SignalChange(time: 40, value: '0'),
        const SignalChange(time: 50, value: '1'),
        const SignalChange(time: 60, value: '0'),
      ]);
      when(() => source.valueAt(refB, start)).thenReturn('0');

      final report = service.analyzeAll(
        {refA: refA, refB: refB},
        source,
        start,
        end,
      );

      expect(report.topSwitchers.first.signalPath, refB);
      expect(report.topSwitchers.last.signalPath, refA);
    });

    test('signals list preserves insertion order', () {
      const refs = ['top.a', 'top.b', 'top.c'];
      for (final r in refs) {
        when(() => source.changesInRange(r, start, end)).thenReturn([]);
        when(() => source.valueAt(r, start)).thenReturn('0');
      }

      final map = {for (final r in refs) r: r};
      final report = service.analyzeAll(map, source, start, end);

      expect(
        report.signals.map((s) => s.signalPath).toList(),
        equals(refs),
      );
    });

    test(
      'signalPath in report uses display path from map value, not ref key',
      () {
        const signalRef = '!';
        const displayPath = 'top.cpu.clk';

        when(() => source.changesInRange(signalRef, start, end)).thenReturn([]);
        when(() => source.valueAt(signalRef, start)).thenReturn('0');

        final report = service.analyzeAll(
          {signalRef: displayPath},
          source,
          start,
          end,
        );

        expect(report.signals.first.signalPath, displayPath);
      },
    );

    test('when ref equals display path, signalPath is unchanged', () {
      const path = 'top.cpu.clk';

      when(() => source.changesInRange(path, start, end)).thenReturn([]);
      when(() => source.valueAt(path, start)).thenReturn('0');

      final report = service.analyzeAll({path: path}, source, start, end);

      expect(report.signals.first.signalPath, path);
    });

    test('clock signals in batch are identified (5 rising edges required)', () {
      const clkRef = 'top.clk';

      // 10 transitions: 5 rising edges → 4 measurable periods → qualifies.
      when(() => source.changesInRange(clkRef, 0, 60)).thenReturn([
        const SignalChange(time: 5, value: '1'),
        const SignalChange(time: 10, value: '0'),
        const SignalChange(time: 15, value: '1'),
        const SignalChange(time: 20, value: '0'),
        const SignalChange(time: 25, value: '1'),
        const SignalChange(time: 30, value: '0'),
        const SignalChange(time: 35, value: '1'),
        const SignalChange(time: 40, value: '0'),
        const SignalChange(time: 45, value: '1'),
        const SignalChange(time: 50, value: '0'),
      ]);
      when(() => source.valueAt(clkRef, 0)).thenReturn('0');

      final report = service.analyzeAll({clkRef: clkRef}, source, 0, 60);

      expect(report.signals.first.isClockCandidate, isTrue);
    });
  });

  // ── computeHeatmapValues ────────────────────────────────────────────────────

  group('computeHeatmapValues', () {
    const range = TimeRange(start: 0, end: 100);

    SignalActivity makeActivity(String path, double rate) => SignalActivity(
      signalPath: path,
      transitionCount: (rate * 100).round(),
      toggleRate: rate,
      isClockCandidate: false,
      timeRange: range,
    );

    test('empty report → empty map', () {
      const report = ActivityReport(
        signals: [],
        timeRange: range,
        totalTransitions: 0,
        topSwitchers: [],
      );
      expect(service.computeHeatmapValues(report), isEmpty);
    });

    test('single signal → heat value 1.0', () {
      final sig = makeActivity('top.a', 0.1);
      final report = ActivityReport(
        signals: [sig],
        timeRange: range,
        totalTransitions: 10,
        topSwitchers: [sig],
      );

      final heat = service.computeHeatmapValues(report);

      expect(heat['top.a'], closeTo(1.0, 1e-10));
    });

    test('all-zero toggle rates → all values are 0.0', () {
      final signals = [
        makeActivity('top.a', 0),
        makeActivity('top.b', 0),
      ];
      final report = ActivityReport(
        signals: signals,
        timeRange: range,
        totalTransitions: 0,
        topSwitchers: signals,
      );

      final heat = service.computeHeatmapValues(report);

      expect(heat['top.a'], closeTo(0.0, 1e-10));
      expect(heat['top.b'], closeTo(0.0, 1e-10));
    });

    test('max signal gets 1.0, others are proportional', () {
      final signals = [
        makeActivity('top.fast', 0.4),
        makeActivity('top.slow', 0.1),
        makeActivity('top.idle', 0),
      ];
      final report = ActivityReport(
        signals: signals,
        timeRange: range,
        totalTransitions: 50,
        topSwitchers: signals,
      );

      final heat = service.computeHeatmapValues(report);

      expect(heat['top.fast'], closeTo(1.0, 1e-10));
      expect(heat['top.slow'], closeTo(0.25, 1e-10));
      expect(heat['top.idle'], closeTo(0.0, 1e-10));
    });

    test('returns a value for every signal in the report', () {
      final signals = List.generate(
        5,
        (i) => makeActivity('top.sig$i', i * 0.1),
      );
      final report = ActivityReport(
        signals: signals,
        timeRange: range,
        totalTransitions: 100,
        topSwitchers: signals,
      );

      final heat = service.computeHeatmapValues(report);

      expect(heat.length, 5);
      for (final s in signals) {
        expect(heat.containsKey(s.signalPath), isTrue);
      }
    });

    test('all heat values are in [0.0, 1.0]', () {
      final signals = [
        makeActivity('top.a', 0.3),
        makeActivity('top.b', 0.05),
        makeActivity('top.c', 0.7),
      ];
      final report = ActivityReport(
        signals: signals,
        timeRange: range,
        totalTransitions: 100,
        topSwitchers: signals,
      );

      final heat = service.computeHeatmapValues(report);

      for (final value in heat.values) {
        expect(value, greaterThanOrEqualTo(0.0));
        expect(value, lessThanOrEqualTo(1.0));
      }
    });
  });
}
