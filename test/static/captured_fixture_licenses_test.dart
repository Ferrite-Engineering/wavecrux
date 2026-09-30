// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Guardrail: every fixture in a captured/ directory must be listed in that
// directory's PROVENANCE.md with a license drawn from the permissive
// allow-list. Captured fixtures derive from public open-source projects;
// the allow-list keeps the corpus compatible with the closed-source
// distribution of the Pro overlay and avoids GPL/AGPL contamination.
//
// Two checks are enforced:
//   1. Every license entry in every PROVENANCE.md is on the allow-list.
//   2. Every committed captured fixture file has a matching entry header in
//      its directory's PROVENANCE.md (so the snapshot was attributed before
//      it was checked in — no anonymous traces).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// SPDX identifiers permitted for captured fixtures. Keep in sync with
/// the documented allow-list in every captured/PROVENANCE.md template.
const _allowedLicenses = <String>{
  'MIT',
  'BSD-2-Clause',
  'BSD-3-Clause',
  'Apache-2.0',
  'ISC',
  'CC0-1.0',
  'public-domain',
};

void main() {
  group('captured fixture license compliance', () {
    test('every PROVENANCE.md license is on the allow-list', () {
      final violations = <String>[];
      for (final provenance in _findProvenanceFiles()) {
        final body = _stripFencedBlocks(provenance.readAsStringSync());
        for (final match in RegExp(
          r'\*\*License:\*\*\s*[^\n]*?\(SPDX:\s*`([^`]+)`\)',
        ).allMatches(body)) {
          final spdx = match.group(1)!.trim();
          if (!_allowedLicenses.contains(spdx)) {
            violations.add(
              '${p.relative(provenance.path)}: SPDX `$spdx` not in allow-list',
            );
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'captured fixtures must use a license from $_allowedLicenses:'
            '\n  ${violations.join('\n  ')}',
      );
    });

    test('every captured fixture file has a PROVENANCE.md entry', () {
      final orphans = <String>[];
      for (final provenance in _findProvenanceFiles()) {
        final dir = provenance.parent;
        final body = provenance.readAsStringSync();
        for (final fixture in _capturedFixtures(dir)) {
          final basename = p.basename(fixture.path);
          // PROVENANCE block headers look like:  ## `<basename>` — <summary>
          final headerPattern = RegExp('##\\s+`${RegExp.escape(basename)}`');
          if (!headerPattern.hasMatch(body)) {
            orphans.add(p.relative(fixture.path));
          }
        }
      }
      expect(
        orphans,
        isEmpty,
        reason:
            'captured fixtures lacking a matching '
            'PROVENANCE.md entry:\n  ${orphans.join('\n  ')}\n'
            'Add a block to the corresponding captured/PROVENANCE.md (see '
            'the template at the top of the file).',
      );
    });
  });
}

/// Strips fenced ```…``` code blocks from a markdown body so the regex
/// doesn't match the placeholder block template at the bottom of each
/// PROVENANCE.md (which carries `<identifier>` examples).
String _stripFencedBlocks(String markdown) {
  return markdown.replaceAll(RegExp(r'```[\s\S]*?```'), '');
}

Iterable<File> _findProvenanceFiles() sync* {
  // Protocol-decoder captures and FSM captures share the same
  // `<root>/<name>/captured/PROVENANCE.md` layout and the same allow-list.
  final roots = [
    'test/fixtures/protocol',
    'verification/fixtures/protocol',
    'test/fixtures/fsm',
    'verification/fixtures/fsm',
  ];
  for (final root in roots) {
    final rootDir = Directory(root);
    if (!rootDir.existsSync()) continue;
    for (final entity in rootDir.listSync()) {
      if (entity is! Directory) continue;
      final provenance = File(p.join(entity.path, 'captured', 'PROVENANCE.md'));
      if (provenance.existsSync()) yield provenance;
    }
  }
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
