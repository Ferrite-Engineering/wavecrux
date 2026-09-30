// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/signal_group.dart';

/// Fixed render height of a [SignalEntryKind.group] header row, in logical
/// pixels. Device-class independent — see [LaneMetrics] for why.
const double kGroupHeaderHeight = 22;

/// Fixed render height of a [SignalEntryKind.separator] row, in logical pixels.
const double kSeparatorHeight = 10;

/// Fixed render height of a [SignalEntryKind.comment] row, in logical pixels.
const double kCommentHeight = 22;

/// Default render height of one translator child (subfield) row, in logical
/// pixels. Slightly shorter than a signal lane — child rows are denser. The
/// touch hit-target for the expand affordance is enlarged independently via
/// `MobileMetrics`, so this stays device-class independent for alignment.
const double kChildRowHeight = 18;

/// The resolved per-row heights fed into [LaneGeometry].
///
/// [minLaneHeight] is the only device-class-dependent input (44 dp on touch,
/// 16 dp on desktop — see `MobileMetrics.minLaneHeight`); the three structural
/// heights are fixed across every device class because bumping a group header,
/// separator, or comment up to the touch floor would push it out of vertical
/// alignment with the wave it sits between.
///
/// This is a value type with structural equality so it can key a Riverpod
/// family: all three per-row columns resolve an *equal* [LaneMetrics] and so
/// share a single cached [LaneGeometry] instance.
@immutable
class LaneMetrics {
  const LaneMetrics({
    required this.minLaneHeight,
    this.groupHeaderHeight = kGroupHeaderHeight,
    this.separatorHeight = kSeparatorHeight,
    this.commentHeight = kCommentHeight,
    this.childRowHeight = kChildRowHeight,
  });

  /// Lower bound applied to a signal row's stored [SignalEntry.laneHeight] at
  /// render time. Never mutates the stored value ("store raw, render clamped").
  final double minLaneHeight;

  /// Render height of a group-header row.
  final double groupHeaderHeight;

  /// Render height of a separator row.
  final double separatorHeight;

  /// Render height of a comment row.
  final double commentHeight;

  /// Render height of one translator child (subfield) row.
  final double childRowHeight;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaneMetrics &&
          other.minLaneHeight == minLaneHeight &&
          other.groupHeaderHeight == groupHeaderHeight &&
          other.separatorHeight == separatorHeight &&
          other.commentHeight == commentHeight &&
          other.childRowHeight == childRowHeight;

  @override
  int get hashCode => Object.hash(
    minLaneHeight,
    groupHeaderHeight,
    separatorHeight,
    commentHeight,
    childRowHeight,
  );
}

/// One flattened row's vertical geometry.
@immutable
class LaneRow {
  const LaneRow({
    required this.entry,
    required this.top,
    required this.height,
    this.childRows = 0,
  });

  /// The entry this row renders.
  final SignalEntry entry;

  /// Top offset of this row from the first row, in logical pixels.
  final double top;

  /// Rendered height of this row (already clamped for signal rows, and inflated
  /// to include any reserved translator child-row space).
  final double height;

  /// Number of translator child (subfield) rows reserved within [height] below
  /// this signal's own value. `0` when the row is collapsed or not bound to a
  /// child-producing translator. The value column renders this many child rows;
  /// the canvas and names list reserve the matching space.
  final int childRows;

  /// Bottom edge of this row (`top + height`). This is the row boundary the
  /// signal-names resize handle straddles.
  double get bottom => top + height;
}

