// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// An inclusive time range selected by the user on the waveform canvas.
///
/// Used for zoom-to-selection and as the future basis for export range
/// selection. [startTime] and [endTime] are simulation ticks and may be in
/// any order — call [normalized] to ensure [startTime] <= [endTime].
@immutable
class TimeSelection {
  const TimeSelection({required this.startTime, required this.endTime});

  /// Simulation tick at the beginning of the selection (may be > [endTime]).
  final int startTime;

  /// Simulation tick at the end of the selection (may be < [startTime]).
  final int endTime;

  /// Absolute duration of the selection in ticks.
  int get duration => (endTime - startTime).abs();

  /// True when [startTime] == [endTime] (zero-duration selection).
  bool get isEmpty => startTime == endTime;

  /// Returns a copy whose [startTime] <= [endTime].
  TimeSelection normalized() {
    if (startTime <= endTime) return this;
    return TimeSelection(startTime: endTime, endTime: startTime);
  }

  /// Returns a copy with the given fields replaced.
  TimeSelection copyWith({int? startTime, int? endTime}) => TimeSelection(
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeSelection &&
          other.startTime == startTime &&
          other.endTime == endTime;

  @override
  int get hashCode => Object.hash(startTime, endTime);

  @override
  String toString() => 'TimeSelection($startTime–$endTime)';
}
