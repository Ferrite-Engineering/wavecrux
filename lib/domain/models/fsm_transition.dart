// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A directed transition from one FSM state to another.
///
/// [fromId] and [toId] reference the [FsmState.id] of the source and
/// destination states. Self-transitions (where `fromId == toId`) are
/// permitted and are recorded when an FSM signal re-asserts the same
/// state value.
@immutable
class FsmTransition {
  const FsmTransition({
    required this.fromId,
    required this.toId,
    required this.count,
    required this.times,
  });

  /// State id from which the transition originates.
  final String fromId;

  /// State id at which the transition ends.
  final String toId;

  /// Number of times this transition was observed.
  final int count;

  /// Sorted simulation ticks at which this transition occurred.
  ///
  /// Length equals [count]. Empty only when the transition is synthesised
  /// for layout purposes (currently never produced).
  final List<int> times;

  /// Whether this is a self-loop (state to itself).
  bool get isSelfLoop => fromId == toId;

  // ── copyWith ───────────────────────────────────────────────────────────────

  FsmTransition copyWith({
    String? fromId,
    String? toId,
    int? count,
    List<int>? times,
  }) => FsmTransition(
    fromId: fromId ?? this.fromId,
    toId: toId ?? this.toId,
    count: count ?? this.count,
    times: times ?? this.times,
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FsmTransition) return false;
    if (runtimeType != other.runtimeType) return false;
    if (fromId != other.fromId) return false;
    if (toId != other.toId) return false;
    if (count != other.count) return false;
    if (times.length != other.times.length) return false;
    for (var i = 0; i < times.length; i++) {
      if (times[i] != other.times[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(fromId, toId, count, Object.hashAll(times));

  @override
  String toString() =>
      'FsmTransition($fromId → $toId, count: $count, times: ${times.length})';
}
