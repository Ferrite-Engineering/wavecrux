// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stems_entry.dart';
import 'package:wavecrux/services/rtl_source/stems_parser.dart';

void main() {
  const parser = StemsParser();

  group('StemsParser — file-table form', () {
    test('module + variable lines using a file id', () {
      const stems = '''
++ comp 0 file /src/cpu.v
++ module top.cpu 0 1
+++ var clk 0 5
+++ var rst 0 6
''';
      final result = parser.parse(stems);
      expect(result.entries, hasLength(3));

      expect(result.entries[0].path, 'top.cpu');
      expect(result.entries[0].sourceFile, '/src/cpu.v');
      expect(result.entries[0].lineNumber, 1);
      expect(result.entries[0].kind, StemsEntryKind.scope);

      expect(result.entries[1].path, 'top.cpu.clk');
      expect(result.entries[1].sourceFile, '/src/cpu.v');
      expect(result.entries[1].lineNumber, 5);
      expect(result.entries[1].kind, StemsEntryKind.variable);

      expect(result.entries[2].path, 'top.cpu.rst');
      expect(result.entries[2].lineNumber, 6);
    });

    test('multiple file-table entries dispatch correctly', () {
      const stems = '''
++ comp 0 file /src/cpu.v
++ comp 1 file /src/alu.v
++ module top.cpu 0 10
+++ var clk 0 12
++ module top.cpu.alu 1 5
+++ var add_o 1 20
''';
      final result = parser.parse(stems);
      expect(result.entries, hasLength(4));
      expect(result.entries[1].sourceFile, '/src/cpu.v');
      expect(result.entries[3].sourceFile, '/src/alu.v');
      expect(result.entries[3].path, 'top.cpu.alu.add_o');
    });

    test('quoted file path with spaces', () {
      const stems = '''
++ comp 0 file "/src/with spaces/cpu.v"
++ module top 0 1
+++ var clk 0 5
''';
      final result = parser.parse(stems);
      expect(result.entries[0].sourceFile, '/src/with spaces/cpu.v');
      expect(result.entries[1].sourceFile, '/src/with spaces/cpu.v');
    });

    test('unknown file id silently drops dependent lines', () {
      const stems = '''
++ comp 0 file /src/cpu.v
++ module top.cpu 7 10
+++ var clk 7 5
''';
      final result = parser.parse(stems);
      // Both `module` and `var` reference unknown file id `7`.
      expect(result.entries, isEmpty);
    });
  });

  group('StemsParser — inline-path form', () {
    test('var with full path and inline file path', () {
      const stems = '''
++ var top.cpu.clk /src/cpu.v 5
++ var top.cpu.rst /src/cpu.v 6
''';
      final result = parser.parse(stems);
      expect(result.entries, hasLength(2));
      expect(result.entries[0].path, 'top.cpu.clk');
      expect(result.entries[0].sourceFile, '/src/cpu.v');
      expect(result.entries[0].lineNumber, 5);
      expect(result.entries[0].kind, StemsEntryKind.variable);
    });

    test('scope with inline path', () {
      const stems = '''
++ scope top.cpu /src/cpu.v 1
''';
      final result = parser.parse(stems);
      expect(result.entries.single.kind, StemsEntryKind.scope);
      expect(result.entries.single.path, 'top.cpu');
    });
  });

  group('StemsParser — robustness', () {
    test('comments and blank lines are skipped', () {
      const stems = '''
# this is a comment
// also a comment

++ comp 0 file /src/cpu.v

++ module top 0 1
+++ var clk 0 5
''';
      final result = parser.parse(stems);
      expect(result.entries, hasLength(2));
    });

    test('unknown directives are ignored', () {
      const stems = '''
++ comp 0 file /src/cpu.v
++ vendor_extension foo bar baz
++ module top 0 1
++ unrelated 1 2 3 4 5
+++ var clk 0 5
+++ also_unrelated stuff 1 2
''';
      final result = parser.parse(stems);
      expect(result.entries, hasLength(2));
      expect(result.entries[0].path, 'top');
      expect(result.entries[1].path, 'top.clk');
    });

    test('malformed lines (too few tokens) are skipped', () {
      const stems = '''
++ comp 0 file /src/cpu.v
++ module
++ module top
++ module top 0
++ module top 0 1
+++ var
+++ var clk
+++ var clk 0
+++ var clk 0 5
''';
      final result = parser.parse(stems);
      expect(result.entries, hasLength(2));
      expect(result.entries[0].path, 'top');
      expect(result.entries[1].path, 'top.clk');
    });

    test('non-numeric line number is rejected', () {
      const stems = '''
++ comp 0 file /src/cpu.v
++ module top 0 1
+++ var clk 0 xyz
+++ var rst 0 10
''';
      final result = parser.parse(stems);
      // module + rst (clk dropped due to bad line number)
      expect(result.entries, hasLength(2));
      expect(result.entries[0].path, 'top');
      expect(result.entries[1].path, 'top.rst');
    });

    test('zero or negative line numbers rejected', () {
      const stems = '''
++ comp 0 file /src/cpu.v
++ module top 0 1
+++ var clk 0 -3
+++ var rst 0 5
''';
      final result = parser.parse(stems);
      // module + rst (clk dropped due to negative line)
      expect(result.entries, hasLength(2));
      expect(result.entries[0].path, 'top');
      expect(result.entries[1].path, 'top.rst');
    });

    test('empty input → empty StemsFile', () {
      final result = parser.parse('');
      expect(result.entries, isEmpty);
    });

    test('windows-style line endings parse correctly', () {
      const stems =
          '++ comp 0 file /src/cpu.v\r\n'
          '++ module top 0 1\r\n'
          '+++ var clk 0 5\r\n';
      final result = parser.parse(stems);
      expect(result.entries, hasLength(2));
      // Stripping `\r` happens at trim().
      expect(result.entries[0].sourceFile, '/src/cpu.v');
    });

    test('+++ var without preceding scope falls back to local name only', () {
      const stems = '''
++ comp 0 file /src/cpu.v
+++ var orphan 0 5
''';
      final result = parser.parse(stems);
      expect(result.entries, hasLength(1));
      expect(result.entries.single.path, 'orphan');
    });

    test('++ var keyword treated as variable with full path', () {
      const stems = '++ var deep.path.signal /src/x.v 12';
      final result = parser.parse(stems);
      expect(result.entries.single.path, 'deep.path.signal');
      expect(result.entries.single.kind, StemsEntryKind.variable);
    });
  });
}
