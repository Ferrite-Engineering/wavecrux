// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/help_urls.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/pattern_expression.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/signal_query/pattern_search_service.dart';
import 'package:wavecrux/shared/widgets/help_link.dart';

// ── dialog-local enums ────────────────────────────────────────────────────────

enum _DialogMode { builder, expression }

enum _TimeRangeMode { visible, full, custom }

// ── mutable row model (local dialog state only) ───────────────────────────────

class _ConditionRow {
  _ConditionRow();

  bool negated = false;
  String? signalRef;
  ConditionOperator operator = ConditionOperator.eq;
  String value = '';
}

// ── PatternSearchDialog ───────────────────────────────────────────────────────

/// Modal dialog for building and running a multi-signal pattern search.
///
/// Shows either a graphical condition builder (Builder mode) or a raw
/// expression text field (Expression mode).  On submit the dialog dispatches
/// to [PatternSearchNotifier.search] and pops.
class PatternSearchDialog extends ConsumerStatefulWidget {
  const PatternSearchDialog({super.key});

  /// Shows the dialog modally.
  ///
  /// Pass [tabContainer] so the dialog's reads of the per-tab
  /// `waveformSourceProvider` / `waveformIsLoadedProvider` (and its dispatch to
  /// the per-tab `PatternSearchNotifier`) resolve against the active tab. The
  /// dialog is pushed by the root navigator, outside the per-tab
  /// [UncontrolledProviderScope], so without this it reads the empty root scope
  /// and behaves as if no file were loaded.
  static Future<void> show(
    BuildContext context, {
    ProviderContainer? tabContainer,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) {
        const dialog = PatternSearchDialog();
        return tabContainer != null
            ? UncontrolledProviderScope(container: tabContainer, child: dialog)
            : dialog;
      },
    );
  }

  @override
  ConsumerState<PatternSearchDialog> createState() =>
      _PatternSearchDialogState();
}

class _PatternSearchDialogState extends ConsumerState<PatternSearchDialog> {
  _DialogMode _mode = _DialogMode.builder;
  _TimeRangeMode _timeRange = _TimeRangeMode.visible;

  // Builder state — at least one row is always present.
  final List<_ConditionRow> _rows = [_ConditionRow()];

  // One connector bool per gap between rows (length = rows.length - 1).
  // true → AND, false → OR.
  final List<bool> _connectorIsAnd = [];

  // Advanced mode raw expression input.
  final TextEditingController _expressionController = TextEditingController();

  // Custom time range inputs.
  final TextEditingController _customStartController = TextEditingController();
  final TextEditingController _customEndController = TextEditingController();

  // Validation error displayed inside the dialog.
  String? _validationError;

  @override
  void dispose() {
    _expressionController.dispose();
    _customStartController.dispose();
    _customEndController.dispose();
    super.dispose();
  }

  // ── row management ────────────────────────────────────────────────────────────

