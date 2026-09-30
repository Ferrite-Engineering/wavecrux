// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';

/// Filter state applied to a loaded [CocotbLogFile].
///
/// Combined with AND semantics by `cocotbFilteredEntriesProvider`: an entry
/// must satisfy *every* active filter to remain visible. An empty
/// [severityFilter] set or a `null` [testNameFilter] / empty [keywordFilter]
/// each mean "no constraint on that dimension".
@immutable
class CocotbFilterState {
  const CocotbFilterState({
    this.testNameFilter,
    this.severityFilter = const {},
    this.keywordFilter = '',
  });

  /// Restrict entries to a specific test by name. `null` means show all tests.
  final String? testNameFilter;

  /// Restrict entries to the given severity levels. An empty set means show
  /// all severities.
  final Set<CocotbLogSeverity> severityFilter;

  /// Case-insensitive substring matched against the entry message. Empty
  /// string disables the keyword filter.
  final String keywordFilter;

  CocotbFilterState copyWith({
    Object? testNameFilter = _unset,
    Set<CocotbLogSeverity>? severityFilter,
    String? keywordFilter,
  }) {
    return CocotbFilterState(
      testNameFilter: testNameFilter == _unset
          ? this.testNameFilter
          : testNameFilter as String?,
      severityFilter: severityFilter ?? this.severityFilter,
      keywordFilter: keywordFilter ?? this.keywordFilter,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CocotbFilterState) return false;
    if (testNameFilter != other.testNameFilter ||
        keywordFilter != other.keywordFilter) {
      return false;
    }
    if (severityFilter.length != other.severityFilter.length) return false;
    for (final s in severityFilter) {
      if (!other.severityFilter.contains(s)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    testNameFilter,
    keywordFilter,
    Object.hashAllUnordered(severityFilter),
  );

  @override
  String toString() =>
      'CocotbFilterState('
      'testName: ${testNameFilter ?? '—'}, '
      'severities: ${severityFilter.map((s) => s.displayLabel).join(',')}, '
      'keyword: "$keywordFilter")';
}

const _unset = Object();
