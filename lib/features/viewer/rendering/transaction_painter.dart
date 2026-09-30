// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
    required this.isError,
    required this.isSelected,
    required this.isDensityBar,
    required this.coalescedCount,
    this.label,
  });

  /// Left edge in canvas coordinates, clamped to the lane.
  final double xStart;

  /// Right edge in canvas coordinates, clamped to the lane.
  final double xEnd;

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
abstract final class TransactionPainter {
  // ── layout constants ──────────────────────────────────────────────────────────

  /// Horizontal margin kept between the lane edge and the first/last block.
  static const double _blockVMargin = 3;

  /// Minimum block width (px) at which the label text is drawn.
  static const double _minWidthForLabel = 24;

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

    final blocks = <TransactionBlock>[];
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
            isError: anyError,
            isSelected: anySelected,
            isDensityBar: true,
            coalescedCount: count,
          ),
        );
        i = j;
        continue;
      }

      blocks.add(
        TransactionBlock(
          xStart: xStart,
          xEnd: xEnd,
          isError: tx.isError,
          isSelected: isSelected(tx),
          isDensityBar: false,
          coalescedCount: 1,
          label: (xEnd - xStart) >= _minWidthForLabel ? tx.label : null,
        ),
      );
      i++;
    }

    return blocks;
  }

  /// Paints all transactions in [transactions] that overlap the currently
  /// visible time window (derived from [timeMapper]) into [laneBounds].
  ///
  /// Pass [selectedTransaction] to highlight a specific block — typically the
  /// row that is selected in the transaction table.
  static void paint({
    required Canvas canvas,
    required Rect laneBounds,
    required List<DecodedTransaction> transactions,
    required TimeMapper timeMapper,
    required Color laneColor,
    required TextStyle labelStyle,
    DecodedTransaction? selectedTransaction,
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
        blockTop,
        block.xEnd,
        blockBottom,
      );
      final rrect = RRect.fromRectAndRadius(
        blockRect,
        const Radius.circular(_cornerRadius),
      );

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

      final label = block.label;
      if (label != null) {
        _paintLabel(
          canvas,
          label,
          blockRect,
          labelStyle,
          isSelected: block.isSelected,
          isError: block.isError,
        );
      }
    }

    canvas.restore();
  }

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

  /// Paints [text] centred within [blockRect], truncating with '…' when
  /// the available width is too narrow.
  static void _paintLabel(
    Canvas canvas,
    String text,
    Rect blockRect,
    TextStyle style, {
    required bool isSelected,
    required bool isError,
  }) {
    final availableWidth = blockRect.width - _labelPadding * 2;
    if (availableWidth < 6) return;

    // Bucketed to whole pixels so panning by a fraction of a pixel does not
    // miss the cache; the sub-pixel difference only shifts the ellipsis point.
    final constraint = availableWidth.floorToDouble();
    final paragraph = _labelParagraph(
      text: text,
      constraint: constraint,
      style: style,
      isSelected: isSelected,
      isError: isError,
    );

    final textX =
        blockRect.left + _labelPadding + (constraint - paragraph.width) / 2;
    final textY = blockRect.top + (blockRect.height - paragraph.height) / 2;

    canvas.drawParagraph(
      paragraph,
      Offset(
        textX.clamp(blockRect.left + _labelPadding, blockRect.right),
        textY,
      ),
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
