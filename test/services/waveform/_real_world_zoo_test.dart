// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Real-world VCD/FST/GHW parser-robustness zoo sweep.
//
// Walks every committed file in `test/fixtures/real_world/` (FST, VCD,
// or .vcd.zst), opens it via [WellenProvider.openFile], and asserts:
//
//   1. The open call returns without throwing.
//   2. The resulting hierarchy is non-empty (≥1 scope, ≥1 variable).
//   3. At least one signal value can be read at a sampled time.
//   4. A sibling `<name>.provenance.json` exists and parses.
//
// What is NOT acceptable: a process-level crash (Rust panic, SIGSEGV,
// FFI-thread death) that takes down the test runner. Decoder behaviour
// is explicitly NOT exercised here — see `test/services/decoders/`
// captured-fixture sweeps for that.
//
// Adding a file is purely additive — drop the trace + sidecar in and
// re-run this test. No fixture-name list to maintain.
//
// See `test/fixtures/real_world/README.md` for the full corpus charter,
// license allow-list, and acquisition target.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

const _zooDir = 'test/fixtures/real_world';
// wellen 0.20 does not natively decompress .vcd.zst or .vcd.gz — those
// extensions are not in the sweep allow-list. If wellen gains compressed
// input support, add `.zst` / `.gz` here.
const _waveformExtensions = {'.fst', '.vcd', '.ghw'};

/// Recursively collect every variable under [scopes].
List<Variable> _allVariables(List<Scope> scopes) {
  final out = <Variable>[];
  void walk(Scope s) {
    out.addAll(s.variables);
    s.childScopes.forEach(walk);
  }

  scopes.forEach(walk);
  return out;
}

List<File> _discoverFixtures() {
  final dir = Directory(_zooDir);
  if (!dir.existsSync()) return const [];
  return dir.listSync().whereType<File>().where((f) {
    final ext = p.extension(f.path).toLowerCase();
    return _waveformExtensions.contains(ext);
  }).toList()..sort((a, b) => a.path.compareTo(b.path));
}

void main() {
  if (!requireWellenFfiLibrary('real-world zoo sweep')) return;

  group('Real-world parser-robustness zoo', () {
    final fixtures = _discoverFixtures();

    test('zoo directory exists', () {
      expect(
        Directory(_zooDir).existsSync(),
        isTrue,
        reason: 'Expected $_zooDir to exist (commit a .gitkeep if empty).',
      );
    });

    if (fixtures.isEmpty) {
      // Empty zoo is OK — the scaffolding is in place for future
      // contributors. The static guardrail still enforces sidecar
      // discipline once files land.
      test('zoo is currently empty (scaffolding only)', () {
        expect(fixtures, isEmpty);
      });
      return;
    }

    for (final fixture in fixtures) {
      final name = p.basenameWithoutExtension(fixture.path);

      test('$name: opens, hierarchy non-empty, samples one value', () async {
        final provider = WellenProvider();
        try {
          await provider.openFile(fixture.path);
          expect(
            provider.rootScopes,
            isNotEmpty,
            reason: 'Hierarchy should have ≥1 root scope after open.',
          );
          final allVars = _allVariables(provider.rootScopes);
          expect(
            allVars,
            isNotEmpty,
            reason: 'Hierarchy should have ≥1 variable after open.',
          );
          // Sample the first variable's value at t=0 to exercise the
          // signal-query path. We don't care what the value is — just
          // that the query returns without crashing (null is acceptable
          // when the signal has no recorded change at t=0).
          final firstVar = allVars.first;
          await provider.loadSignal(firstVar.signalRef);
          provider.valueAt(firstVar.signalRef, provider.startTime);
        } finally {
          provider.close();
        }
      });

      test('$name: has a parseable .provenance.json sidecar', () {
        final sidecarPath =
            '${p.withoutExtension(fixture.path)}.provenance.json';
        final sidecar = File(sidecarPath);
        expect(
          sidecar.existsSync(),
          isTrue,
          reason: 'Missing sidecar $sidecarPath',
        );
        final json =
            jsonDecode(sidecar.readAsStringSync()) as Map<String, dynamic>;
        expect(
          json['license_spdx'],
          isA<String>(),
          reason: 'sidecar must declare license_spdx',
        );
      });
    }
  });
}
