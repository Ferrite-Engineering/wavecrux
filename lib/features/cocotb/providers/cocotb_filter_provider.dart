// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/models/cocotb_filter_state.dart';

part 'cocotb_filter_provider.g.dart';

/// Filter state applied to the loaded cocotb log.
///
/// Independent from [cocotbLogProvider] so the filter persists when the log
/// is unloaded and reloaded. Use [clearAll] to reset to the no-filter
/// default.
@Riverpod(keepAlive: true)
class CocotbFilter extends _$CocotbFilter {
  @override
  CocotbFilterState build() => const CocotbFilterState();

  /// Restrict to a single test name. Pass `null` to show all tests.
  void setTestName(String? testName) {
    state = state.copyWith(testNameFilter: testName);
  }

  /// Toggles whether [severity] is included in the visible severity set.
  /// When the set becomes empty, all severities are visible by convention.
  void toggleSeverity(CocotbLogSeverity severity) {
    final next = Set<CocotbLogSeverity>.of(state.severityFilter);
    if (!next.add(severity)) {
      next.remove(severity);
    }
    state = state.copyWith(severityFilter: next);
  }

  /// Sets the keyword substring filter. Pass an empty string to disable.
  void setKeyword(String keyword) {
    state = state.copyWith(keywordFilter: keyword);
  }

  /// Resets to the unfiltered default.
  void clearAll() {
    state = const CocotbFilterState();
  }
}
