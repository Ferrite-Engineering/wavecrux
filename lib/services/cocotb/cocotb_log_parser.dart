// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:developer' as developer;
import 'dart:math' show pow;

import 'package:logging/logging.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/models/cocotb_log_entry.dart';
import 'package:wavecrux/domain/models/cocotb_log_file.dart';
import 'package:wavecrux/domain/models/timescale.dart';

/// A log line the parser matched and then dropped. The line patterns admit
/// only the severities [CocotbLogSeverity.fromString] knows, so this means the
/// two have drifted and lines are vanishing from the user's log view.
/// `developer.log` emits nothing from a release build.
final _log = Logger('wavecrux.cocotb');

/// Parses cocotb-formatted log files into a [CocotbLogFile].
///
/// Cocotb (a Python coroutine-based HDL testbench framework) emits structured
/// log lines through Python's `logging` module. The default formatter
/// produces lines of the form:
/// ```text
/// <sim_time> <severity> <logger_name> <message>
/// ```
/// for example:
/// ```text
///    100.00ns INFO     cocotb.test_basic                  Applied reset
/// ```
///
/// Timestamps may carry an SI unit suffix (`fs`, `ps`, `ns`, `us`, `µs`, `ms`,
/// `s`) or be plain integer tick counts. A [Timescale] supplied at parse
/// time is used to normalise unit-suffixed timestamps to the waveform's tick
/// unit; integer timestamps are treated as already-in-ticks. When no
/// timescale is supplied the parser defaults to `1 ns/tick`.
///
/// The parser is tolerant: malformed lines, blank lines, comments, and
/// Python tracebacks attached to a preceding log entry never raise — they
/// are skipped (with a `dart:developer` trace) or attached to the
/// preceding entry as continuation context.
///
/// Test-boundary detection scans messages emitted by `cocotb.regression`:
/// `running test_X (N/M)`, `test_X passed`, `test_X failed`, and the final
/// `N tests run: M passed, K failed` summary line.
class CocotbLogParser {
  const CocotbLogParser();

  // ── regular expressions ────────────────────────────────────────────────────

  /// Full line: `<timestamp> <severity> <logger> <message>`.
  ///
  /// The timestamp is a decimal number with an optional SI unit suffix that
  /// follows the digits without any whitespace (cocotb's default formatter
  /// produces `100.00ns` rather than `100.00 ns`).
  static final RegExp _fullLine = RegExp(
    r'^\s*'
    r'([0-9]+(?:\.[0-9]+)?)\s*(fs|ps|ns|us|µs|ms|s)?\s+'
    r'(DEBUG|INFO|WARNING|WARN|ERROR|CRITICAL|FATAL)\s+'
    r'(\S+)\s+'
    r'(.*)$',
    caseSensitive: false,
  );

  /// Severity-only line (no timestamp).
  static final RegExp _noTimestampLine = RegExp(
    r'^\s*'
    r'(DEBUG|INFO|WARNING|WARN|ERROR|CRITICAL|FATAL)\s+'
    r'(\S+)\s+'
    r'(.*)$',
    caseSensitive: false,
  );

  /// `running test_X (N/M)` from cocotb.regression.
  static final RegExp _testStart = RegExp(
    r'^running\s+(\S+)\s*\((\d+)\s*/\s*(\d+)\)',
    caseSensitive: false,
  );

  /// `test_X passed` or `test_X failed` from cocotb.regression.
  static final RegExp _testResult = RegExp(
    r'^(\S+)\s+(passed|failed)\s*$',
    caseSensitive: false,
  );

  /// `N tests run: M passed, K failed` summary line.
  static final RegExp _summary = RegExp(
    r'(\d+)\s+tests?\s+run:?\s*(\d+)\s+passed,?\s*(\d+)\s+failed',
    caseSensitive: false,
  );

  /// SI prefix → base-10 exponent relative to seconds. Must be checked in
  /// length-decreasing order so that `ms` is not matched as `s`.
  static const Map<String, int> _unitExponents = {
    'fs': -15,
    'ps': -12,
    'ns': -9,
    'us': -6,
    'µs': -6,
    'ms': -3,
    's': 0,
  };

  // ── parse ──────────────────────────────────────────────────────────────────

