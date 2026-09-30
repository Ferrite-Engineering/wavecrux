// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/time_range.dart';

/// Switching activity analysis result for a single signal.
@immutable
class SignalActivity {
  const SignalActivity({
    required this.signalPath,
    required this.transitionCount,
    required this.toggleRate,
    required this.isClockCandidate,
    required this.timeRange,
    this.estimatedFrequency,
    this.dutyCycle,
  });

  /// Full hierarchical path of the signal (e.g. `"top.cpu.clk"`).
  final String signalPath;

  /// Number of value changes observed within [timeRange].
  final int transitionCount;

  /// Average transitions per simulation tick within [timeRange].
  ///
  /// Equal to `transitionCount / timeRange.duration`, or `0.0` when the
  /// duration is zero.
  final double toggleRate;

  /// Whether this signal meets the clock-candidate criteria: 1-bit, periodic
  /// within 5 % period tolerance, and 40–60 % duty cycle.
  final bool isClockCandidate;

  /// Estimated clock frequency in Hz.
  ///
  /// Non-null only when [isClockCandidate] is `true` and the waveform's
  /// timescale is known.
  final double? estimatedFrequency;

  /// Fraction of [timeRange] that the signal spends in the high (`'1'`) state.
  ///
  /// Computed only for 1-bit signals; `null` for multi-bit or real signals.
  final double? dutyCycle;

  /// The analysis window used to derive these statistics.
  final TimeRange timeRange;

  // ── copyWith ─────────────────────────────────────────────────────────────

  static const _unset = Object();

  SignalActivity copyWith({
    String? signalPath,
    int? transitionCount,
    double? toggleRate,
    bool? isClockCandidate,
    TimeRange? timeRange,
    Object? estimatedFrequency = _unset,
    Object? dutyCycle = _unset,
  }) => SignalActivity(
    signalPath: signalPath ?? this.signalPath,
    transitionCount: transitionCount ?? this.transitionCount,
    toggleRate: toggleRate ?? this.toggleRate,
    isClockCandidate: isClockCandidate ?? this.isClockCandidate,
    timeRange: timeRange ?? this.timeRange,
    estimatedFrequency: estimatedFrequency == _unset
        ? this.estimatedFrequency
        : estimatedFrequency as double?,
    dutyCycle: dutyCycle == _unset ? this.dutyCycle : dutyCycle as double?,
  );

  // ── equality ─────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalActivity &&
          runtimeType == other.runtimeType &&
          signalPath == other.signalPath &&
          transitionCount == other.transitionCount &&
          toggleRate == other.toggleRate &&
          isClockCandidate == other.isClockCandidate &&
          estimatedFrequency == other.estimatedFrequency &&
          dutyCycle == other.dutyCycle &&
          timeRange == other.timeRange;

  @override
  int get hashCode => Object.hash(
    signalPath,
    transitionCount,
    toggleRate,
    isClockCandidate,
    estimatedFrequency,
    dutyCycle,
    timeRange,
  );

  @override
  String toString() =>
      'SignalActivity(path: $signalPath, transitions: $transitionCount, '
      'toggleRate: $toggleRate, clock: $isClockCandidate, '
      'freq: $estimatedFrequency, duty: $dutyCycle, range: $timeRange)';
}
