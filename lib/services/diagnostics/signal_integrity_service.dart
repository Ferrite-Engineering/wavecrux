// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/signal_integrity_report.dart';
import 'package:wavecrux/domain/models/timescale.dart';

/// Analyses a loaded [WaveformDataSource] for common simulation integrity
/// issues.
///
/// Call [analyze] once after a file is loaded. The method iterates every
/// variable, loads each one via [WaveformDataSource.loadSignal] (which is a
/// no-op for signals already in memory), and checks for five conditions:
///
/// * **Constant** — ≤1 value change across the full time range.
/// * **X/Z-only** — every recorded value contains only x/z characters.
/// * **Glitches** — multiple transitions at the exact same timestamp.
/// * **Clocks** — 1-bit signals with ≥10 uniform transitions and 40–60 %
///   duty cycle spanning ≥50 % of the simulation time range.
/// * **Stuck-at-reset** — signal starts x/z, transitions exactly once to a
///   defined value, and never changes again.
///
/// For very large files (thousands of signals) the analysis may take several
/// seconds because every signal must be loaded. A future optimisation is to
/// batch-load and batch-unload signals to cap peak memory, but for the MVP
/// loading all signals sequentially is acceptable.
class SignalIntegrityService {
  const SignalIntegrityService();

  /// Analyse all signals in [source] for integrity issues.
  ///
  /// [onProgress] is called with `(analyzed, total)` after each signal is
  /// processed, which lets the UI show a running progress indicator.
  Future<SignalIntegrityReport> analyze(
    WaveformDataSource source, {
    void Function(int analyzed, int total)? onProgress,
  }) async {
    final sw = Stopwatch()..start();

    final allVariables = source.findVariables(const SignalFilter());
    final total = allVariables.length;
    final startTime = source.startTime;
    final endTime = source.endTime;
    final totalRange = endTime - startTime;
    final timescale = source.timescale;

    final constantPaths = <String>[];
    final xzOnlyPaths = <String>[];
    final glitchSignals = <String, int>{};
    final detectedClocks = <ClockInfo>[];
    final stuckAtResetPaths = <String>[];

    for (var i = 0; i < total; i++) {
      final variable = allVariables[i];
      await source.loadSignal(variable.signalRef);

      final changes = source.changesInRange(
        variable.signalRef,
        startTime,
        endTime + 1,
      );

      // X/Z-only takes priority: an undriven signal stuck at X with only one
      // dumpvars entry would otherwise be misclassified as constant.
      final isAllXz = _allXz(changes);
      if (isAllXz) {
        xzOnlyPaths.add(variable.fullPath);
      } else if (changes.length <= 1) {
        // Constant: ≤1 entry with a defined value (e.g., tied to 0/1).
        constantPaths.add(variable.fullPath);
      }

      // Glitches: multiple entries sharing the same timestamp.
      final glitchCount = _glitchTimestampCount(changes);
      if (glitchCount > 0) {
        glitchSignals[variable.fullPath] = glitchCount;
      }

      // Clocks: scalar signals with periodic, uniform transitions.
      final bw = variable.bitWidth;
      if (!variable.isReal && (bw == null || bw == 1)) {
        final clock = _detectClock(
          changes: changes,
          totalRange: totalRange,
          timescale: timescale,
          signalRef: variable.signalRef,
          signalPath: variable.fullPath,
        );
        if (clock != null) detectedClocks.add(clock);
      }

      // Stuck-at-reset: X/Z at t=startTime, exactly one real transition, done.
      if (changes.length == 2 &&
          _isXz(changes.first.value) &&
          !_isXz(changes.last.value)) {
        stuckAtResetPaths.add(variable.fullPath);
      }

      onProgress?.call(i + 1, total);
    }

    sw.stop();

    return SignalIntegrityReport(
      constantSignalPaths: List.unmodifiable(constantPaths),
      xzOnlySignalPaths: List.unmodifiable(xzOnlyPaths),
      glitchSignals: Map.unmodifiable(glitchSignals),
      detectedClocks: List.unmodifiable(detectedClocks),
      stuckAtResetPaths: List.unmodifiable(stuckAtResetPaths),
      analysisTimeMs: sw.elapsedMicroseconds / 1000.0,
      signalsAnalyzed: total,
    );
  }

