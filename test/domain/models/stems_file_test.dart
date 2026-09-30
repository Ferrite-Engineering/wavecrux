// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stems_entry.dart';
import 'package:wavecrux/domain/models/stems_file.dart';

void main() {
  StemsEntry variable(String path, String file, int line) => StemsEntry(
    path: path,
    sourceFile: file,
    lineNumber: line,
    kind: StemsEntryKind.variable,
  );

  StemsEntry scope(String path, String file, int line) => StemsEntry(
    path: path,
    sourceFile: file,
    lineNumber: line,
    kind: StemsEntryKind.scope,
  );

  group('StemsFile.lookup — exact match', () {
    test('matches a variable entry exactly', () {
      final file = StemsFile(
        entries: [
          variable('top.cpu.clk', '/src/cpu.v', 12),
          variable('top.cpu.rst', '/src/cpu.v', 13),
        ],
      );
      expect(file.lookup('top.cpu.clk')?.lineNumber, 12);
      expect(file.lookup('top.cpu.rst')?.lineNumber, 13);
    });

    test('returns null when path is empty', () {
      final file = StemsFile(entries: [variable('a', 'f', 1)]);
      expect(file.lookup(''), isNull);
    });

    test('returns null when there is no match at any tier', () {
      final file = StemsFile(entries: [variable('top.x', 'f', 1)]);
      expect(file.lookup('other.signal'), isNull);
    });

    test('prefers a variable over a scope at the same path', () {
      final file = StemsFile(
        entries: [
          scope('top.cpu', '/src/cpu.v', 5),
          variable('top.cpu', '/src/cpu.v', 99),
        ],
      );
      // Variable wins.
      expect(file.lookup('top.cpu')?.kind, StemsEntryKind.variable);
      expect(file.lookup('top.cpu')?.lineNumber, 99);
    });
  });

  group('StemsFile.lookup — case-insensitive match', () {
    test('matches uppercase request against lowercase entry', () {
      final file = StemsFile(entries: [variable('top.cpu.clk', 'f.v', 7)]);
      expect(file.lookup('TOP.CPU.CLK')?.lineNumber, 7);
    });

    test('falls through to suffix when case-insensitive miss', () {
      final file = StemsFile(entries: [variable('cpu.alu.add_o', 'f.v', 21)]);
      // Different prefix path, but same trailing name.
      expect(file.lookup('top.alu.add_o')?.lineNumber, 21);
    });
  });

  group('StemsFile.lookup — local-name suffix match', () {
    test('matches by trailing component when full path differs', () {
      final file = StemsFile(entries: [variable('top.dut.cpu.clk', 'f.v', 4)]);
      // Different scope chain, same local name.
      expect(file.lookup('alt.module.clk')?.lineNumber, 4);
    });

    test('strips bit-range suffix from request and from entry', () {
      final file = StemsFile(
        entries: [variable('top.cpu.data', '/src/cpu.v', 33)],
      );
      expect(file.lookup('top.cpu.data[7:0]')?.lineNumber, 33);
      // And vice-versa.
      final file2 = StemsFile(
        entries: [variable('top.cpu.data[31:0]', '/src/cpu.v', 33)],
      );
      expect(file2.lookup('top.cpu.data')?.lineNumber, 33);
    });

    test('prefers variables over scopes when names collide', () {
      final file = StemsFile(
        entries: [
          scope('mod.thing', 'f.v', 5),
          variable('other.thing', 'f.v', 50),
        ],
      );
      expect(file.lookup('top.thing')?.kind, StemsEntryKind.variable);
      expect(file.lookup('top.thing')?.lineNumber, 50);
    });

    test('returns null when local name is empty', () {
      final file = StemsFile(entries: [variable('a', 'f', 1)]);
      // Suffix of empty string would just be the empty string — covered by
      // the early-return path.
      expect(file.lookup(''), isNull);
    });
  });

  group('StemsFile.lookupScope', () {
    test('finds a scope by exact path', () {
      final file = StemsFile(
        entries: [
          scope('top.cpu', '/src/cpu.v', 5),
          variable('top.cpu.clk', '/src/cpu.v', 7),
        ],
      );
      expect(file.lookupScope('top.cpu')?.lineNumber, 5);
    });

    test('falls back to case-insensitive match', () {
      final file = StemsFile(entries: [scope('top.cpu', 'f.v', 5)]);
      expect(file.lookupScope('TOP.CPU')?.lineNumber, 5);
    });

    test('does not match variable entries', () {
      final file = StemsFile(entries: [variable('top.cpu', 'f.v', 5)]);
      expect(file.lookupScope('top.cpu'), isNull);
    });

    test('returns null on empty input', () {
      final file = StemsFile(entries: [scope('a', 'f', 1)]);
      expect(file.lookupScope(''), isNull);
    });
  });

  group('StemsFile.sourceFiles', () {
    test('returns distinct paths in first-occurrence order', () {
      final file = StemsFile(
        entries: [
          variable('a', 'one.v', 1),
          variable('b', 'two.v', 2),
          variable('c', 'one.v', 3),
          variable('d', 'three.v', 4),
          variable('e', 'two.v', 5),
        ],
      );
      expect(file.sourceFiles, ['one.v', 'two.v', 'three.v']);
    });

    test('empty for empty stems', () {
      const empty = StemsFile();
      expect(empty.sourceFiles, isEmpty);
      expect(empty.isEmpty, isTrue);
      expect(empty.length, 0);
    });
  });

  group('StemsFile equality', () {
    test('equal when entries match in order', () {
      final a = StemsFile(entries: [variable('a', 'f', 1), scope('b', 'f', 2)]);
      final b = StemsFile(entries: [variable('a', 'f', 1), scope('b', 'f', 2)]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('inequal when entries differ in order', () {
      final a = StemsFile(
        entries: [variable('a', 'f', 1), variable('b', 'f', 2)],
      );
      final b = StemsFile(
        entries: [variable('b', 'f', 2), variable('a', 'f', 1)],
      );
      expect(a, isNot(b));
    });

    test('copyWith replaces entries list', () {
      final a = StemsFile(entries: [variable('a', 'f', 1)]);
      final b = a.copyWith(entries: [variable('b', 'g', 2)]);
      expect(b.length, 1);
      expect(b.entries.single.path, 'b');
    });

    test('toString includes count', () {
      final a = StemsFile(entries: [variable('a', 'f', 1)]);
      expect(a.toString(), contains('1'));
    });
  });
}
