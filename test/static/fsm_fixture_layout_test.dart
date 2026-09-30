// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guardrail (FSM robustness plan — Layer B).
//
// Every FSM fixture machine directory must follow the `generated/` +
// `captured/` split — no loose fixture files at the `<machine>/` root. Mirror
// of `fixture_dir_layout_test.dart` for the `test/fixtures/fsm/` tree.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/os_detritus.dart';

void main() {
  test('fsm/<machine>/ has no loose fixture files at its root', () {
    const roots = ['test/fixtures/fsm', 'verification/fixtures/fsm'];
    final violations = <String>[];

    for (final root in roots) {
      final rootDir = Directory(root);
      if (!rootDir.existsSync()) continue;
      for (final machine in rootDir.listSync()) {
        if (machine is! Directory) continue;
        for (final inner in machine.listSync()) {
          // Only the `generated/` and `captured/` subdirectories may hold
          // fixtures; a README at the machine root is fine, as is the
          // detritus an OS writes when someone browses the corpus. Any other
          // dotfile is a stray and is reported.
          if (inner is! File) continue;
          final base = p.basename(inner.path);
          if (base == 'README.md') continue;
          if (isOsDetritus(base)) continue;
          violations.add(p.relative(inner.path));
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'loose files at fsm/<machine>/ root — all fixtures must live '
          'in generated/ or captured/',
    );
  });
}
