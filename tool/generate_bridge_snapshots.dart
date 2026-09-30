// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// tool/generate_bridge_snapshots.dart
//
// Generates the canonical "bridge snapshot" `.expected.json` companions used
// by the Layer 1 cross-bridge equivalence suite (ARCHITECTURE.md §8.9, Layer 1
// — Wellen-vs-Wellen bridge validation).
//
// Both `WellenProvider` (FFI, desktop/mobile) and `WellenWasmProvider` (WASM,
// web) wrap the *same* `wellen` Rust crate. The cross-bridge test asserts they
// return identical query results for every fixture. FFI cannot run inside a
// browser, so the two bridges cannot be diffed in a single process. Instead we
// freeze the FFI side here — this tool runs each fixture through the real
// `WellenProvider` FFI path and records its exact answers for `valueAt`,
// `changesInRange`, `nextTransition`, and `prevTransition` — and commit them.
// The Chrome-headless WASM test then asserts `WellenWasmProvider` reproduces
// the same committed snapshot. Any divergence pinpoints a marshalling-bridge
// bug (FFI pointers vs WASM linear memory), exactly the Layer 1 signal.
//
// The output schema is identical to the hand-authored VCD companions under
// `test/fixtures/vcd/*.expected.json`, so a single reader
// (`bridge_snapshot.dart`) drives the test against both hand and generated
// companions. Signals are keyed by hierarchical full path — the opaque
// `signalRef` is backend-specific and legitimately differs between FFI and WASM.
//
// Usage (requires the wellen FFI library built — `cd native/wellen_ffi &&
// cargo build --release`). Runs under the Flutter test runner because the
// provider pulls in `package:flutter/foundation.dart`, which a bare
// `dart run` cannot load:
//
//   flutter test tool/generate_bridge_snapshots.dart
//
// Regenerate after changing a fixture's waveform. The hand-authored VCD
// companions are NOT touched (they are the Layer 2 known-answer gold); this
// tool only writes the companions listed in `_targets`.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

/// The companions this tool owns. Each entry is `(fixturePath, outputPath)`.
///
/// We deliberately do NOT regenerate `scalar_basics` and `deep_hierarchy` —
/// those hand-authored companions are byte-for-byte consistent with the FFI
/// provider (audited: 0 mismatches), so they remain the independently verified
/// Layer 2 gold.
///
/// The rest are FFI-authoritative here because hand-authoring them is either
/// impossible or proved error-prone:
///   * `direction_test` — no hand companion existed.
///   * `vhdl_types` (GHW) — binary, impossible to hand-author.
///   * `vector_formats` — the hand file carried a stale `valueAt(byte8, 100)`
///     value (`10101010`, the t=30 value, where the held value is `00000111`).
///   * `analog_real` — the hand file used Dart-style real formatting
///     (`0.0`, `1e12`, `-0.0`, `1e-12`, `25.0`) whereas `wellen` emits plain
///     decimal expansions (`0`, `1000000000000`, `-0`, `0.000000000001`, `25`).
/// Both latent errors were caught by `web_cross_bridge_test.dart` and are fixed
/// by regenerating from the real provider output.
const _targets = <(String, String)>[
  (
    'test/fixtures/vcd/direction_test.vcd',
    'test/fixtures/vcd/direction_test.expected.json',
  ),
  (
    'test/fixtures/vcd/vector_formats.vcd',
    'test/fixtures/vcd/vector_formats.expected.json',
  ),
  (
    'test/fixtures/vcd/analog_real.vcd',
    'test/fixtures/vcd/analog_real.expected.json',
  ),
  (
    'test/fixtures/ghw/vhdl_types.ghw',
    'test/fixtures/ghw/vhdl_types.expected.json',
  ),
];

void main() {
  test('generate bridge snapshots', () async {
    for (final (fixture, output) in _targets) {
      final file = File(fixture);
      if (!file.existsSync()) {
        stderr.writeln('SKIP $fixture — fixture not found');
        continue;
      }
      stdout.writeln('Generating $output from $fixture ...');
      final provider = WellenProvider();
      await provider.openFile(fixture);
      final snapshot = await _buildSnapshot(provider);
      provider.close();
      const encoder = JsonEncoder.withIndent('  ');
      File(output).writeAsStringSync('${encoder.convert(snapshot)}\n');
      stdout.writeln('  wrote ${(snapshot['signals'] as Map).length} signals');
    }
    stdout.writeln('Done.');
  });
}