  /// Parses [content] (the entire log file as a single string) into a
  /// [CocotbLogFile]. [filePath] is recorded on the result for downstream UI.
  ///
  /// [timescale] is used to convert unit-bearing timestamps to ticks. When
  /// `null` (or [TimescaleUnit.unknown]), `1 ns/tick` is assumed — the
  /// cocotb default and the most common HDL timescale.
  CocotbLogFile parse(
    String content,
    String filePath, {
    Timescale? timescale,
  }) {
    final effectiveTimescale = _effectiveTimescale(timescale);

    final entries = <CocotbLogEntry>[];
    final testNames = <String>[];
    final seenTestNames = <String>{};
    final severityCounts = <CocotbLogSeverity, int>{};
    final testResults = <String, bool>{};
    int? totalTests;
    int? passedTests;
    int? failedTests;
    int? minTicks;
    int? maxTicks;

    String? currentTestName;
    CocotbLogEntry? lastEntry;

    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final lineNumber = i + 1;
      final rawLine = lines[i];
      // Strip trailing CR for files saved with CRLF line endings.
      final line = rawLine.endsWith('\r')
          ? rawLine.substring(0, rawLine.length - 1)
          : rawLine;

      if (line.trim().isEmpty) continue;

      // ── Stage 1: full timestamped line ──────────────────────────────────
      final fullMatch = _fullLine.firstMatch(line);
      if (fullMatch != null) {
        final tsValue = fullMatch.group(1)!;
        final tsUnit = fullMatch.group(2);
        final sevStr = fullMatch.group(3)!;
        final loggerName = fullMatch.group(4)!;
        final message = fullMatch.group(5)!.trimRight();

        final severity = CocotbLogSeverity.fromString(sevStr);
        if (severity == null) {
          _log.warning(
            'unrecognised severity "$sevStr" at line $lineNumber — skipping',
          );
          continue;
        }

        final timeStr = tsUnit == null ? tsValue : '$tsValue$tsUnit';
        final ticks = _parseTimestamp(timeStr, effectiveTimescale);

        final entry = _buildEntry(
          simTimeTicks: ticks,
          simTimeString: timeStr,
          severity: severity,
          loggerName: loggerName,
          message: message,
          lineNumber: lineNumber,
          currentTestName: currentTestName,
        );

        // Update test-tracking state.
        currentTestName = _afterEntry(
          entry: entry,
          currentTestName: currentTestName,
          testNames: testNames,
          seenTestNames: seenTestNames,
          testResults: testResults,
        );

        // Summary?
        final summary = _parseSummary(entry.message);
        if (summary != null &&
            entry.loggerName.toLowerCase().startsWith('cocotb.regression')) {
          totalTests = summary.$1;
          passedTests = summary.$2;
          failedTests = summary.$3;
        }

        entries.add(entry);
        lastEntry = entry;
        severityCounts.update(severity, (v) => v + 1, ifAbsent: () => 1);
        if (ticks != null) {
          minTicks = minTicks == null || ticks < minTicks ? ticks : minTicks;
          maxTicks = maxTicks == null || ticks > maxTicks ? ticks : maxTicks;
        }
        continue;
      }

      // ── Stage 2: severity-only line (no timestamp) ──────────────────────
      final noTsMatch = _noTimestampLine.firstMatch(line);
      if (noTsMatch != null) {
        final sevStr = noTsMatch.group(1)!;
        final loggerName = noTsMatch.group(2)!;
        final message = noTsMatch.group(3)!.trimRight();
        final severity = CocotbLogSeverity.fromString(sevStr);
        if (severity == null) {
          _log.warning(
            'unrecognised severity "$sevStr" at line $lineNumber — skipping',
          );
          continue;
        }

        final entry = _buildEntry(
          simTimeTicks: null,
          simTimeString: null,
          severity: severity,
          loggerName: loggerName,
          message: message,
          lineNumber: lineNumber,
          currentTestName: currentTestName,
        );

        currentTestName = _afterEntry(
          entry: entry,
          currentTestName: currentTestName,
          testNames: testNames,
          seenTestNames: seenTestNames,
          testResults: testResults,
        );

        final summary = _parseSummary(entry.message);
        if (summary != null &&
            entry.loggerName.toLowerCase().startsWith('cocotb.regression')) {
          totalTests = summary.$1;
          passedTests = summary.$2;
          failedTests = summary.$3;
        }

        entries.add(entry);
        lastEntry = entry;
        severityCounts.update(severity, (v) => v + 1, ifAbsent: () => 1);
        continue;
      }

      // ── Stage 3: continuation line ──────────────────────────────────────
      // Inherits severity, logger, and test from the previous entry. Lines
      // that arrive before any structured entry (banners, blank-ish prefixes)
      // are skipped to avoid creating entries with no useful metadata.
      if (lastEntry == null) {
        developer.log(
          'cocotb_log_parser: malformed line $lineNumber with no preceding '
          'entry — skipping: "$line"',
          name: 'cocotb_log_parser',
        );
        continue;
      }

      final entry = CocotbLogEntry(
        severity: lastEntry.severity,
        loggerName: lastEntry.loggerName,
        message: line.trimRight(),
        lineNumber: lineNumber,
        testName: currentTestName,
      );
      entries.add(entry);
      severityCounts.update(
        entry.severity,
        (v) => v + 1,
        ifAbsent: () => 1,
      );
      // Note: lastEntry stays at the last *structured* entry so that
      // multiple traceback lines all inherit the same metadata.
    }

    final timeRange = (minTicks != null && maxTicks != null)
        ? (minTicks, maxTicks)
        : null;

