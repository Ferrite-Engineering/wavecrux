// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// 2D position of an FSM state node, in normalised model coordinates
/// (typically `[0, 1] × [0, 1]`). The widget multiplies by canvas size to
/// project to pixels.
@immutable
class FsmStatePosition {
  const FsmStatePosition({
    required this.stateId,
    required this.x,
    required this.y,
  });

  /// State id from [FsmState.id] this position belongs to.
  final String stateId;

  /// Normalised x coordinate in `[0, 1]`.
  final double x;

  /// Normalised y coordinate in `[0, 1]`.
  final double y;

  FsmStatePosition copyWith({String? stateId, double? x, double? y}) =>
      FsmStatePosition(
        stateId: stateId ?? this.stateId,
        x: x ?? this.x,
        y: y ?? this.y,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsmStatePosition &&
          runtimeType == other.runtimeType &&
          stateId == other.stateId &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => Object.hash(stateId, x, y);

  @override
  String toString() =>
      'FsmStatePosition(state: $stateId, x: ${x.toStringAsFixed(3)}, '
      'y: ${y.toStringAsFixed(3)})';
}

/// Computed layout for an entire FSM diagram.
///
/// Produced by the graph-layout service from an [FsmModel]; consumed by
/// the bubble-diagram painter.
@immutable
class FsmLayout {
  const FsmLayout({required this.positions});

  /// Position for each state, keyed by [FsmState.id].
  final Map<String, FsmStatePosition> positions;

  /// Lookup helper. Returns `null` for unknown state ids.
  FsmStatePosition? operator [](String stateId) => positions[stateId];

  /// Whether the layout has any positions.
  bool get isEmpty => positions.isEmpty;

  bool get isNotEmpty => positions.isNotEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FsmLayout) return false;
    if (positions.length != other.positions.length) return false;
    for (final entry in positions.entries) {
      if (other.positions[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(
    positions.entries.map((e) => Object.hash(e.key, e.value)),
  );

  @override
  String toString() => 'FsmLayout(${positions.length} positions)';
}
