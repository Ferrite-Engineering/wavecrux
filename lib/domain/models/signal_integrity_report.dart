// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Auto-detected clock signal with estimated frequency and duty cycle.
@immutable
class ClockInfo {
  const ClockInfo({
    required this.signalRef,
    required this.signalPath,
    required this.periodTicks,
    required this.dutyCyclePercent,
    required this.estimatedFrequency,
  });

  final String signalRef;
  final String signalPath;

  /// Measured period in simulation ticks.
  final int periodTicks;

  /// Duty cycle as a percentage (0.0–100.0).
  final double dutyCyclePercent;

  /// Human-readable frequency string, e.g. "100 MHz".
  final String estimatedFrequency;

  ClockInfo copyWith({
    String? signalRef,
    String? signalPath,
    int? periodTicks,
    double? dutyCyclePercent,
    String? estimatedFrequency,
  }) => ClockInfo(
    signalRef: signalRef ?? this.signalRef,
    signalPath: signalPath ?? this.signalPath,
    periodTicks: periodTicks ?? this.periodTicks,
    dutyCyclePercent: dutyCyclePercent ?? this.dutyCyclePercent,
    estimatedFrequency: estimatedFrequency ?? this.estimatedFrequency,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClockInfo &&
          runtimeType == other.runtimeType &&
          signalRef == other.signalRef &&
          signalPath == other.signalPath &&
          periodTicks == other.periodTicks &&
          dutyCyclePercent == other.dutyCyclePercent &&
          estimatedFrequency == other.estimatedFrequency;

  @override
  int get hashCode => Object.hash(
    signalRef,
    signalPath,
    periodTicks,
    dutyCyclePercent,
    estimatedFrequency,
  );

  @override
  String toString() =>
      'ClockInfo('
      'path: $signalPath, '
      'period: $periodTicks ticks, '
      'duty: $dutyCyclePercent%, '
      'freq: $estimatedFrequency'
      ')';
}

/// Results of running signal integrity checks over a loaded waveform.
@immutable
class SignalIntegrityReport {
  const SignalIntegrityReport({
    required this.constantSignalPaths,
    required this.xzOnlySignalPaths,
    required this.glitchSignals,
    required this.detectedClocks,
    required this.stuckAtResetPaths,
    required this.analysisTimeMs,
    required this.signalsAnalyzed,
  });

  /// Signals with ≤1 transition across the full simulation time range.
  final List<String> constantSignalPaths;

  /// Signals where every value at every transition contains x or z.
  final List<String> xzOnlySignalPaths;

  /// Signals that have multiple transitions at the exact same timestamp.
  ///
  /// Maps full signal path to the count of same-timestamp multi-transitions.
  final Map<String, int> glitchSignals;

  /// Signals identified as clocks (periodic, 40–60% duty cycle).
  final List<ClockInfo> detectedClocks;

  /// Signals that are X at t=0, transition exactly once, then never change.
  final List<String> stuckAtResetPaths;

  final double analysisTimeMs;
  final int signalsAnalyzed;

  SignalIntegrityReport copyWith({
    List<String>? constantSignalPaths,
    List<String>? xzOnlySignalPaths,
    Map<String, int>? glitchSignals,
    List<ClockInfo>? detectedClocks,
    List<String>? stuckAtResetPaths,
    double? analysisTimeMs,
    int? signalsAnalyzed,
  }) => SignalIntegrityReport(
    constantSignalPaths: constantSignalPaths ?? this.constantSignalPaths,
    xzOnlySignalPaths: xzOnlySignalPaths ?? this.xzOnlySignalPaths,
    glitchSignals: glitchSignals ?? this.glitchSignals,
    detectedClocks: detectedClocks ?? this.detectedClocks,
    stuckAtResetPaths: stuckAtResetPaths ?? this.stuckAtResetPaths,
    analysisTimeMs: analysisTimeMs ?? this.analysisTimeMs,
    signalsAnalyzed: signalsAnalyzed ?? this.signalsAnalyzed,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalIntegrityReport &&
          runtimeType == other.runtimeType &&
          _listEqual(constantSignalPaths, other.constantSignalPaths) &&
          _listEqual(xzOnlySignalPaths, other.xzOnlySignalPaths) &&
          _mapEqual(glitchSignals, other.glitchSignals) &&
          _listEqual(detectedClocks, other.detectedClocks) &&
          _listEqual(stuckAtResetPaths, other.stuckAtResetPaths) &&
          analysisTimeMs == other.analysisTimeMs &&
          signalsAnalyzed == other.signalsAnalyzed;

  @override
  int get hashCode => Object.hashAll([
    Object.hashAll(constantSignalPaths),
    Object.hashAll(xzOnlySignalPaths),
    Object.hashAll(
      glitchSignals.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAll(detectedClocks),
    Object.hashAll(stuckAtResetPaths),
    analysisTimeMs,
    signalsAnalyzed,
  ]);

  @override
  String toString() =>
      'SignalIntegrityReport('
      'constant: ${constantSignalPaths.length}, '
      'xzOnly: ${xzOnlySignalPaths.length}, '
      'glitches: ${glitchSignals.length}, '
      'clocks: ${detectedClocks.length}, '
      'stuckAtReset: ${stuckAtResetPaths.length}, '
      'analyzed: $signalsAnalyzed'
      ')';

  static bool _listEqual<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _mapEqual(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}
