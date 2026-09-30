// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:wavecrux/core/utils/speakable_text.dart';
import 'package:wavecrux/features/decoders/providers/transaction_table_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// The transaction table's column headers and rows.
///
/// **The rows are one keyboard control.** A `DataTable` puts a focusable ink
/// well in every cell, so a keyboard walked a report cell by cell — eleven
/// Tab stops per APB transaction, each read as a bare value with no row
/// around it. Here the rows hold no focus nodes of their own. The whole body
/// is one Tab stop, after the sortable column headers: Up and Down move
/// between rows, Home and End go to the first and last, Page Up and Page Down
/// move a screenful, Left and Right scroll the wide columns sideways, and
/// Enter or Space does what a click does — select the transaction and move
/// the primary cursor and the view to its start.
///
/// **Each row is one sentence.** The row number cell carries the row's
/// semantics — number, decoder, start to end, label, and the error when the
/// decoder flagged one — and the other cells are excluded, so a screen reader
/// hears the row once instead of as loose values. The label is converted with
/// [speakableText]: decoders write arrows into labels (`R 0x08 → 0xFF`), and
/// those labels are pinned by fixture snapshots, so the arrow is turned into
/// a word here, where it is spoken, rather than where it is produced.
///
/// The visible table is the `DataTable` it always was. Row clicks are
/// resolved against the laid-out rows rather than per-cell ink wells, so the
/// whole row stays clickable without putting a focus node in every cell.
class TransactionTableBody extends StatefulWidget {
  const TransactionTableBody({
    required this.rows,
    required this.fieldKeys,
    required this.filter,
    required this.selectedRow,
    required this.horizontalScrollController,
    required this.onSort,
    required this.onRowTap,
    super.key,
  });

  /// The rows to show, already filtered and sorted.
  final List<TableTransaction> rows;

  /// The dynamic field columns after the fixed ones.
  final List<String> fieldKeys;

  /// The sort state the headers show.
  final TransactionTableFilter filter;

  /// Currently selected `(transaction, decoderInstanceId)` or null.
  final (Object, String)? selectedRow;

  /// Horizontal scroll of the table, owned by the panel.
  final ScrollController horizontalScrollController;

  /// Called when a sortable header is activated.
  final void Function(TransactionSortColumn, {required bool ascending}) onSort;

  /// Called when a row is clicked or activated from the keyboard.
  final ValueChanged<TableTransaction> onRowTap;

  @override
  State<TransactionTableBody> createState() => _TransactionTableBodyState();
}

class _TransactionTableBodyState extends State<TransactionTableBody> {
  final _verticalScrollController = ScrollController();
  final GlobalKey _tableKey = GlobalKey();
  final FocusNode _rowsFocus = FocusNode(debugLabel: 'Transaction rows');

  /// The row the keyboard is on, and where it was last found.
  TableTransaction? _current;
  int _currentIndex = 0;

  static const double _horizontalStep = 48;