  // ── private helpers ────────────────────────────────────────────────────────

  /// Returns true when [value] consists entirely of x / X / z / Z characters.
  static bool _isXz(String value) {
    if (value.isEmpty) return false;
    for (var i = 0; i < value.length; i++) {
      final c = value[i];
      if (c != 'x' && c != 'X' && c != 'z' && c != 'Z') return false;
    }
    return true;
  }

  /// Returns true when every change in [changes] is an x/z value.
  static bool _allXz(List<SignalChange> changes) =>
      changes.isNotEmpty && changes.every((c) => _isXz(c.value));

  /// Returns the number of distinct timestamps at which the signal changes
  /// more than once (i.e. glitch timestamps).
  static int _glitchTimestampCount(List<SignalChange> changes) {
    if (changes.length < 2) return 0;
    final seen = <int>{};
    final duplicates = <int>{};
    for (final c in changes) {
      if (!seen.add(c.time)) duplicates.add(c.time);
    }
    return duplicates.length;
  }

  /// Attempts to classify [changes] as a clock signal.
  ///
  /// Returns a [ClockInfo] when all conditions are met:
  /// * ≥10 transitions (11+ change entries including the initial dumpvars).
  /// * Intervals between consecutive changes are approximately uniform
  ///   (standard deviation < 10 % of the mean).
  /// * No zero-length intervals (no glitches at the same timestamp).
  /// * Duty cycle (fraction of time the signal is high) is 40–60 %.
  /// * Active signal range spans ≥50 % of [totalRange].
  static ClockInfo? _detectClock({
    required List<SignalChange> changes,
    required int totalRange,
    required Timescale? timescale,
    required String signalRef,
    required String signalPath,
  }) {
    if (changes.length < 11) return null;

    // Intervals between consecutive transitions.
    final intervals = <int>[];
    for (var i = 1; i < changes.length; i++) {
      intervals.add(changes[i].time - changes[i - 1].time);
    }

    // No glitches (zero-length intervals) allowed for clock detection.
    if (intervals.any((d) => d <= 0)) return null;

    // Uniformity check: SD / mean < 10 %.
    final mean = intervals.reduce((a, b) => a + b) / intervals.length;
    if (mean == 0) return null;
    final variance =
        intervals.map((d) => (d - mean) * (d - mean)).reduce((a, b) => a + b) /
        intervals.length;
    final sd = math.sqrt(variance);
    if (sd / mean > 0.1) return null;

    // Duty cycle: fraction of time the signal value is '1'.
    var highTicks = 0;
    for (var i = 0; i < changes.length - 1; i++) {
      if (changes[i].value == '1') {
        highTicks += changes[i + 1].time - changes[i].time;
      }
    }
    final activeRange = changes.last.time - changes.first.time;
    if (activeRange <= 0) return null;
    final dutyCycle = highTicks / activeRange * 100.0;
    if (dutyCycle < 40.0 || dutyCycle > 60.0) return null;

    // Must span ≥50 % of the total simulation time range.
    if (totalRange > 0 && activeRange < totalRange * 0.5) return null;

    // Period = 2× the mean half-period interval.
    final periodTicks = (mean * 2).round();

    return ClockInfo(
      signalRef: signalRef,
      signalPath: signalPath,
      periodTicks: periodTicks,
      dutyCyclePercent: dutyCycle,
      estimatedFrequency: _frequencyString(periodTicks, timescale),
    );
  }

  /// Formats a clock frequency from [periodTicks] and the simulation
  /// [timescale]. Falls back to a tick-count string when the timescale is
  /// unavailable.
  static String _frequencyString(int periodTicks, Timescale? timescale) {
    final spt = timescale?.secondsPerTick;
    if (spt == null || spt == 0.0 || periodTicks <= 0) {
      return '$periodTicks ticks/period';
    }
    final hz = 1.0 / (periodTicks * spt);
    if (hz >= 1e9) return '${(hz / 1e9).toStringAsFixed(2)} GHz';
    if (hz >= 1e6) return '${(hz / 1e6).toStringAsFixed(2)} MHz';
    if (hz >= 1e3) return '${(hz / 1e3).toStringAsFixed(2)} kHz';
    return '${hz.toStringAsFixed(2)} Hz';
  }
}
