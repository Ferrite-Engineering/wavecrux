// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Compact in-memory representation of a single signal's value-change list.
//
// Both `WellenProvider` (FFI, desktop/mobile) and `WellenWasmProvider`
// (web/WASM) cache per-signal change lists on the calling isolate so that
// the synchronous query methods (`valueAt`, `changesInRange`, …) never
// have to cross the FFI / JS boundary at query time. The shape of that
// cache dominates the Dart-side memory footprint for multi-GB captures:
// at ~95 bytes per transition (the old `List<SignalChange>` shape), a
// 5 GB / 80 M-transition capture would consume more memory in the Dart
// cache than the entire wellen native heap does for the same data.
//
// [CompactChanges] holds the same data as three flat typed arrays:
//
//   * `times`        — sorted simulation ticks (8 B / change)
//   * `valueOffsets` — start offset into `valueBuf` for each change, plus
//                      a trailing sentinel = `valueBuf.length` so the
//                      slice for change `i` is
//                      `valueBuf[valueOffsets[i] .. valueOffsets[i+1]]`
//                      (4 B / change)
//   * `valueBuf`     — concatenated value bytes (avg ~1–9 B / change for
//                      typical scalar / 32-bit-bus VCDs)
//
// Total ~14–20 bytes/change, a ~5× shrink on real fixtures. The
// change-list is also a single set of three TypedData allocations rather
// than N+1 Dart objects, so it's friendlier to the GC during scrub / pan.
//
// Value-string encoding is **ASCII**, always. wellen guarantees this for
// every supported source format (VCD, FST, GHW): value strings are
// always one of `0/1/x/z/X/Z/H/L/U/W/-`, hex digits, real-number text,
// or a fixed set of bit-vector prefixes. There is no path through which
// a non-ASCII byte reaches `valueBuf`, so `valueAt` skips the UTF-8
// decoder entirely and uses `String.fromCharCodes`, which is several
// times faster on the per-character hot path.
//
// Queries:
//   * `timeAt(idx)`       — O(1) read from `times`
//   * `valueAt(idx)`      — O(value length) ASCII decode, no allocations
//                           beyond the returned `String`
//   * `upperBoundLE` /
//     `lowerBoundGE` /
//     `lowerBoundGT`      — O(log N) binary search on `times`, used by
//                           the public query methods to scope a slice

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/signal_change.dart';

@immutable
class CompactChanges {
  CompactChanges({
    required this.times,
    required this.valueOffsets,
    required this.valueBuf,
    this.xChangeIndex,
  }) : assert(
         valueOffsets.length == times.length + 1,
         'valueOffsets must carry a trailing sentinel',
       ),
       assert(
         times.isEmpty || valueOffsets[times.length] <= valueBuf.length,
         'value buffer must hold every slice up to the sentinel',
       );

  /// Sentinel for a signal that loaded successfully but had no transitions.
  static final empty = CompactChanges(
    times: List<int>.empty(),
    valueOffsets: Uint32List(1),
    valueBuf: Uint8List(0),
  );

  /// Sorted simulation ticks, one per change.
  ///
  /// Typed as `List<int>` rather than `Uint64List` because **64-bit typed
  /// arrays do not exist on the web** (`Uint64List`/`Int64List` throw
  /// `UnsupportedError` under dart2js/DDC — JS has no 64-bit integers). On
  /// desktop/mobile the FFI provider still backs this with a `Uint64List`
  /// (constructed in the worker isolate), so the compact 8-bytes-per-tick
  /// representation is unchanged there; the web provider backs it with a plain
  /// `List<int>`. `valueOffsets` / `valueBuf` stay typed — only the 64-bit
  /// `times` array is unrepresentable on the web.
  final List<int> times;
  final Uint32List valueOffsets;
  final Uint8List valueBuf;

  /// Ascending indexes of the changes whose value carries an unknown bit
  /// (`x` / `X`), as [buildXChangeIndex] computes it, or null when the
  /// builder of this store did not compute one.
  ///
  /// The FFI provider builds it in the worker isolate while it compacts the
  /// value bytes, so the column queries in `display_changes.dart` never scan
  /// a signal's bytes on the UI isolate. A store without one gets it built
  /// lazily, on the first column query that needs it.
  final Uint32List? xChangeIndex;

  int get length => times.length;

  bool get isEmpty => times.isEmpty;

  int timeAt(int idx) => times[idx];

  /// Decodes the value bytes for [idx] as an ASCII string. Wellen
  /// guarantees ASCII for every source format; non-ASCII bytes never
  /// reach `valueBuf`, so the UTF-8 decoder is intentionally skipped.
  String valueAt(int idx) {
    final start = valueOffsets[idx];
    final end = valueOffsets[idx + 1];
    if (start == end) return '';
    return String.fromCharCodes(valueBuf, start, end);
  }

  /// Whether the value at [idx] carries an unknown bit (`x` or `X`) —
  /// the byte-level form of `value.toLowerCase().contains('x')`, without
  /// decoding the value into a [String].
  bool valueContainsX(int idx) {
    final end = valueOffsets[idx + 1];
    for (var b = valueOffsets[idx]; b < end; b++) {
      final c = valueBuf[b];
      if (c == 0x78 || c == 0x58) return true;
    }
    return false;
  }