  void _addRow() {
    setState(() {
      _rows.add(_ConditionRow());
      _connectorIsAnd.add(true);
      _validationError = null;
    });
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows.removeAt(index);
      // Remove the connector that was immediately after this row (or before, if
      // it was the last row).
      if (_connectorIsAnd.isNotEmpty) {
        _connectorIsAnd.removeAt(
          index < _connectorIsAnd.length ? index : _connectorIsAnd.length - 1,
        );
      }
      _validationError = null;
    });
  }

  // ── search dispatch ───────────────────────────────────────────────────────────

  Future<void> _runSearch() async {
    final source = ref.read(waveformSourceProvider).value;
    if (source == null) return;

    PatternExpression expression;
    try {
      expression = _buildExpression();
    } on FormatException catch (e) {
      setState(() => _validationError = e.message);
      return;
    }

    final (searchStart, searchEnd) = _resolveTimeRange(source);

    if (!mounted) return;
    Navigator.of(context).pop();

    await ref
        .read(patternSearchProvider.notifier)
        .search(expression, searchStart, searchEnd);
  }

  PatternExpression _buildExpression() {
    if (_mode == _DialogMode.expression) {
      final text = _expressionController.text.trim();
      if (text.isEmpty) {
        throw const FormatException('Expression must not be empty');
      }
      return const PatternSearchService().parseExpression(text);
    }

    // Builder mode — validate each row.
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      if (row.signalRef == null || row.signalRef!.isEmpty) {
        throw FormatException('Row ${i + 1}: a signal must be selected');
      }
      final v = row.value.trim();
      if (v.isEmpty) {
        throw FormatException('Row ${i + 1}: value must not be empty');
      }
      if (!_isValidNumeric(v)) {
        throw FormatException('Row ${i + 1}: invalid numeric value "$v"');
      }
    }

    // Build the expression tree left-to-right.
    var expr = _rowToCondition(_rows[0]);
    for (var i = 1; i < _rows.length; i++) {
      final right = _rowToCondition(_rows[i]);
      final useAnd = i - 1 >= _connectorIsAnd.length || _connectorIsAnd[i - 1];
      expr = useAnd
          ? AndExpression(left: expr, right: right)
          : OrExpression(left: expr, right: right);
    }
    return expr;
  }

  PatternExpression _rowToCondition(_ConditionRow row) {
    final cond = SignalCondition(
      signalPath: row.signalRef!,
      operator: row.operator,
      value: row.value.trim(),
    );
    return row.negated ? NotExpression(operand: cond) : cond;
  }

  (int, int) _resolveTimeRange(WaveformDataSource source) {
    switch (_timeRange) {
      case _TimeRangeMode.full:
        return (source.startTime, source.endTime);
      case _TimeRangeMode.visible:
        return ref.read(visibleTimeRangeProvider);
      case _TimeRangeMode.custom:
        final start =
            int.tryParse(_customStartController.text.trim()) ??
            source.startTime;
        final end =
            int.tryParse(_customEndController.text.trim()) ?? source.endTime;
        return (start, end);
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final signals = ref.watch(signalVariablesMapProvider);
    final isLoaded = ref.watch(waveformIsLoadedProvider);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 660),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── title + mode toggle ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.patternSearchDialogTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  HelpLink(
                    url: HelpUrls.patternSearch,
                    tooltip: l10n.helpLinkPatternSearchSyntax,
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<_DialogMode>(
                    segments: [
                      ButtonSegment(
                        value: _DialogMode.builder,
                        label: Text(l10n.patternSearchBuilderMode),
                      ),
                      ButtonSegment(
                        value: _DialogMode.expression,
                        label: Text(l10n.patternSearchAdvancedMode),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 16),

            // ── scrollable content ────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isLoaded)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          l10n.patternSearchNoSignals,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    else if (_mode == _DialogMode.builder)
                      _buildBuilderSection(l10n, signals, colorScheme)
                    else
                      _buildExpressionSection(l10n),

                    const SizedBox(height: 14),
                    _buildTimeRangeSection(l10n),

                    if (_validationError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _validationError!,
                        style: TextStyle(
                          color: colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            const Divider(height: 1),

            // ── action buttons ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.patternSearchCancelButton),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: isLoaded ? _runSearch : null,
                    child: Text(l10n.patternSearchSearchButton),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── builder section ───────────────────────────────────────────────────────────

  Widget _buildBuilderSection(
    L10N l10n,
    Map<String, Variable> signals,
    ColorScheme colorScheme,
  ) {
    // Sort signal refs by display name so the dropdown is alphabetical.
    final sortedRefs = signals.keys.toList()
      ..sort((a, b) {
        final nameA = signals[a]?.name ?? a;
        final nameB = signals[b]?.name ?? b;
        return nameA.compareTo(nameB);
      });
    final children = <Widget>[];

    for (var i = 0; i < _rows.length; i++) {
      children.add(
        _buildConditionRow(l10n, i, signals, sortedRefs, colorScheme),
      );
      if (i < _rows.length - 1) {
        children.add(_buildConnectorRow(l10n, i));
      }
    }

    children.add(
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _addRow,
          icon: const Icon(Icons.add, size: 16),
          label: Text(l10n.patternSearchAddCondition),
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildConditionRow(
    L10N l10n,
    int index,
    Map<String, Variable> signalsMap,
    List<String> sortedRefs,
    ColorScheme colorScheme,
  ) {
    final row = _rows[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          // NOT toggle chip.
          FilterChip(
            label: Text(l10n.patternSearchConditionNot),
            selected: row.negated,
            onSelected: (v) => setState(() => row.negated = v),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 6),

          // Signal dropdown.
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              key: ValueKey('signal_${index}_${row.signalRef}'),
              initialValue: row.signalRef,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.patternSearchSignalHint,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                border: const OutlineInputBorder(),
              ),
              items: sortedRefs.map((signalRef) {
                final variable = signalsMap[signalRef];
                final displayName = variable?.name ?? signalRef;
                final fullPath = variable?.fullPath ?? signalRef;
                return DropdownMenuItem(
                  value: signalRef,
                  child: Tooltip(
                    message: fullPath,
                    child: Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() => row.signalRef = v),
            ),
          ),
          const SizedBox(width: 6),

          // Operator dropdown.
          DropdownButton<ConditionOperator>(
            value: row.operator,
            isDense: true,
            items: ConditionOperator.values
                .map(
                  (op) => DropdownMenuItem(
                    value: op,
                    child: Text(_operatorLabel(l10n, op)),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => row.operator = v);
            },
          ),
          const SizedBox(width: 6),

          // Value field.
          SizedBox(
            width: 88,
            child: TextFormField(
              initialValue: row.value,
              decoration: InputDecoration(
                labelText: l10n.patternSearchValueHint,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => row.value = v,
            ),
          ),

          // Remove button (hidden when only one row).
          if (_rows.length > 1)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 18),
              tooltip: l10n.patternSearchRemoveRowTooltip,
              onPressed: () => _removeRow(index),
              color: colorScheme.error,
              visualDensity: VisualDensity.compact,
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildConnectorRow(L10N l10n, int index) {
    final isAnd = index >= _connectorIsAnd.length || _connectorIsAnd[index];
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: true,
            label: Text(l10n.patternSearchConnectorAnd),
          ),
          ButtonSegment(
            value: false,
            label: Text(l10n.patternSearchConnectorOr),
          ),
        ],
        selected: {isAnd},
        onSelectionChanged: (s) =>
            setState(() => _connectorIsAnd[index] = s.first),
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  // ── expression section ────────────────────────────────────────────────────────

  Widget _buildExpressionSection(L10N l10n) {
    return TextField(
      controller: _expressionController,
      maxLines: 3,
      decoration: InputDecoration(
        hintText: l10n.patternSearchExpressionHint,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.all(10),
      ),
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    );
  }

  // ── time range section ────────────────────────────────────────────────────────

  Widget _buildTimeRangeSection(L10N l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.patternSearchTimeRangeLabel,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        RadioGroup<_TimeRangeMode>(
          groupValue: _timeRange,
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _timeRange = v;
                _validationError = null;
              });
            }
          },
          child: Row(
            children: [
              _timeRadio(
                _TimeRangeMode.visible,
                l10n.patternSearchTimeRangeVisible,
              ),
              const SizedBox(width: 12),
              _timeRadio(_TimeRangeMode.full, l10n.patternSearchTimeRangeFull),
              const SizedBox(width: 12),
              _timeRadio(
                _TimeRangeMode.custom,
                l10n.patternSearchTimeRangeCustom,
              ),
            ],
          ),
        ),
        if (_timeRange == _TimeRangeMode.custom) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _customStartController,
                  decoration: InputDecoration(
                    labelText: l10n.patternSearchTimeRangeStart,
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
                width: 130,
                child: TextField(
                  controller: _customEndController,
                  decoration: InputDecoration(
                    labelText: l10n.patternSearchTimeRangeEnd,
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
        ],
      ],
    );
  }

  Widget _timeRadio(_TimeRangeMode mode, String label) {
    return GestureDetector(
      onTap: () => setState(() {
        _timeRange = mode;
        _validationError = null;
      }),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Radio<_TimeRangeMode>(
            value: mode,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────────

  String _operatorLabel(L10N l10n, ConditionOperator op) => switch (op) {
    ConditionOperator.eq => l10n.patternSearchOperatorEq,
    ConditionOperator.neq => l10n.patternSearchOperatorNeq,
    ConditionOperator.gt => l10n.patternSearchOperatorGt,
    ConditionOperator.lt => l10n.patternSearchOperatorLt,
    ConditionOperator.gte => l10n.patternSearchOperatorGte,
    ConditionOperator.lte => l10n.patternSearchOperatorLte,
    ConditionOperator.bitAnd => l10n.patternSearchOperatorBitAnd,
    ConditionOperator.bitOr => l10n.patternSearchOperatorBitOr,
  };

  /// Returns `true` when [text] is a valid numeric literal or x/z pattern.
  ///
  /// Accepts `0x…` (hex), `0b…` (binary), plain decimal, and pure x/z strings
  /// (e.g. `x`, `xx`, `zz`, `bxxxx`). x/z values pass validation and produce
  /// 0 matches — evaluation always returns false when the condition value is x/z.
  static bool _isValidNumeric(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    // x/z literals: pure x/z chars, or b-prefixed x/z (VCD-style notation).
    if (RegExp(r'^[xXzZ]+$').hasMatch(t)) return true;
    if (RegExp(r'^[bB][xXzZ]+$').hasMatch(t)) return true;
    if (t.startsWith('0x') || t.startsWith('0X')) {
      return BigInt.tryParse(t.substring(2), radix: 16) != null;
    }
    if (t.startsWith('0b') || t.startsWith('0B')) {
      return BigInt.tryParse(t.substring(2), radix: 2) != null;
    }
    return BigInt.tryParse(t) != null;
  }
}
