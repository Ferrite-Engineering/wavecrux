// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/signal_match.dart';

/// Summary counts derived from a [DiffResult].
@immutable
class DiffSummary {
  const DiffSummary({
    required this.matchedCount,
    required this.differentCount,
    required this.aOnlyCount,
    required this.bOnlyCount,
  });

  /// Number of signals present in both files (whether identical or different).
  final int matchedCount;

  /// Number of matched signals whose values differ in at least one time range.
  final int differentCount;

  /// Number of signals found only in file A.
  final int aOnlyCount;

  /// Number of signals found only in file B.
  final int bOnlyCount;

  /// Number of matched signals that are identical across the compared time range.
  int get identicalCount => matchedCount - differentCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiffSummary &&
          runtimeType == other.runtimeType &&
          matchedCount == other.matchedCount &&
          differentCount == other.differentCount &&
          aOnlyCount == other.aOnlyCount &&
          bOnlyCount == other.bOnlyCount;

  @override
  int get hashCode =>
      Object.hash(matchedCount, differentCount, aOnlyCount, bOnlyCount);

  @override
  String toString() =>
      'DiffSummary(matched: $matchedCount, '
      'different: $differentCount, aOnly: $aOnlyCount, bOnly: $bOnlyCount)';
}

/// The complete result of comparing two waveform files.
@immutable
class DiffResult {
  const DiffResult({
    required this.matchedSignals,
    required this.unmatchedA,
    required this.unmatchedB,
  });

  /// All signal pairs that were matched between file A and file B.
  ///
  /// Both identical and different pairs are included.  Sort by
  /// [SignalMatch.isDifferent] descending to show differences first.
  final List<SignalMatch> matchedSignals;

  /// Full hierarchical paths of signals found only in file A (no match in B).
  final List<String> unmatchedA;

  /// Full hierarchical paths of signals found only in file B (no match in A).
  final List<String> unmatchedB;

  /// Derived summary counts.
  DiffSummary get summary => DiffSummary(
    matchedCount: matchedSignals.length,
    differentCount: matchedSignals.where((m) => m.isDifferent).length,
    aOnlyCount: unmatchedA.length,
    bOnlyCount: unmatchedB.length,
  );

  DiffResult copyWith({
    List<SignalMatch>? matchedSignals,
    List<String>? unmatchedA,
    List<String>? unmatchedB,
  }) => DiffResult(
    matchedSignals: matchedSignals ?? this.matchedSignals,
    unmatchedA: unmatchedA ?? this.unmatchedA,
    unmatchedB: unmatchedB ?? this.unmatchedB,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiffResult &&
          runtimeType == other.runtimeType &&
          _listEqual(matchedSignals, other.matchedSignals) &&
          _listEqual(unmatchedA, other.unmatchedA) &&
          _listEqual(unmatchedB, other.unmatchedB);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(matchedSignals),
    Object.hashAll(unmatchedA),
    Object.hashAll(unmatchedB),
  );

  @override
  String toString() =>
      'DiffResult(matched: ${matchedSignals.length}, '
      'unmatchedA: ${unmatchedA.length}, unmatchedB: ${unmatchedB.length})';

  static bool _listEqual<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
