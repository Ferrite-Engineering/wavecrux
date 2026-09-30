// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Range queries that answer from the packed per-signal change store instead
// of materializing one `SignalChange` (and one `String`) per transition.
//
// `WaveformDataSource.changesInRange` returns every change in the range as an
// object, which is right for an analysis that must see each one, and wrong
// for anything bounded by a pixel width. A lane at fit-all on a large trace
// holds hundreds of thousands of transitions in a range the viewport draws in
// ~1600 columns; the painters coalesce them per column anyway, so building
// the objects first is pure UI-thread cost.
//
// [WaveformDataSourceDisplayQueries.changesForDisplay] is the column-bounded
// form: per pixel column it keeps at most the handful of changes the column
// needs to look right (see [decimateChanges]), and it finds each column by
// binary search on the packed `times` array, so a dense lane costs
// O(columns × log changes-per-column) rather than O(changes). The same
// shape — binary search on the sorted store plus a cached per-signal index —
// is what the transaction lane already does.

import 'dart:typed_data';

import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/services/waveform/compact_changes.dart';

/// A [WaveformDataSource] whose loaded signals are held in [CompactChanges],
/// exposed so column-bounded queries can read the packed arrays directly.
///
/// Optional: a source that does not implement it (a test fake, the streaming
/// VCD source) is served by the same queries through
/// [WaveformDataSource.changesInRange], with identical results.
// A class rather than a function type: callers test for it with `is` on a
// data source they already hold.
// ignore: one_member_abstracts
abstract interface class CompactChangesSource {
  /// The packed change store for [signalRef], or null when the signal is not
  /// loaded.
  CompactChanges? compactChangesFor(String signalRef);
}

/// Column-bounded range queries over any [WaveformDataSource].
extension WaveformDataSourceDisplayQueries on WaveformDataSource {
  /// The changes of [signalRef] in `[start, end)` that a lane drawing
  /// [ticksPerColumn] ticks per pixel column needs, in time order. Columns
  /// are laid out from [columnOrigin] (the tick at the left edge of column
  /// zero), so passing the viewport's pan offset aligns them with the
  /// painter's pixel columns.
  ///
  /// See [decimateChanges] for what a column keeps. [magnitude], when given,
  /// also keeps each column's smallest and largest value by that measure —
  /// what an analog lane needs to draw a column's full swing.
  List<SignalChange> changesForDisplay(
    String signalRef,
    int start,
    int end, {
    required double ticksPerColumn,
    double columnOrigin = 0,
    double Function(String value)? magnitude,
  }) {
    final self = this;
    if (self is CompactChangesSource) {
      final compact = (self as CompactChangesSource).compactChangesFor(
        signalRef,
      );
      if (compact == null || compact.isEmpty) return const [];
      return _decimate(
        _CompactView(compact),
        compact.lowerBoundGE(start),
        compact.lowerBoundGE(end),
        ticksPerColumn: ticksPerColumn,
        columnOrigin: columnOrigin,
        magnitude: magnitude,
      );
    }
    return decimateChanges(
      changesInRange(signalRef, start, end),
      ticksPerColumn: ticksPerColumn,
      columnOrigin: columnOrigin,
      magnitude: magnitude,
    );
  }
}

/// Reduces [changes] (time-ordered) to what a lane drawing [ticksPerColumn]
/// ticks per pixel column can show, without losing anything it should show.
///
/// A column holding one or two changes keeps them. A busier column keeps:
///
/// * its first and last change, so the value entering and leaving the column
///   is exact;
/// * when those two hold the same value, the first change in between that
///   does not — so a pulse that starts and ends inside one column (a
///   `0 → 1 → 0` glitch narrower than a pixel) is still two distinct values
///   in that column, which the painters draw as a full-height mark;
/// * the first change carrying an unknown bit, when neither of the above
///   does — the painters keep an `x` sticky across a column, and dropping it
///   would hide it;
/// * with [magnitude], the column's smallest and largest value — the min/max
///   per pixel column an analog trace needs.
///
/// So a column costs at most six entries however many transitions it holds,
/// and a result is bounded by the column count rather than the change count.
/// A non-positive or non-finite [ticksPerColumn] returns [changes] unchanged.
List<SignalChange> decimateChanges(
  List<SignalChange> changes, {
  required double ticksPerColumn,
  double columnOrigin = 0,
  double Function(String value)? magnitude,
}) => _decimate(
  _ListView(changes),
  0,
  changes.length,
  ticksPerColumn: ticksPerColumn,
  columnOrigin: columnOrigin,
  magnitude: magnitude,
);

List<SignalChange> _decimate(
  _ChangeView view,
  int startIdx,
  int endIdx, {
  required double ticksPerColumn,
  required double columnOrigin,
  required double Function(String value)? magnitude,
}) {
  if (endIdx <= startIdx) return const [];
  if (!(ticksPerColumn > 0) || !ticksPerColumn.isFinite) {
    return view.slice(startIdx, endIdx);
  }
  final out = <SignalChange>[];
  final picks = <int>[];
  var i = startIdx;
  while (i < endIdx) {
    final column = ((view.timeAt(i) - columnOrigin) / ticksPerColumn).floor();
    // Times are integral, so the first tick of the next column is the
    // ceiling of its left edge.
    final nextColumnStart = (columnOrigin + (column + 1) * ticksPerColumn)
        .ceil();
    var j = view.firstAtOrAfter(nextColumnStart, i + 1, endIdx);
    if (j <= i) j = i + 1;
    if (j - i <= 2) {
      // The common case at any zoom where changes are not denser than
      // pixels: keep the column as it is.
      out.add(view.changeAt(i));
      if (j - i == 2) out.add(view.changeAt(i + 1));
    } else {
      _pickColumn(view, i, j, magnitude, picks);
      for (final k in picks) {
        out.add(view.changeAt(k));
      }
    }
    i = j;
  }
  return out;
}

