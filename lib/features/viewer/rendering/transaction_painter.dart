// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:collection/collection.dart' show PriorityQueue;
import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// One resolved draw unit produced by [TransactionPainter.buildBlocks].
///
/// A block is either a normal transaction rect, or — when transactions are
/// narrower than a pixel column — a density bar standing in for every
/// transaction that fell in that column.
@immutable
class TransactionBlock {
  const TransactionBlock({
    required this.xStart,
    required this.xEnd,
    required this.top,
    required this.bottom,
    required this.index,
    required this.isError,
    required this.isSelected,
    required this.isDensityBar,
    required this.coalescedCount,
    this.occludes = false,
    this.label,
    this.shortLabel,
  });

  /// Left edge in canvas coordinates, clamped to the lane.
  final double xStart;

  /// Right edge in canvas coordinates, clamped to the lane.
  final double xEnd;

  /// Top edge in canvas coordinates. Overlapping transactions are packed into
  /// sub-rows, so this is the top of the block's sub-row, not of the lane.
  final double top;

  /// Bottom edge in canvas coordinates.
  final double bottom;

  /// Index into the source transaction list of the transaction this block
  /// draws (the first one, for a density bar).
  final int index;

  /// True when this block overlaps a block drawn earlier in the same sub-row,
  /// so it is painted over an opaque backing that hides the earlier block's
  /// label instead of mixing the two texts.
  final bool occludes;

  /// True when this block, or any transaction coalesced into it, is an error.
  final bool isError;

  /// True when this block, or any transaction coalesced into it, is the
  /// selected transaction.
  final bool isSelected;

  /// True when the block stands for sub-pixel transactions rather than one
  /// resolvable block; drawn as a single vertical bar with no label.
  final bool isDensityBar;

  /// Number of source transactions this block represents (1 unless
  /// [isDensityBar]).
  final int coalescedCount;

  /// Label to draw centred in the block, or null when the block is too
  /// narrow for text.
  final String? label;

  /// The transaction's [DecodedTransaction.shortLabel], drawn instead of
  /// [label] when [label] does not fit, or alone when the block is too
  /// narrow for [label] but wide enough for a short form. Null when the
  /// decoder gave none or the block is too narrow even for it.
  final String? shortLabel;
}

/// Paints decoded protocol-decoder transactions onto a dedicated lane.
///
/// Each [DecodedTransaction] is drawn as a coloured rounded-rect block
/// spanning [DecodedTransaction.startTime] to [DecodedTransaction.endTime].
/// When the block is wide enough the [DecodedTransaction.label] is drawn
/// centred inside it.  Error transactions ([DecodedTransaction.isError])
/// receive a red border and diagonal hatch fill.
///
/// The currently [selectedTransaction] is drawn with a brighter outline and
/// fill to indicate selection — used to mirror the highlight in the
/// transaction table.
///
/// Cost is bounded by the viewport, not by the transaction count. The visible
/// window is located by binary search over the time-ordered list, and
/// transactions narrower than a pixel column are coalesced into density bars,
/// so a fully zoomed-out million-transaction decode draws at most about one
/// block per pixel of lane width. Paint objects are hoisted out of the draw
/// loop and laid-out label paragraphs are cached across frames.
///
/// Transactions whose spans overlap are packed into sub-rows (greedy interval
/// partitioning over the whole list, so a transaction keeps its sub-row while
/// the view pans). The lane splits into as many sub-rows as the visible
/// transactions need, up to what its height allows; past that, sub-rows are
/// reused and a block that still overlaps an earlier one in its sub-row is
/// painted over an opaque backing, so one label is readable instead of two
/// overprinted ones.
abstract final class TransactionPainter {
  // ── layout constants ──────────────────────────────────────────────────────────

  /// Vertical margin kept between the lane edge and the blocks.
  static const double _blockVMargin = 3;

  /// Smallest sub-row height (px) the lane splits into for overlapping
  /// transactions. A 28 px lane holds two.
  static const double _minSubRowHeight = 10;

  /// Vertical gap (px) between adjacent sub-rows.
  static const double _subRowGap = 1;

  /// Smallest label font size (px) drawn in a sub-row; below it the label
  /// is dropped rather than drawn illegibly.
  static const double _minSubRowFontSize = 7;

  /// Minimum block width (px) at which the label text is drawn.
  static const double _minWidthForLabel = 24;

  /// Minimum block width (px) at which a short label is drawn.
  static const double _minWidthForShortLabel = 12;

