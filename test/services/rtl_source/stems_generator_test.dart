// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stems_entry.dart';
import 'package:wavecrux/services/rtl_source/stems_generator.dart';
import 'package:wavecrux/services/rtl_source/stems_parser.dart';
import 'package:wavecrux/services/rtl_source/stems_writer.dart';

void main() {
  const generator = StemsGenerator();

  const topV = '''
module top(
  input wire clk,
  output [7:0] q
);
  wire [3:0] cnt;
  cpu u_cpu (.clk(clk), .q(q));
endmodule
''';

  const cpuV = '''
module cpu(
  input clk,
  output [7:0] q
);
  reg [7:0] acc;
  alu u_alu (.a(acc));
endmodule
''';

  group('hierarchy elaboration', () {
    test('auto-detects the unique top and elaborates the full hierarchy', () {
      final result = generator.generate(
        sources: {'top.v': topV, 'cpu.v': cpuV},
      );

      expect(result.resolvedTop, 'top');
      final paths = result.stems.entries.map((e) => e.path).toSet();
      expect(
        paths,
        containsAll(<String>{
          'top', 'top.clk', 'top.q', 'top.cnt', // top scope + signals
          'top.u_cpu', 'top.u_cpu.clk', 'top.u_cpu.q', 'top.u_cpu.acc',
          'top.u_cpu.u_alu', // unresolved child kept as a scope
        }),
      );
    });

    test('scope vs variable kinds are correct', () {
      final stems = generator
          .generate(
            sources: {'top.v': topV, 'cpu.v': cpuV},
          )
          .stems;
      StemsEntry of(String p) => stems.entries.firstWhere((e) => e.path == p);
      expect(of('top').kind, StemsEntryKind.scope);
      expect(of('top.u_cpu').kind, StemsEntryKind.scope);
      expect(of('top.clk').kind, StemsEntryKind.variable);
      expect(of('top.u_cpu.acc').kind, StemsEntryKind.variable);
    });

    test('entries point at the correct source file', () {
      final stems = generator
          .generate(
            sources: {'top.v': topV, 'cpu.v': cpuV},
          )
          .stems;
      expect(stems.lookup('top.clk')!.sourceFile, 'top.v');
      expect(stems.lookup('top.u_cpu.acc')!.sourceFile, 'cpu.v');
    });

    test('warns about an unresolved instantiated module type', () {
      final result = generator.generate(
        sources: {'top.v': topV, 'cpu.v': cpuV},
      );
      expect(result.warnings.any((w) => w.contains('alu')), isTrue);
    });
  });

  group('top resolution', () {
    test('reports multiple candidate tops and refuses to guess', () {
      // Two independent, never-instantiated modules → ambiguous.
      const a = 'module a(input x); endmodule';
      const b = 'module b(input y); endmodule';
      final result = generator.generate(sources: {'a.v': a, 'b.v': b});
      expect(result.resolvedTop, isNull);
      expect(result.availableTops, ['a', 'b']);
      expect(result.stems.isEmpty, isTrue);
      expect(result.warnings.any((w) => w.contains('Multiple')), isTrue);
    });

    test('honors an explicit top module', () {
      final result = generator.generate(
        sources: {'top.v': topV, 'cpu.v': cpuV},
        topModule: 'cpu',
      );
      expect(result.resolvedTop, 'cpu');
      final paths = result.stems.entries.map((e) => e.path).toSet();
      expect(paths, containsAll(<String>{'cpu', 'cpu.acc', 'cpu.u_alu'}));
      expect(paths.any((p) => p.startsWith('top')), isFalse);
    });

    test('empty input yields an empty stems file with a warning', () {
      final result = generator.generate(sources: {});
      expect(result.stems.isEmpty, isTrue);
      expect(result.warnings, isNotEmpty);
    });
  });

  test('cyclic instantiation is truncated, not infinite', () {
    const a = '''
module a(input x);
  b u_b();
endmodule
''';
    const b = '''
module b(input y);
  a u_a();
endmodule
''';
    // Neither is a unique top (both instantiated) → pass one explicitly.
    final result = generator.generate(
      sources: {'a.v': a, 'b.v': b},
      topModule: 'a',
    );
    expect(result.resolvedTop, 'a');
    expect(
      result.warnings.any((w) => w.toLowerCase().contains('cyclic')),
      isTrue,
    );
    // Produced a bounded hierarchy: a → a.u_b → a.u_b.u_a (then truncated).
    final paths = result.stems.entries.map((e) => e.path).toSet();
    expect(paths, contains('a.u_b.u_a'));
  });

  test('generated stems round-trip through the on-disk format', () {
    const writer = StemsWriter();
    const parser = StemsParser();
    final generated = generator
        .generate(
          sources: {'top.v': topV, 'cpu.v': cpuV},
        )
        .stems;

    final reparsed = parser.parse(writer.write(generated));

    // The reparsed file resolves the same signals to the same locations — the
    // full generate → write → load round trip a user actually exercises.
    for (final path in ['top.clk', 'top.u_cpu.acc']) {
      final a = generated.lookup(path)!;
      final b = reparsed.lookup(path)!;
      expect(b.sourceFile, a.sourceFile);
      expect(b.lineNumber, a.lineNumber);
      expect(b.kind, a.kind);
    }
  });
}
