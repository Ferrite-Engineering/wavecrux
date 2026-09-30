// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_integrity_report.dart';

const _clock = ClockInfo(
  signalRef: '!',
  signalPath: 'top.clk',
  periodTicks: 10,
  dutyCyclePercent: 50,
  estimatedFrequency: '100 MHz',
);

const _baseReport = SignalIntegrityReport(
  constantSignalPaths: ['top.vdd', 'top.gnd'],
  xzOnlySignalPaths: ['top.nc'],
  glitchSignals: {'top.data': 3},
  detectedClocks: [_clock],
  stuckAtResetPaths: ['top.reset_n'],
  analysisTimeMs: 412.5,
  signalsAnalyzed: 3200,
);

void main() {
  group('ClockInfo', () {
    test('stores all fields', () {
      expect(_clock.signalRef, '!');
      expect(_clock.signalPath, 'top.clk');
      expect(_clock.periodTicks, 10);
      expect(_clock.dutyCyclePercent, 50.0);
      expect(_clock.estimatedFrequency, '100 MHz');
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    test('copyWith with no args returns equal object', () {
      expect(_clock.copyWith(), equals(_clock));
    });

    test('copyWith changes only estimatedFrequency', () {
      final updated = _clock.copyWith(estimatedFrequency: '200 MHz');
      expect(updated.estimatedFrequency, '200 MHz');
      expect(updated.signalPath, _clock.signalPath);
      expect(updated.periodTicks, _clock.periodTicks);
    });

    test('copyWith changes only dutyCyclePercent', () {
      final updated = _clock.copyWith(dutyCyclePercent: 40);
      expect(updated.dutyCyclePercent, 40.0);
      expect(updated.estimatedFrequency, _clock.estimatedFrequency);
    });

    // ── equality ──────────────────────────────────────────────────────────────

    test('equal objects compare as equal', () {
      final a = _clock.copyWith();
      final b = _clock.copyWith();
      expect(a, equals(b));
    });

    test('differing periodTicks makes objects unequal', () {
      final a = _clock.copyWith(periodTicks: 10);
      final b = _clock.copyWith(periodTicks: 20);
      expect(a, isNot(equals(b)));
    });

    test('differing signalPath makes objects unequal', () {
      final a = _clock.copyWith(signalPath: 'top.clk');
      final b = _clock.copyWith(signalPath: 'top.clk2');
      expect(a, isNot(equals(b)));
    });

    // ── hashCode ──────────────────────────────────────────────────────────────

    test('equal objects have equal hashCodes', () {
      final a = _clock.copyWith();
      final b = _clock.copyWith();
      expect(a.hashCode, equals(b.hashCode));
    });

    // ── toString ──────────────────────────────────────────────────────────────

    test('toString contains signal path and frequency', () {
      final s = _clock.toString();
      expect(s, contains('top.clk'));
      expect(s, contains('100 MHz'));
    });

    test('toString contains period and duty cycle', () {
      final s = _clock.toString();
      expect(s, contains('10'));
      expect(s, contains('50'));
    });
  });

  group('SignalIntegrityReport', () {
    test('stores all fields', () {
      expect(_baseReport.constantSignalPaths, ['top.vdd', 'top.gnd']);
      expect(_baseReport.xzOnlySignalPaths, ['top.nc']);
      expect(_baseReport.glitchSignals, {'top.data': 3});
      expect(_baseReport.detectedClocks, [_clock]);
      expect(_baseReport.stuckAtResetPaths, ['top.reset_n']);
      expect(_baseReport.analysisTimeMs, 412.5);
      expect(_baseReport.signalsAnalyzed, 3200);
    });

    test('empty report has all empty collections', () {
      const empty = SignalIntegrityReport(
        constantSignalPaths: [],
        xzOnlySignalPaths: [],
        glitchSignals: {},
        detectedClocks: [],
        stuckAtResetPaths: [],
        analysisTimeMs: 0,
        signalsAnalyzed: 0,
      );
      expect(empty.constantSignalPaths, isEmpty);
      expect(empty.xzOnlySignalPaths, isEmpty);
      expect(empty.glitchSignals, isEmpty);
      expect(empty.detectedClocks, isEmpty);
      expect(empty.stuckAtResetPaths, isEmpty);
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    test('copyWith with no args returns equal object', () {
      expect(_baseReport.copyWith(), equals(_baseReport));
    });

    test('copyWith changes only constantSignalPaths', () {
      final updated = _baseReport.copyWith(constantSignalPaths: ['top.vdd']);
      expect(updated.constantSignalPaths, ['top.vdd']);
      expect(updated.xzOnlySignalPaths, _baseReport.xzOnlySignalPaths);
      expect(updated.signalsAnalyzed, _baseReport.signalsAnalyzed);
    });

    test('copyWith changes only glitchSignals', () {
      final updated = _baseReport.copyWith(
        glitchSignals: {'top.data': 5, 'top.bus': 2},
      );
      expect(updated.glitchSignals, {'top.data': 5, 'top.bus': 2});
      expect(updated.detectedClocks, _baseReport.detectedClocks);
    });

    test('copyWith changes only detectedClocks', () {
      final newClock = _clock.copyWith(signalPath: 'top.clk2');
      final updated = _baseReport.copyWith(detectedClocks: [newClock]);
      expect(updated.detectedClocks.length, 1);
      expect(updated.detectedClocks.first.signalPath, 'top.clk2');
      expect(updated.constantSignalPaths, _baseReport.constantSignalPaths);
    });

    // ── equality ──────────────────────────────────────────────────────────────

    test('equal reports compare as equal', () {
      final a = _baseReport.copyWith();
      final b = _baseReport.copyWith();
      expect(a, equals(b));
    });

    test('differing constantSignalPaths makes reports unequal', () {
      final a = _baseReport.copyWith(constantSignalPaths: ['top.vdd']);
      final b = _baseReport.copyWith(
        constantSignalPaths: ['top.vdd', 'top.gnd', 'top.extra'],
      );
      expect(a, isNot(equals(b)));
    });

    test('differing glitchSignals makes reports unequal', () {
      final a = _baseReport.copyWith(glitchSignals: {'top.data': 3});
      final b = _baseReport.copyWith(glitchSignals: {'top.data': 4});
      expect(a, isNot(equals(b)));
    });

    test('differing detectedClocks makes reports unequal', () {
      final a = _baseReport.copyWith(detectedClocks: []);
      final b = _baseReport.copyWith(detectedClocks: [_clock]);
      expect(a, isNot(equals(b)));
    });

    test('differing signalsAnalyzed makes reports unequal', () {
      final a = _baseReport.copyWith(signalsAnalyzed: 100);
      final b = _baseReport.copyWith(signalsAnalyzed: 200);
      expect(a, isNot(equals(b)));
    });

    // ── hashCode ──────────────────────────────────────────────────────────────

    test('equal objects have equal hashCodes', () {
      final a = _baseReport.copyWith();
      final b = _baseReport.copyWith();
      expect(a.hashCode, equals(b.hashCode));
    });

    // ── toString ──────────────────────────────────────────────────────────────

    test('toString contains list counts', () {
      final s = _baseReport.toString();
      expect(s, contains('2')); // constantSignalPaths.length
      expect(
        s,
        contains('1'),
      ); // xzOnlySignalPaths.length, detectedClocks.length
    });

    test('toString contains signalsAnalyzed', () {
      expect(_baseReport.toString(), contains('3200'));
    });
  });
}