  /// Horizontal padding for a short label in a block too narrow for the
  /// usual [_labelPadding].
  static const double _shortLabelPadding = 2;

  /// Minimum block width (px) at which the block is drawn as a filled rect
  /// rather than a single vertical line.
  static const double _minWidthForRect = 2;

  /// Corner radius for transaction block rounded-rects.
  static const double _cornerRadius = 3;

  /// Horizontal padding between block edge and label text.
  static const double _labelPadding = 5;

  /// Upper bound on retained laid-out label paragraphs. Decoded traces reuse
  /// a small vocabulary of labels, so a modest cache absorbs nearly every
  /// lookup; the oldest entry is disposed when the cap is reached.
  static const int _paragraphCacheCapacity = 256;

  // ── public API ────────────────────────────────────────────────────────────────

  /// Resolves the transactions overlapping the visible window into the blocks
  /// that will actually be drawn into [laneBounds].
  ///
  /// [transactions] must be ordered by ascending
  /// [DecodedTransaction.startTime] — the sort applied once at the provider
  /// boundary ([decodeAll] in `active_decoders_provider.dart`) — because the
  /// visible window is located by binary search. Transactions MAY overlap:
  /// AXI-family decoders emit at completion time, so an early long burst can
  /// still be in flight while later shorter bursts start and finish. The left
  /// bound is therefore located via a prefix-max of endTime rather than a
  /// walk-back over immediate predecessors, so an early overlapping
  /// transaction is never skipped.
  static List<TransactionBlock> buildBlocks({
    required Rect laneBounds,
    required List<DecodedTransaction> transactions,
    required TimeMapper timeMapper,
    DecodedTransaction? selectedTransaction,
  }) {
    if (transactions.isEmpty || timeMapper.isEmpty) {
      return const <TransactionBlock>[];
    }

    final visStart = timeMapper.visibleStartTime;
    final visEnd = timeMapper.visibleEndTime;

    // Everything at or past `hi` starts after the window and can never
    // overlap it.
    final hi = _firstStartAfter(transactions, visEnd);
    if (hi == 0) return const <TransactionBlock>[];

    // Left bound: the first index whose prefix-max endTime reaches `visStart`.
    // The prefix-max array is monotonic non-decreasing, so every transaction
    // before this index ends strictly before the window and cannot overlap it
    // — including the overlapping case where an early long transaction is
    // followed by shorter ones that end sooner. Individual entries at or after
    // `lo` that still end before the window (their endTime did not set the
    // running max) are skipped in the draw loop below.
    final lo = _firstReachingEnd(_prefixMaxEnd(transactions), visStart);
    if (lo >= hi) return const <TransactionBlock>[];

    final left = laneBounds.left;
    final right = laneBounds.right;
    double xFor(int time) =>
        (left + timeMapper.timeToPixel(time)).clamp(left, right);

    bool isSelected(DecodedTransaction tx) =>
        selectedTransaction != null &&
        selectedTransaction.startTime == tx.startTime &&
        selectedTransaction.endTime == tx.endTime &&
        selectedTransaction.label == tx.label;

    final blockTop = laneBounds.top + _blockVMargin;
    final blockBottom = math.max(blockTop, laneBounds.bottom - _blockVMargin);
    final packedRows = _packedRows(transactions);

    // First pass: resolve the visible draw units and the deepest sub-row any
    // visible block needs. Geometry is assigned once that depth is known.
    final blocks = <TransactionBlock>[];
    final blockRows = <int>[];
    var visibleDepth = 1;
    var i = lo;
    while (i < hi) {
      final tx = transactions[i];
      // The prefix-max left bound can admit entries that end before the window
      // (an earlier sibling set the running max). They do not overlap and would
      // otherwise clamp to a spurious bar at the lane's left edge.
      if (tx.endTime < visStart) {
        i++;
        continue;
      }
      final xStart = xFor(tx.startTime);
      final xEnd = xFor(tx.endTime);

      if (xEnd - xStart < _minWidthForRect) {
        // Sub-pixel: absorb every following narrow transaction that lands in
        // the same pixel column into one density bar, so the block count
        // stays bounded by the lane width however deep the zoom-out is.
        final column = xStart.floorToDouble();
        var anyError = tx.isError;
        var anySelected = isSelected(tx);
        var count = 1;
        var j = i + 1;
        while (j < hi) {
          final next = transactions[j];
          final nextStart = xFor(next.startTime);
          if (nextStart.floorToDouble() != column) break;
          if (xFor(next.endTime) - nextStart >= _minWidthForRect) break;
          // Consume same-column sub-pixel neighbours, but only count those that
          // actually overlap the window — the leftmost column can also hold
          // pre-window entries admitted by the prefix-max left bound.
          if (next.endTime >= visStart) {
            anyError = anyError || next.isError;
            anySelected = anySelected || isSelected(next);
            count++;
          }
          j++;
        }
        blocks.add(
          TransactionBlock(
            xStart: column,
            xEnd: column,
            top: blockTop,
            bottom: blockBottom,
            index: i,
            isError: anyError,
            isSelected: anySelected,
            isDensityBar: true,
            coalescedCount: count,
          ),
        );
        blockRows.add(-1);
        i = j;
        continue;
      }

      final row = packedRows[i];
      if (row + 1 > visibleDepth) visibleDepth = row + 1;
      blocks.add(
        TransactionBlock(
          xStart: xStart,
          xEnd: xEnd,
          top: blockTop,
          bottom: blockBottom,
          index: i,
          isError: tx.isError,
          isSelected: isSelected(tx),
          isDensityBar: false,
          coalescedCount: 1,
          label: (xEnd - xStart) >= _minWidthForLabel ? tx.label : null,
          shortLabel: (xEnd - xStart) >= _minWidthForShortLabel
              ? tx.shortLabel
              : null,
        ),
      );
      blockRows.add(row);
      i++;
    }

    // Second pass: split the lane into as many sub-rows as the visible
    // overlap needs and its height allows. Density bars keep the full height.
    final available = math.max(
      1,
      ((blockBottom - blockTop + _subRowGap) / (_minSubRowHeight + _subRowGap))
          .floor(),
    );
    final rowCount = math.min(visibleDepth, available);
    final rowHeight =
        (blockBottom - blockTop - _subRowGap * (rowCount - 1)) / rowCount;
    final rowEnd = List<double>.filled(rowCount, double.negativeInfinity);
    for (var k = 0; k < blocks.length; k++) {
      final packed = blockRows[k];
      if (packed < 0) continue;
      final block = blocks[k];
      final row = packed % rowCount;
      final top = blockTop + row * (rowHeight + _subRowGap);
      // Blocks arrive in start order, so an overlap with anything earlier in
      // this sub-row shows up against the furthest right edge drawn so far.
      // Abutting blocks (one ends where the next starts) do not occlude.
      final occludes = block.xStart < rowEnd[row] - 0.5;
      if (block.xEnd > rowEnd[row]) rowEnd[row] = block.xEnd;
      blocks[k] = TransactionBlock(
        xStart: block.xStart,
        xEnd: block.xEnd,
        top: top,
        bottom: top + rowHeight,
        index: block.index,
        isError: block.isError,
        isSelected: block.isSelected,
        isDensityBar: false,
        coalescedCount: 1,
        occludes: occludes,
        label: block.label,
        shortLabel: block.shortLabel,
      );
    }

    return blocks;
  }

