// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Immutable snapshot of cursor placement in the waveform viewport.
///
/// The primary cursor is placed by a single click; the secondary cursor enables
/// delta-time and frequency measurement between two points. Either cursor may be
/// absent (null) — the secondary cursor is typically only set when the user
/// explicitly places it.
@immutable
class CursorState {
  const CursorState({
    this.primaryCursorTime,
    this.secondaryCursorTime,
  });

  /// Simulation tick at which the primary cursor is placed, or null if unset.
  final int? primaryCursorTime;

  /// Simulation tick at which the secondary cursor is placed, or null if unset.
  final int? secondaryCursorTime;

  /// Absolute tick-count difference between primary and secondary cursor.
  ///
  /// Returns null when either cursor is unset.
  int? get deltaTicks {
    final p = primaryCursorTime;
    final s = secondaryCursorTime;
    if (p == null || s == null) return null;
    return (s - p).abs();
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// Pass [_unset] as a value to explicitly clear a nullable field.
  CursorState copyWith({
    Object? primaryCursorTime = _unset,
    Object? secondaryCursorTime = _unset,
  }) => CursorState(
    primaryCursorTime: primaryCursorTime == _unset
        ? this.primaryCursorTime
        : primaryCursorTime as int?,
    secondaryCursorTime: secondaryCursorTime == _unset
        ? this.secondaryCursorTime
        : secondaryCursorTime as int?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CursorState &&
          runtimeType == other.runtimeType &&
          primaryCursorTime == other.primaryCursorTime &&
          secondaryCursorTime == other.secondaryCursorTime;

  @override
  int get hashCode => Object.hash(primaryCursorTime, secondaryCursorTime);

  @override
  String toString() =>
      'CursorState(primary: $primaryCursorTime, secondary: $secondaryCursorTime)';
}

// Sentinel used to distinguish "not provided" from an explicit null in copyWith.
const _unset = Object();