  /// Whether changes [a] and [b] hold byte-identical values, compared in
  /// place without decoding either one.
  bool sameValue(int a, int b) {
    final aStart = valueOffsets[a];
    final bStart = valueOffsets[b];
    final len = valueOffsets[a + 1] - aStart;
    if (valueOffsets[b + 1] - bStart != len) return false;
    for (var i = 0; i < len; i++) {
      if (valueBuf[aStart + i] != valueBuf[bStart + i]) return false;
    }
    return true;
  }

  /// Returns the index of the last change whose time `<=` [time], or
  /// `-1` if no such change exists.
  int upperBoundLE(int time) {
    var lo = 0;
    var hi = times.length - 1;
    var found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >>> 1;
      if (times[mid] <= time) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  /// Returns the smallest index `i` such that `times[i] >= time`, or
  /// `times.length` if every change is earlier than [time].
  int lowerBoundGE(int time) {
    var lo = 0;
    var hi = times.length;
    while (lo < hi) {
      final mid = (lo + hi) >>> 1;
      if (times[mid] < time) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Returns the smallest index `i` such that `times[i] > time`, or
  /// `times.length` if every change is at or before [time].
  int lowerBoundGT(int time) {
    var lo = 0;
    var hi = times.length;
    while (lo < hi) {
      final mid = (lo + hi) >>> 1;
      if (times[mid] <= time) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Materializes the slice `[startIdx, endIdxExclusive)` as a
  /// `List<SignalChange>`. Used by `changesInRange` after the
  /// boundary binary searches identify the range. Manual loop is
  /// measurably faster than `List.generate` here because the
  /// hot-path reads on `times` (a `Uint64List` on native) / `Uint32List` /
  /// `Uint8List` benefit from bounds-check elimination when the loop bound is
  /// the length of the same backing store.
  List<SignalChange> sliceToList(int startIdx, int endIdxExclusive) {
    final count = endIdxExclusive - startIdx;
    if (count <= 0) return const [];
    final result = List<SignalChange>.filled(count, _placeholder);
    final t = times;
    final off = valueOffsets;
    final buf = valueBuf;
    for (var i = 0; i < count; i++) {
      final idx = startIdx + i;
      final vStart = off[idx];
      final vEnd = off[idx + 1];
      final value = vStart == vEnd
          ? ''
          : String.fromCharCodes(buf, vStart, vEnd);
      result[i] = SignalChange(time: t[idx], value: value);
    }
    return result;
  }

  /// Placeholder used only to construct the result via `List.filled` so
  /// every slot is overwritten in the same loop. Never escapes.
  static const _placeholder = SignalChange(time: 0, value: '');
}

/// The ascending indexes of the changes in a compact store whose value bytes
/// carry an unknown bit (`x` or `X`). One pass over [valueBuf]; sparse, so a
/// signal with no `x` anywhere costs an empty list.
Uint32List buildXChangeIndex(Uint32List valueOffsets, Uint8List valueBuf) {
  final hits = <int>[];
  final n = valueOffsets.length - 1;
  for (var i = 0; i < n; i++) {
    final end = valueOffsets[i + 1];
    for (var b = valueOffsets[i]; b < end; b++) {
      final c = valueBuf[b];
      if (c == 0x78 || c == 0x58) {
        hits.add(i);
        break;
      }
    }
  }
  return Uint32List.fromList(hits);
}

/// Builds a [CompactChanges] from a pre-existing `List<SignalChange>`.
///
/// Used by the `injectLoadedSignal` testing helpers on both providers so
/// existing unit tests can drive the query path without spinning up the
/// worker isolate or the WebAssembly module.
CompactChanges buildCompactFromList(List<SignalChange> changes) {
  if (changes.isEmpty) return CompactChanges.empty;
  final n = changes.length;
  // Plain List<int> (not Uint64List) so this is web-safe — see the note on
  // [CompactChanges.times]. On native the FFI load path passes a Uint64List
  // directly; this helper is used by the injectLoadedSignal test seams.
  final times = List<int>.filled(n, 0);
  final offsets = Uint32List(n + 1);
  // Two passes so we can size valueBuf exactly. First pass records
  // (codeUnit count) per entry; second pass copies. We use codeUnits
  // rather than UTF-8 bytes because [CompactChanges.valueAt] is
  // ASCII-only — non-ASCII input here would round-trip wrong, which
  // is what we want: it surfaces bad fixture data instead of silently
  // mangling it.
  final lengths = Uint32List(n);
  var total = 0;
  for (var i = 0; i < n; i++) {
    final s = changes[i].value;
    lengths[i] = s.length;
    total += s.length;
  }
  final valueBuf = Uint8List(total);
  var cursor = 0;
  for (var i = 0; i < n; i++) {
    times[i] = changes[i].time;
    offsets[i] = cursor;
    final s = changes[i].value;
    for (var c = 0; c < s.length; c++) {
      valueBuf[cursor + c] = s.codeUnitAt(c);
    }
    cursor += lengths[i];
  }
  offsets[n] = cursor;
  // Indexed here, like the worker's load path, so a test seam exercises the
  // same query path a loaded signal does.
  return CompactChanges(
    times: times,
    valueOffsets: offsets,
    valueBuf: valueBuf,
    xChangeIndex: buildXChangeIndex(offsets, valueBuf),
  );
}
