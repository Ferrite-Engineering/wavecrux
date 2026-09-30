// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/cocotb_log_entry.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_filtered_entries_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';

part 'cocotb_visible_markers_provider.g.dart';

/// Returns only filtered entries whose [CocotbLogEntry.simTimeTicks] is
/// within the current visible time range.
///
/// Used by the timeline overlay to skip painting markers outside the
/// viewport. Recomputes whenever the filter, log, or zoom/pan state
/// changes.
///
/// Entries with no timestamp (continuation lines, tracebacks) are excluded
/// because they have no place on the timeline.
@riverpod
List<CocotbLogEntry> cocotbVisibleMarkers(Ref ref) {
  final entries = ref.watch(cocotbFilteredEntriesProvider);
  if (entries.isEmpty) return const [];

  final (start, end) = ref.watch(visibleTimeRangeProvider);
  if (end <= start) return const [];

  return entries
      .where((entry) {
        final ticks = entry.simTimeTicks;
        if (ticks == null) return false;
        return ticks >= start && ticks <= end;
      })
      .toList(growable: false);
}
