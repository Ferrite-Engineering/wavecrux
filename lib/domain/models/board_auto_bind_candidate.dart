// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';

/// Confidence level of one [BoardAutoBindCandidate].
///
/// Mirrors the decoder auto-bind tier model but adds a dedicated
/// `vectorFanOut` tier that captures the killer board-specific
/// match: one wide vector signal binding all N members of a slot
/// family by bit index (LSB → slot 0).
enum BoardAutoBindConfidence {
  /// A single multi-bit signal was matched against an entire slot
  /// family (`led*`, `sw*`). Each member of the family is a
  /// per-bit binding into the same vector. Strongest possible match.
  vectorFanOut,

  /// One direct 1-bit signal was matched against one slot. The
  /// match was either an exact name match or a case-insensitive
  /// match.
  exactMatch,

  /// One signal was matched against one slot via the board alias
  /// table (`key` ↔ `btn`, `hex` ↔ `seg`, etc.).
  knownAlias,

  /// Levenshtein distance ≤ 2 fuzzy match against the slot name.
  fuzzyMatch,

  /// No plausible signal in the loaded design.
  noMatch,
}

/// One auto-bind candidate produced by [BoardAutoBindService] for a
/// single board slot.
///
/// For ordinary 1-to-1 matches [binding] is a vanilla
/// `StageSignalBinding(signalRef: …)`. For [BoardAutoBindConfidence.
/// vectorFanOut] matches the binding additionally carries a
/// `bitIndex` that picks the slot's bit out of the bound vector.
@immutable
class BoardAutoBindCandidate {
  const BoardAutoBindCandidate({
    required this.confidence,
    required this.matchReason,
    this.binding,
    this.familyPrefix,
  });

  /// Tier confidence for this candidate.
  final BoardAutoBindConfidence confidence;

  /// Short human-readable explanation of how the match was derived
  /// (used as a tooltip in the preview dialog).
  final String matchReason;

  /// The proposed binding, or null when no match was found.
  final StageSignalBinding? binding;

  /// When [confidence] is [BoardAutoBindConfidence.vectorFanOut],
  /// the slot family this candidate belongs to (e.g. `'led'`).
  /// Used by the preview dialog to group fan-out candidates under
  /// a single header.
  final String? familyPrefix;

  bool get isMatch => confidence != BoardAutoBindConfidence.noMatch;
}

/// Aggregate result of [BoardAutoBindService.computeBindings].
@immutable
class BoardAutoBindResult {
  const BoardAutoBindResult({required this.candidates});

  /// Map from slot name → candidate.
  final Map<String, BoardAutoBindCandidate> candidates;
}
