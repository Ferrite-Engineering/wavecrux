// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Guardrail: every captured/ fixture file (.vcd / .fst / .vcd.zst) must
// have a sibling <name>.expected_transactions.json snapshot. Captured
// fixtures land in this corpus only after their decode output has been
// hand-verified and committed as a snapshot — a captured fixture with no
// snapshot is a "trace nobody actually ran the decoder against," which
// silently bypasses the auto-discovery sweep.
//
// The check is fully filesystem-driven — adding a captured fixture means
// adding a snapshot, removing one removes both, no test edit required.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('every captured fixture has a sibling .expected_transactions.json', () {
    final capturedDirs = _findCapturedDirs();
    expect(
      capturedDirs,
      isNotEmpty,
      reason:
          'no captured/ directories found under test/fixtures/protocol/ '
          'or verification/fixtures/protocol/ — the corpus is mis-laid out',
    );

    final orphans = <String>[];
    for (final dir in capturedDirs) {
      for (final fixture in _capturedFixtures(dir)) {
        final base = fixture.path
            .replaceFirst(RegExp(r'\.vcd\.zst$'), '')
            .replaceFirst(RegExp(r'\.(vcd|fst)$'), '');
        final snapshot = File('$base.expected_transactions.json');
        if (!snapshot.existsSync()) {
          orphans.add(p.relative(fixture.path));
        }
      }
    }

    expect(
      orphans,
      isEmpty,
      reason:
          'captured fixtures missing a sibling '
          '.expected_transactions.json snapshot:\n  ${orphans.join('\n  ')}\n'
          'Run `dart run tool/regenerate_captured_snapshots.dart` (when it '
          'lands) or hand-run the decoder against the fixture and commit the '
          'JSON output.',
    );
  });
}

List<Directory> _findCapturedDirs() {
  final roots = ['test/fixtures/protocol', 'verification/fixtures/protocol'];
  final out = <Directory>[];
  for (final root in roots) {
    final rootDir = Directory(root);
    if (!rootDir.existsSync()) continue;
    for (final entity in rootDir.listSync()) {
      if (entity is! Directory) continue;
      final captured = Directory(p.join(entity.path, 'captured'));
      if (captured.existsSync()) out.add(captured);
    }
  }
  return out;
}

Iterable<File> _capturedFixtures(Directory captured) sync* {
  for (final entity in captured.listSync()) {
    if (entity is! File) continue;
    final path = entity.path;
    if (path.endsWith('.vcd') ||
        path.endsWith('.fst') ||
        path.endsWith('.vcd.zst')) {
      yield entity;
    }
  }
}
