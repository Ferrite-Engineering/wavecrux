// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/pattern_expression.dart';
import 'package:wavecrux/domain/models/pattern_match.dart';
import 'package:wavecrux/domain/models/time_range.dart';

/// Result returned by `PatternSearchService.search`.
///
/// Contains all [matches] (time regions where [expression] was true) within
/// [searchRange], along with the original expression for display purposes.
@immutable
class PatternSearchResult {
  const PatternSearchResult({
    required this.matches,
    required this.expression,
    required this.searchRange,
  });

  /// All non-overlapping match regions in ascending time order.
  final List<PatternMatch> matches;

  /// The expression that was evaluated.
  final PatternExpression expression;

  /// The time range over which the search was performed.
  final TimeRange searchRange;

  bool get hasMatches => matches.isNotEmpty;

  int get matchCount => matches.length;

  PatternSearchResult copyWith({
    List<PatternMatch>? matches,
    PatternExpression? expression,
    TimeRange? searchRange,
  }) => PatternSearchResult(
    matches: matches ?? List.of(this.matches),
    expression: expression ?? this.expression,
    searchRange: searchRange ?? this.searchRange,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PatternSearchResult &&
          runtimeType == other.runtimeType &&
          expression == other.expression &&
          searchRange == other.searchRange &&
          _listsEqual(matches, other.matches);

  @override
  int get hashCode => Object.hash(
    expression,
    searchRange,
    Object.hashAll(matches),
  );

  @override
  String toString() =>
      'PatternSearchResult(${matches.length} matches, range: $searchRange)';

  static bool _listsEqual(List<PatternMatch> a, List<PatternMatch> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
