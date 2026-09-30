// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/signal_activity.dart';
import 'package:wavecrux/domain/models/time_range.dart';

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Aggregated switching activity analysis for a set of signals.
@immutable
class ActivityReport {
  const ActivityReport({
    required this.signals,
    required this.timeRange,
    required this.totalTransitions,
    required this.topSwitchers,
  });

  /// Activity results for every analyzed signal, in the order they were
  /// analyzed.
  final List<SignalActivity> signals;

  /// The analysis window common to all signals.
  final TimeRange timeRange;

  /// Sum of [SignalActivity.transitionCount] across all signals.
  final int totalTransitions;

  /// [signals] sorted by [SignalActivity.toggleRate] descending (highest
  /// toggle rate first).
  final List<SignalActivity> topSwitchers;

  // ── equality ─────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityReport &&
          runtimeType == other.runtimeType &&
          _listEquals(signals, other.signals) &&
          timeRange == other.timeRange &&
          totalTransitions == other.totalTransitions &&
          _listEquals(topSwitchers, other.topSwitchers);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(signals),
    timeRange,
    totalTransitions,
    Object.hashAll(topSwitchers),
  );

  @override
  String toString() =>
      'ActivityReport(signals: ${signals.length}, range: $timeRange, '
      'totalTransitions: $totalTransitions)';
}
