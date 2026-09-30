// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/rtl_source/hdl_declaration_parser.dart';
import 'package:wavecrux/services/rtl_source/hdl_module.dart';

/// Asserts that [signal]'s 1-based line, looked up in [source], contains
/// [token] — verifies the line mapping without hand-counting line numbers.
void expectSignalAtLineWith(
  HdlModule module,
  String name,
  String source,
  String token,
) {
  final sig = module.signals.firstWhere(
    (s) => s.name == name,
    orElse: () => fail(
      'signal "$name" not found in ${module.name} '
      '(${module.signals.map((s) => s.name).toList()})',
    ),
  );
  final lines = source.split('\n');
  expect(
    lines[sig.lineNumber - 1],
    contains(token),
    reason:
        '$name mapped to line ${sig.lineNumber}: "${lines[sig.lineNumber - 1]}"',
  );
}

void main() {
  const parser = HdlDeclarationParser();

  group('Verilog / SystemVerilog', () {
    const src = '''
// a counter
module top(
  input  wire       clk,
  input  wire       rst_n,
  output reg  [7:0] q
);
  wire [3:0] internal_cnt;
  reg        busy;
  cpu u_cpu (
    .clk(clk),
    .q(q)
  );
  alu #(.WIDTH(8)) u_alu (.a(q));
endmodule

module cpu(input clk, output [7:0] q);
  reg [7:0] acc;
endmodule
''';

    late List<HdlModule> modules;
    setUp(() {
      modules = parser.parse(sourceFile: 'design.v', content: src);
    });

    test('finds both modules', () {
      expect(modules.map((m) => m.name).toSet(), {'top', 'cpu'});
    });

    test('top module declaration line points at `module top`', () {
      final top = modules.firstWhere((m) => m.name == 'top');
      expect(src.split('\n')[top.declarationLine - 1], contains('module top'));
    });

    test('captures ANSI header ports and body declarations with lines', () {
      final top = modules.firstWhere((m) => m.name == 'top');
      expect(
        top.signals.map((s) => s.name).toSet(),
        {'clk', 'rst_n', 'q', 'internal_cnt', 'busy'},
      );
      expectSignalAtLineWith(top, 'clk', src, 'clk');
      expectSignalAtLineWith(top, 'q', src, 'output reg');
      expectSignalAtLineWith(top, 'internal_cnt', src, 'internal_cnt');
      expectSignalAtLineWith(top, 'busy', src, 'busy');
    });

    test('captures instantiations (with and without param overrides)', () {
      final top = modules.firstWhere((m) => m.name == 'top');
      final insts = {
        for (final i in top.instances) i.instanceName: i.moduleType,
      };
      expect(insts, {'u_cpu': 'cpu', 'u_alu': 'alu'});
    });

    test('does not treat keywords/constructs as instances or signals', () {
      final cpu = modules.firstWhere((m) => m.name == 'cpu');
      expect(cpu.signals.map((s) => s.name).toSet(), {'clk', 'q', 'acc'});
      expect(cpu.instances, isEmpty);
    });

    test('strips comments so commented-out code is ignored', () {
      const commented = '''
module m(input a);
  // wire ghost;
  /* reg ghost2; */
  wire real_one;
endmodule
''';
      final m = parser.parse(sourceFile: 'm.v', content: commented).single;
      expect(m.signals.map((s) => s.name).toSet(), {'a', 'real_one'});
    });
  });

  group('VHDL', () {
    const src = '''
-- a counter
entity counter is
  port (
    clk : in  std_logic;
    q   : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of counter is
  signal cnt : unsigned(7 downto 0);
begin
  u_sub : entity work.subblock
    port map (clk => clk);
end architecture;
''';

    test('merges entity ports and architecture signals/instances', () {
      final modules = parser.parse(sourceFile: 'counter.vhd', content: src);
      // Two HdlModules share the name `counter` (entity + architecture);
      // exercised as the generator merges them, but assert both halves here.
      final names = <String>{};
      final signals = <String>{};
      final instances = <String, String>{};
      for (final m in modules.where((m) => m.name == 'counter')) {
        names.add(m.name);
        signals.addAll(m.signals.map((s) => s.name));
        for (final i in m.instances) {
          instances[i.instanceName] = i.moduleType;
        }
      }
      expect(names, {'counter'});
      expect(signals, containsAll(<String>{'clk', 'q', 'cnt'}));
      expect(instances, {'u_sub': 'subblock'});
    });

    test('entity declaration line points at `entity counter`', () {
      final modules = parser.parse(sourceFile: 'counter.vhd', content: src);
      final entity = modules.firstWhere(
        (m) => m.name == 'counter' && m.signals.any((s) => s.name == 'clk'),
      );
      expect(
        src.split('\n')[entity.declarationLine - 1],
        contains('entity counter'),
      );
    });
  });
}
