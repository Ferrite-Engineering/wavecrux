// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A single state in a finite state machine.
///
/// [id] is the raw signal value (decimal integer string, e.g. `"0"`, `"15"`)
/// that identifies the state in the underlying signal. [label] is the
/// human-readable name (from a translate filter or user annotation), or
/// the same as [id] when no mapping is available.
@immutable
class FsmState {
  const FsmState({
    required this.id,
    required this.label,
    required this.entryCount,
    required this.firstEntryTime,
  });

  /// Stable identifier (decimal integer as string) for this state.
  final String id;

  /// Human-readable label, e.g. `"IDLE"`. Falls back to [id] if no
  /// translation exists.
  final String label;

  /// Number of times the FSM entered this state across the analysed time
  /// range.
  final int entryCount;

  /// Simulation tick when this state was first entered, or `null` if the
  /// state appears only as an initial value with no recorded entry.
  final int? firstEntryTime;

  // ── copyWith ───────────────────────────────────────────────────────────────

  static const _unset = Object();

  FsmState copyWith({
    String? id,
    String? label,
    int? entryCount,
    Object? firstEntryTime = _unset,
  }) => FsmState(
    id: id ?? this.id,
    label: label ?? this.label,
    entryCount: entryCount ?? this.entryCount,
    firstEntryTime: firstEntryTime == _unset
        ? this.firstEntryTime
        : firstEntryTime as int?,
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsmState &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          entryCount == other.entryCount &&
          firstEntryTime == other.firstEntryTime;

  @override
  int get hashCode => Object.hash(id, label, entryCount, firstEntryTime);

  @override
  String toString() =>
      'FsmState(id: $id, label: $label, entries: $entryCount, '
      'firstEntry: $firstEntryTime)';
}
