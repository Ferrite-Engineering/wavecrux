// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Guardrail: every `.gtkw` fixture carries its golden snapshot(s) — the gtkw
// analog of the decoders' captured_fixture_companion_test.dart.
//
//   generated/<name>.gtkw  ->  <name>.expected_parse.json
//                          AND  <name>.expected_session.json
//   captured/<name>.gtkw   ->  <name>.expected_parse.json
//
// A `.gtkw` with no parse golden is a "save file nobody ran the parser
// against" — it silently bypasses the auto-discovering golden sweep in
// test/services/session/gtkw_golden_test.dart. Generated saves additionally
// carry the full parse→import golden (captured saves can't — no committed
// dumpfile). Fully filesystem-driven: add a fixture + its golden(s), no test
// edit needed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _generatedDir = 'test/fixtures/gtkw/generated';
const _capturedDir = 'test/fixtures/gtkw/captured';

void main() {
  test('every generated .gtkw has parse + session goldens', () {
    final orphans = <String>[];
    for (final fixture in _gtkwFiles(_generatedDir)) {
      final base = fixture.path.replaceFirst(RegExp(r'\.gtkw$'), '');
      if (!File('$base.expected_parse.json').existsSync()) {
        orphans.add(
          '${p.relative(fixture.path)} → missing .expected_parse.json',
        );
      }
      if (!File('$base.expected_session.json').existsSync()) {
        orphans.add(
          '${p.relative(fixture.path)} → missing .expected_session.json',
        );
      }
    }
    expect(
      orphans,
      isEmpty,
      reason:
          'generated .gtkw fixtures missing a golden:\n  '
          '${orphans.join('\n  ')}\n'
          'Run `dart run tool/generate_gtkw_fixtures.dart`.',
    );
  });

  test('every captured .gtkw has a parse golden', () {
    final captured = _gtkwFiles(_capturedDir);
    expect(
      captured,
      isNotEmpty,
      reason: 'no captured .gtkw fixtures found — corpus mis-laid out',
    );

    final orphans = <String>[];
    for (final fixture in captured) {
      final base = fixture.path.replaceFirst(RegExp(r'\.gtkw$'), '');
      if (!File('$base.expected_parse.json').existsSync()) {
        orphans.add(p.relative(fixture.path));
      }
    }
    expect(
      orphans,
      isEmpty,
      reason:
          'captured .gtkw fixtures missing a sibling '
          '.expected_parse.json:\n  ${orphans.join('\n  ')}\n'
          'Run `dart run tool/generate_gtkw_fixtures.dart`.',
    );
  });
}

List<File> _gtkwFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  return d
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.gtkw'))
      .toList();
}