Future<Map<String, dynamic>> _buildSnapshot(WellenProvider p) async {
  final metadata = <String, dynamic>{
    'timescale': p.timescale == null
        ? null
        : {'factor': p.timescale!.factor, 'unit': p.timescale!.unit.name},
    'startTime': p.startTime,
    'endTime': p.endTime,
    'date': p.date,
    'version': p.version,
  };

  final signals = <String, dynamic>{};
  for (final v in p.findVariables(const SignalFilter())) {
    await p.loadSignal(v.signalRef);
    signals[v.fullPath] = _signalProbes(p, v.signalRef, p.endTime);
  }

  return {
    'metadata': metadata,
    'hierarchy': {
      'rootScopes': p.rootScopes.map(_scopeJson).toList(),
    },
    'signals': signals,
  };
}

Map<String, dynamic> _scopeJson(Scope s) => {
  'name': s.name,
  'type': s.type.name,
  'path': s.path,
  'childScopes': s.childScopes.map(_scopeJson).toList(),
  'variables': s.variables.map(_variableJson).toList(),
};

Map<String, dynamic> _variableJson(Variable v) => {
  'name': v.name,
  'fullPath': v.fullPath,
  'varType': v.varType.name,
  'bitWidth': v.bitWidth,
  'direction': v.direction.name,
};

/// Builds the probe set for one signal by *recording the FFI provider's actual
/// answers*. These become the gold the WASM bridge must reproduce.
Map<String, dynamic> _signalProbes(WellenProvider p, String ref, int end) {
  final all = p.changesInRange(ref, 0, end + 1);
  final times = <int>[for (final c in all) c.time];

  // valueAt probe times: before the first change, at and just-before every
  // change, at midpoints, and well past the end.
  final valueTimes = <int>{-1, 0, end, end + 1, end * 2 + 1};
  for (var i = 0; i < times.length; i++) {
    valueTimes
      ..add(times[i])
      ..add(times[i] - 1);
    final next = i + 1 < times.length ? times[i + 1] : end + 1;
    if (next > times[i] + 1) valueTimes.add(times[i] + (next - times[i]) ~/ 2);
  }
  final sortedValueTimes = valueTimes.toList()..sort();

  // changesInRange probes: zero-width, full span, and each adjacent window.
  final ranges = <(int, int)>[
    (0, 0),
    (0, end + 1),
  ];
  for (var i = 0; i < times.length; i++) {
    final lo = times[i];
    final hi = i + 1 < times.length ? times[i + 1] + 1 : end + 1;
    ranges.add((lo, hi));
  }

  final transitionAnchors = <int>{-1, 0, end, end + 1, ...times}.toList()
    ..sort();

  return {
    'allChanges': [for (final c in all) _change(c.time, c.value)],
    'valueAt': [
      for (final t in sortedValueTimes)
        {'time': t, 'expected': p.valueAt(ref, t)},
    ],
    'changesInRange': [
      for (final (lo, hi) in ranges)
        {
          'start': lo,
          'end': hi,
          'expected': [
            for (final c in p.changesInRange(ref, lo, hi))
              _change(c.time, c.value),
          ],
        },
    ],
    'nextTransition': [
      for (final t in transitionAnchors)
        {
          'afterTime': t,
          'expected': _transition(p.nextTransition(ref, t)),
        },
    ],
    'prevTransition': [
      for (final t in transitionAnchors)
        {
          'beforeTime': t,
          'expected': _transition(p.prevTransition(ref, t)),
        },
    ],
  };
}

Map<String, dynamic> _change(int time, String value) => {
  'time': time,
  'value': value,
};

Map<String, dynamic>? _transition(SignalChange? t) =>
    t == null ? null : {'time': t.time, 'value': t.value};
