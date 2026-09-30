// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/activity_report.dart';
import 'package:wavecrux/domain/models/signal_activity.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/time_range.dart';

/// Stateless service for analyzing signal switching activity.
///
/// All signals must be pre-loaded via [WaveformDataSource.loadSignal] before
/// calling these methods.  The [signalPath] parameter is passed directly to
/// [WaveformDataSource] as the `signalRef` for data queries.
class SwitchingActivityService {
  const SwitchingActivityService();

  // ── public API ──────────────────────────────────────────────────────────────

  /// Analyzes switching activity for [signalPath] over `[startTime, endTime)`.
  ///
  /// - [transitionCount] equals the number of value changes whose value
  ///   actually differs from the previous state. A change record whose value
  ///   matches the signal's value just before that record (typically the
  ///   initial-state dump emitted at time 0 by `$dumpvars`) is not counted
  ///   as a transition — a constant signal therefore reports `0` transitions
  ///   even though wellen retains one value-change record for the initial
  ///   value.
  /// - [toggleRate] equals `transitionCount / duration` (0 when duration ≤ 0).
  /// - [dutyCycle] is computed for 1-bit signals; `null` for multi-bit or real.
  /// - [isClockCandidate] is always `false`; call [detectClock] to classify
  ///   clocks.
  SignalActivity analyzeSignal(
    String signalPath,
    WaveformDataSource query,
    int startTime,
    int endTime,
  ) {
    final changes = query.changesInRange(signalPath, startTime, endTime);
    final initialValue = query.valueAt(signalPath, startTime);

    // Walk the change list comparing each record to the previous value.
    // The first record may carry the same value as `valueAt(startTime)`
    // when it represents the initial-state dump for the signal — in that
    // case the value did not transition. All subsequent records always
    // differ from the immediately preceding one because that is wellen's
    // value-change recording rule, but we still walk explicitly to handle
    // any partial-range edge case.
    var transitionCount = 0;
    var previousValue = initialValue;
    for (final change in changes) {
      if (change.value != previousValue) {
        transitionCount++;
      }
      previousValue = change.value;
    }

    final duration = endTime - startTime;
    final toggleRate = duration > 0 ? transitionCount / duration : 0.0;

    double? dutyCycle;
    if (_isSingleBitChanges(changes, initialValue)) {
      dutyCycle = _computeDutyCycle(changes, initialValue, startTime, endTime);
    }

    return SignalActivity(
      signalPath: signalPath,
      transitionCount: transitionCount,
      toggleRate: toggleRate,
      isClockCandidate: false,
      timeRange: TimeRange(start: startTime, end: endTime),
      dutyCycle: dutyCycle,
    );
  }

  /// Analyzes [signalPath] and also tests whether it is a clock candidate.
  ///
  /// A signal is classified as a clock when:
  /// - It is a 1-bit signal.
  /// - It has at least 4 transitions (≥ 2 measurable rising-edge periods).
  /// - Consecutive rising-edge periods are consistent within 5 % of the mean.
  /// - Duty cycle is between 40 % and 60 %.
  ///
  /// [SignalActivity.estimatedFrequency] is set in Hz when the clock criteria
  /// are met and the waveform's [WaveformDataSource.timescale] is known.
  SignalActivity detectClock(
    String signalPath,
    WaveformDataSource query,
    int startTime,
    int endTime,
  ) {
    final base = analyzeSignal(signalPath, query, startTime, endTime);

    // Multi-bit and real signals cannot be clocks.
    if (base.dutyCycle == null) return base;

    final changes = query.changesInRange(signalPath, startTime, endTime);

    // Need at least 8 transitions to measure 4 rising-edge periods reliably.
    if (changes.length < 8) return base;

    // Collect times of rising edges (transitions to high).
    final risingTimes = changes
        .where((c) => _isHigh(c.value))
        .map((c) => c.time)
        .toList();

    // Need at least 5 rising edges to measure 4 periods.
    if (risingTimes.length < 5) return base;

    // Compute period between consecutive rising edges.
    final risingPeriods = <int>[];
    for (var i = 1; i < risingTimes.length; i++) {
      risingPeriods.add(risingTimes[i] - risingTimes[i - 1]);
    }

    final avgPeriod =
        risingPeriods.reduce((a, b) => a + b) / risingPeriods.length;
    if (avgPeriod <= 0) return base;

    // All periods must be within 5 % of the mean.
    final isConsistent = risingPeriods.every(
      (p) => (p - avgPeriod).abs() / avgPeriod <= 0.05,
    );
    if (!isConsistent) return base;

    // Period jitter (stddev / mean) must be < 2 %. Real simulation clocks have
    // zero jitter; irregular toggle signals are rejected by this check.
    var variance = 0.0;
    for (final p in risingPeriods) {
      final diff = p - avgPeriod;
      variance += diff * diff;
    }
    variance /= risingPeriods.length;
    if (math.sqrt(variance) / avgPeriod > 0.02) return base;

    // Duty cycle must be in the 40–60 % window.
    final dc = base.dutyCycle!;
    if (dc < 0.40 || dc > 0.60) return base;

    // Frequency in Hz when timescale is available.
    double? estimatedFrequency;
    final secondsPerTick = query.timescale?.secondsPerTick;
    if (secondsPerTick != null && secondsPerTick > 0) {
      estimatedFrequency = 1.0 / (avgPeriod * secondsPerTick);
    }

    return base.copyWith(
      isClockCandidate: true,
      estimatedFrequency: estimatedFrequency,
    );
  }

