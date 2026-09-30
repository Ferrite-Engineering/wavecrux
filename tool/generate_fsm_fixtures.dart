// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates FSM state-register VCD fixtures for the FSM golden sweep
// (FSM robustness plan — Layer A).
//
// Output (mirrored to both test/ and verification/ trees):
//   test/fixtures/fsm/<machine>/generated/<machine>.vcd
//   verification/fixtures/fsm/<machine>/generated/<machine>.vcd
//
// Usage:
//   dart run tool/generate_fsm_fixtures.dart
//
// This tool is PURE DART (no FFI): it only emits the deterministic .vcd
// files. The matching `.expected_fsm.json` golden is produced by the golden
// sweep test, which parses these VCDs through the REAL wellen FFI and runs
// FsmAnalysisService over the result:
//
//   REGENERATE=1 flutter test test/services/signal_query/fsm_golden_test.dart
//
// Splitting it this way keeps generation FFI-free (a plain `dart run`) while
// the golden reflects exactly what the production parser produces.
//
// Each machine is a single multi-bit `STATE` register under scope `tb`; the
// FSM analyzer reconstructs the state graph from that one signal's value
// changes, so no clock or other signals are needed.
//
// ignore_for_file: avoid_print, prefer_const_constructors

import 'dart:io';

const _testRoot = 'test/fixtures/fsm';
const _verificationRoot = 'verification/fixtures/fsm';

void main() {
  for (final m in _machines) {
    final vcd = _renderVcd(m);
    for (final root in const [_testRoot, _verificationRoot]) {
      final dir = Directory('$root/${m.name}/generated')
        ..createSync(recursive: true);
      File('${dir.path}/${m.name}.vcd').writeAsStringSync(vcd);
    }
  }

  print('Generated FSM fixtures:');
  for (final m in _machines) {
    print('  $_testRoot/${m.name}/generated/${m.name}.vcd');
  }
  print(
    'and in $_verificationRoot/. Now (re)generate the goldens against the '
    'real parser:\n'
    '  REGENERATE=1 flutter test '
    'test/services/signal_query/fsm_golden_test.dart',
  );
}

// ── machine authoring API ────────────────────────────────────────────────────

/// A single FSM scenario: a `width`-bit STATE register that holds [initial]
/// at t=0 and takes each [changes] value at its tick. Values are either an
/// `int` state number or the string `'x'` / `'z'` (emitted as a full-width
/// undefined value, exercising the analyzer's chain-break path through the
/// real parser).
class _Machine {
  const _Machine({
    required this.name,
    required this.width,
    required this.initial,
    required this.changes,
  });

  final String name;
  final int width;
  final Object initial;
  final List<(int, Object)> changes; // (tick, value), strictly increasing
}

String _renderVcd(_Machine m) {
  const id = '!'; // single signal → first printable-ASCII id
  final buf = StringBuffer()
    ..writeln(r'$timescale 1ns $end')
    ..writeln(r'$scope module tb $end')
    ..writeln('\$var wire ${m.width}  $id  STATE \$end')
    ..writeln(r'$upscope $end')
    ..writeln(r'$enddefinitions $end')
    ..writeln(r'$dumpvars')
    ..writeln('${_encode(m.initial, m.width)} $id')
    ..writeln(r'$end');

  for (final (tick, value) in m.changes) {
    buf
      ..writeln('#$tick')
      ..writeln('${_encode(value, m.width)} $id');
  }
  return buf.toString();
}

/// Encodes a state value as a VCD vector literal (`b<bits>`).
String _encode(Object v, int width) {
  if (v is int) {
    return 'b${v.toUnsigned(width).toRadixString(2).padLeft(width, '0')}';
  }
  if (v == 'x' || v == 'z') {
    return 'b${(v as String) * width}';
  }
  if (v is String) return v.startsWith('b') ? v : 'b$v';
  throw StateError('state value must be int or "x"/"z": $v');
}

// ── machine library ──────────────────────────────────────────────────────────

/// Gray code for [i]: `i ^ (i >> 1)`.
int _gray(int i) => i ^ (i >> 1);

final _machines = <_Machine>[
  // Classic 3-state cycle IDLE(0) → GO(1) → STOP(2) → IDLE, three laps.
  // Anchor: exactly 3 states, 9 transitions.
  _Machine(
    name: 'traffic_light',
    width: 2,
    initial: 0,
    changes: [
      for (var lap = 0; lap < 3; lap++) ...[
        (lap * 30 + 10, 1),
        (lap * 30 + 20, 2),
        (lap * 30 + 30, 0),
      ],
    ],
  ),

  // One-hot encoded 8-state walking ring (1,2,4,…,128 → wrap). Sparse:
  // every transition is unique. Anchor: 8 states, 8 transitions.
  _Machine(
    name: 'onehot_8',
    width: 8,
    initial: 1,
    changes: [
      for (var i = 1; i < 8; i++) (i * 10, 1 << i),
      (80, 1), // wrap 128 → 1
    ],
  ),

  // 5-bit Gray-code ring: 32 distinct states, dense large-N case.
  // Anchor: 32 states, 32 transitions (31 steps + wrap).
  _Machine(
    name: 'gray_counter_5bit',
    width: 5,
    initial: _gray(0),
    changes: [
      for (var i = 1; i < 32; i++) (i * 10, _gray(i)),
      (320, _gray(0)), // wrap back to 0
    ],
  ),

  // Undefined-at-boot then settles, with a mid-stream glitch. Exercises the
  // x/z chain-break end-to-end through the real parser. Anchor: 4 states
  // (0,1,2,3), and NO transition crosses an x gap.
  _Machine(
    name: 'glitchy_reset',
    width: 3,
    initial: 'x',
    changes: [
      (10, 0),
      (20, 1), // 0 → 1 recorded
      (30, 'x'), // glitch — chain breaks
      (40, 2), // no transition into 2
      (50, 3), // 2 → 3 recorded
      (60, 0), // 3 → 0 recorded
    ],
  ),
];
