// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The selection-to-row-id resolver.
//
// **Why this is a file and not three lines inlined at each call site.** The
// signal selection is keyed by `Variable.fullPath`; `LaneRow.entry.signalRef`
// is a different opaque string for the same signal. Comparing one against the
// other never matches, and it fails *silently* — the caller concludes nothing
// is selected while the user is looking at a highlighted row.
//
// That mistake shipped twice. Once in the band confine control,
// where its own widget test seeded the selection with a signalRef and so agreed
// with the bug. Once in Add Annotation at Cursor, where it produced "select
// exactly one signal" for a user who had.

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';

Variable _v(String name) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  // Deliberately unlike the fullPath: `top.clk` vs `ref_clk`. A fixture where
  // the two happened to coincide would pass against the bug.
  signalRef: 'ref_$name',
  scopePath: 'top',
  bitWidth: 8,
);

LaneGeometry _geometry(List<String> names) => LaneGeometry(
  entries: [
    for (final name in names)
      SignalEntry.signal(
        signalRef: _v(name).signalRef,
        displayName: name,
        signalPath: _v(name).fullPath,
      ),
  ],
  metrics: const LaneMetrics(minLaneHeight: 16),
);

void main() {
  test('resolves the single selected row by fullPath', () {
    expect(
      singleSelectedRowId(_geometry(['clk', 'data']), {'top.data'}),
      'top.data',
    );
  });

  test('a signalRef never resolves — that is the whole bug', () {
    // If this ever returns non-null, the resolver has started accepting the
    // wrong key space and both call sites will silently work on the wrong row.
    expect(singleSelectedRowId(_geometry(['clk']), {'ref_clk'}), isNull);
  });

  test('null for zero or several — "the selected lane" has no answer', () {
    final geometry = _geometry(['clk', 'data']);
    expect(singleSelectedRowId(geometry, const {}), isNull);
    expect(singleSelectedRowId(geometry, {'top.clk', 'top.data'}), isNull);
  });

  test('null when the selected signal is not on this canvas', () {
    // Selected in the tree but never added to the view: there is no lane to
    // confine a band to, and no row to anchor a note on.
    expect(singleSelectedRowId(_geometry(['clk']), {'top.data'}), isNull);
  });

  test('skips group headers rather than matching their null path', () {
    final geometry = LaneGeometry(
      entries: [
        const SignalEntry.group(groupName: 'bus'),
        SignalEntry.signal(
          signalRef: 'ref_clk',
          displayName: 'clk',
          signalPath: 'top.clk',
        ),
      ],
      metrics: const LaneMetrics(minLaneHeight: 16),
    );
    expect(singleSelectedRowId(geometry, {'top.clk'}), 'top.clk');
  });
}