  @override
  void initState() {
    super.initState();
    _rowsFocus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(TransactionTableBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.rows, widget.rows)) return;
    final rows = widget.rows;
    if (rows.isEmpty) return;
    final found = _current == null ? -1 : rows.indexOf(_current!);
    _currentIndex = found != -1
        ? found
        : _currentIndex.clamp(0, rows.length - 1);
    _current = rows[_currentIndex];
  }

  @override
  void dispose() {
    _rowsFocus
      ..removeListener(_onFocusChanged)
      ..dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  bool get _rowsFocused => _rowsFocus.hasPrimaryFocus;

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() {});
    if (_rowsFocused) _reveal(_currentIndex);
  }

  int get _sortColumnIndex => switch (widget.filter.sortColumn) {
    TransactionSortColumn.rowNumber => 0,
    TransactionSortColumn.decoder => 1,
    TransactionSortColumn.startTime => 2,
    TransactionSortColumn.endTime => 3,
    TransactionSortColumn.label => 4,
  };

  TransactionSortColumn? _columnFromIndex(int idx) => switch (idx) {
    0 => TransactionSortColumn.rowNumber,
    1 => TransactionSortColumn.decoder,
    2 => TransactionSortColumn.startTime,
    3 => TransactionSortColumn.endTime,
    4 => TransactionSortColumn.label,
    _ => null,
  };

  // ── rows and keys ─────────────────────────────────────────────────────────

  void _setCurrent(int index) {
    final rows = widget.rows;
    if (rows.isEmpty) return;
    setState(() {
      _currentIndex = index.clamp(0, rows.length - 1);
      _current = rows[_currentIndex];
    });
  }

  void _moveTo(int index) {
    _setCurrent(index);
    _reveal(_currentIndex);
  }

  void _focusRow(int index) {
    _setCurrent(index);
    _rowsFocus.requestFocus();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // A sortable header inside the table has focus; its keys are its own.
    if (!node.hasPrimaryFocus || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final rows = widget.rows;
    if (rows.isEmpty) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final index = _currentIndex.clamp(0, rows.length - 1);
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveTo(index + 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveTo(index - 1);
    } else if (key == LogicalKeyboardKey.home) {
      _moveTo(0);
    } else if (key == LogicalKeyboardKey.end) {
      _moveTo(rows.length - 1);
    } else if (key == LogicalKeyboardKey.pageDown) {
      _moveTo(index + _pageRows);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _moveTo(index - _pageRows);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      _scrollSideways(
        key == LogicalKeyboardKey.arrowRight
            ? _horizontalStep
            : -_horizontalStep,
      );
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      // A held Enter must not re-run the jump once per auto-repeat.
      if (event is KeyDownEvent) {
        _setCurrent(index);
        widget.onRowTap(rows[index]);
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  RenderTable? get _renderTable {
    RenderTable? find(RenderObject object) {
      if (object is RenderTable) return object;
      RenderTable? found;
      object.visitChildren((child) => found ??= find(child));
      return found;
    }

    final root = _tableKey.currentContext?.findRenderObject();
    return root == null ? null : find(root);
  }

  int get _pageRows {
    final table = _renderTable;
    if (table == null ||
        table.rows < 2 ||
        !_verticalScrollController.hasClients) {
      return 1;
    }
    final rowHeight = table.getRowBox(1).height;
    final viewport = _verticalScrollController.position.viewportDimension;
    return math.max(1, (viewport / rowHeight).floor() - 1);
  }

  /// Scrolls the least distance that brings row [index] fully into view.
  void _reveal(int index) {
    final table = _renderTable;
    if (table == null ||
        index + 1 >= table.rows ||
        !_verticalScrollController.hasClients) {
      return;
    }
    final row = table.getRowBox(index + 1);
    final position = _verticalScrollController.position;
    final double target;
    if (row.top < position.pixels) {
      target = row.top;
    } else if (row.bottom > position.pixels + position.viewportDimension) {
      target = row.bottom - position.viewportDimension;
    } else {
      return;
    }
    _verticalScrollController.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  void _scrollSideways(double delta) {
    final controller = widget.horizontalScrollController;
    if (!controller.hasClients) return;
    final position = controller.position;
    controller.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  /// A click anywhere on a data row, resolved against the laid-out rows.
  void _onTapUp(TapUpDetails details) {
    final table = _renderTable;
    if (table == null) return;
    final local = table.globalToLocal(details.globalPosition);
    for (var y = 1; y < table.rows; y++) {
      if (table.getRowBox(y).contains(local)) {
        final index = y - 1;
        if (index >= widget.rows.length) return;
        _setCurrent(index);
        widget.onRowTap(widget.rows[index]);
        return;
      }
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10N.of(context);
    final words = SpeakableGlyphWords.of(l10n);
    final isDesktop = switch (theme.platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => false,
    };

    DataColumn sortable(String text, int index, {bool numeric = false}) {
      final sorted = index == _sortColumnIndex;
      return DataColumn(
        numeric: numeric,
        label: Semantics(
          button: true,
          label: text,
          value: !sorted
              ? null
              : widget.filter.sortAscending
              ? l10n.transactionTableSortedAscending
              : l10n.transactionTableSortedDescending,
          child: ExcludeSemantics(child: Text(text)),
        ),
        onSort: (i, asc) {
          final column = _columnFromIndex(i);
          if (column != null) widget.onSort(column, ascending: asc);
        },
      );
    }

    final columns = [
      sortable(l10n.transactionTableColumnIndex, 0, numeric: true),
      sortable(l10n.transactionTableColumnDecoder, 1),
      sortable(l10n.transactionTableColumnStartTime, 2, numeric: true),
      sortable(l10n.transactionTableColumnEndTime, 3, numeric: true),
      sortable(l10n.transactionTableColumnLabel, 4),
      for (final key in widget.fieldKeys) DataColumn(label: Text(key)),
    ];

    final rows = [
      for (var i = 0; i < widget.rows.length; i++)
        _buildRow(i, theme, l10n, words, isDesktop: isDesktop),
    ];

    final table = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapUp: _onTapUp,
        child: DataTable(
          key: _tableKey,
          sortColumnIndex: _sortColumnIndex,
          sortAscending: widget.filter.sortAscending,
          showCheckboxColumn: false,
          columns: columns,
          rows: rows,
          headingRowHeight: 32,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 32,
          horizontalMargin: 12,
          columnSpacing: 16,
        ),
      ),
    );

    return FocusTraversalGroup(
      policy: _HeadersBeforeRows(_rowsFocus),
      child: Semantics(
        // Spoken once, as focus enters the table: nothing else says the rows
        // move with the arrow keys. Touch screen readers swipe instead.
        container: isDesktop,
        explicitChildNodes: true,
        label: isDesktop ? l10n.transactionTableKeyboardHint : null,
        child: Focus(
          focusNode: _rowsFocus,
          // The current row announces itself; a node for the whole table
          // would be a second, nameless focus.
          includeSemantics: false,
          onKeyEvent: _onKeyEvent,
          child: Scrollbar(
            controller: widget.horizontalScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: widget.horizontalScrollController,
              child: Scrollbar(
                controller: _verticalScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _verticalScrollController,
                  child: table,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(
    int index,
    ThemeData theme,
    L10N l10n,
    SpeakableGlyphWords words, {
    required bool isDesktop,
  }) {
    final row = widget.rows[index];
    final tx = row.transaction;
    final isSelected =
        widget.selectedRow != null &&
        widget.selectedRow!.$1 == tx &&
        widget.selectedRow!.$2 == row.decoderInstanceId;
    final isCurrent = _rowsFocused && index == _currentIndex;

    final label = speakableText(tx.label, words);
    final message = tx.errorMessage;
    final spoken = !tx.isError
        ? l10n.transactionTableRowSpoken(
            '${row.rowIndex}',
            row.decoderDisplayName,
            '${tx.startTime}',
            '${tx.endTime}',
            label,
          )
        : message == null || message.isEmpty
        ? l10n.transactionTableRowSpokenError(
            '${row.rowIndex}',
            row.decoderDisplayName,
            '${tx.startTime}',
            '${tx.endTime}',
            label,
          )
        : l10n.transactionTableRowSpokenErrorMessage(
            '${row.rowIndex}',
            row.decoderDisplayName,
            '${tx.startTime}',
            '${tx.endTime}',
            label,
            speakableText(message, words),
          );

    return DataRow(
      selected: isSelected,
      color: WidgetStateProperty.resolveWith<Color?>((states) {
        final Color? base;
        if (isSelected) {
          base = theme.colorScheme.primaryContainer.withValues(alpha: 0.45);
        } else if (tx.isError) {
          base = theme.colorScheme.errorContainer.withValues(alpha: 0.35);
        } else {
          base = null;
        }
        if (!isCurrent) return base;
        // The keyboard's row: a stronger primary tint over whatever the row
        // already shows, so it reads as focused on selected and error rows.
        return Color.alphaBlend(
          theme.colorScheme.primary.withValues(alpha: 0.24),
          base ?? theme.colorScheme.surface,
        );
      }),
      cells: [
        DataCell(
          Semantics(
            container: true,
            button: true,
            selected: isSelected,
            label: spoken,
            focusable: true,
            focused: isCurrent,
            onFocus: theme.platform == TargetPlatform.iOS
                ? null
                : () => _focusRow(index),
            onTap: () {
              _setCurrent(index);
              widget.onRowTap(row);
            },
            child: ExcludeSemantics(child: Text('${row.rowIndex}')),
          ),
        ),
        DataCell(ExcludeSemantics(child: Text(row.decoderDisplayName))),
        DataCell(ExcludeSemantics(child: Text('${tx.startTime}'))),
        DataCell(ExcludeSemantics(child: Text('${tx.endTime}'))),
        DataCell(
          ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tx.isError)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.error_outline,
                      size: 14,
                      color: theme.colorScheme.error,
                    ),
                  ),
                Flexible(
                  child: Text(tx.label, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
        for (final key in widget.fieldKeys)
          DataCell(ExcludeSemantics(child: Text(tx.fields[key] ?? ''))),
      ],
    );
  }
}

/// Reading order for the table, with the rows' single Tab stop after every
/// sortable header.
///
/// The rows' focus node spans the whole table, headers included, so plain
/// reading order cannot tell it from the first header: both start at the
/// table's top-left corner.
class _HeadersBeforeRows extends ReadingOrderTraversalPolicy {
  _HeadersBeforeRows(this.rows);

  final FocusNode rows;

  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) {
    final sorted = super.sortDescendants(descendants, currentNode).toList();
    if (sorted.remove(rows)) sorted.add(rows);
    return sorted;
  }
}
