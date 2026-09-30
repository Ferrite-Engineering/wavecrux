// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/search_mode.dart';
import 'package:wavecrux/domain/enums/signal_direction.dart';
import 'package:wavecrux/domain/enums/signal_type_category.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/features/search/providers/search_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/signal_query/signal_search_service.dart';

/// Modal signal search dialog opened via Ctrl+F / Cmd+F.
///
/// Provides real-time filtering by name (substring or glob), type category,
/// bit-width range, and scope-path prefix. Click a result to add it to the
/// waveform viewer; Ctrl/Cmd+click (or tap the checkbox) to multi-select,
/// then use "Add N Signals" for bulk add.
///
/// Call [SignalSearchDialog.show] rather than constructing directly.
class SignalSearchDialog extends ConsumerStatefulWidget {
  const SignalSearchDialog({super.key});

  /// Opens the dialog, resetting the filter to a clean state first.
  ///
  /// Pass [tabContainer] so that [hierarchyProvider] and
  /// [signalGroupsProvider] resolve from the active tab's
  /// [ProviderContainer] rather than the root container. Dialogs are rendered
  /// outside the per-tab [UncontrolledProviderScope] (their context is a child
  /// of the Navigator, which sits above the tab scope), so provider reads
  /// inside the dialog always resolve from the root container where no file is
  /// loaded — passing the container bypasses this Navigator-scope gap.
  static Future<void> show(
    BuildContext context, {
    ProviderContainer? tabContainer,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) {
        const dialog = SignalSearchDialog();
        return tabContainer != null
            ? UncontrolledProviderScope(container: tabContainer, child: dialog)
            : dialog;
      },
    );
  }

  @override
  ConsumerState<SignalSearchDialog> createState() => _SignalSearchDialogState();
}

class _SignalSearchDialogState extends ConsumerState<SignalSearchDialog> {
  final _searchController = TextEditingController();
  final _minWidthController = TextEditingController();
  final _maxWidthController = TextEditingController();
  final _scopeController = TextEditingController();

  /// Keyed by `Variable.fullPath` (row identity), never signalRef (data
  /// identity): FST files alias one underlying signal into many hierarchy
  /// rows that all share a signalRef, so a ref-keyed set checked every alias
  /// at once and bulk-added all of them. Mirrors the tree's selection keying.
  final _selectedPaths = <String>{};
  var _showAdvancedFilters = false;

  /// Whether `search.used` has already been recorded for this dialog session.
  var _recordedSearchUsed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(searchDialogFilterProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _minWidthController.dispose();
    _maxWidthController.dispose();
    _scopeController.dispose();
    super.dispose();
  }

  void _toggleSelection(String fullPath) {
    setState(() {
      if (_selectedPaths.contains(fullPath)) {
        _selectedPaths.remove(fullPath);
      } else {
        _selectedPaths.add(fullPath);
      }
    });
  }

  void _addResult(SearchResult result) {
    ref.read(signalGroupsProvider.notifier).addSignal(result.variable);
    _recordSearchUsed();
  }

  void _addSelected(List<SearchResult> results) {
    final toAdd = results
        .where((r) => _selectedPaths.contains(r.variable.fullPath))
        .map((r) => r.variable)
        .toList();
    ref.read(signalGroupsProvider.notifier).addSignals(toAdd);
    setState(_selectedPaths.clear);
    _recordSearchUsed();
  }

  void _addAll(List<SearchResult> results) {
    ref
        .read(signalGroupsProvider.notifier)
        .addSignals(results.map((r) => r.variable).toList());
    _recordSearchUsed();
  }

