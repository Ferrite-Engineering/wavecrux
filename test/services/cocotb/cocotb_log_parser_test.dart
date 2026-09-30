// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/services/cocotb/cocotb_log_parser.dart';

void main() {
  const parser = CocotbLogParser();
  const ns = Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);
  const ps = Timescale(factor: 1, unit: TimescaleUnit.picoSeconds);
  const tenNs = Timescale(factor: 10, unit: TimescaleUnit.nanoSeconds);

  group('CocotbLogParser — basic parsing', () {
    test('parses a simple INFO line', () {
      const log =
          '   100.00ns INFO     cocotb.test_basic                  Applied reset';
      final result = parser.parse(log, '/tmp/log.txt', timescale: ns);
      expect(result.entries, hasLength(1));
      final e = result.entries.single;
      expect(e.simTimeTicks, 100);
      expect(e.simTimeString, '100.00ns');
      expect(e.severity, CocotbLogSeverity.info);
      expect(e.loggerName, 'cocotb.test_basic');
      expect(e.message, 'Applied reset');
      expect(e.lineNumber, 1);
    });

    test('parses mixed severity levels', () {
      const log = '''
   0.00ns DEBUG    cocotb.test                  debug msg
  10.00ns INFO     cocotb.test                  info msg
  20.00ns WARNING  cocotb.test                  warn msg
  30.00ns ERROR    cocotb.test                  error msg
  40.00ns CRITICAL cocotb.test                  critical msg
''';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries, hasLength(5));
      expect(result.entries[0].severity, CocotbLogSeverity.debug);
      expect(result.entries[1].severity, CocotbLogSeverity.info);
      expect(result.entries[2].severity, CocotbLogSeverity.warning);
      expect(result.entries[3].severity, CocotbLogSeverity.error);
      expect(result.entries[4].severity, CocotbLogSeverity.critical);
      expect(result.severityCounts, {
        CocotbLogSeverity.debug: 1,
        CocotbLogSeverity.info: 1,
        CocotbLogSeverity.warning: 1,
        CocotbLogSeverity.error: 1,
        CocotbLogSeverity.critical: 1,
      });
    });

    test('preserves filePath on the result', () {
      final result = parser.parse('', '/some/path.txt');
      expect(result.filePath, '/some/path.txt');
    });

    test('handles empty input', () {
      final result = parser.parse('', '/log.txt');
      expect(result.entries, isEmpty);
      expect(result.testNames, isEmpty);
      expect(result.severityCounts, isEmpty);
      expect(result.testResults, isEmpty);
      expect(result.totalTests, isNull);
      expect(result.timeRangeTicks, isNull);
    });

    test('skips blank lines', () {
      const log = '''


   10.00ns INFO     cocotb.t                  m1

   20.00ns INFO     cocotb.t                  m2

''';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries, hasLength(2));
      expect(result.entries[0].lineNumber, 3);
      expect(result.entries[1].lineNumber, 5);
    });

    test('handles CRLF line endings', () {
      const log =
          '   10.00ns INFO     cocotb.t                  m1\r\n'
          '   20.00ns INFO     cocotb.t                  m2\r\n';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries, hasLength(2));
      expect(result.entries[0].message, 'm1');
      expect(result.entries[1].message, 'm2');
    });

    test('lineNumber is 1-based and matches source line', () {
      const log = '\n\n   10.00ns INFO     cocotb.t                  hello';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries.single.lineNumber, 3);
    });
  });

  group('CocotbLogParser — timestamp parsing', () {
    test('parses ns timestamps with 1 ns timescale → identity', () {
      const log = '   100.00ns INFO     cocotb.t                  hello';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries.single.simTimeTicks, 100);
    });

    test('parses us timestamps', () {
      const log = '     1.50us INFO     cocotb.t                  hello';
      final result = parser.parse(log, '/log', timescale: ns);
      // 1.5us = 1500ns = 1500 ticks at 1ns/tick
      expect(result.entries.single.simTimeTicks, 1500);
    });

    test('parses ms timestamps', () {
      const log = '     2.00ms INFO     cocotb.t                  hello';
      final result = parser.parse(log, '/log', timescale: ns);
      // 2ms = 2,000,000ns
      expect(result.entries.single.simTimeTicks, 2000000);
    });

    test('parses ps timestamps', () {
      const log = '   500.00ps INFO     cocotb.t                  hello';
      final result = parser.parse(log, '/log', timescale: ns);
      // 500ps = 0.5ns ≈ 1 (rounded)
      expect(result.entries.single.simTimeTicks, anyOf(0, 1));
    });

    test('parses fs timestamps', () {
      const log = ' 1000000.00fs INFO     cocotb.t                  hello';
      final result = parser.parse(log, '/log', timescale: ns);
      // 1,000,000 fs = 1 ns = 1 tick
      expect(result.entries.single.simTimeTicks, 1);
    });

    test('parses second-unit timestamps', () {
      const log = '     1.00s INFO     cocotb.t                  hello';
      final result = parser.parse(log, '/log', timescale: ns);
      // 1s = 1,000,000,000 ns
      expect(result.entries.single.simTimeTicks, 1000000000);
    });

    test('parses µs (Unicode mu) timestamps', () {
      const log = '     2.00µs INFO     cocotb.t                  hello';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries.single.simTimeTicks, 2000);
    });

    test('parses integer timestamps with no unit', () {
      const log = '       500 INFO     cocotb.t                  hello';
      final result = parser.parse(log, '/log', timescale: ns);
      // No unit → already in tick units
      expect(result.entries.single.simTimeTicks, 500);
      expect(result.entries.single.simTimeString, '500');
    });

    test('1 ps timescale: 1ns timestamp = 1000 ticks', () {
      const log = '   1.00ns INFO     cocotb.t                  hello';
      final result = parser.parse(log, '/log', timescale: ps);
      expect(result.entries.single.simTimeTicks, 1000);
    });

    test('10 ns timescale: 100ns timestamp = 10 ticks', () {
      const log = '   100.00ns INFO     cocotb.t                  hello';
      final result = parser.parse(log, '/log', timescale: tenNs);
      expect(result.entries.single.simTimeTicks, 10);
    });

    test('null timescale defaults to 1 ns/tick', () {
      const log = '   42.00ns INFO     cocotb.t                  hello';
      final result = parser.parse(log, '/log');
      expect(result.entries.single.simTimeTicks, 42);
    });

    test('unknown timescale unit also defaults to 1 ns/tick', () {
      const unk = Timescale(factor: 1, unit: TimescaleUnit.unknown);
      const log = '   42.00ns INFO     cocotb.t                  hello';
      final result = parser.parse(log, '/log', timescale: unk);
      expect(result.entries.single.simTimeTicks, 42);
    });

    test('very large timestamps survive rounding', () {
      const log = ' 999999999.00ns INFO     cocotb.t                  hello';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries.single.simTimeTicks, 999999999);
    });

    test('zero timestamp parses to 0 ticks', () {
      const log = '     0.00ns INFO     cocotb.t                  hello';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries.single.simTimeTicks, 0);
    });
  });

  group('CocotbLogParser — test boundaries', () {
    test('detects test start lines', () {
      const log =
          '     0.00ns INFO     cocotb.regression                  '
          'running test_basic (1/3)';
      final result = parser.parse(log, '/log', timescale: ns);
      final e = result.entries.single;
      expect(e.isTestStart, isTrue);
      expect(e.testName, 'test_basic');
      expect(result.testNames, ['test_basic']);
    });

    test('detects test pass lines', () {
      const log = '''
     0.00ns INFO     cocotb.regression                  running test_basic (1/1)
  1000.00ns INFO     cocotb.regression                  test_basic passed
''';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries[1].isTestResult, isTrue);
      expect(result.entries[1].testPassed, isTrue);
      expect(result.testResults, {'test_basic': true});
    });

    test('detects test fail lines', () {
      const log = '''
     0.00ns INFO     cocotb.regression                  running test_x (1/1)
  1000.00ns INFO     cocotb.regression                  test_x failed
''';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries[1].isTestResult, isTrue);
      expect(result.entries[1].testPassed, isFalse);
      expect(result.testResults, {'test_x': false});
    });

    test('test name propagates to entries within the test', () {
      const log = '''
     0.00ns INFO     cocotb.regression                  running test_a (1/1)
   100.00ns INFO     cocotb.test_a                      hello
   200.00ns DEBUG    cocotb.test_a                      world
  1000.00ns INFO     cocotb.regression                  test_a passed
''';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries[0].testName, 'test_a');
      expect(result.entries[1].testName, 'test_a');
      expect(result.entries[2].testName, 'test_a');
      expect(result.entries[3].testName, 'test_a');
    });

    test('entries before any test start have null testName', () {
      const log = '''
     0.00ns INFO     cocotb                             pre-test banner
     0.00ns INFO     cocotb.regression                  running test_a (1/1)
''';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries[0].testName, isNull);
      expect(result.entries[1].testName, 'test_a');
    });

    test('entries after a result line have null testName', () {
      const log = '''
     0.00ns INFO     cocotb.regression                  running test_a (1/1)
  1000.00ns INFO     cocotb.regression                  test_a passed
  2000.00ns INFO     cocotb                             outside-test message
''';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries[2].testName, isNull);
    });
  });

  group('CocotbLogParser — summary line', () {
    test('extracts total/passed/failed counts', () {
      const log = '''
  3000.00ns INFO     cocotb.regression                  3 tests run: 2 passed, 1 failed
''';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.totalTests, 3);
      expect(result.passedTests, 2);
      expect(result.failedTests, 1);
    });

    test('absent summary leaves counts null', () {
      const log =
          '     0.00ns INFO     cocotb.regression                  '
          'running test_a (1/1)';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.totalTests, isNull);
      expect(result.passedTests, isNull);
      expect(result.failedTests, isNull);
    });

    test('summary singular form is also accepted', () {
      const log =
          '  3000.00ns INFO     cocotb.regression                  '
          '1 test run: 1 passed, 0 failed';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.totalTests, 1);
      expect(result.passedTests, 1);
      expect(result.failedTests, 0);
    });
  });

  group('CocotbLogParser — continuation and malformed lines', () {
    test('lines without timestamp inherit severity/logger from previous', () {
      const log = '''
     0.00ns INFO     cocotb.regression                  running test_a (1/1)
   100.00ns ERROR    cocotb.test_a                      Traceback (most recent call last):
  File "/path/to/test.py", line 42, in test_a
    assert False
AssertionError: assertion failed
  1000.00ns INFO     cocotb.regression                  test_a failed
''';
      final result = parser.parse(log, '/log', timescale: ns);
      // 4 structured + 3 continuation = entries 0..6
      expect(result.entries.length, greaterThanOrEqualTo(4));
      // The traceback continuation lines (3 lines after the ERROR) have no
      // timestamp but inherit the ERROR severity and cocotb.test_a logger.
      final tb = result.entries
          .where((e) => e.simTimeTicks == null && e.message.contains('File'))
          .toList();
      expect(tb, isNotEmpty);
      expect(tb.first.severity, CocotbLogSeverity.error);
      expect(tb.first.loggerName, 'cocotb.test_a');
      expect(tb.first.testName, 'test_a');
    });

    test('lines before any structured entry are skipped', () {
      const log = '''
banner without any logging structure
another raw line
   100.00ns INFO     cocotb.t                           first real entry
''';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries, hasLength(1));
      expect(result.entries.single.message, 'first real entry');
    });

    test('lines without a timestamp but with severity/logger parse', () {
      const log =
          'INFO     cocotb.test                        no timestamp message';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries, hasLength(1));
      final e = result.entries.single;
      expect(e.simTimeTicks, isNull);
      expect(e.simTimeString, isNull);
      expect(e.severity, CocotbLogSeverity.info);
      expect(e.loggerName, 'cocotb.test');
      expect(e.message, 'no timestamp message');
    });

    test('log with only non-timestamped lines', () {
      const log = '''
INFO     cocotb.t                  m1
WARN     cocotb.t                  m2
ERROR    cocotb.t                  m3
''';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries, hasLength(3));
      expect(result.entries.every((e) => e.simTimeTicks == null), isTrue);
      expect(result.timeRangeTicks, isNull);
    });

    test('Unicode characters in messages are preserved', () {
      const log =
          '    10.00ns INFO     cocotb.test_unicode                '
          'Hello 世界 — résumé café ✓';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.entries.single.message, 'Hello 世界 — résumé café ✓');
    });

    test('logger names with dots and underscores are extracted whole', () {
      const log =
          '   10.00ns INFO     cocotb.test.deeply.nested_thing_42     hello';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(
        result.entries.single.loggerName,
        'cocotb.test.deeply.nested_thing_42',
      );
    });
  });

  group('CocotbLogParser — derived summaries', () {
    test('testNames preserves order of first appearance and dedupes', () {
      const log = '''
     0.00ns INFO     cocotb.regression                  running test_a (1/3)
  1000.00ns INFO     cocotb.regression                  test_a passed
  1000.00ns INFO     cocotb.regression                  running test_b (2/3)
  2000.00ns INFO     cocotb.regression                  test_b failed
  2000.00ns INFO     cocotb.regression                  running test_c (3/3)
  3000.00ns INFO     cocotb.regression                  test_c passed
''';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.testNames, ['test_a', 'test_b', 'test_c']);
    });

    test('severityCounts are accurate', () {
      const log = '''
   10.00ns INFO     cocotb.t                  m1
   20.00ns INFO     cocotb.t                  m2
   30.00ns WARNING  cocotb.t                  m3
   40.00ns ERROR    cocotb.t                  m4
   50.00ns ERROR    cocotb.t                  m5
   60.00ns CRITICAL cocotb.t                  m6
''';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.severityCounts[CocotbLogSeverity.info], 2);
      expect(result.severityCounts[CocotbLogSeverity.warning], 1);
      expect(result.severityCounts[CocotbLogSeverity.error], 2);
      expect(result.severityCounts[CocotbLogSeverity.critical], 1);
      expect(result.severityCounts[CocotbLogSeverity.debug], isNull);
    });

    test('testResults maps each test to pass/fail', () {
      const log = '''
     0.00ns INFO     cocotb.regression                  running test_a (1/2)
  1000.00ns INFO     cocotb.regression                  test_a passed
  1000.00ns INFO     cocotb.regression                  running test_b (2/2)
  2000.00ns INFO     cocotb.regression                  test_b failed
''';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.testResults, {'test_a': true, 'test_b': false});
    });

    test('timeRangeTicks spans earliest to latest timestamped entry', () {
      const log = '''
   100.00ns INFO     cocotb.t                  m1
INFO     cocotb.t                              continuation no timestamp
   500.00ns INFO     cocotb.t                  m2
    50.00ns INFO     cocotb.t                  m3 (out of order)
''';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.timeRangeTicks, (50, 500));
    });

    test('timeRangeTicks is null when no timestamps are present', () {
      const log =
          'INFO     cocotb.t                              no timestamp here';
      final result = parser.parse(log, '/log', timescale: ns);
      expect(result.timeRangeTicks, isNull);
    });
  });

  group('CocotbLogParser — basic_log.txt fixture', () {
    test('parses the bundled basic_log.txt', () {
      final content = File(
        'test/fixtures/cocotb/basic_log.txt',
      ).readAsStringSync();
      final result = parser.parse(content, 'basic_log.txt', timescale: ns);

      expect(result.entries.length, 14);
      expect(result.testNames, ['test_basic', 'test_fifo', 'test_edge_cases']);
      expect(result.testResults, {
        'test_basic': true,
        'test_fifo': false,
        'test_edge_cases': true,
      });
      expect(result.totalTests, 3);
      expect(result.passedTests, 2);
      expect(result.failedTests, 1);
      expect(result.timeRangeTicks, (0, 3000));
      expect(result.severityCounts[CocotbLogSeverity.info], greaterThan(0));
      expect(result.severityCounts[CocotbLogSeverity.error], 1);
      expect(result.severityCounts[CocotbLogSeverity.critical], 1);

      final readData = result.entries.firstWhere(
        (e) => e.message.contains('Read data'),
      );
      expect(readData.severity, CocotbLogSeverity.debug);
      expect(readData.testName, 'test_basic');
    });
  });

  group('CocotbLogParser — edge_cases_log.txt fixture', () {
    test('parses the edge cases fixture without throwing', () {
      final content = File(
        'test/fixtures/cocotb/edge_cases_log.txt',
      ).readAsStringSync();
      final result = parser.parse(content, 'edge_cases_log.txt', timescale: ns);

      expect(result.entries, isNotEmpty);
      expect(result.testNames, contains('test_unicode'));
      expect(result.testNames, contains('test_no_timestamp'));
      expect(result.testResults['test_unicode'], isFalse);
      expect(result.testResults['test_no_timestamp'], isTrue);
      expect(result.totalTests, 2);
      expect(result.passedTests, 1);
      expect(result.failedTests, 1);

      // Unicode entry preserved verbatim.
      final unicodeEntry = result.entries.firstWhere(
        (e) => e.message.contains('世界'),
      );
      expect(unicodeEntry.message, contains('résumé'));

      // Microsecond timestamp converts correctly: 1500us = 1,500,000 ns ticks.
      final usEntry = result.entries.firstWhere(
        (e) => e.message.contains('Microsecond'),
      );
      expect(usEntry.simTimeTicks, 1500000);

      // Millisecond timestamp converts correctly: 2ms = 2,000,000 ns ticks.
      final msEntry = result.entries.firstWhere(
        (e) => e.message.contains('Millisecond'),
      );
      expect(msEntry.simTimeTicks, 2000000);

      // Integer-only timestamp parses without a unit.
      final intEntry = result.entries.firstWhere(
        (e) => e.message.contains('Integer-only tick'),
      );
      expect(intEntry.simTimeTicks, 500);
      expect(intEntry.simTimeString, '500');

      // WARN alias is mapped to warning.
      final warnEntry = result.entries.firstWhere(
        (e) => e.message.contains('Old-style WARN'),
      );
      expect(warnEntry.severity, CocotbLogSeverity.warning);
    });
  });
}
