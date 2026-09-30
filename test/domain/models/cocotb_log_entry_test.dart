// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/models/cocotb_log_entry.dart';

void main() {
  group('CocotbLogEntry', () {
    const baseEntry = CocotbLogEntry(
      simTimeTicks: 100,
      simTimeString: '100.00ns',
      severity: CocotbLogSeverity.info,
      loggerName: 'cocotb.test_basic',
      message: 'Applied reset',
      lineNumber: 3,
      testName: 'test_basic',
    );

    // ── construction ─────────────────────────────────────────────────────────

    test('stores all fields', () {
      expect(baseEntry.simTimeTicks, 100);
      expect(baseEntry.simTimeString, '100.00ns');
      expect(baseEntry.severity, CocotbLogSeverity.info);
      expect(baseEntry.loggerName, 'cocotb.test_basic');
      expect(baseEntry.message, 'Applied reset');
      expect(baseEntry.lineNumber, 3);
      expect(baseEntry.testName, 'test_basic');
      expect(baseEntry.isTestStart, isFalse);
      expect(baseEntry.isTestResult, isFalse);
      expect(baseEntry.testPassed, isNull);
    });

    test('isTestStart and isTestResult default to false', () {
      const e = CocotbLogEntry(
        severity: CocotbLogSeverity.info,
        loggerName: 'cocotb.regression',
        message: 'Some message',
        lineNumber: 1,
      );
      expect(e.isTestStart, isFalse);
      expect(e.isTestResult, isFalse);
    });

    test('test boundary fields can be set explicitly', () {
      const e = CocotbLogEntry(
        severity: CocotbLogSeverity.info,
        loggerName: 'cocotb.regression',
        message: 'running test_basic (1/3)',
        lineNumber: 1,
        testName: 'test_basic',
        isTestStart: true,
      );
      expect(e.isTestStart, isTrue);
      expect(e.testName, 'test_basic');
    });

    test('testPassed flag is preserved when isTestResult is true', () {
      const e = CocotbLogEntry(
        severity: CocotbLogSeverity.info,
        loggerName: 'cocotb.regression',
        message: 'test_basic passed',
        lineNumber: 7,
        testName: 'test_basic',
        isTestResult: true,
        testPassed: true,
      );
      expect(e.isTestResult, isTrue);
      expect(e.testPassed, isTrue);
    });

    // ── copyWith ─────────────────────────────────────────────────────────────

    test('copyWith with no args returns equal object', () {
      expect(baseEntry.copyWith(), equals(baseEntry));
    });

    test('copyWith replaces individual fields', () {
      final e = baseEntry.copyWith(
        message: 'New message',
        severity: CocotbLogSeverity.error,
        lineNumber: 99,
      );
      expect(e.message, 'New message');
      expect(e.severity, CocotbLogSeverity.error);
      expect(e.lineNumber, 99);
      expect(e.simTimeTicks, baseEntry.simTimeTicks);
      expect(e.loggerName, baseEntry.loggerName);
    });

    test('copyWith can clear simTimeTicks to null', () {
      final e = baseEntry.copyWith(simTimeTicks: null);
      expect(e.simTimeTicks, isNull);
      expect(e.simTimeString, baseEntry.simTimeString);
    });

    test('copyWith can clear simTimeString to null', () {
      final e = baseEntry.copyWith(simTimeString: null);
      expect(e.simTimeString, isNull);
      expect(e.simTimeTicks, baseEntry.simTimeTicks);
    });

    test('copyWith can clear testName to null', () {
      final e = baseEntry.copyWith(testName: null);
      expect(e.testName, isNull);
    });

    test('copyWith can clear testPassed to null', () {
      const e = CocotbLogEntry(
        severity: CocotbLogSeverity.info,
        loggerName: 'cocotb.regression',
        message: 'test_basic passed',
        lineNumber: 1,
        isTestResult: true,
        testPassed: true,
      );
      final cleared = e.copyWith(testPassed: null);
      expect(cleared.testPassed, isNull);
      expect(cleared.isTestResult, isTrue);
    });

    test('copyWith preserves bool flag values when not specified', () {
      const e = CocotbLogEntry(
        severity: CocotbLogSeverity.info,
        loggerName: 'cocotb.regression',
        message: 'm',
        lineNumber: 1,
        isTestStart: true,
      );
      final c = e.copyWith(message: 'updated');
      expect(c.isTestStart, isTrue);
    });

    // ── equality ─────────────────────────────────────────────────────────────

    test('equal when all fields match', () {
      const a = CocotbLogEntry(
        simTimeTicks: 100,
        simTimeString: '100ns',
        severity: CocotbLogSeverity.info,
        loggerName: 'cocotb.test',
        message: 'x',
        lineNumber: 1,
      );
      const b = CocotbLogEntry(
        simTimeTicks: 100,
        simTimeString: '100ns',
        severity: CocotbLogSeverity.info,
        loggerName: 'cocotb.test',
        message: 'x',
        lineNumber: 1,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when simTimeTicks differs', () {
      final b = baseEntry.copyWith(simTimeTicks: 200);
      expect(baseEntry, isNot(equals(b)));
    });

    test('not equal when severity differs', () {
      final b = baseEntry.copyWith(severity: CocotbLogSeverity.error);
      expect(baseEntry, isNot(equals(b)));
    });

    test('not equal when message differs', () {
      final b = baseEntry.copyWith(message: 'different');
      expect(baseEntry, isNot(equals(b)));
    });

    test('not equal when lineNumber differs', () {
      final b = baseEntry.copyWith(lineNumber: 99);
      expect(baseEntry, isNot(equals(b)));
    });

    test('not equal when isTestStart differs', () {
      final b = baseEntry.copyWith(isTestStart: true);
      expect(baseEntry, isNot(equals(b)));
    });

    // ── toString ─────────────────────────────────────────────────────────────

    test('toString contains key fields', () {
      final s = baseEntry.toString();
      expect(s, contains('100.00ns'));
      expect(s, contains('INFO'));
      expect(s, contains('cocotb.test_basic'));
      expect(s, contains('Applied reset'));
      expect(s, contains('test_basic'));
    });

    test('toString handles missing timestamp', () {
      const e = CocotbLogEntry(
        severity: CocotbLogSeverity.info,
        loggerName: 'cocotb.test',
        message: 'm',
        lineNumber: 1,
      );
      expect(e.toString(), contains('—'));
    });
  });
}
