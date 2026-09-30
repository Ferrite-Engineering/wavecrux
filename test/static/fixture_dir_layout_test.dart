// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Guardrail: every per-decoder fixture directory under
// test/fixtures/protocol/ and verification/fixtures/protocol/ must
// follow the generated/ + captured/ split — no loose fixture files at
// the <decoder>/ root. The coexistence harness directory `multi/` is
// exempt: it composes from per-decoder corpora rather than holding its
// own.
//
// Catches the failure mode "regenerated a fixture without updating the
// generator to write to generated/" — i.e. a .vcd appearing back at the
// <decoder>/ root.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/os_detritus.dart';

/// Decoder directories exempted from the generated/captured/ split.
/// Open-core has `multi/` for coexistence fixtures; nothing else.
const _exemptDirs = <String>{
  'multi',
};

void main() {
  test('protocol/<decoder>/ has no loose fixture files at its root', () {
    final roots = ['test/fixtures/protocol', 'verification/fixtures/protocol'];
    final violations = <String>[];

    for (final root in roots) {
      final rootDir = Directory(root);
      if (!rootDir.existsSync()) continue;
      for (final entity in rootDir.listSync()) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (_exemptDirs.contains(name)) continue;

        for (final inner in entity.listSync()) {
          if (inner is! File) continue;
          final base = p.basename(inner.path);
          if (base == 'README.md') continue;
          // Opening the corpus in Finder is not a corpus defect. Named
          // detritus only — a dotfile this guard has not been told about is a
          // stray, and is reported.
          if (isOsDetritus(base)) continue;
          violations.add(p.relative(inner.path));
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'loose files at the <decoder>/ root — every fixture must '
          'live in generated/ or captured/:\n  ${violations.join('\n  ')}\n'
          'If this file is a regenerated fixture, update the generator to '
          'write to <decoder>/generated/.',
    );
  });
}
