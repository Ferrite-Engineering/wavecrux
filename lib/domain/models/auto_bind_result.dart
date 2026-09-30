// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/auto_bind_candidate.dart';

/// Aggregate result of running the decoder auto-bind algorithm for one
/// [DecoderDefinition] against the loaded waveform.
///
/// The dialog UI consumes this to pre-fill the binding picker and to
/// surface ambiguity warnings ("two equally viable AXI buses found").
@immutable
class AutoBindResult {
  const AutoBindResult({
    required this.candidates,
    this.detectedPrefix,
    this.detectedScopePath,
    this.ambiguousPrefixes = const [],
  });

  /// One [AutoBindCandidate] per decoder binding, keyed by the binding's
  /// logical [name] (e.g. `'aclk'`, `'awvalid'`, `'mosi'`).
  ///
  /// Bindings that the user had already manually bound (passed in via
  /// `existingBindings`) get a passthrough candidate with confidence
  /// [AutoBindConfidence.exactSuffix] and `matchReason: 'manually bound'`.
  final Map<String, AutoBindCandidate> candidates;

  /// Common signal prefix detected by Tier A (e.g. `'m_axi_'`, `'S00_AXI_'`),
  /// or `null` if no shared prefix could be inferred.
  ///
  /// Useful for the dialog UI — it can show "Detected bus: m_axi_" near the
  /// auto-bind button so the user can verify the algorithm picked the right
  /// bus on a multi-bus design.
  final String? detectedPrefix;

  /// Common scope path detected by Tier A (e.g. `'tb.dut'`), or `null`.
  final String? detectedScopePath;

  /// When more than one (scope, prefix) group scored within ~20% of the
  /// winner, those rival prefixes are listed here so the UI can warn the
  /// user that the auto-bind result may have picked the wrong bus.
  final List<String> ambiguousPrefixes;

  // ── computed ───────────────────────────────────────────────────────────────

  /// Number of candidates resolved with confidence [AutoBindConfidence.exactSuffix].
  ///
  /// This is the strongest-confidence bucket; UIs typically treat ≥ 80% of
  /// bindings landing here as a "trust the auto-bind" signal.
  int get exactMatchCount {
    var count = 0;
    for (final candidate in candidates.values) {
      if (candidate.confidence == AutoBindConfidence.exactSuffix) count++;
    }
    return count;
  }

  /// Whether the algorithm flagged competing bus prefixes that the user
  /// should disambiguate manually.
  bool get hasAmbiguity => ambiguousPrefixes.isNotEmpty;

  /// Whether no candidates were produced at all (e.g. empty available
  /// signals or no required bindings on the decoder).
  bool get isEmpty => candidates.isEmpty;

  // ── copyWith ───────────────────────────────────────────────────────────────

  AutoBindResult copyWith({
    Map<String, AutoBindCandidate>? candidates,
    String? detectedPrefix,
    String? detectedScopePath,
    List<String>? ambiguousPrefixes,
    bool clearDetectedPrefix = false,
    bool clearDetectedScopePath = false,
  }) => AutoBindResult(
    candidates: candidates ?? this.candidates,
    detectedPrefix: clearDetectedPrefix
        ? null
        : (detectedPrefix ?? this.detectedPrefix),
    detectedScopePath: clearDetectedScopePath
        ? null
        : (detectedScopePath ?? this.detectedScopePath),
    ambiguousPrefixes: ambiguousPrefixes ?? this.ambiguousPrefixes,
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AutoBindResult) return false;
    if (detectedPrefix != other.detectedPrefix) return false;
    if (detectedScopePath != other.detectedScopePath) return false;
    if (candidates.length != other.candidates.length) return false;
    for (final key in candidates.keys) {
      if (!other.candidates.containsKey(key)) return false;
      if (candidates[key] != other.candidates[key]) return false;
    }
    if (ambiguousPrefixes.length != other.ambiguousPrefixes.length) {
      return false;
    }
    for (var i = 0; i < ambiguousPrefixes.length; i++) {
      if (ambiguousPrefixes[i] != other.ambiguousPrefixes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    detectedPrefix,
    detectedScopePath,
    Object.hashAll(
      candidates.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAll(ambiguousPrefixes),
  );

  @override
  String toString() =>
      'AutoBindResult(candidates: ${candidates.length}, '
      'detectedPrefix: $detectedPrefix, '
      'detectedScopePath: $detectedScopePath, '
      'ambiguousPrefixes: $ambiguousPrefixes)';
}
