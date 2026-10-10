// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Guards that CompactChanges is backing-store-agnostic for its `times` array.
//
// `times` is typed `List<int>` (not `Uint64List`) because 64-bit typed arrays
// throw `UnsupportedError` on the web. On native the FFI provider backs it with
// a `Uint64List`; on web the WASM provider backs it with a plain `List<int>`.
// Both must drive the synchronous query path (valueAt / changesInRange /
// binary searches) identically. This test runs the query path over both
// backings to prove the widening didn't change behavior and to lock in the
// web-safe representation. (The real web bridge is covered by the Pro web
// integration test; this is the VM-runnable equivalence guard.)

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/services/waveform/compact_changes.dart';

CompactChanges _build(List<int> times, List<String> values) {
  assert(times.length == values.length, 'times/values length mismatch');
  final n = times.length;
  final offsets = Uint32List(n + 1);
  var total = 0;
  for (final v in values) {
    total += v.length;
  }
  final buf = Uint8List(total);
  var cursor = 0;
  for (var i = 0; i < n; i++) {
    offsets[i] = cursor;
    final s = values[i];
    for (var c = 0; c < s.length; c++) {
      buf[cursor + c] = s.codeUnitAt(c);
    }
    cursor += s.length;
  }
  offsets[n] = cursor;
  return CompactChanges(times: times, valueOffsets: offsets, valueBuf: buf);
}

void main() {
  // The same logical change-list, expressed with two different `times`
  // backings: a Uint64List (native FFI representation) and a plain List<int>
  // (web WASM representation). Wellen times here: clk-like toggles.
  const rawTimes = [0, 10, 20, 30, 40, 50];
  const rawValues = ['0', '1', '0', '1', '0', '1'];

  final backings = <String, List<int>>{
    'Uint64List (native)': Uint64List.fromList(rawTimes),
    'List<int> (web)': List<int>.from(rawTimes),
  };

  for (final entry in backings.entries) {
    group('CompactChanges with ${entry.key}', () {
      late CompactChanges c;
      setUp(() => c = _build(entry.value, rawValues));

      test('length / isEmpty / timeAt', () {
        expect(c.length, 6);
        expect(c.isEmpty, isFalse);
        expect(c.timeAt(0), 0);
        expect(c.timeAt(5), 50);
      });

      test('valueAt decodes ASCII value bytes', () {
        expect(c.valueAt(0), '0');
        expect(c.valueAt(1), '1');
        expect(c.valueAt(5), '1');
      });

      test('upperBoundLE finds the change active at a time', () {
        expect(c.upperBoundLE(0), 0);
        expect(c.upperBoundLE(15), 1); // active change is the one at t=10
        expect(c.upperBoundLE(50), 5);
        expect(c.upperBoundLE(-1), -1); // nothing before the first change
      });

      test('lowerBoundGE / lowerBoundGT', () {
        expect(c.lowerBoundGE(20), 2);
        expect(c.lowerBoundGE(25), 3);
        expect(c.lowerBoundGT(20), 3);
        expect(c.lowerBoundGE(100), 6); // past the end
      });

      test('sliceToList materializes a sub-range', () {
        final slice = c.sliceToList(1, 4);
        expect(slice.map((s) => s.time).toList(), [10, 20, 30]);
        expect(slice.map((s) => s.value).toList(), ['1', '0', '1']);
      });
    });
  }

  test('empty sentinel is queryable and web-safe', () {
    final e = CompactChanges.empty;
    expect(e.isEmpty, isTrue);
    expect(e.length, 0);
    expect(e.upperBoundLE(10), -1);
    expect(e.lowerBoundGE(10), 0);
    expect(e.sliceToList(0, 0), isEmpty);
  });

  test('buildCompactFromList round-trips and is web-safe', () {
    final c = buildCompactFromList(const [
      SignalChange(time: 0, value: '0'),
      SignalChange(time: 100, value: '1'),
    ]);
    expect(c.length, 2);
    expect(c.timeAt(1), 100);
    expect(c.valueAt(1), '1');
    // No assumption that `times` is a Uint64List — only that it's a List<int>.
    expect(c.times, isA<List<int>>());
  });

  test('buildXChangeIndex lists the changes carrying an unknown bit', () {
    final c = _build(
      [0, 1, 2, 3, 4, 5],
      ['0', 'x', 'b10', 'b1X0', '', 'z'],
    );
    expect(buildXChangeIndex(c.valueOffsets, c.valueBuf), [1, 3]);
    expect(buildXChangeIndex(Uint32List(1), Uint8List(0)), isEmpty);
  });

  test('buildCompactFromList carries the x index, as a load does', () {
    final c = buildCompactFromList(const [
      SignalChange(time: 0, value: '0'),
      SignalChange(time: 5, value: 'X'),
      SignalChange(time: 9, value: '1'),
    ]);
    expect(c.xChangeIndex, [1]);
  });
}
