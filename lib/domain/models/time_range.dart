// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A closed time interval [start, end] in simulation ticks.
@immutable
class TimeRange {
  const TimeRange({required this.start, required this.end})
    : assert(end >= start, 'end must be >= start');

  final int start;
  final int end;

  /// Duration in ticks.
  int get duration => end - start;

  TimeRange copyWith({int? start, int? end}) =>
      TimeRange(start: start ?? this.start, end: end ?? this.end);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeRange &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TimeRange($start – $end)';
}
