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
//
// Nor does a packed source's result build the changes it keeps: it is a
// [DisplayChanges] over the store and the kept indexes, and the painters read
// each change's time and value from the store by index. Only a consumer that
// indexes it as a `List<SignalChange>` gets objects, one per access.

import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
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
  DisplayChanges changesForDisplay(
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
      if (compact == null || compact.isEmpty) return DisplayChanges.empty;
      return _decimate(
        _CompactView(compact),
        compact.lowerBoundGE(start),
        compact.lowerBoundGE(end),
        ticksPerColumn: ticksPerColumn,
        columnOrigin: columnOrigin,
        magnitude: magnitude,
      );
    }
    final changes = changesInRange(signalRef, start, end);
    return _decimate(
      _ListView(changes),
      0,
      changes.length,
      ticksPerColumn: ticksPerColumn,
      columnOrigin: columnOrigin,
      magnitude: magnitude,
    );
  }
}

/// A lane's time-ordered changes as the column queries return them.
///
/// A `List<SignalChange>` for any consumer, plus [timeAt] and [valueAt],
/// which read one field without building the change. The painters read
/// through these two, so a result over a packed store never builds the
/// objects: it holds the kept changes' times, gathered up front (every frame
/// reads them, and picks spread over a store of millions of changes would
/// otherwise cost a cache miss each), and decodes a value on its first
/// [valueAt], keeping it. A repaint from the same result, which is every
/// frame of a pan inside the cached band, decodes nothing, and the part of
/// the band no frame reaches is never decoded at all.
///
/// One concrete class, so the painters' per-change reads stay monomorphic.
/// Unmodifiable.
final class DisplayChanges extends ListBase<SignalChange> {
  DisplayChanges._(this._times, this._values, this._store, this._picks);

  /// The changes of [store] at [picks] (ascending indexes).
  DisplayChanges._picked(CompactChanges store, List<int> picks)
    : this._(
        _gather(store.times, picks),
        List<String?>.filled(picks.length, null),
        store,
        Uint32List.fromList(picks),
      );

  /// [changes], copied into the same layout.
  factory DisplayChanges.fromList(List<SignalChange> changes) {
    final n = changes.length;
    final times = _newTimes(n);
    final values = List<String?>.filled(n, null);
    for (var i = 0; i < n; i++) {
      final c = changes[i];
      times[i] = c.time;
      values[i] = c.value;
    }
    return DisplayChanges._(times, values, null, null);
  }

  /// [changes] itself when it is already a [DisplayChanges], else a copy —
  /// what lets a painter take any `List<SignalChange>`. The copy is kept
  /// with the list, so a lane that repaints from the same plain list (the
  /// diff lane's XOR trace) copies it once rather than every frame; lane
  /// data is immutable, and a list whose length changed is copied afresh.
  factory DisplayChanges.of(List<SignalChange> changes) {
    if (changes is DisplayChanges) return changes;
    if (changes.isEmpty) return empty;
    final cached = _copies[changes];
    if (cached != null && cached.length == changes.length) return cached;
    return _copies[changes] = DisplayChanges.fromList(changes);
  }

  static final Expando<DisplayChanges> _copies = Expando<DisplayChanges>(
    'display changes copy',
  );

  /// No changes.
  static final DisplayChanges empty = DisplayChanges.fromList(const []);

  /// Times in a `Uint64List` on native, which keeps large ticks unboxed; the
  /// web has no 64-bit typed array (see [CompactChanges.times]).
  static List<int> _newTimes(int n) =>
      kIsWeb ? List<int>.filled(n, 0) : Uint64List(n);

  static List<int> _gather(List<int> times, List<int> picks) {
    final n = picks.length;
    final out = _newTimes(n);
    for (var i = 0; i < n; i++) {
      out[i] = times[picks[i]];
    }
    return out;
  }

  final List<int> _times;

  /// Decoded values; null until first read for a packed result.
  final List<String?> _values;

  /// The store a packed result decodes from, and the index in it of each
  /// change; null for a result copied from a list, whose values are all set.
  final CompactChanges? _store;
  final Uint32List? _picks;

  @override
  int get length => _times.length;

  /// The time of change [i].
  int timeAt(int i) => _times[i];

  /// The value of change [i].
  String valueAt(int i) => _values[i] ?? _decode(i);

  String _decode(int i) => _values[i] = _store!.valueAt(_picks![i]);

  @override
  SignalChange operator [](int index) =>
      SignalChange(time: _times[index], value: valueAt(index));

  @override
  set length(int newLength) =>
      throw UnsupportedError('DisplayChanges is unmodifiable');

  @override
  void operator []=(int index, SignalChange value) =>
      throw UnsupportedError('DisplayChanges is unmodifiable');
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
DisplayChanges decimateChanges(
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

DisplayChanges _decimate(
  _ChangeView view,
  int startIdx,
  int endIdx, {
  required double ticksPerColumn,
  required double columnOrigin,
  required double Function(String value)? magnitude,
}) {
  if (endIdx <= startIdx) return DisplayChanges.empty;
  if (!(ticksPerColumn > 0) || !ticksPerColumn.isFinite) {
    return view.slice(startIdx, endIdx);
  }
  final out = <int>[];
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
      out.add(i);
      if (j - i == 2) out.add(i + 1);
    } else {
      _pickColumn(view, i, j, magnitude, picks);
      out.addAll(picks);
    }
    i = j;
  }
  return view.pick(out);
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

  /// The changes `[from, to)`.
  DisplayChanges slice(int from, int to);

  /// The changes at [indexes], ascending.
  DisplayChanges pick(List<int> indexes);
}

final class _CompactView extends _ChangeView {
  _CompactView(this.c);

  final CompactChanges c;

  @override
  int timeAt(int i) => c.times[i];

  @override
  String valueAt(int i) => c.valueAt(i);

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
  DisplayChanges slice(int from, int to) =>
      DisplayChanges._picked(c, [for (var i = from; i < to; i++) i]);

  @override
  DisplayChanges pick(List<int> indexes) => DisplayChanges._picked(c, indexes);
}

final class _ListView extends _ChangeView {
  _ListView(this.changes);

  final List<SignalChange> changes;

  @override
  int timeAt(int i) => changes[i].time;

  @override
  String valueAt(int i) => changes[i].value;

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
  DisplayChanges slice(int from, int to) => DisplayChanges.of(
    from == 0 && to == changes.length ? changes : changes.sublist(from, to),
  );

  @override
  DisplayChanges pick(List<int> indexes) =>
      DisplayChanges.fromList([for (final k in indexes) changes[k]]);
}

bool _stringHasX(String value) {
  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    if (c == 0x78 || c == 0x58) return true;
  }
  return false;
}

/// Indexes of the changes whose value carries an unknown bit, per packed
/// store. A store loaded by the FFI provider carries one built in the worker
/// isolate ([CompactChanges.xChangeIndex]); any other is indexed on the first
/// column query that needs it — one pass over the value bytes — and the
/// index is dropped with the store when the signal is unloaded.
final Expando<Uint32List> _xIndexes = Expando<Uint32List>('x change index');

Uint32List _xIndex(CompactChanges c) =>
    c.xChangeIndex ??
    (_xIndexes[c] ??= buildXChangeIndex(c.valueOffsets, c.valueBuf));