  /// The transaction drawn at [position] in a lane painted into [laneBounds],
  /// or null when [position] is over no block.
  ///
  /// Uses the same layout as [paint], so a click on an overlapping
  /// transaction's sub-row selects that transaction, and where blocks are
  /// drawn over each other the topmost (last painted) one wins. A density
  /// bar is hit within a couple of pixels and yields the first transaction
  /// it stands for.
  static DecodedTransaction? hitTest({
    required Rect laneBounds,
    required List<DecodedTransaction> transactions,
    required TimeMapper timeMapper,
    required Offset position,
  }) {
    if (position.dy < laneBounds.top || position.dy > laneBounds.bottom) {
      return null;
    }
    final blocks = buildBlocks(
      laneBounds: laneBounds,
      transactions: transactions,
      timeMapper: timeMapper,
    );
    // The lane's top and bottom margins belong to the nearest sub-row.
    final y = position.dy.clamp(
      laneBounds.top + _blockVMargin,
      math.max(
        laneBounds.top + _blockVMargin,
        laneBounds.bottom - _blockVMargin,
      ),
    );
    for (var k = blocks.length - 1; k >= 0; k--) {
      final block = blocks[k];
      if (y < block.top - _subRowGap || y > block.bottom + _subRowGap) {
        continue;
      }
      final tolerance = block.isDensityBar ? 2.0 : 0.0;
      if (position.dx >= block.xStart - tolerance &&
          position.dx <= block.xEnd + tolerance) {
        return transactions[block.index];
      }
    }
    return null;
  }

