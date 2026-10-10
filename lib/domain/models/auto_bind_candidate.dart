// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// How confident the auto-bind algorithm is that the chosen [signalRef] is
/// the correct mapping for a given decoder binding.
///
/// Ordered from strongest to weakest signal of correctness; the UI uses this
/// to decide whether to highlight a candidate as a confident pick or a
/// guess that the user should review.
enum AutoBindConfidence {
  /// Exact suffix match in a shared scope and shared prefix
  /// (e.g. all of `m_axi_*` in `tb.dut`). Strongest signal of correctness.
  exactSuffix,

  /// Case-insensitive direct suffix match without shared prefix detection.
  caseInsensitive,

  /// Match via the built-in alias table (e.g. `mosi` ↔ `sdo`).
  knownAlias,

  /// Levenshtein-distance fuzzy match (≤ 2 edits) — weakest positive signal.
  fuzzyMatch,

  /// No plausible candidate was found.
  noMatch,
}

/// One auto-bind suggestion for a single decoder binding.
///
/// Produced by the auto-bind service and consumed by the decoder
/// configuration dialog so it can pre-fill bindings and indicate per-row
/// confidence to the user.
@immutable
class AutoBindCandidate {
  const AutoBindCandidate({
    required this.signalRef,
    required this.confidence,
    required this.matchReason,
    this.alternatives = const [],
    this.fullPath,
  });

  /// The chosen waveform signal reference (`Variable.signalRef`), or `null`
  /// when [confidence] is [AutoBindConfidence.noMatch].
  final String? signalRef;

  /// How strong the match is — see [AutoBindConfidence].
  final AutoBindConfidence confidence;

  /// Human-readable, English explanation of why this signal was chosen.
  ///
  /// Localized labels are the dialog UI's responsibility; this string is for
  /// developer logs, debug overlays, and tests.
  final String matchReason;

  /// Other plausible signal references the user could pick instead, capped at
  /// three entries by the service. Typically populated for fuzzy matches and
  /// ambiguous prefix scenarios.
  final List<String> alternatives;

  /// Hierarchical name (`Variable.fullPath`) of the signal that matched, or
  /// `null` when the candidate did not come from a name match (a manual
  /// binding passed through, or [AutoBindConfidence.noMatch]).
  ///
  /// Several names can share one [signalRef] when a waveform aliases them, so
  /// the reference alone cannot say which name the match was made on; this
  /// is what the preview shows.
  final String? fullPath;

  // ── copyWith ───────────────────────────────────────────────────────────────

  AutoBindCandidate copyWith({
    String? signalRef,
    AutoBindConfidence? confidence,
    String? matchReason,
    List<String>? alternatives,
    String? fullPath,
    bool clearSignalRef = false,
  }) => AutoBindCandidate(
    signalRef: clearSignalRef ? null : (signalRef ?? this.signalRef),
    confidence: confidence ?? this.confidence,
    matchReason: matchReason ?? this.matchReason,
    alternatives: alternatives ?? this.alternatives,
    fullPath: clearSignalRef ? null : (fullPath ?? this.fullPath),
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AutoBindCandidate) return false;
    if (signalRef != other.signalRef) return false;
    if (confidence != other.confidence) return false;
    if (matchReason != other.matchReason) return false;
    if (fullPath != other.fullPath) return false;
    if (alternatives.length != other.alternatives.length) return false;
    for (var i = 0; i < alternatives.length; i++) {
      if (alternatives[i] != other.alternatives[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    signalRef,
    confidence,
    matchReason,
    Object.hashAll(alternatives),
    fullPath,
  );

  @override
  String toString() =>
      'AutoBindCandidate(signalRef: $signalRef, '
      'confidence: $confidence, matchReason: $matchReason, '
      'alternatives: $alternatives, fullPath: $fullPath)';
}
