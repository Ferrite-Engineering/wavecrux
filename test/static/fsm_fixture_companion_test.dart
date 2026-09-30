// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guardrail (FSM robustness plan — Layer B).
//
// Every FSM fixture trace (.vcd / .fst / .vcd.zst) under a machine's
// generated/ or captured/ directory must have a sibling
// `<name>.expected_fsm.json` golden, and the corpus must be non-empty — so a
// new machine (or a future captured trace) physically cannot ship without a
// committed golden. Mirror of `captured_fixture_companion_test.dart`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('FSM fixture companions', () {
    test('the generated corpus is non-empty', () {
      final traces = _allFsmTraces('test/fixtures/fsm');
      expect(
        traces,
        isNotEmpty,
        reason:
            'no FSM fixtures found — run '
            '`dart run tool/generate_fsm_fixtures.dart`',
      );
    });

    test('every FSM fixture has a sibling .expected_fsm.json', () {
      final orphans = <String>[];
      for (final root in const [
        'test/fixtures/fsm',
        'verification/fixtures/fsm',
      ]) {
        for (final trace in _allFsmTraces(root)) {
          final base = trace.path
              .replaceFirst(RegExp(r'\.vcd\.zst$'), '')
              .replaceFirst(RegExp(r'\.(vcd|fst)$'), '');
          if (!File('$base.expected_fsm.json').existsSync()) {
            orphans.add(p.relative(trace.path));
          }
        }
      }
      expect(
        orphans,
        isEmpty,
        reason:
            'FSM fixtures missing a .expected_fsm.json sibling — run '
            'REGENERATE=1 flutter test '
            'test/services/signal_query/fsm_golden_test.dart',
      );
    });
  });
}

/// Every trace file under any `fsm/<machine>/{generated,captured}/`.
List<File> _allFsmTraces(String root) {
  final rootDir = Directory(root);
  if (!rootDir.existsSync()) return const [];
  final out = <File>[];
  for (final machine in rootDir.listSync().whereType<Directory>()) {
    for (final tier in const ['generated', 'captured']) {
      final dir = Directory(p.join(machine.path, tier));
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync().whereType<File>()) {
        final path = file.path;
        if (path.endsWith('.vcd') ||
            path.endsWith('.fst') ||
            path.endsWith('.vcd.zst')) {
          out.add(file);
        }
      }
    }
  }
  return out;
}
