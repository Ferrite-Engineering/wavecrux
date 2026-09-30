// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_async/crux_async.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_filter_provider.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_filtered_entries_provider.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_log_entry_row.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_severity_chips.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Dockable panel showing the parsed cocotb log entries with filters.
///
/// Layout:
///   [header: title + count badge + clear-log button]
///   [filter bar: test-name dropdown · severity chips · keyword field]
///   [scrollable list of CocotbLogEntryRow]
///
/// The keyword field debounces input by 300 ms before pushing the filter
/// state, so wide-character typists don't trigger a recompute on every
/// keystroke.
///
/// The panel is layout-agnostic — it accepts whatever constraints the
/// parent gives it and adapts. Hosted in the bottom pane on desktop /
/// tablet, and as a modal bottom sheet on phone.
class CocotbLogPanel extends ConsumerStatefulWidget {
  const CocotbLogPanel({super.key});

  @override
  ConsumerState<CocotbLogPanel> createState() => _CocotbLogPanelState();
}

class _CocotbLogPanelState extends ConsumerState<CocotbLogPanel> {
  final _keywordController = TextEditingController();
  final _keywordDebounce = Debouncer(
    duration: const Duration(milliseconds: 300),
  );

  @override
  void initState() {
    super.initState();
    // Sync the controller with any pre-existing filter state (e.g. when
    // the panel re-opens after being hidden).
    final initial = ref.read(cocotbFilterProvider).keywordFilter;
    if (initial.isNotEmpty) _keywordController.text = initial;
  }

  @override
  void dispose() {
    _keywordDebounce.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  void _onKeywordChanged(String value) {
    _keywordDebounce.run(
      () => ref.read(cocotbFilterProvider.notifier).setKeyword(value),
    );
  }

  /// Empties the keyword field and drops any keystroke still waiting out the
  /// debounce. Without the cancel, a keystroke typed just before a clear
  /// lands after it and puts the keyword back.
  void _discardKeyword() {
    _keywordDebounce.cancel();
    _keywordController.clear();
  }

  /// The keyword field's own clear button: takes effect at once rather than
  /// after the debounce, since there is no typing burst to wait out.
  void _clearKeyword() {
    _discardKeyword();
    ref.read(cocotbFilterProvider.notifier).setKeyword('');
  }

  /// The header's clear-filter button: every filter goes, and the keyword
  /// field shows the empty keyword the filter now holds.
  void _clearFilter() {
    _discardKeyword();
    ref.read(cocotbFilterProvider.notifier).clearAll();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final log = ref.watch(cocotbLogProvider);

    if (log == null) {
      return CruxPanelEmptyState(message: l10n.cocotbLogEmpty);
    }

    final filter = ref.watch(cocotbFilterProvider);
    final filterNotifier = ref.read(cocotbFilterProvider.notifier);
    final filtered = ref.watch(cocotbFilteredEntriesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          totalCount: log.entries.length,
          filteredCount: filtered.length,
          onClearLog: () => ref.read(cocotbLogProvider.notifier).clear(),
          onClearFilter: _clearFilter,
          l10n: l10n,
        ),
        const Divider(height: 1),
        _FilterBar(
          testNames: log.testNames,
          selectedTestName: filter.testNameFilter,
          onTestNameChanged: filterNotifier.setTestName,
          keywordController: _keywordController,
          onKeywordChanged: _onKeywordChanged,
          onKeywordCleared: _clearKeyword,
          l10n: l10n,
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? CruxPanelEmptyState(message: l10n.cocotbLogFilteredEmpty)
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) =>
                      CocotbLogEntryRow(entry: filtered[index]),
                ),
        ),
      ],
    );
  }
}

// ── _Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.totalCount,
    required this.filteredCount,
    required this.onClearLog,
    required this.onClearFilter,
    required this.l10n,
  });

  final int totalCount;
  final int filteredCount;
  final VoidCallback onClearLog;
  final VoidCallback onClearFilter;
  final L10N l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFiltered = filteredCount != totalCount;
    final countLabel = isFiltered
        ? l10n.cocotbLogFilteredCount(filteredCount, totalCount)
        : l10n.cocotbLogEntryCount(totalCount);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Text(
            l10n.cocotbLogPanelTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              countLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Spacer(),
          if (isFiltered)
            Tooltip(
              message: l10n.cocotbLogClearFilter,
              child: IconButton(
                icon: const Icon(Icons.filter_alt_off, size: 18),
                onPressed: onClearFilter,
                visualDensity: VisualDensity.compact,
              ),
            ),
          Tooltip(
            message: l10n.cocotbLogClearAction,
            child: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onClearLog,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _FilterBar ───────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.testNames,
    required this.selectedTestName,
    required this.onTestNameChanged,
    required this.keywordController,
    required this.onKeywordChanged,
    required this.onKeywordCleared,
    required this.l10n,
  });

  final List<String> testNames;
  final String? selectedTestName;
  final ValueChanged<String?> onTestNameChanged;
  final TextEditingController keywordController;
  final ValueChanged<String> onKeywordChanged;
  final VoidCallback onKeywordCleared;
  final L10N l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Test name dropdown.
          DropdownButton<String?>(
            value: selectedTestName,
            isDense: true,
            hint: Text(l10n.cocotbLogAllTests),
            items: <DropdownMenuItem<String?>>[
              DropdownMenuItem<String?>(
                child: Text(l10n.cocotbLogAllTests),
              ),
              for (final name in testNames)
                DropdownMenuItem<String?>(
                  value: name,
                  child: Text(name),
                ),
            ],
            onChanged: onTestNameChanged,
          ),
          // Severity chips.
          const CocotbSeverityChips(),
          // Keyword search.
          SizedBox(
            width: 200,
            height: 32,
            child: TextField(
              controller: keywordController,
              decoration: InputDecoration(
                hintText: l10n.cocotbLogKeywordHint,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search, size: 16),
                suffixIcon: keywordController.text.isNotEmpty
                    ? IconButton(
                        tooltip: l10n.cocotbLogClearKeywordTooltip,
                        icon: const Icon(Icons.clear, size: 16),
                        padding: EdgeInsets.zero,
                        onPressed: onKeywordCleared,
                      )
                    : null,
              ),
              onChanged: onKeywordChanged,
            ),
          ),
        ],
      ),
    );
  }
}
