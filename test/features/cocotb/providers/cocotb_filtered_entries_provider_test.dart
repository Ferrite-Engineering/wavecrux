// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/models/cocotb_log_entry.dart';
import 'package:wavecrux/domain/models/cocotb_log_file.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_filter_provider.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_filtered_entries_provider.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';

CocotbLogEntry _e({
  required int line,
  required CocotbLogSeverity severity,
  required String message,
  String? testName,
  int? ticks,
}) => CocotbLogEntry(
  severity: severity,
  loggerName: 'cocotb.test',
  message: message,
  lineNumber: line,
  simTimeTicks: ticks,
  testName: testName,
);

CocotbLogFile _file(List<CocotbLogEntry> entries, {List<String>? testNames}) {
  return CocotbLogFile(
    filePath: '/tmp/run.log',
    entries: List.unmodifiable(entries),
    testNames: List.unmodifiable(testNames ?? const <String>[]),
    severityCounts: const {},
    testResults: const {},
  );
}

ProviderContainer _container(CocotbLogFile file) {
  final container = ProviderContainer(
    overrides: [
      cocotbLogProvider.overrideWith(_FixedLog.new),
    ],
  );
  // Initialise the override with the desired file.
  container.read(cocotbLogProvider.notifier).state = file;
  addTearDown(container.dispose);
  return container;
}

class _FixedLog extends CocotbLog {
  @override
  CocotbLogFile? build() => null;
}

void main() {
  group('cocotbFilteredEntries', () {
    test('returns empty list when no log loaded', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(cocotbFilteredEntriesProvider), isEmpty);
    });

    test('returns all entries when no filter is active', () {
      final container = _container(
        _file([
          _e(line: 1, severity: CocotbLogSeverity.info, message: 'a'),
          _e(line: 2, severity: CocotbLogSeverity.error, message: 'b'),
        ]),
      );
      expect(container.read(cocotbFilteredEntriesProvider), hasLength(2));
    });

    test('keyword filter applies case-insensitively', () {
      final container = _container(
        _file([
          _e(line: 1, severity: CocotbLogSeverity.info, message: 'Reset done'),
          _e(line: 2, severity: CocotbLogSeverity.info, message: 'Tick 5'),
        ]),
      );
      container.read(cocotbFilterProvider.notifier).setKeyword('RESET');
      final results = container.read(cocotbFilteredEntriesProvider);
      expect(results, hasLength(1));
      expect(results.first.message, 'Reset done');
    });

    test('severity filter restricts to selected levels', () {
      final container = _container(
        _file([
          _e(line: 1, severity: CocotbLogSeverity.info, message: 'a'),
          _e(line: 2, severity: CocotbLogSeverity.error, message: 'b'),
          _e(line: 3, severity: CocotbLogSeverity.warning, message: 'c'),
        ]),
      );
      container
          .read(cocotbFilterProvider.notifier)
          .toggleSeverity(CocotbLogSeverity.error);
      final results = container.read(cocotbFilteredEntriesProvider);
      expect(results, hasLength(1));
      expect(results.first.severity, CocotbLogSeverity.error);
    });

    test('testName filter matches exactly', () {
      final container = _container(
        _file([
          _e(
            line: 1,
            severity: CocotbLogSeverity.info,
            message: 'a',
            testName: 'test_x',
          ),
          _e(
            line: 2,
            severity: CocotbLogSeverity.info,
            message: 'b',
            testName: 'test_y',
          ),
        ]),
      );
      container.read(cocotbFilterProvider.notifier).setTestName('test_y');
      final results = container.read(cocotbFilteredEntriesProvider);
      expect(results, hasLength(1));
      expect(results.first.testName, 'test_y');
    });

    test('combined filters use AND semantics', () {
      final container = _container(
        _file([
          _e(
            line: 1,
            severity: CocotbLogSeverity.info,
            message: 'reset',
            testName: 'test_x',
          ),
          _e(
            line: 2,
            severity: CocotbLogSeverity.error,
            message: 'reset',
            testName: 'test_x',
          ),
          _e(
            line: 3,
            severity: CocotbLogSeverity.error,
            message: 'tick',
            testName: 'test_y',
          ),
        ]),
      );
      container.read(cocotbFilterProvider.notifier)
        ..setTestName('test_x')
        ..toggleSeverity(CocotbLogSeverity.error)
        ..setKeyword('reset');
      final results = container.read(cocotbFilteredEntriesProvider);
      expect(results, hasLength(1));
      expect(results.first.lineNumber, 2);
    });

    test('empty severity set means all severities pass', () {
      final container = _container(
        _file([
          _e(line: 1, severity: CocotbLogSeverity.info, message: 'a'),
          _e(line: 2, severity: CocotbLogSeverity.error, message: 'b'),
        ]),
      );
      // No severity toggled — both should pass.
      expect(container.read(cocotbFilteredEntriesProvider), hasLength(2));
    });
  });
}