    return CocotbLogFile(
      filePath: filePath,
      entries: List.unmodifiable(entries),
      testNames: List.unmodifiable(testNames),
      severityCounts: Map.unmodifiable(severityCounts),
      testResults: Map.unmodifiable(testResults),
      totalTests: totalTests,
      passedTests: passedTests,
      failedTests: failedTests,
      timeRangeTicks: timeRange,
    );
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  Timescale _effectiveTimescale(Timescale? timescale) {
    if (timescale == null || timescale.unit == TimescaleUnit.unknown) {
      return const Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);
    }
    return timescale;
  }

  /// Builds an entry with test-boundary metadata pre-computed.
  CocotbLogEntry _buildEntry({
    required int? simTimeTicks,
    required String? simTimeString,
    required CocotbLogSeverity severity,
    required String loggerName,
    required String message,
    required int lineNumber,
    required String? currentTestName,
  }) {
    final isRegressionLogger = loggerName.toLowerCase().startsWith(
      'cocotb.regression',
    );

    var testName = currentTestName;
    var isTestStart = false;
    var isTestResult = false;
    bool? testPassed;

    if (isRegressionLogger) {
      final start = _parseTestStart(message);
      if (start != null) {
        testName = start.$1;
        isTestStart = true;
      } else {
        final result = _parseTestResult(loggerName, message);
        if (result != null) {
          testName = result.$1;
          isTestResult = true;
          testPassed = result.$2;
        }
      }
    }

    return CocotbLogEntry(
      simTimeTicks: simTimeTicks,
      simTimeString: simTimeString,
      severity: severity,
      loggerName: loggerName,
      message: message,
      lineNumber: lineNumber,
      testName: testName,
      isTestStart: isTestStart,
      isTestResult: isTestResult,
      testPassed: testPassed,
    );
  }

  /// Updates per-test bookkeeping after appending [entry] and returns the
  /// new "current test name" used for subsequent untagged entries.
  String? _afterEntry({
    required CocotbLogEntry entry,
    required String? currentTestName,
    required List<String> testNames,
    required Set<String> seenTestNames,
    required Map<String, bool> testResults,
  }) {
    if (entry.isTestStart && entry.testName != null) {
      final name = entry.testName!;
      if (seenTestNames.add(name)) testNames.add(name);
      return name;
    }
    if (entry.isTestResult && entry.testName != null) {
      final name = entry.testName!;
      if (seenTestNames.add(name)) testNames.add(name);
      if (entry.testPassed != null) testResults[name] = entry.testPassed!;
      return null;
    }
    return currentTestName;
  }

  /// Converts a timestamp string like `"100.00ns"` or `"100"` to simulation
  /// ticks. Returns `null` when [timeStr] cannot be parsed.
  int? _parseTimestamp(String timeStr, Timescale timescale) {
    final cleaned = timeStr.trim();
    if (cleaned.isEmpty) return null;

    int unitExponent;
    String numericPart;
    final unitEntry = _matchUnit(cleaned);
    if (unitEntry == null) {
      // No unit → integer ticks already in the timescale's unit.
      numericPart = cleaned;
      unitExponent = timescale.unit.exponent ?? -9;
    } else {
      numericPart = cleaned
          .substring(0, cleaned.length - unitEntry.key.length)
          .trim();
      unitExponent = unitEntry.value;
    }

    final value = double.tryParse(numericPart);
    if (value == null) return null;
    if (value.isNaN || value.isInfinite) return null;

    final timescaleExp = timescale.unit.exponent ?? -9;
    final relativeExp = unitExponent - timescaleExp;
    final scaled = value * pow(10.0, relativeExp) / timescale.factor;
    if (scaled.isNaN || scaled.isInfinite) return null;
    return scaled.round();
  }

  MapEntry<String, int>? _matchUnit(String s) {
    final lower = s.toLowerCase();
    // Length-descending iteration so `ms` is matched before `s`.
    final units = _unitExponents.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final unit in units) {
      if (lower.endsWith(unit)) {
        return MapEntry(unit, _unitExponents[unit]!);
      }
    }
    return null;
  }

  /// Extracts `(testName, index, total)` from `running test_X (N/M)`.
  (String, int, int)? _parseTestStart(String message) {
    final m = _testStart.firstMatch(message);
    if (m == null) return null;
    final name = m.group(1);
    final index = int.tryParse(m.group(2)!);
    final total = int.tryParse(m.group(3)!);
    if (name == null || index == null || total == null) return null;
    return (name, index, total);
  }

  /// Extracts `(testName, passed)` from `test_X passed` / `test_X failed`.
  /// Only matches when the entry's [loggerName] is `cocotb.regression*`.
  (String, bool)? _parseTestResult(String loggerName, String message) {
    if (!loggerName.toLowerCase().startsWith('cocotb.regression')) return null;
    final m = _testResult.firstMatch(message);
    if (m == null) return null;
    final name = m.group(1)!;
    final outcome = m.group(2)!.toLowerCase();
    return (name, outcome == 'passed');
  }

  /// Extracts `(total, passed, failed)` from `N tests run: M passed, K failed`.
  (int, int, int)? _parseSummary(String message) {
    final m = _summary.firstMatch(message);
    if (m == null) return null;
    final total = int.tryParse(m.group(1)!);
    final passed = int.tryParse(m.group(2)!);
    final failed = int.tryParse(m.group(3)!);
    if (total == null || passed == null || failed == null) return null;
    return (total, passed, failed);
  }
}