  /// Records `search.used` the first time this dialog session puts a result on
  /// the canvas.
  ///
  /// Not on open, and not on keystroke. Opening is an attempt — and at open the
  /// filter has just been reset to [SearchMode.substring], so an open-time
  /// record could never report `signal_glob` and the mode dimension would be a
  /// constant. Committing a result is the point at which the search did its
  /// job, and the effective mode is known. Once per dialog session, so adding
  /// six signals one at a time is one use of search, not six.
  void _recordSearchUsed() {
    if (_recordedSearchUsed) return;
    _recordedSearchUsed = true;
    final mode = ref.read(searchDialogFilterProvider).mode;
    ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'search.used',
            properties: <String, Object?>{
              // Prefixed rather than bare, because `pattern` search shares this
              // event and `substring` alone would not say which search it was.
              'mode': 'signal_${telemetryEnumToken(mode)}',
            },
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final filter = ref.watch(searchDialogFilterProvider);
    final results = ref.watch(searchResultsProvider);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, minWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogHeader(l10n: l10n),
            const Divider(height: 1),
            _SearchBar(
              l10n: l10n,
              searchController: _searchController,
              filter: filter,
            ),
            _TypeFilterRow(
              l10n: l10n,
              filter: filter,
              showAdvanced: _showAdvancedFilters,
              onToggleAdvanced: () =>
                  setState(() => _showAdvancedFilters = !_showAdvancedFilters),
            ),
            if (_showAdvancedFilters)
              _AdvancedFilterRow(
                l10n: l10n,
                filter: filter,
                minWidthController: _minWidthController,
                maxWidthController: _maxWidthController,
                scopeController: _scopeController,
              ),
            const Divider(height: 1),
            _ResultCountBar(l10n: l10n, count: results.length),
            Flexible(
              child: _ResultsList(
                l10n: l10n,
                results: results,
                selectedPaths: _selectedPaths,
                filter: filter,
                onTap: _addResult,
                onToggleSelect: _toggleSelection,
              ),
            ),
            const Divider(height: 1),
            _ActionRow(
              l10n: l10n,
              results: results,
              selectedCount: _selectedPaths.length,
              onAddSelected: () => _addSelected(results),
              onAddAll: () => _addAll(results),
              onClose: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.l10n});

