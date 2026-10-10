// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';
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
/// **Only the rows on screen are built.** Decoders run over the whole trace,
/// so a UART capture alone can be tens of thousands of transactions, and a
/// `DataTable` lays out every row and sizes its columns by walking all of
/// them. The headers are still a `DataTable`, with no rows and fixed column
/// widths, so they look, sort and read as they always did; the rows below
/// are a fixed-height lazy list that uses the same widths. Widths come from
/// measuring the few longest values in each column rather than every cell,
/// and a row's position is its index times the row height, so moving the
/// keyboard to any row, the last of twenty thousand included, scrolls
/// straight to it.
///
/// Each row is one gesture detector, so the whole row stays clickable
/// without putting a focus node in every cell.
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
  final FocusNode _rowsFocus = FocusNode(debugLabel: 'Transaction rows');

  /// The row the keyboard is on, and where it was last found.
  TableTransaction? _current;
  int _currentIndex = 0;

  /// Column widths, and what they were measured for.
  List<double> _widths = const [];
  Object? _widthsKey;

  static const double _horizontalStep = 48;
  static const double _headingHeight = 32;
  static const double _rowHeight = 28;
  static const double _horizontalMargin = 12;
  static const double _columnSpacing = 16;

  /// The sort arrow and its gap beside a sortable header's label.
  static const double _sortArrowWidth = 18;

  /// The error icon and its gap before an error row's label.
  static const double _errorIconWidth = 18;

  /// How many of a column's longest values are measured for its width.
  static const int _measuredPerColumn = 16;

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

  static bool _isNumeric(int column) =>
      column == 0 || column == 2 || column == 3;

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

  /// Height the rows have below the pinned headers.
  double? get _rowsViewport {
    if (!_verticalScrollController.hasClients) return null;
    return _verticalScrollController.position.viewportDimension -
        _headingHeight;
  }

  int get _pageRows {
    final viewport = _rowsViewport;
    if (viewport == null) return 1;
    return math.max(1, (viewport / _rowHeight).floor() - 1);
  }

  /// Scrolls the least distance that brings row [index] fully into view
  /// below the headers.
  ///
  /// The headers are pinned above the rows, so row `index` is visible while
  /// the scroll offset lies between its bottom less the rows' viewport and
  /// its top.
  void _reveal(int index) {
    final viewport = _rowsViewport;
    if (viewport == null) return;
    final position = _verticalScrollController.position;
    final top = index * _rowHeight;
    final bottom = top + _rowHeight;
    final double target;
    if (top < position.pixels) {
      target = top;
    } else if (bottom > position.pixels + viewport) {
      target = bottom - viewport;
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

  // ── column widths ─────────────────────────────────────────────────────────

  /// Each column's width, padding included: the wider of its header and
  /// its longest value.
  ///
  /// Only the [_measuredPerColumn] longest values of a column, by character
  /// count, are laid out as text; measuring every cell is the walk this
  /// table exists to avoid. A shorter value that is wider in a proportional
  /// font is ellipsized rather than overflowing its cell.
  List<double> _columnWidths({
    required List<String> headers,
    required TextStyle headingStyle,
    required TextStyle dataStyle,
    required TextScaler textScaler,
    required TextDirection textDirection,
  }) {
    final key = (
      widget.rows,
      Object.hashAll(widget.fieldKeys),
      Object.hashAll(headers),
      headingStyle,
      dataStyle,
      textScaler,
      textDirection,
    );
    if (key == _widthsKey) return _widths;

    final fieldKeys = widget.fieldKeys;
    final columnCount = 5 + fieldKeys.length;
    final longest = [
      for (var c = 0; c < columnCount; c++) _Longest(_measuredPerColumn),
    ];
    final longestErrorLabels = _Longest(_measuredPerColumn);
    for (final row in widget.rows) {
      final tx = row.transaction;
      longest[0].add('${row.rowIndex}');
      longest[1].add(row.decoderDisplayName);
      longest[2].add('${tx.startTime}');
      longest[3].add('${tx.endTime}');
      (tx.isError ? longestErrorLabels : longest[4]).add(tx.label);
      for (var f = 0; f < fieldKeys.length; f++) {
        longest[5 + f].add(tx.fields[fieldKeys[f]] ?? '');
      }
    }

    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final width = painter.width.ceilToDouble();
      painter.dispose();
      return width;
    }

    double widest(Iterable<String> texts) =>
        texts.fold(0, (w, t) => math.max(w, measure(t, dataStyle)));

    final widths = <double>[];
    for (var c = 0; c < columnCount; c++) {
      final header =
          measure(headers[c], headingStyle) + (c < 5 ? _sortArrowWidth : 0);
      var content = widest(longest[c].values);
      if (c == 4) {
        final errors = longestErrorLabels.values;
        if (errors.isNotEmpty) {
          content = math.max(content, widest(errors) + _errorIconWidth);
        }
      }
      final start = c == 0 ? _horizontalMargin : _columnSpacing / 2;
      final end = c == columnCount - 1 ? _horizontalMargin : _columnSpacing / 2;
      // One pixel of slack: a text measured to the pixel can still round
      // past it when laid out inside the cell.
      widths.add(start + math.max(header, content) + 1 + end);
    }
    _widthsKey = key;
    return _widths = widths;
  }

  EdgeInsetsDirectional _cellPadding(int column, int columnCount) =>
      EdgeInsetsDirectional.only(
        start: column == 0 ? _horizontalMargin : _columnSpacing / 2,
        end: column == columnCount - 1 ? _horizontalMargin : _columnSpacing / 2,
      );

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

    final dataTableTheme = DataTableTheme.of(context);
    final headingStyle = DefaultTextStyle.of(context).style.merge(
      dataTableTheme.headingTextStyle ?? theme.textTheme.titleSmall,
    );
    final dataStyle =
        dataTableTheme.dataTextStyle ?? theme.textTheme.bodyMedium!;

    final headers = [
      l10n.transactionTableColumnIndex,
      l10n.transactionTableColumnDecoder,
      l10n.transactionTableColumnStartTime,
      l10n.transactionTableColumnEndTime,
      l10n.transactionTableColumnLabel,
      ...widget.fieldKeys,
    ];
    final widths = _columnWidths(
      headers: headers,
      headingStyle: headingStyle,
      dataStyle: dataStyle,
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    );
    final tableWidth = widths.fold<double>(0, (sum, w) => sum + w);

    DataColumn sortable(int index) {
      final text = headers[index];
      final sorted = index == _sortColumnIndex;
      return DataColumn(
        numeric: _isNumeric(index),
        columnWidth: FixedColumnWidth(widths[index]),
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

    // The column headers: a `DataTable` with no rows, so the headers keep
    // their look, sort arrows and focus behaviour, at the rows' widths.
    final headings = DataTable(
      sortColumnIndex: _sortColumnIndex,
      sortAscending: widget.filter.sortAscending,
      showCheckboxColumn: false,
      columns: [
        for (var i = 0; i < 5; i++) sortable(i),
        for (var f = 0; f < widget.fieldKeys.length; f++)
          DataColumn(
            columnWidth: FixedColumnWidth(widths[5 + f]),
            label: Text(widget.fieldKeys[f]),
          ),
      ],
      rows: const [],
      headingRowHeight: _headingHeight,
      horizontalMargin: _horizontalMargin,
      columnSpacing: _columnSpacing,
    );

    final divider = Divider.createBorderSide(context, width: 1);
    final rows = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: CustomScrollView(
        controller: _verticalScrollController,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _HeadingsDelegate(
              height: _headingHeight,
              // Rows scroll under the pinned headers.
              child: ColoredBox(
                color: theme.colorScheme.surface,
                child: headings,
              ),
            ),
          ),
          SliverFixedExtentList(
            itemExtent: _rowHeight,
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildRow(
                index,
                theme,
                l10n,
                words,
                widths: widths,
                divider: divider,
                dataStyle: dataStyle,
              ),
              childCount: widget.rows.length,
            ),
          ),
        ],
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
          child: LayoutBuilder(
            builder: (context, constraints) => Scrollbar(
              controller: widget.horizontalScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: widget.horizontalScrollController,
                child: SizedBox(
                  // At least the pane's width, so the vertical scrollbar
                  // sits at the pane's edge when the columns are narrow.
                  width: math.max(tableWidth, constraints.maxWidth),
                  child: Scrollbar(
                    controller: _verticalScrollController,
                    thumbVisibility: true,
                    child: rows,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(
    int index,
    ThemeData theme,
    L10N l10n,
    SpeakableGlyphWords words, {
    required List<double> widths,
    required BorderSide divider,
    required TextStyle dataStyle,
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

    final Color? base;
    if (isSelected) {
      base = theme.colorScheme.primaryContainer.withValues(alpha: 0.45);
    } else if (tx.isError) {
      base = theme.colorScheme.errorContainer.withValues(alpha: 0.35);
    } else {
      base = null;
    }
    // The keyboard's row: a stronger primary tint over whatever the row
    // already shows, so it reads as focused on selected and error rows.
    final color = !isCurrent
        ? base
        : Color.alphaBlend(
            theme.colorScheme.primary.withValues(alpha: 0.24),
            base ?? theme.colorScheme.surface,
          );

    final cells = <Widget>[
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
      ExcludeSemantics(child: Text(row.decoderDisplayName)),
      ExcludeSemantics(child: Text('${tx.startTime}')),
      ExcludeSemantics(child: Text('${tx.endTime}')),
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
      for (final key in widget.fieldKeys)
        ExcludeSemantics(child: Text(tx.fields[key] ?? '')),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // The row-number cell already carries the row's tap action.
      excludeFromSemantics: true,
      onTap: () {
        _setCurrent(index);
        widget.onRowTap(row);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          border: Border(top: divider),
        ),
        child: DefaultTextStyle(
          style: dataStyle,
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          child: Row(
            children: [
              for (var c = 0; c < cells.length; c++)
                SizedBox(
                  width: widths[c],
                  child: Padding(
                    padding: _cellPadding(c, cells.length),
                    child: Align(
                      alignment: _isNumeric(c)
                          ? AlignmentDirectional.centerEnd
                          : AlignmentDirectional.centerStart,
                      child: cells[c],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The few longest strings added, by character count.
class _Longest {
  _Longest(this.limit);

  final int limit;
  final List<String> values = [];
  int _shortestKept = -1;

  void add(String value) {
    if (values.length == limit && value.length <= _shortestKept) return;
    values.add(value);
    if (values.length > limit) {
      values
        ..sort((a, b) => b.length.compareTo(a.length))
        ..removeLast();
    }
    if (values.length == limit) {
      _shortestKept = values.map((v) => v.length).reduce(math.min);
    }
  }
}

/// The column headers, pinned above the rows.
class _HeadingsDelegate extends SliverPersistentHeaderDelegate {
  _HeadingsDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;

  // The headers carry the sort state, so they rebuild with the table.
  @override
  bool shouldRebuild(_HeadingsDelegate oldDelegate) => true;
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
