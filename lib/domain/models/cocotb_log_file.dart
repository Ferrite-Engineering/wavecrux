// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/models/cocotb_log_entry.dart';

/// A fully parsed cocotb log file: the ordered list of [entries] plus
/// derived summaries used by the diagnostics UI and the waveform overlay.
///
/// All summary fields are pre-computed by [CocotbLogParser] so that the UI
/// layer can render counts, time ranges, and per-test status without having
/// to scan [entries] on every rebuild.
@immutable
class CocotbLogFile {
  const CocotbLogFile({
    required this.filePath,
    required this.entries,
    required this.testNames,
    required this.severityCounts,
    required this.testResults,
    this.totalTests,
    this.passedTests,
    this.failedTests,
    this.timeRangeTicks,
  });

  /// Absolute path to the source log file.
  final String filePath;

  /// All parsed entries in source order. May be empty.
  final List<CocotbLogEntry> entries;

  /// Unique test names found in the log, in order of first appearance.
  final List<String> testNames;

  /// Number of entries per severity level. Keys for severities that did not
  /// appear are absent (callers should default to 0).
  final Map<CocotbLogSeverity, int> severityCounts;

  /// Pass / fail outcome per test, keyed by test name. `true` = passed.
  /// Tests that started but produced no result line are absent from the map.
  final Map<String, bool> testResults;

  /// Total tests reported by the cocotb summary line, when present.
  final int? totalTests;

  /// Passed tests reported by the cocotb summary line, when present.
  final int? passedTests;

  /// Failed tests reported by the cocotb summary line, when present.
  final int? failedTests;

  /// `(earliest, latest)` simulation tick across all timestamped entries, or
  /// `null` when the log contains no timestamps.
  final (int, int)? timeRangeTicks;

  // ── copyWith ───────────────────────────────────────────────────────────────

  CocotbLogFile copyWith({
    String? filePath,
    List<CocotbLogEntry>? entries,
    List<String>? testNames,
    Map<CocotbLogSeverity, int>? severityCounts,
    Map<String, bool>? testResults,
    Object? totalTests = _unset,
    Object? passedTests = _unset,
    Object? failedTests = _unset,
    Object? timeRangeTicks = _unset,
  }) => CocotbLogFile(
    filePath: filePath ?? this.filePath,
    entries: entries ?? this.entries,
    testNames: testNames ?? this.testNames,
    severityCounts: severityCounts ?? this.severityCounts,
    testResults: testResults ?? this.testResults,
    totalTests: totalTests == _unset ? this.totalTests : totalTests as int?,
    passedTests: passedTests == _unset ? this.passedTests : passedTests as int?,
    failedTests: failedTests == _unset ? this.failedTests : failedTests as int?,
    timeRangeTicks: timeRangeTicks == _unset
        ? this.timeRangeTicks
        : timeRangeTicks as (int, int)?,
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CocotbLogFile) return false;
    if (filePath != other.filePath ||
        totalTests != other.totalTests ||
        passedTests != other.passedTests ||
        failedTests != other.failedTests ||
        timeRangeTicks != other.timeRangeTicks) {
      return false;
    }
    if (entries.length != other.entries.length) return false;
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] != other.entries[i]) return false;
    }
    if (testNames.length != other.testNames.length) return false;
    for (var i = 0; i < testNames.length; i++) {
      if (testNames[i] != other.testNames[i]) return false;
    }
    if (severityCounts.length != other.severityCounts.length) return false;
    for (final entry in severityCounts.entries) {
      if (other.severityCounts[entry.key] != entry.value) return false;
    }
    if (testResults.length != other.testResults.length) return false;
    for (final entry in testResults.entries) {
      if (other.testResults[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// Hash on identity-cardinality fields only; entry/list hashing on every
  /// rebuild would be expensive for large logs.
  @override
  int get hashCode => Object.hash(
    filePath,
    entries.length,
    testNames.length,
    severityCounts.length,
    testResults.length,
    totalTests,
    passedTests,
    failedTests,
    timeRangeTicks,
  );

  @override
  String toString() =>
      'CocotbLogFile('
      'path: $filePath, '
      'entries: ${entries.length}, '
      'tests: ${testNames.length}, '
      'results: $passedTests/$totalTests passed, '
      'timeRangeTicks: $timeRangeTicks)';
}

const _unset = Object();
