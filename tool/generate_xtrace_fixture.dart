// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates the X-Trace verification fixture used by the manual
// verification guide §6.2.
//
// Output:
//   verification/fixtures/vcd/xtrace.vcd
//
// Usage:
//   dart run tool/generate_xtrace_fixture.dart
//
// The fixture matches the §6.2.2 spec verbatim:
//   - All signals sit under one `top` scope so they are mutual siblings
//     for the X-Trace causal-chain heuristic.
//   - `data_out` is an 8-bit wire that takes deterministic values up to
//     T=80 ns and then sits at 8'h03 until the upstream X event.
//   - `status` is a 1-bit wire that holds `0` until T=200 ns.
//   - Both `data_out` and `status` go `x` at T=200 ns so the X-Trace
//     causal-chain panel shows `data_out` as the root and `status` as
//     its co-temporal sibling.
//   - `addr`, `clean_sig`, `clk`, `enable` are uninvolved — they hold
//     valid values at T=200 ns so they do NOT show up in the X-Trace
//     overlay or the sibling list.
//
// Simulation range: T=0 to T=300 ns (the guide instructs verifiers to
// place the cursor "near T=200 ns").
//
// ignore_for_file: avoid_print

import 'dart:io';

void main() {
  final lines = <String>[
    r'$timescale 1 ns $end',
    r'$scope module top $end',
    r'$var wire 1 ! clk $end',
    r'$var wire 1 " enable $end',
    r'$var wire 8 # data_out $end',
    r'$var wire 1 $ status $end',
    r'$var wire 8 % addr $end',
    r'$var wire 1 & clean_sig $end',
    r'$upscope $end',
    r'$enddefinitions $end',
    // Initial dump at T=0.
    r'$dumpvars',
    '0!',
    '1"',
    'b00000000 #',
    r'0$',
    'b00010000 %',
    '1&',
    r'$end',
  ];

  void step(int t, List<String> changes) {
    lines.add('#$t');
    lines.addAll(changes);
  }

  // Clock toggling pattern up to T=190 ns. Every 10 ns the clock
  // toggles. Inject sparse changes on the data wires so non-clock
  // signals also exercise transitions before the X event.
  for (var t = 10; t <= 190; t += 10) {
    final clkLevel = (t ~/ 10) % 2 == 0 ? '0' : '1';
    final extras = <String>[];
    if (t == 20) extras.add('b00000001 #');
    if (t == 40) extras.add('b00000010 #');
    if (t == 60) extras.add('b00010001 %');
    if (t == 80) {
      extras
        ..add('b00000011 #')
        ..add('0&');
    }
    step(t, ['$clkLevel!', ...extras]);
  }

  // The X event: data_out and status both go fully X at T=200 ns.
  step(200, ['0!', 'bxxxxxxxx #', r'x$']);

  // Tail clock toggles up to T=300 ns so the canvas has timeline room
  // either side of the X-origin cursor.
  for (var t = 210; t <= 300; t += 10) {
    final clkLevel = (t ~/ 10) % 2 == 0 ? '0' : '1';
    step(t, ['$clkLevel!']);
  }

  const outPath = 'verification/fixtures/vcd/xtrace.vcd';
  File(outPath).writeAsStringSync('${lines.join('\n')}\n');
  print('Wrote $outPath');
}
