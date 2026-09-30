// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';

/// A single parsed entry from a cocotb log file.
///
/// Each entry corresponds to one source line of a cocotb-formatted log. The
/// timestamp ([simTimeTicks]) is the simulation time normalised to the
/// waveform's tick unit, enabling correlation with signals on the timeline.
/// Entries without a parseable timestamp (continuation lines, Python
/// tracebacks) keep [simTimeTicks] `null` but retain their position in the
/// source via [lineNumber].
///
/// Test-boundary metadata ([testName], [isTestStart], [isTestResult],
/// [testPassed]) is populated by the parser when it recognises lines emitted
/// by the `cocotb.regression` logger such as `running test_X (1/3)` or
/// `test_X passed`.
@immutable
class CocotbLogEntry {
  const CocotbLogEntry({
    required this.severity,
    required this.loggerName,
    required this.message,
    required this.lineNumber,
    this.simTimeTicks,
    this.simTimeString,
    this.testName,
    this.isTestStart = false,
    this.isTestResult = false,
    this.testPassed,
  });

  /// Simulation time of this entry in waveform ticks, or `null` when the
  /// source line has no timestamp (continuation lines, tracebacks).
  final int? simTimeTicks;

  /// Original timestamp string from the log (e.g. `"100.00ns"`), or `null`
  /// when no timestamp was present.
  final String? simTimeString;

  /// Severity level emitted by cocotb's logger.
  final CocotbLogSeverity severity;

  /// Fully qualified Python logger name, e.g. `"cocotb.test_basic"`.
  final String loggerName;

  /// The log message text, with the timestamp / severity / logger fields
  /// stripped.
  final String message;

  /// 1-based line number in the source log file.
  final int lineNumber;

  /// The cocotb test this entry belongs to, when known.
  ///
  /// Set to the most recently announced test name from a `cocotb.regression`
  /// `running test_X` line. `null` for entries that occur before the first
  /// test starts (e.g. setup/banner lines).
  final String? testName;

  /// `true` when this entry is a `running test_X (N/M)` regression line.
  final bool isTestStart;

  /// `true` when this entry is a `test_X passed` or `test_X failed`
  /// regression line.
  final bool isTestResult;

  /// Pass / fail outcome — populated only when [isTestResult] is `true`.
  final bool? testPassed;

  // ── copyWith ───────────────────────────────────────────────────────────────

  /// Returns a copy with the given fields replaced. Pass [_unset] semantics
  /// via the special sentinel to explicitly clear a nullable field.
  CocotbLogEntry copyWith({
    Object? simTimeTicks = _unset,
    Object? simTimeString = _unset,
    CocotbLogSeverity? severity,
    String? loggerName,
    String? message,
    int? lineNumber,
    Object? testName = _unset,
    bool? isTestStart,
    bool? isTestResult,
    Object? testPassed = _unset,
  }) => CocotbLogEntry(
    simTimeTicks: simTimeTicks == _unset
        ? this.simTimeTicks
        : simTimeTicks as int?,
    simTimeString: simTimeString == _unset
        ? this.simTimeString
        : simTimeString as String?,
    severity: severity ?? this.severity,
    loggerName: loggerName ?? this.loggerName,
    message: message ?? this.message,
    lineNumber: lineNumber ?? this.lineNumber,
    testName: testName == _unset ? this.testName : testName as String?,
    isTestStart: isTestStart ?? this.isTestStart,
    isTestResult: isTestResult ?? this.isTestResult,
    testPassed: testPassed == _unset ? this.testPassed : testPassed as bool?,
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CocotbLogEntry &&
          runtimeType == other.runtimeType &&
          simTimeTicks == other.simTimeTicks &&
          simTimeString == other.simTimeString &&
          severity == other.severity &&
          loggerName == other.loggerName &&
          message == other.message &&
          lineNumber == other.lineNumber &&
          testName == other.testName &&
          isTestStart == other.isTestStart &&
          isTestResult == other.isTestResult &&
          testPassed == other.testPassed;

  @override
  int get hashCode => Object.hash(
    simTimeTicks,
    simTimeString,
    severity,
    loggerName,
    message,
    lineNumber,
    testName,
    isTestStart,
    isTestResult,
    testPassed,
  );

  @override
  String toString() =>
      'CocotbLogEntry('
      'line: $lineNumber, '
      'simTime: ${simTimeString ?? '—'} ($simTimeTicks ticks), '
      'severity: ${severity.displayLabel}, '
      'logger: $loggerName, '
      'test: ${testName ?? '—'}, '
      'message: "$message")';
}

const _unset = Object();