  /// Paints all transactions in [transactions] that overlap the currently
  /// visible time window (derived from [timeMapper]) into [laneBounds].
  ///
  /// Pass [selectedTransaction] to highlight a specific block — typically the
  /// row that is selected in the transaction table.
  ///
  /// [backgroundColor] is the colour behind the lane. A block that overlaps
  /// an earlier one in its sub-row is backed with it, opaque, so the earlier
  /// block's label does not show through; without it such blocks are drawn
  /// translucent as before.
  static void paint({
    required Canvas canvas,
    required Rect laneBounds,
    required List<DecodedTransaction> transactions,
    required TimeMapper timeMapper,
    required Color laneColor,
    required TextStyle labelStyle,
    DecodedTransaction? selectedTransaction,
    Color? backgroundColor,
  }) {
    final blockTop = laneBounds.top + _blockVMargin;
    final blockBottom = laneBounds.bottom - _blockVMargin;
    if (blockBottom <= blockTop) return;

    final blocks = buildBlocks(
      laneBounds: laneBounds,
      transactions: transactions,
      timeMapper: timeMapper,
      selectedTransaction: selectedTransaction,
    );
    if (blocks.isEmpty) return;

    canvas
      ..save()
      ..clipRect(laneBounds);

    // Hoisted out of the loop: a Paint is read at draw time, so one instance
    // can be re-tinted per block instead of allocating up to three per block.
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()..style = PaintingStyle.stroke;
    final hatchPaint = Paint()
      ..color = _errorColor.withValues(alpha: 0.35)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    // The lane's own tint over the canvas, made opaque: what an occluding
    // block hides the earlier block behind.
    final backingColor = backgroundColor == null
        ? null
        : Color.alphaBlend(
            laneColor.withValues(alpha: 0.06),
            backgroundColor.withValues(alpha: 1),
          );
    // Sub-rows shrink the label to fit; a full-height block keeps the
    // configured size.
    final baseFontSize = labelStyle.fontSize ?? 10;

    for (final block in blocks) {
      final baseColor = block.isError ? _errorColor : laneColor;

      if (block.isDensityBar) {
        strokePaint
          ..color = baseColor
          ..strokeWidth = 1;
        canvas.drawLine(
          Offset(block.xStart, blockTop),
          Offset(block.xStart, blockBottom),
          strokePaint,
        );
        continue;
      }

      final blockRect = Rect.fromLTRB(
        block.xStart,
        block.top,
        block.xEnd,
        block.bottom,
      );
      final rrect = RRect.fromRectAndRadius(
        blockRect,
        const Radius.circular(_cornerRadius),
      );

      if (block.occludes && backingColor != null) {
        fillPaint.color = backingColor;
        canvas.drawRRect(rrect, fillPaint);
      }

      fillPaint.color = baseColor.withValues(
        alpha: block.isSelected ? 0.45 : 0.25,
      );
      canvas.drawRRect(rrect, fillPaint);

      if (block.isError) {
        _paintErrorHatch(canvas, blockRect, hatchPaint);
      }

      strokePaint
        ..color = block.isSelected
            ? baseColor
            : baseColor.withValues(alpha: 0.7)
        ..strokeWidth = block.isSelected ? 2.0 : 1.0;
      canvas.drawRRect(rrect, strokePaint);

      if (block.label != null || block.shortLabel != null) {
        final isSubRow = blockRect.height < blockBottom - blockTop - 0.5;
        final fontSize = isSubRow
            ? math.min(baseFontSize, blockRect.height - 1.5)
            : baseFontSize;
        if (fontSize >= _minSubRowFontSize || !isSubRow) {
          if (isSubRow) {
            canvas
              ..save()
              ..clipRect(blockRect);
          }
          _paintLabel(
            canvas,
            block,
            blockRect,
            fontSize == baseFontSize
                ? labelStyle
                : labelStyle.copyWith(fontSize: fontSize),
          );
          if (isSubRow) canvas.restore();
        }
      }
    }

    canvas.restore();
  }

  /// The text [paint] draws in [block] with [style]: the full label when it
  /// fits, else the decoder's short label when it has one, else the full
  /// label truncated with an ellipsis. Null when nothing is drawn.
  @visibleForTesting
  static String? debugDrawnLabel(TransactionBlock block, TextStyle style) =>
      _layoutLabel(
        block,
        Rect.fromLTRB(block.xStart, block.top, block.xEnd, block.bottom),
        style,
      )?.text;

