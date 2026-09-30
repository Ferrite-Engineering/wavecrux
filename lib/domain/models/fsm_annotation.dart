// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// User-supplied state-name annotation for an FSM signal.
///
/// When no GTKWave translate filter is assigned to a signal, the user can
/// mark it as an FSM and provide a map from raw integer values to state
/// names directly. Annotations are stored per-signal (keyed by signalRef)
/// in [FsmAnnotationNotifier].
@immutable
class FsmAnnotation {
  const FsmAnnotation({
    required this.signalRef,
    required this.stateLabels,
  });

  /// Reconstructs an annotation from its [toJson] representation. Missing or
  /// malformed fields degrade gracefully (empty label map / empty ref) so a
  /// partially-corrupt session entry never aborts the surrounding restore.
  factory FsmAnnotation.fromJson(Map<String, dynamic> json) {
    final rawLabels = json['labels'];
    return FsmAnnotation(
      signalRef: json['signalRef'] as String? ?? '',
      stateLabels: {
        if (rawLabels is Map)
          for (final e in rawLabels.entries)
            if (e.value is String) e.key.toString(): e.value as String,
      },
    );
  }

  /// Opaque signal reference of the FSM signal.
  final String signalRef;

  /// Map from decimal integer state id (as string) → human-readable label.
  ///
  /// Values not present in this map fall back to their raw id when the
  /// FSM model is built.
  final Map<String, String> stateLabels;

  /// Whether [stateLabels] has at least one entry.
  bool get hasLabels => stateLabels.isNotEmpty;

  /// Returns the label for [stateId], or null if no label is assigned.
  String? labelFor(String stateId) => stateLabels[stateId];

  // ── JSON ───────────────────────────────────────────────────────────────────

  /// Serializes this annotation to a JSON-encodable map. Round-trips through
  /// the `.wavecrux` session file's `fsmAnnotations` map (keyed by signalRef).
  Map<String, dynamic> toJson() => {
    'signalRef': signalRef,
    'labels': Map<String, String>.from(stateLabels),
  };

  // ── copyWith ───────────────────────────────────────────────────────────────

  FsmAnnotation copyWith({
    String? signalRef,
    Map<String, String>? stateLabels,
  }) => FsmAnnotation(
    signalRef: signalRef ?? this.signalRef,
    stateLabels: stateLabels ?? this.stateLabels,
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FsmAnnotation) return false;
    if (runtimeType != other.runtimeType) return false;
    if (signalRef != other.signalRef) return false;
    if (stateLabels.length != other.stateLabels.length) return false;
    for (final entry in stateLabels.entries) {
      if (other.stateLabels[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    signalRef,
    Object.hashAll(
      stateLabels.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() =>
      'FsmAnnotation(signal: $signalRef, labels: ${stateLabels.length})';
}