  /// Analyzes all signals in [signalRefToPath] and returns an [ActivityReport].
  ///
  /// Keys are opaque signal references used for [WaveformDataSource] queries;
  /// values are the display paths stored in each [SignalActivity.signalPath].
  /// Each signal is processed with [detectClock] so clock candidates are
  /// automatically identified.
  ActivityReport analyzeAll(
    Map<String, String> signalRefToPath,
    WaveformDataSource query,
    int startTime,
    int endTime,
  ) {
    final signals = signalRefToPath.entries.map((e) {
      final activity = detectClock(e.key, query, startTime, endTime);
      return e.key == e.value
          ? activity
          : activity.copyWith(signalPath: e.value);
    }).toList();

    final totalTransitions = signals.fold(
      0,
      (sum, s) => sum + s.transitionCount,
    );

    final topSwitchers = [...signals]
      ..sort((a, b) => b.toggleRate.compareTo(a.toggleRate));

    return ActivityReport(
      signals: signals,
      timeRange: TimeRange(start: startTime, end: endTime),
      totalTransitions: totalTransitions,
      topSwitchers: topSwitchers,
    );
  }

  /// Normalizes toggle rates to [0.0, 1.0] for heatmap rendering.
  ///
  /// The signal with the highest toggle rate maps to `1.0`; all others are
  /// scaled linearly.  Returns an empty map for an empty report.  When all
  /// signals have a zero toggle rate, every value is `0.0`.
  Map<String, double> computeHeatmapValues(ActivityReport report) {
    if (report.signals.isEmpty) return {};

    final maxRate = report.signals.map((s) => s.toggleRate).reduce(math.max);

    if (maxRate == 0) {
      return {for (final s in report.signals) s.signalPath: 0.0};
    }

    return {
      for (final s in report.signals) s.signalPath: s.toggleRate / maxRate,
    };
  }

  // ── helpers ─────────────────────────────────────────────────────────────────

  /// Returns `true` when every value in [changes] and [initialValue] is a
  /// single-bit VCD value.
  ///
  /// Returns `false` when both [changes] is empty and [initialValue] is `null`,
  /// since the bit width cannot be determined.
  bool _isSingleBitChanges(
    List<SignalChange> changes,
    String? initialValue,
  ) {
    if (changes.isEmpty && initialValue == null) return false;
    if (initialValue != null && !_isSingleBitValue(initialValue)) return false;
    return changes.every((c) => _isSingleBitValue(c.value));
  }

  /// Returns `true` for single-bit VCD values: `'0'`, `'1'`, `'x'`, `'z'`
  /// (case-insensitive) and their `'b'`-prefixed equivalents (`'b0'`, `'b1'`,
  /// `'bx'`, `'bz'`).
  bool _isSingleBitValue(String value) {
    if (value.length == 1) return '01xzXZ'.contains(value);
    if (value.length == 2 && value.startsWith('b')) {
      return '01xzXZ'.contains(value[1]);
    }
    return false;
  }

  bool _isHigh(String value) => value == '1' || value == 'b1';

  /// Computes the fraction of `[startTime, endTime)` during which the signal
  /// is in the high state.
  ///
  /// Assumes `'0'` when [initialValue] is `null`.
  double _computeDutyCycle(
    List<SignalChange> changes,
    String? initialValue,
    int startTime,
    int endTime,
  ) {
    final duration = endTime - startTime;
    if (duration <= 0) return 0;

    var highTicks = 0;
    var currentValue = initialValue ?? '0';
    var currentTime = startTime;

    for (final change in changes) {
      if (_isHigh(currentValue)) {
        highTicks += change.time - currentTime;
      }
      currentValue = change.value;
      currentTime = change.time;
    }

    // Final segment: from the last change to endTime.
    if (_isHigh(currentValue)) {
      highTicks += endTime - currentTime;
    }

    return highTicks / duration;
  }
}