  /// Releases every cached label paragraph, so a test can measure cache
  /// behaviour from a known-empty state. Production code relies on the
  /// capacity bound instead.
  @visibleForTesting
  static void clearParagraphCache() {
    for (final paragraph in _paragraphCache.values) {
      paragraph.dispose();
    }
    _paragraphCache.clear();
  }

  /// Number of laid-out label paragraphs currently retained.
  @visibleForTesting
  static int get debugParagraphCacheSize => _paragraphCache.length;

  // ── private helpers ───────────────────────────────────────────────────────────

  static const Color _errorColor = Color(0xFFEF5350); // Red 400

  /// Insertion-ordered so the oldest entry is the eviction victim.
  static final LinkedHashMap<String, ui.Paragraph> _paragraphCache =
      LinkedHashMap<String, ui.Paragraph>();

  /// Index of the first transaction whose startTime exceeds [time], i.e. the
  /// exclusive end of the candidate window.
  static int _firstStartAfter(List<DecodedTransaction> list, int time) {
    var low = 0;
    var high = list.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (list[mid].startTime > time) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }

  /// Cache of the prefix-max endTime array, keyed by the (immutable)
  /// transaction list instance. Decoders rebuild the list on each decode, so
  /// the entry is naturally invalidated when the data changes, and the
  /// [Expando] lets the array be reclaimed together with its list. Computing it
  /// is O(n) once per list; every subsequent paint reuses it, keeping per-frame
  /// cost bounded by the viewport rather than the transaction count.
  static final Expando<List<int>> _prefixMaxEndCache = Expando<List<int>>();

  /// Running maximum of [DecodedTransaction.endTime] over `list[0..i]`. Because
  /// the source is sorted by ascending startTime but endTimes may overlap, this
  /// monotonic array is what makes the visible-window left bound overlap-safe.
  static List<int> _prefixMaxEnd(List<DecodedTransaction> list) {
    final cached = _prefixMaxEndCache[list];
    if (cached != null) return cached;
    final prefix = List<int>.filled(list.length, 0);
    var runningMax = list[0].endTime;
    for (var i = 0; i < list.length; i++) {
      final end = list[i].endTime;
      if (end > runningMax) runningMax = end;
      prefix[i] = runningMax;
    }
    _prefixMaxEndCache[list] = prefix;
    return prefix;
  }

  /// Cache of each list's sub-row assignment, keyed like [_prefixMaxEndCache].
  static final Expando<Uint16List> _packedRowCache = Expando<Uint16List>();

  /// Sub-row of every transaction in [list], by greedy interval partitioning:
  /// each transaction takes the lowest sub-row whose previous occupant has
  /// ended by the time it starts. A transaction that starts exactly where
  /// another ends shares its sub-row, so back-to-back traffic stays on one
  /// row and only genuine overlaps (AXI bursts in flight, a decoder notice
  /// spanning a packet) move down. O(n log d) for overlap depth d, computed
  /// once per list.
  static Uint16List _packedRows(List<DecodedTransaction> list) {
    final cached = _packedRowCache[list];
    if (cached != null) return cached;
    final rows = Uint16List(list.length);
    // (endTime, row) of every occupied sub-row, earliest end first.
    final busy = PriorityQueue<(int, int)>((a, b) => a.$1.compareTo(b.$1));
    final free = PriorityQueue<int>();
    var nextRow = 0;
    for (var i = 0; i < list.length; i++) {
      final tx = list[i];
      while (busy.isNotEmpty && busy.first.$1 <= tx.startTime) {
        free.add(busy.removeFirst().$2);
      }
      final row = free.isNotEmpty ? free.removeFirst() : nextRow++;
      rows[i] = math.min(row, 0xFFFF);
      busy.add((tx.endTime, row));
    }
    _packedRowCache[list] = rows;
    return rows;
  }