/// Fills [picks] with the indexes a column of three or more changes,
/// `[first, endExclusive)`, keeps, in ascending order. See [decimateChanges].
void _pickColumn(
  _ChangeView view,
  int first,
  int endExclusive,
  double Function(String value)? magnitude,
  List<int> picks,
) {
  final last = endExclusive - 1;
  picks
    ..clear()
    ..add(first);
  var anyX = view.hasX(first) || view.hasX(last);
  if (view.sameValue(first, last)) {
    for (var m = first + 1; m < last; m++) {
      if (!view.sameValue(m, last)) {
        picks.add(m);
        anyX = anyX || view.hasX(m);
        break;
      }
    }
  }
  if (!anyX) {
    final x = view.firstXIn(first + 1, last);
    if (x >= 0) picks.add(x);
  }
  if (magnitude != null) {
    var minIdx = -1;
    var maxIdx = -1;
    var minV = double.infinity;
    var maxV = double.negativeInfinity;
    for (var m = first; m <= last; m++) {
      final v = magnitude(view.valueAt(m));
      if (!v.isFinite) continue;
      if (v < minV) {
        minV = v;
        minIdx = m;
      }
      if (v > maxV) {
        maxV = v;
        maxIdx = m;
      }
    }
    if (minIdx >= 0) picks.add(minIdx);
    if (maxIdx >= 0) picks.add(maxIdx);
  }
  picks.add(last);
  if (picks.length > 2) {
    picks.sort();
    // Remove repeats in place (a pick can coincide with first or last).
    var w = 1;
    for (var r = 1; r < picks.length; r++) {
      if (picks[r] != picks[w - 1]) picks[w++] = picks[r];
    }
    picks.length = w;
  }
}

/// Read access to one signal's time-ordered changes, by index.
abstract class _ChangeView {
  int timeAt(int i);
  String valueAt(int i);
  SignalChange changeAt(int i);
  bool hasX(int i);
  bool sameValue(int a, int b);

  /// The first index in `[from, to)` whose value carries an unknown bit, or
  /// -1 when none does.
  int firstXIn(int from, int to);

  /// The first index in `[from, to)` whose time is at or after [time], or
  /// [to] when none is. Galloping search from [from], so a column that holds
  /// k changes is crossed in O(log k).
  int firstAtOrAfter(int time, int from, int to) {
    if (from >= to || timeAt(from) >= time) return from;
    // timeAt(lo) < time is invariant.
    var lo = from;
    var step = 1;
    var hi = from + step;
    while (hi < to && timeAt(hi) < time) {
      lo = hi;
      step <<= 1;
      hi = from + step;
    }
    if (hi > to) hi = to;
    // Answer is in (lo, hi].
    var a = lo + 1;
    var b = hi;
    while (a < b) {
      final mid = (a + b) >>> 1;
      if (timeAt(mid) < time) {
        a = mid + 1;
      } else {
        b = mid;
      }
    }
    return a;
  }

  List<SignalChange> slice(int from, int to) => [
    for (var i = from; i < to; i++) changeAt(i),
  ];
}

final class _CompactView extends _ChangeView {
  _CompactView(this.c);

  final CompactChanges c;

  @override
  int timeAt(int i) => c.times[i];

  @override
  String valueAt(int i) => c.valueAt(i);

  @override
  SignalChange changeAt(int i) =>
      SignalChange(time: c.times[i], value: c.valueAt(i));

  @override
  bool hasX(int i) => c.valueContainsX(i);

  @override
  bool sameValue(int a, int b) => c.sameValue(a, b);

  @override
  int firstXIn(int from, int to) {
    final xs = _xIndex(c);
    if (xs.isEmpty) return -1;
    var lo = 0;
    var hi = xs.length;
    while (lo < hi) {
      final mid = (lo + hi) >>> 1;
      if (xs[mid] < from) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < xs.length && xs[lo] < to ? xs[lo] : -1;
  }

  @override
  List<SignalChange> slice(int from, int to) => c.sliceToList(from, to);
}

final class _ListView extends _ChangeView {
  _ListView(this.changes);

  final List<SignalChange> changes;

  @override
  int timeAt(int i) => changes[i].time;

  @override
  String valueAt(int i) => changes[i].value;

  @override
  SignalChange changeAt(int i) => changes[i];

  @override
  bool hasX(int i) => _stringHasX(changes[i].value);

  @override
  bool sameValue(int a, int b) => changes[a].value == changes[b].value;

  @override
  int firstXIn(int from, int to) {
    for (var i = from; i < to; i++) {
      if (_stringHasX(changes[i].value)) return i;
    }
    return -1;
  }

  @override
  List<SignalChange> slice(int from, int to) =>
      from == 0 && to == changes.length ? changes : changes.sublist(from, to);
}

bool _stringHasX(String value) {
  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    if (c == 0x78 || c == 0x58) return true;
  }
  return false;
}

/// Indexes of the changes whose value carries an unknown bit, per packed
/// store. Built on the first column query that needs it — one pass over the
/// value bytes — and dropped with the store when the signal is unloaded.
/// Sparse: a signal with no `x` anywhere costs an empty list.
final Expando<Uint32List> _xIndexes = Expando<Uint32List>('x change index');

Uint32List _xIndex(CompactChanges c) {
  final cached = _xIndexes[c];
  if (cached != null) return cached;
  final hits = <int>[];
  for (var i = 0; i < c.length; i++) {
    if (c.valueContainsX(i)) hits.add(i);
  }
  final index = Uint32List.fromList(hits);
  _xIndexes[c] = index;
  return index;
}
