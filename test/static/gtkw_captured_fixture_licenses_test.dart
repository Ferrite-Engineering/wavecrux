// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Guardrail: every captured `.gtkw` save is attributed in
// test/fixtures/gtkw/captured/PROVENANCE.md with a license drawn from the
// permissive allow-list — the gtkw analog of
// captured_fixture_licenses_test.dart for the protocol decoders.
//
// Captured saves come from public open-source projects; the allow-list keeps
// the corpus compatible with the closed-source distribution of the Pro overlay
// and avoids GPL/AGPL contamination (notably GTKWave's own GPL
// examples/*.gtkw, which are therefore ineligible).
//
// Two checks:
//   1. Every license entry in PROVENANCE.md is on the allow-list.
//   2. Every committed captured `.gtkw` has a matching entry header.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _capturedDir = 'test/fixtures/gtkw/captured';

/// SPDX identifiers permitted for captured fixtures. Kept in sync with the
/// protocol-decoder allow-list and the PROVENANCE.md template.
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
  group('captured .gtkw fixture license compliance', () {
    final provenance = File(p.join(_capturedDir, 'PROVENANCE.md'));

    test('PROVENANCE.md exists', () {
      expect(
        provenance.existsSync(),
        isTrue,
        reason: 'missing $_capturedDir/PROVENANCE.md',
      );
    });

    test('every PROVENANCE.md license is on the allow-list', () {
      final body = _stripFencedBlocks(provenance.readAsStringSync());
      final violations = <String>[];
      for (final match in RegExp(
        r'\*\*License:\*\*\s*[^\n]*?\(SPDX:\s*`([^`]+)`\)',
      ).allMatches(body)) {
        final spdx = match.group(1)!.trim();
        if (!_allowedLicenses.contains(spdx)) {
          violations.add('SPDX `$spdx` not in allow-list');
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'captured .gtkw saves must use a license from '
            '$_allowedLicenses:\n  ${violations.join('\n  ')}',
      );
    });

    test('every captured .gtkw file has a PROVENANCE.md entry', () {
      final body = provenance.readAsStringSync();
      final orphans = <String>[];
      for (final fixture in _gtkwFiles(_capturedDir)) {
        final basename = p.basename(fixture.path);
        final headerPattern = RegExp('##\\s+`${RegExp.escape(basename)}`');
        if (!headerPattern.hasMatch(body)) {
          orphans.add(p.relative(fixture.path));
        }
      }
      expect(
        orphans,
        isEmpty,
        reason:
            'captured .gtkw saves lacking a PROVENANCE.md entry:\n  '
            '${orphans.join('\n  ')}\nAdd a block (see the template).',
      );
    });
  });
}

/// Strips fenced ```…``` blocks so the regex doesn't match the template at the
/// top of PROVENANCE.md (which carries `<identifier>` placeholders).
String _stripFencedBlocks(String markdown) =>
    markdown.replaceAll(RegExp(r'```[\s\S]*?```'), '');

List<File> _gtkwFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  return d
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.gtkw'))
      .toList();
}