  /// Index of the first entry whose prefix-max endTime is at or after [time].
  /// Every entry before it ends strictly before [time] and cannot overlap a
  /// window starting there.
  static int _firstReachingEnd(List<int> prefixMaxEnd, int time) {
    var low = 0;
    var high = prefixMaxEnd.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (prefixMaxEnd[mid] < time) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// Draws diagonal hatch lines over [rect] to indicate an error transaction.
  static void _paintErrorHatch(Canvas canvas, Rect rect, Paint hatchPaint) {
    const spacing = 5.0;
    final left = rect.left;
    final right = rect.right;
    final top = rect.top;
    final bottom = rect.bottom;
    final diag = (right - left) + (bottom - top);

    canvas
      ..save()
      ..clipRect(rect);

    var offset = 0.0;
    while (offset < diag) {
      canvas.drawLine(
        Offset(math.min(left + offset, right), top),
        Offset(left, math.min(top + offset, bottom)),
        hatchPaint,
      );
      offset += spacing;
    }

    canvas.restore();
  }

  /// Paints the block's label centred within [blockRect]: the full label
  /// when it fits, else the short label when the decoder gave one, else the
  /// full label truncated with '…'.
  static void _paintLabel(
    Canvas canvas,
    TransactionBlock block,
    Rect blockRect,
    TextStyle style,
  ) {
    final layout = _layoutLabel(block, blockRect, style);
    if (layout == null) return;
    final (:paragraph, :padding, :constraint, text: _) = layout;

    final textX = blockRect.left + padding + (constraint - paragraph.width) / 2;
    final textY = blockRect.top + (blockRect.height - paragraph.height) / 2;

    canvas.drawParagraph(
      paragraph,
      Offset(textX.clamp(blockRect.left + padding, blockRect.right), textY),
    );
  }

  /// Lays out the label [_paintLabel] draws in [block], or null when the
  /// block has no room for any.
  static ({
    String text,
    ui.Paragraph paragraph,
    double padding,
    double constraint,
  })?
  _layoutLabel(TransactionBlock block, Rect blockRect, TextStyle style) {
    // Bucketed to whole pixels so panning by a fraction of a pixel does not
    // miss the cache; the sub-pixel difference only shifts the ellipsis point.
    double? constraintFor(double padding) {
      final available = blockRect.width - padding * 2;
      return available < 6 ? null : available.floorToDouble();
    }

    final full = block.label;
    final short = block.shortLabel;
    if (full != null) {
      final constraint = constraintFor(_labelPadding);
      if (constraint != null) {
        final paragraph = _labelParagraph(
          text: full,
          constraint: constraint,
          style: style,
          isSelected: block.isSelected,
          isError: block.isError,
        );
        if (!paragraph.didExceedMaxLines || short == null) {
          return (
            text: full,
            paragraph: paragraph,
            padding: _labelPadding,
            constraint: constraint,
          );
        }
      }
    }
    if (short == null) return null;
    final constraint = constraintFor(_shortLabelPadding);
    if (constraint == null) return null;
    return (
      text: short,
      paragraph: _labelParagraph(
        text: short,
        constraint: constraint,
        style: style,
        isSelected: block.isSelected,
        isError: block.isError,
      ),
      padding: _shortLabelPadding,
      constraint: constraint,
    );
  }

  /// Returns a laid-out paragraph for [text], building it only on a cache
  /// miss. Paragraph construction and layout is the dominant per-label cost,
  /// and an uncached paragraph is also never released.
  static ui.Paragraph _labelParagraph({
    required String text,
    required double constraint,
    required TextStyle style,
    required bool isSelected,
    required bool isError,
  }) {
    final fontSize = style.fontSize ?? 10;
    final key =
        '$constraint|$fontSize|${style.fontFamily}|'
        '${isSelected ? 1 : 0}${isError ? 1 : 0}|$text';

    final cached = _paragraphCache.remove(key);
    if (cached != null) {
      // Re-insert to refresh recency.
      _paragraphCache[key] = cached;
      return cached;
    }

    final labelColor = isError
        ? const Color(0xFFFFCDD2) // Red 100 — readable on error background
        : const Color(0xFFE8EAF6); // Indigo 50 — readable on dark backgrounds

    final paragraph =
        (ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  textDirection: ui.TextDirection.ltr,
                  maxLines: 1,
                  ellipsis: '…',
                ),
              )
              ..pushStyle(
                ui.TextStyle(
                  color: labelColor,
                  fontSize: fontSize,
                  fontWeight: isSelected
                      ? ui.FontWeight.w600
                      : ui.FontWeight.w400,
                  fontFamily: style.fontFamily,
                  fontFamilyFallback: style.fontFamilyFallback,
                ),
              )
              ..addText(text))
            .build()
          ..layout(ui.ParagraphConstraints(width: constraint));

    if (_paragraphCache.length >= _paragraphCacheCapacity) {
      final oldestKey = _paragraphCache.keys.first;
      _paragraphCache.remove(oldestKey)?.dispose();
    }
    _paragraphCache[key] = paragraph;
    return paragraph;
  }
}
