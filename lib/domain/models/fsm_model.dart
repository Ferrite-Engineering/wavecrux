// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/fsm_state.dart';
import 'package:wavecrux/domain/models/fsm_transition.dart';
import 'package:wavecrux/domain/models/time_range.dart';

/// A complete finite state machine model derived from a signal's value
/// changes within an analysed [timeRange].
///
/// The model is purely descriptive — it carries no positional information.
/// Layout (state placement on a 2D plane) is computed separately by the
/// graph-layout service so that FSM analysis remains UI-agnostic.
@immutable
class FsmModel {
  const FsmModel({
    required this.signalRef,
    required this.signalPath,
    required this.timeRange,
    required this.states,
    required this.transitions,
    required this.totalTransitionCount,
  });

  /// Opaque reference of the source signal in [WaveformDataSource].
  final String signalRef;

  /// Hierarchical path of the source signal (e.g. `"top.cpu.state"`).
  final String signalPath;

  /// Time range over which the FSM was analysed.
  final TimeRange timeRange;

  /// All discovered states, sorted by [FsmState.id] (numeric ascending).
  final List<FsmState> states;

  /// All discovered transitions. May contain self-loops.
  final List<FsmTransition> transitions;

  /// Sum of [FsmTransition.count] across all transitions.
  ///
  /// Used by the bubble diagram to render percentages on edge labels.
  final int totalTransitionCount;

  /// Whether the FSM has only one observed state (degenerate trivial case).
  bool get isTrivial => states.length <= 1;

  /// Convenience lookup: state with id [id], or null.
  FsmState? stateById(String id) {
    for (final s in states) {
      if (s.id == id) return s;
    }
    return null;
  }

  // ── copyWith ───────────────────────────────────────────────────────────────

  FsmModel copyWith({
    String? signalRef,
    String? signalPath,
    TimeRange? timeRange,
    List<FsmState>? states,
    List<FsmTransition>? transitions,
    int? totalTransitionCount,
  }) => FsmModel(
    signalRef: signalRef ?? this.signalRef,
    signalPath: signalPath ?? this.signalPath,
    timeRange: timeRange ?? this.timeRange,
    states: states ?? this.states,
    transitions: transitions ?? this.transitions,
    totalTransitionCount: totalTransitionCount ?? this.totalTransitionCount,
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FsmModel) return false;
    if (runtimeType != other.runtimeType) return false;
    if (signalRef != other.signalRef) return false;
    if (signalPath != other.signalPath) return false;
    if (timeRange != other.timeRange) return false;
    if (totalTransitionCount != other.totalTransitionCount) return false;
    if (states.length != other.states.length) return false;
    for (var i = 0; i < states.length; i++) {
      if (states[i] != other.states[i]) return false;
    }
    if (transitions.length != other.transitions.length) return false;
    for (var i = 0; i < transitions.length; i++) {
      if (transitions[i] != other.transitions[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    signalRef,
    signalPath,
    timeRange,
    totalTransitionCount,
    Object.hashAll(states),
    Object.hashAll(transitions),
  );

  @override
  String toString() =>
      'FsmModel(signal: $signalPath, states: ${states.length}, '
      'transitions: ${transitions.length}, total: $totalTransitionCount, '
      'range: $timeRange)';
}