  final L10N l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          const Icon(Icons.search, size: 20),
          const SizedBox(width: 10),
          Text(
            l10n.searchDialogTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Search bar ────────────────────────────────────────────────────────────────

class _SearchBar extends ConsumerWidget {
  const _SearchBar({
    required this.l10n,
    required this.searchController,
    required this.filter,
  });

  final L10N l10n;
  final TextEditingController searchController;
  final SearchDialogFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchController,
              autofocus: true,
              onChanged: (v) =>
                  ref.read(searchDialogFilterProvider.notifier).setQuery(v),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'JetBrainsMono',
                fontFamilyFallback: const [
                  'FiraCode',
                  'Courier New',
                  'monospace',
                ],
              ),
              decoration: InputDecoration(
                hintText: l10n.searchDialogSearchHint,
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                prefixIcon: const Icon(Icons.search, size: 18),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                suffixIcon: filter.query.isNotEmpty
                    ? IconButton(
                        tooltip: l10n.signalSearchClearQueryTooltip,
                        icon: const Icon(Icons.clear, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: () {
                          searchController.clear();
                          ref
                              .read(searchDialogFilterProvider.notifier)
                              .setQuery('');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<SearchMode>(
            segments: [
              ButtonSegment(
                value: SearchMode.substring,
                label: Text(l10n.searchDialogModeSubstring),
              ),
              ButtonSegment(
                value: SearchMode.glob,
                label: Text(l10n.searchDialogModeGlob),
              ),
            ],
            selected: {filter.mode},
            onSelectionChanged: (sel) => ref
                .read(searchDialogFilterProvider.notifier)
                .setMode(sel.first),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Type + direction filter row ───────────────────────────────────────────────

class _TypeFilterRow extends ConsumerWidget {
  const _TypeFilterRow({
    required this.l10n,
    required this.filter,
    required this.showAdvanced,
    required this.onToggleAdvanced,
  });

  final L10N l10n;
  final SearchDialogFilter filter;
  final bool showAdvanced;
  final VoidCallback onToggleAdvanced;

  String _categoryLabel(SignalTypeCategory cat) => switch (cat) {
    SignalTypeCategory.wire => l10n.searchDialogTypeWire,
    SignalTypeCategory.reg => l10n.searchDialogTypeReg,
    SignalTypeCategory.integer => l10n.searchDialogTypeInteger,
    SignalTypeCategory.real => l10n.searchDialogTypeReal,
    SignalTypeCategory.port => l10n.searchDialogTypePort,
  };

  String _directionLabel(SignalDirection dir) => switch (dir) {
    SignalDirection.input => l10n.searchDialogDirectionInput,
    SignalDirection.output => l10n.searchDialogDirectionOutput,
    SignalDirection.inout => l10n.searchDialogDirectionInout,
    SignalDirection.unknown => '',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(searchDialogFilterProvider.notifier);
    final chipStyle = Theme.of(context).textTheme.labelSmall;
    const chipPadding = EdgeInsets.symmetric(horizontal: 4);
    const chipDensity = VisualDensity.compact;
    const chipTarget = MaterialTapTargetSize.shrinkWrap;

    final typeChips = Wrap(
      spacing: 6,
      runSpacing: 4,
      children: SignalTypeCategory.values.map((cat) {
        final isSelected = filter.selectedCategories.contains(cat);
        return FilterChip(
          label: Text(_categoryLabel(cat)),
          selected: isSelected,
          onSelected: (_) => notifier.toggleCategory(cat),
          visualDensity: chipDensity,
          materialTapTargetSize: chipTarget,
          padding: chipPadding,
          labelStyle: chipStyle,
        );
      }).toList(),
    );

    // Only show the 3 meaningful direction values in the UI (skip unknown).
    final directionValues = [
      SignalDirection.input,
      SignalDirection.output,
      SignalDirection.inout,
    ];

    final directionChips = Wrap(
      spacing: 6,
      runSpacing: 4,
      children: directionValues.map((dir) {
        final isSelected = filter.selectedDirections.contains(dir);
        return FilterChip(
          label: Text(_directionLabel(dir)),
          selected: isSelected,
          onSelected: (_) => notifier.toggleDirection(dir),
          visualDensity: chipDensity,
          materialTapTargetSize: chipTarget,
          padding: chipPadding,
          labelStyle: chipStyle,
          avatar: Icon(
            _iconForDirection(dir),
            size: 12,
          ),
        );
      }).toList(),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                typeChips,
                const SizedBox(height: 4),
                directionChips,
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              showAdvanced ? Icons.expand_less : Icons.tune,
              size: 18,
            ),
            tooltip: l10n.searchDialogFiltersLabel,
            onPressed: onToggleAdvanced,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          if (!filter.isDefault)
            TextButton(
              onPressed: () {
                ref.read(searchDialogFilterProvider.notifier).reset();
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                l10n.searchDialogClearFilters,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Advanced filters ──────────────────────────────────────────────────────────

class _AdvancedFilterRow extends ConsumerWidget {
  const _AdvancedFilterRow({
    required this.l10n,
    required this.filter,
    required this.minWidthController,
    required this.maxWidthController,
    required this.scopeController,
  });

  final L10N l10n;
  final SearchDialogFilter filter;
  final TextEditingController minWidthController;
  final TextEditingController maxWidthController;
  final TextEditingController scopeController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(searchDialogFilterProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: TextField(
              controller: minWidthController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: theme.textTheme.bodySmall,
              onChanged: (v) => notifier.setMinBitWidth(int.tryParse(v)),
              decoration: InputDecoration(
                labelText: l10n.searchDialogWidthMin,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: TextField(
              controller: maxWidthController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: theme.textTheme.bodySmall,
              onChanged: (v) => notifier.setMaxBitWidth(int.tryParse(v)),
              decoration: InputDecoration(
                labelText: l10n.searchDialogWidthMax,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: scopeController,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'JetBrainsMono',
                fontFamilyFallback: const [
                  'FiraCode',
                  'Courier New',
                  'monospace',
                ],
              ),
              onChanged: notifier.setScopePath,
              decoration: InputDecoration(
                hintText: l10n.searchDialogScopeHint,
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Result count bar ──────────────────────────────────────────────────────────

class _ResultCountBar extends StatelessWidget {
  const _ResultCountBar({required this.l10n, required this.count});

  final L10N l10n;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          count == 0
              ? l10n.searchDialogNoResults
              : l10n.searchDialogResultCount(count),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

// ── Results list ──────────────────────────────────────────────────────────────

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.l10n,
    required this.results,
    required this.selectedPaths,
    required this.filter,
    required this.onTap,
    required this.onToggleSelect,
  });

  final L10N l10n;
  final List<SearchResult> results;
  final Set<String> selectedPaths;
  final SearchDialogFilter filter;
  final void Function(SearchResult) onTap;
  final void Function(String fullPath) onToggleSelect;

  @override
  Widget build(BuildContext context) {
    // Keep the results region a fixed height in both states so the dialog
    // does not grow/shrink as the match count changes. A bare Center under the
    // Flexible's bounded constraints would expand to fill the remaining dialog
    // height, ballooning the empty state — pin it to the same 320 dp as the
    // populated list instead.
    if (results.isEmpty) {
      return SizedBox(
        height: 320,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.searchDialogNoResults,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
      );
    }

    // A traversal group, so the rows sort as one block. Ungrouped, the
    // window-wide reading order placed the rows the list builds below its
    // visible edge after the Add All / Close buttons beside them.
    return SizedBox(
      height: 320,
      child: FocusTraversalGroup(
        child: ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: results.length,
          itemBuilder: (context, i) {
            final result = results[i];
            final isSelected = selectedPaths.contains(result.variable.fullPath);
            return _ResultRow(
              result: result,
              isSelected: isSelected,
              filter: filter,
              onTap: () {
                final isCtrl =
                    HardwareKeyboard.instance.isControlPressed ||
                    HardwareKeyboard.instance.isMetaPressed;
                if (isCtrl) {
                  onToggleSelect(result.variable.fullPath);
                } else {
                  onTap(result);
                }
              },
              onToggleSelect: () => onToggleSelect(result.variable.fullPath),
            );
          },
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.result,
    required this.isSelected,
    required this.filter,
    required this.onTap,
    required this.onToggleSelect,
  });

  final SearchResult result;
  final bool isSelected;
  final SearchDialogFilter filter;
  final VoidCallback onTap;
  final VoidCallback onToggleSelect;

  static const double _kRowHeight = 36;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = result.variable;

    final bgColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : Colors.transparent;

    // One node per row: the checkbox, named after the signal. The row's own
    // tap would otherwise add a second tap action, which stops Flutter merging
    // the texts into the checkbox, so a screen reader heard a group of loose
    // text followed by an unlabelled check box. The texts are the same words
    // as the label, so they are excluded rather than read twice.
    final semanticLabel = <String>[
      v.name,
      v.scopePath,
      if (v.bitWidth != null && v.bitWidth! > 1) '[${v.bitWidth! - 1}:0]',
    ].join(', ');

    return GestureDetector(
      onTap: onTap,
      excludeFromSemantics: true,
      child: Container(
        height: _kRowHeight,
        color: bgColor,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Checkbox(
                value: isSelected,
                onChanged: (_) => onToggleSelect(),
                semanticLabel: semanticLabel,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _iconForVarType(v.varType),
              size: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: ExcludeSemantics(
                child: _HighlightedName(
                  name: v.name,
                  result: result,
                  baseStyle: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'JetBrainsMono',
                    fontFamilyFallback: const [
                      'FiraCode',
                      'Courier New',
                      'monospace',
                    ],
                  ),
                  highlightColor: theme.colorScheme.primary.withValues(
                    alpha: 0.28,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: ExcludeSemantics(
                child: Text(
                  v.scopePath,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    fontFamily: 'JetBrainsMono',
                    fontFamilyFallback: const [
                      'FiraCode',
                      'Courier New',
                      'monospace',
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ),
            if (v.bitWidth != null && v.bitWidth! > 1) ...[
              const SizedBox(width: 6),
              ExcludeSemantics(
                child: Text(
                  '[${v.bitWidth! - 1}:0]',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.40),
                    fontSize: 10,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

// ── Highlighted name ──────────────────────────────────────────────────────────

class _HighlightedName extends StatelessWidget {
  const _HighlightedName({
    required this.name,
    required this.result,
    required this.baseStyle,
    required this.highlightColor,
  });

  final String name;
  final SearchResult result;
  final TextStyle? baseStyle;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    if (!result.hasHighlight) {
      return Text(name, style: baseStyle, overflow: TextOverflow.ellipsis);
    }
    final (start, end) = result.nameMatchRange!;
    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: baseStyle,
        children: [
          if (start > 0) TextSpan(text: name.substring(0, start)),
          TextSpan(
            text: name.substring(start, end),
            style: baseStyle?.copyWith(
              backgroundColor: highlightColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (end < name.length) TextSpan(text: name.substring(end)),
        ],
      ),
    );
  }
}

// ── Action row ────────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.l10n,
    required this.results,
    required this.selectedCount,
    required this.onAddSelected,
    required this.onAddAll,
    required this.onClose,
  });

  final L10N l10n;
  final List<SearchResult> results;
  final int selectedCount;
  final VoidCallback onAddSelected;
  final VoidCallback onAddAll;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          if (results.isNotEmpty) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.searchDialogAddAll),
              onPressed: onAddAll,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (selectedCount > 0) ...[
            FilledButton.icon(
              icon: const Icon(Icons.playlist_add, size: 16),
              label: Text(l10n.searchDialogAddSelected(selectedCount)),
              onPressed: onAddSelected,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
          ],
          const Spacer(),
          TextButton(
            onPressed: onClose,
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

IconData _iconForDirection(SignalDirection dir) => switch (dir) {
  SignalDirection.input => Icons.arrow_downward,
  SignalDirection.output => Icons.arrow_upward,
  SignalDirection.inout => Icons.swap_vert,
  SignalDirection.unknown => Icons.help_outline,
};

IconData _iconForVarType(VarType varType) => switch (varType) {
  VarType.real ||
  VarType.realTime ||
  VarType.svShortReal ||
  VarType.realParameter => Icons.show_chart,
  VarType.integer ||
  VarType.svInt ||
  VarType.svShortInt ||
  VarType.svLongInt ||
  VarType.svByte => Icons.tag,
  VarType.event || VarType.eventParameter => Icons.flash_on,
  VarType.string => Icons.text_fields,
  VarType.parameter => Icons.settings,
  VarType.port => Icons.input,
  _ => Icons.graphic_eq,
};
