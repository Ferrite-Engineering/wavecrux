// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stems_entry.dart';

void main() {
  group('StemsEntry', () {
    test('equality on all fields', () {
      const a = StemsEntry(
        path: 'top.cpu.clk',
        sourceFile: '/src/cpu.v',
        lineNumber: 42,
        kind: StemsEntryKind.variable,
      );
      const b = StemsEntry(
        path: 'top.cpu.clk',
        sourceFile: '/src/cpu.v',
        lineNumber: 42,
        kind: StemsEntryKind.variable,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when any field differs', () {
      const base = StemsEntry(
        path: 'top.cpu',
        sourceFile: '/src/cpu.v',
        lineNumber: 1,
        kind: StemsEntryKind.scope,
      );
      const diffPath = StemsEntry(
        path: 'top.alu',
        sourceFile: '/src/cpu.v',
        lineNumber: 1,
        kind: StemsEntryKind.scope,
      );
      const diffFile = StemsEntry(
        path: 'top.cpu',
        sourceFile: '/src/alu.v',
        lineNumber: 1,
        kind: StemsEntryKind.scope,
      );
      const diffLine = StemsEntry(
        path: 'top.cpu',
        sourceFile: '/src/cpu.v',
        lineNumber: 2,
        kind: StemsEntryKind.scope,
      );
      const diffKind = StemsEntry(
        path: 'top.cpu',
        sourceFile: '/src/cpu.v',
        lineNumber: 1,
        kind: StemsEntryKind.variable,
      );
      expect(base, isNot(diffPath));
      expect(base, isNot(diffFile));
      expect(base, isNot(diffLine));
      expect(base, isNot(diffKind));
    });

    test('copyWith preserves unchanged fields', () {
      const a = StemsEntry(
        path: 'a',
        sourceFile: 'f.v',
        lineNumber: 1,
        kind: StemsEntryKind.variable,
      );
      final b = a.copyWith(lineNumber: 10);
      expect(b.path, 'a');
      expect(b.sourceFile, 'f.v');
      expect(b.lineNumber, 10);
      expect(b.kind, StemsEntryKind.variable);
    });

    test('toString contains path and line', () {
      const a = StemsEntry(
        path: 'top.x',
        sourceFile: 'design.v',
        lineNumber: 99,
        kind: StemsEntryKind.variable,
      );
      final s = a.toString();
      expect(s, contains('top.x'));
      expect(s, contains('design.v'));
      expect(s, contains('99'));
    });
  });
}