/// The single shared source of truth for waveform-lane vertical geometry.
///
/// Given the ordered top-level [entries] (groups recursed into, collapsed
/// groups skipped) and the resolved [metrics], it computes every flattened
/// row's [LaneRow.height] and cumulative [LaneRow.top]. All three per-row
/// columns — the signal-names list, the waveform canvas, and the value column —
/// source row heights from here (via [heightForEntry]) so they cannot drift
/// out of vertical alignment with one another.
///
/// **Store raw, render clamped.** [heightForEntry] clamps a signal row's stored
/// [SignalEntry.laneHeight] up to [LaneMetrics.minLaneHeight] *only at render
/// time*; the stored value is never flattened. A desktop session with a sub-44
/// dp lane therefore re-opens at its stored height on desktop. This clamp lives
/// here and nowhere else.
///
/// XOR-diff lanes and protocol-transaction lanes are *not* modelled here: they
/// are conditional, are sized by their own shared constants (`diffXorLaneHeight`
/// / `transactionLaneHeight`), and are layered on identically by the canvas and
/// value column. [totalHeight] and [rows] therefore describe the pure
/// signal/group/separator/comment stack.
@immutable
class LaneGeometry {
  /// Builds the geometry for [entries] under [metrics].
  factory LaneGeometry({
    required List<SignalEntry> entries,
    required LaneMetrics metrics,
    Map<String, int> childRowCounts = const {},
  }) {
    final rows = <LaneRow>[];
    var top = 0.0;
    void visit(List<SignalEntry> es) {
      for (final entry in es) {
        final childRows = entry.kind == SignalEntryKind.signal
            ? (childRowCounts[entry.id] ?? 0)
            : 0;
        final height = heightForEntry(entry, metrics, childRows: childRows);
        rows.add(
          LaneRow(
            entry: entry,
            top: top,
            height: height,
            childRows: childRows,
          ),
        );
        top += height;
        if (entry.kind == SignalEntryKind.group && !entry.collapsed) {
          visit(entry.children);
        }
      }
    }

    visit(entries);
    return LaneGeometry._(rows: List.unmodifiable(rows), metrics: metrics);
  }

  const LaneGeometry._({required this.rows, required this.metrics});

  /// The flattened rows, in display order.
  final List<LaneRow> rows;

  /// The metrics this geometry was computed under.
  final LaneMetrics metrics;

  /// Total stacked height of all rows (excludes XOR-diff / transaction lanes).
  double get totalHeight => rows.isEmpty ? 0.0 : rows.last.bottom;

  /// Top offset of the row at flattened [index].
  double topAt(int index) => rows[index].top;

  /// Rendered height of the row at flattened [index].
  double heightAt(int index) => rows[index].height;

  /// The rendered height of [entry] under [metrics].
  ///
  /// This is the **one** place the signal-row min-height clamp and the fixed
  /// structural heights are applied. Every column calls through here (directly
  /// for leaf rows, or via [LaneGeometry] for the flattened stack), so a
  /// per-row height can never be re-derived inconsistently.
  /// [childRows] reserves additional height for that many translator child
  /// (subfield) rows below a signal's own value — the one place expanded-row
  /// height is computed, so the three columns reserve identical space.
  static double heightForEntry(
    SignalEntry entry,
    LaneMetrics metrics, {
    int childRows = 0,
  }) => switch (entry.kind) {
    SignalEntryKind.signal =>
      math.max(entry.laneHeight, metrics.minLaneHeight) +
          childRows * metrics.childRowHeight,
    SignalEntryKind.group => metrics.groupHeaderHeight,
    SignalEntryKind.separator => metrics.separatorHeight,
    SignalEntryKind.comment => metrics.commentHeight,
  };
}

/// The **row id** of the one selected signal, when exactly one is selected and
/// it is on this canvas — otherwise `null`.
///
/// **The trap this exists to close.** `selectedVariablesProvider` is keyed by
/// `Variable.fullPath` (row identity), *not* by `signalRef`. Those are two
/// different opaque strings for the same signal, and comparing a selection
/// value against `LaneRow.entry.signalRef` silently never matches — the caller
/// sees "nothing is selected" while the user is looking at a highlighted row.
/// It shipped that way twice, in the band confine control and in Add
/// Annotation at Cursor, and both times the mistake was invisible: no crash, no
/// log, just a control that never appeared or an action that refused.
///
/// `fullPath` is also exactly what `SignalEntry.signalPath` holds and what
/// `Annotation.rowId` means, so the selected value *is* the row id — no lookup
/// through `signalVariablesByPathProvider` is needed, only a check that the row
/// is currently on the canvas.
///
/// Pure and geometry-in so it can be unit-tested without a container, and so
/// there is one implementation rather than one per call site.
String? singleSelectedRowId(LaneGeometry geometry, Set<String> selection) {
  if (selection.length != 1) return null;
  final candidate = selection.first;
  for (final row in geometry.rows) {
    if (row.entry.signalPath == candidate) return candidate;
  }
  return null;
}
