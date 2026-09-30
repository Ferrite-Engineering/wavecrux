// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/cocotb_log_entry.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_filter_provider.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';

part 'cocotb_filtered_entries_provider.g.dart';

/// Returns the loaded log's entries filtered by the active
/// [CocotbFilterState].
///
/// Filters combine with AND semantics: an entry must match every active
/// dimension. An empty filter for a dimension (`null` test, empty severity
/// set, empty keyword) means "no constraint" on that dimension.
///
/// When no log is loaded, returns an empty list.
@riverpod
List<CocotbLogEntry> cocotbFilteredEntries(Ref ref) {
  final log = ref.watch(cocotbLogProvider);
  if (log == null) return const [];

  final filter = ref.watch(cocotbFilterProvider);

  final keyword = filter.keywordFilter.trim().toLowerCase();
  final severities = filter.severityFilter;
  final testName = filter.testNameFilter;

  return log.entries
      .where((entry) {
        if (testName != null && entry.testName != testName) {
          return false;
        }
        if (severities.isNotEmpty && !severities.contains(entry.severity)) {
          return false;
        }
        if (keyword.isNotEmpty &&
            !entry.message.toLowerCase().contains(keyword)) {
          return false;
        }
        return true;
      })
      .toList(growable: false);
}
