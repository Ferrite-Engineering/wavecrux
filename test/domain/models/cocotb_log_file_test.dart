// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/models/cocotb_log_entry.dart';
import 'package:wavecrux/domain/models/cocotb_log_file.dart';

void main() {
  group('CocotbLogFile', () {
    const e1 = CocotbLogEntry(
      simTimeTicks: 100,
      severity: CocotbLogSeverity.info,
      loggerName: 'cocotb.test',
      message: 'm1',
      lineNumber: 1,
    );
    const e2 = CocotbLogEntry(
      simTimeTicks: 200,
      severity: CocotbLogSeverity.warning,
      loggerName: 'cocotb.test',
      message: 'm2',
      lineNumber: 2,
    );

    const base = CocotbLogFile(
      filePath: '/tmp/log.txt',
      entries: [e1, e2],
      testNames: ['test_a', 'test_b'],
      severityCounts: {
        CocotbLogSeverity.info: 1,
        CocotbLogSeverity.warning: 1,
      },
      testResults: {'test_a': true, 'test_b': false},
      totalTests: 2,
      passedTests: 1,
      failedTests: 1,
      timeRangeTicks: (100, 200),
    );

    // ── construction ─────────────────────────────────────────────────────────

    test('stores all fields', () {
      expect(base.filePath, '/tmp/log.txt');
      expect(base.entries, hasLength(2));
      expect(base.testNames, ['test_a', 'test_b']);
      expect(base.severityCounts[CocotbLogSeverity.info], 1);
      expect(base.testResults['test_a'], isTrue);
      expect(base.totalTests, 2);
      expect(base.timeRangeTicks, const (100, 200));
    });

    test('summary fields can be null when not extracted', () {
      const f = CocotbLogFile(
        filePath: '/tmp/x.txt',
        entries: [],
        testNames: [],
        severityCounts: {},
        testResults: {},
      );
      expect(f.totalTests, isNull);
      expect(f.passedTests, isNull);
      expect(f.failedTests, isNull);
      expect(f.timeRangeTicks, isNull);
    });

    // ── copyWith ─────────────────────────────────────────────────────────────

    test('copyWith with no args returns equal object', () {
      expect(base.copyWith(), equals(base));
    });

    test('copyWith replaces individual fields', () {
      final f = base.copyWith(filePath: '/other.txt', totalTests: 99);
      expect(f.filePath, '/other.txt');
      expect(f.totalTests, 99);
      expect(f.entries, base.entries);
    });

    test('copyWith can clear nullable summary fields', () {
      final f = base.copyWith(
        totalTests: null,
        passedTests: null,
        failedTests: null,
        timeRangeTicks: null,
      );
      expect(f.totalTests, isNull);
      expect(f.passedTests, isNull);
      expect(f.failedTests, isNull);
      expect(f.timeRangeTicks, isNull);
    });

    // ── equality ─────────────────────────────────────────────────────────────

    test('equal when all fields match', () {
      const clone = CocotbLogFile(
        filePath: '/tmp/log.txt',
        entries: [e1, e2],
        testNames: ['test_a', 'test_b'],
        severityCounts: {
          CocotbLogSeverity.info: 1,
          CocotbLogSeverity.warning: 1,
        },
        testResults: {'test_a': true, 'test_b': false},
        totalTests: 2,
        passedTests: 1,
        failedTests: 1,
        timeRangeTicks: (100, 200),
      );
      expect(base, equals(clone));
      expect(base.hashCode, clone.hashCode);
    });

    test('not equal when filePath differs', () {
      expect(base, isNot(equals(base.copyWith(filePath: '/other.txt'))));
    });

    test('not equal when entries differ in length', () {
      expect(
        base,
        isNot(equals(base.copyWith(entries: const [e1]))),
      );
    });

    test('not equal when entries differ in content', () {
      const e3 = CocotbLogEntry(
        simTimeTicks: 300,
        severity: CocotbLogSeverity.error,
        loggerName: 'cocotb.x',
        message: 'm3',
        lineNumber: 3,
      );
      expect(
        base,
        isNot(equals(base.copyWith(entries: const [e1, e3]))),
      );
    });

    test('not equal when severityCounts differ', () {
      expect(
        base,
        isNot(
          equals(
            base.copyWith(
              severityCounts: const {CocotbLogSeverity.info: 1},
            ),
          ),
        ),
      );
    });

    test('not equal when testNames order differs', () {
      expect(
        base,
        isNot(equals(base.copyWith(testNames: const ['test_b', 'test_a']))),
      );
    });

    test('not equal when testResults differ', () {
      expect(
        base,
        isNot(
          equals(
            base.copyWith(testResults: const {'test_a': false, 'test_b': true}),
          ),
        ),
      );
    });

    test('not equal when timeRangeTicks differ', () {
      expect(
        base,
        isNot(equals(base.copyWith(timeRangeTicks: const (50, 250)))),
      );
    });

    test('two empty files at the same path are equal', () {
      const a = CocotbLogFile(
        filePath: '/p.txt',
        entries: [],
        testNames: [],
        severityCounts: {},
        testResults: {},
      );
      const b = CocotbLogFile(
        filePath: '/p.txt',
        entries: [],
        testNames: [],
        severityCounts: {},
        testResults: {},
      );
      expect(a, equals(b));
    });

    // ── toString ─────────────────────────────────────────────────────────────

    test('toString includes path and counts', () {
      final s = base.toString();
      expect(s, contains('/tmp/log.txt'));
      expect(s, contains('entries: 2'));
      expect(s, contains('tests: 2'));
    });
  });
}
