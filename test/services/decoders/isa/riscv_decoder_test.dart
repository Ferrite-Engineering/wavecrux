// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';
import 'package:wavecrux/services/decoders/isa/isa_decoder_assets.dart';
import 'package:wavecrux/services/decoders/isa/riscv_decoder.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

InstructionSet _loadAsset(String name) => parseInstructionSetToml(
  File('assets/decoders/isa/riscv/$name.toml').readAsStringSync(),
  sourceLabel: '$name.toml',
);

IsaDecoderAssets _testAssets() => IsaDecoderAssets.fromMap({
  'RV32I': _loadAsset('RV32I'),
  'RV32M': _loadAsset('RV32M'),
  'RV32A': _loadAsset('RV32A'),
  'RV32F': _loadAsset('RV32F'),
  'RV32C-lower': _loadAsset('RV32C-lower'),
  'RV64I': _loadAsset('RV64I'),
  'RV64M': _loadAsset('RV64M'),
  'RV64A': _loadAsset('RV64A'),
  'RV64D': _loadAsset('RV64D'),
  'RV64C-lower': _loadAsset('RV64C-lower'),
});

SignalValueQuery _makeQuery(Map<String, List<(int, String)>> changes) {
  return (signal, time) {
    final list = changes[signal] ?? const [];
    String? held;
    for (final (t, v) in list) {
      if (t > time) break;
      held = v;
    }
    return held;
  };
}

SignalChangesQuery _makeChangesQuery(
  Map<String, List<(int, String)>> changes,
) {
  return (signal, start, end) {
    final list = changes[signal] ?? const [];
    return [
      for (final e in list)
        if (e.$1 >= start && e.$1 < end) e,
    ];
  };
}

String _bin(int value, int width) {
  final masked = value.toUnsigned(width);
  return 'b${masked.toRadixString(2).padLeft(width, '0')}';
}

/// Build clock + instruction (+ optional PC) change lists for a sequence
/// of (instruction, pc?) cycles. Edges land at t=5, 15, 25, … matching
/// what tool/generate_riscv_fixtures.dart emits.
Map<String, List<(int, String)>> _buildChanges({
  required List<(int instr, int? pc)> cycles,
  bool includePc = false,
}) {
  final clk = <(int, String)>[];
  final instr = <(int, String)>[(0, _bin(0, 32))];
  final pc = <(int, String)>[(0, _bin(0, 64))];
  for (var i = 0; i < cycles.length; i++) {
    final risingT = 5 + i * 10;
    final fallingT = risingT + 5;
    final updateT = risingT - 1;
    instr.add((updateT, _bin(cycles[i].$1, 32)));
    if (includePc && cycles[i].$2 != null) {
      pc.add((updateT, _bin(cycles[i].$2!, 64)));
    }
    clk
      ..add((risingT, '1'))
      ..add((fallingT, '0'));
  }
  return {
    'clk': clk,
    'instruction': instr,
    if (includePc) 'pc': pc,
  };
}

void main() {
  group('RiscvDecoder.decoderDefinition', () {
    test('id is `riscv` and category is instructionTrace', () {
      const def = RiscvDecoder.decoderDefinition;
      expect(def.id, 'riscv');
      expect(
        def.requiredSignals.map((s) => s.name).toList(),
        containsAll(['clk', 'instruction']),
      );
      expect(
        def.optionalSignals.map((s) => s.name).toList(),
        containsAll(['valid', 'pc']),
      );
      expect(
        def.parameters.map((p) => p.name).toList(),
        containsAll(['xlen', 'ext_m', 'ext_a', 'ext_f', 'ext_d', 'ext_c']),
      );
    });
  });

  group('RiscvDecoder.decode — RV32I basic fixture', () {
    test('emits one transaction per cycle, matching expected disassembly', () {
      final cycles = <(int, int?)>[
        (0x00c58533, null), // add a0, a1, a2
        (0x00a30293, null), // addi t0, t1, 10
        (0x00612423, null), // sw t1, 8(sp)
        (0x00c12503, null), // lw a0, 12(sp)
        (0x12345537, null), // lui a0, 0x12345
        (0x00000073, null), // ecall
      ];
      final changes = _buildChanges(cycles: cycles);
      final decoder = RiscvDecoder(
        const DecoderConfig(
          signalBindings: {
            'clk': 'tb.clk',
            'instruction': 'tb.instruction',
          },
          parameters: {
            'xlen': '32',
            'ext_m': false,
            'ext_a': false,
            'ext_f': false,
            'ext_d': false,
            'ext_c': false,
          },
        ),
        _testAssets(),
      );
      final txs = decoder.decode(
        0,
        100,
        _makeQuery(changes),
        _makeChangesQuery(changes),
      );
      expect(txs, hasLength(6));
      expect(txs.map((t) => t.label), [
        'add a0, a1, a2',
        'addi t0, t1, 10',
        'sw t1, 8(sp)',
        'lw a0, 12(sp)',
        'lui a0, 0x12345',
        'ecall',
      ]);
      expect(txs.map((t) => t.startTime), [5, 15, 25, 35, 45, 55]);
      expect(txs.first.fields['mnemonic'], 'add');
      expect(txs.first.fields['disasm'], 'add a0, a1, a2');
      expect(txs.first.fields['raw'], '0x00C58533');
      expect(txs.first.isError, isFalse);
    });
  });

  group('RiscvDecoder.decode — RV32IM fixture (M extension)', () {
    test('mul/div appear when ext_m=true', () {
      final cycles = <(int, int?)>[
        (0x02c58533, null), // mul a0, a1, a2
        (0x02c5c533, null), // div a0, a1, a2
      ];
      final changes = _buildChanges(cycles: cycles);
      final decoder = RiscvDecoder(
        const DecoderConfig(
          signalBindings: {
            'clk': 'tb.clk',
            'instruction': 'tb.instruction',
          },
          parameters: {'xlen': '32', 'ext_m': true},
        ),
        _testAssets(),
      );
      final txs = decoder.decode(
        0,
        50,
        _makeQuery(changes),
        _makeChangesQuery(changes),
      );
      expect(txs.map((t) => t.label), ['mul a0, a1, a2', 'div a0, a1, a2']);
    });

    test('mul/div go UNKNOWN when ext_m=false (gated)', () {
      final cycles = <(int, int?)>[(0x02c58533, null)];
      final changes = _buildChanges(cycles: cycles);
      final decoder = RiscvDecoder(
        const DecoderConfig(
          signalBindings: {
            'clk': 'tb.clk',
            'instruction': 'tb.instruction',
          },
          parameters: {'xlen': '32', 'ext_m': false},
        ),
        _testAssets(),
      );
      final txs = decoder.decode(
        0,
        50,
        _makeQuery(changes),
        _makeChangesQuery(changes),
      );
      expect(txs, hasLength(1));
      expect(txs[0].isError, isTrue);
      expect(txs[0].label, contains('UNKNOWN INSN'));
    });
  });

  group('RiscvDecoder.decode — RV64I fixture (XLEN=64)', () {
    test('ld/sd/addw + redefined slli decode correctly', () {
      final cycles = <(int, int?)>[
        (0x01013503, null), // ld a0, 16(sp)
        (0x00613c23, null), // sd t1, 24(sp)
        (0x00c5853b, null), // addw a0, a1, a2
        (0x02031293, null), // slli t0, t1, 32 (RV64-only 6-bit shamt)
      ];
      final changes = _buildChanges(cycles: cycles);
      final decoder = RiscvDecoder(
        const DecoderConfig(
          signalBindings: {
            'clk': 'tb.clk',
            'instruction': 'tb.instruction',
          },
          parameters: {'xlen': '64', 'ext_m': false},
        ),
        _testAssets(),
      );
      final txs = decoder.decode(
        0,
        100,
        _makeQuery(changes),
        _makeChangesQuery(changes),
      );
      expect(txs.map((t) => t.label), [
        'ld a0, 16(sp)',
        'sd t1, 24(sp)',
        'addw a0, a1, a2',
        'slli t0, t1, 32',
      ]);
    });
  });

  group('RiscvDecoder.decode — PC binding', () {
    test('PC appears in label and fields when bound', () {
      final cycles = <(int, int?)>[
        (0x00a30293, 0x80000000),
        (0x00c58533, 0x80000004),
        (0x00000073, 0x80000008),
      ];
      final changes = _buildChanges(cycles: cycles, includePc: true);
      final decoder = RiscvDecoder(
        const DecoderConfig(
          signalBindings: {
            'clk': 'tb.clk',
            'instruction': 'tb.instruction',
            'pc': 'tb.pc',
          },
          parameters: {'xlen': '32'},
        ),
        _testAssets(),
      );
      final txs = decoder.decode(
        0,
        100,
        _makeQuery(changes),
        _makeChangesQuery(changes),
      );
      expect(txs, hasLength(3));
      expect(txs[0].label, '[0x80000000] addi t0, t1, 10');
      expect(txs[0].fields['pc'], '0x80000000');
      expect(txs[2].label, '[0x80000008] ecall');
    });

    test('valid signal gates fetch — low-valid cycles are skipped', () {
      final cycles = <(int, int?)>[
        (0x00a30293, null), // valid=1 → emit
        (0x00c58533, null), // valid=0 → skip
        (0x00000073, null), // valid=1 → emit
      ];
      final changes = _buildChanges(cycles: cycles);
      // valid signal: high at cycles 0 and 2, low at cycle 1
      changes['valid'] = [(0, '0'), (4, '1'), (14, '0'), (24, '1')];
      final decoder = RiscvDecoder(
        const DecoderConfig(
          signalBindings: {
            'clk': 'tb.clk',
            'instruction': 'tb.instruction',
            'valid': 'tb.valid',
          },
          parameters: {'xlen': '32'},
        ),
        _testAssets(),
      );
      final txs = decoder.decode(
        0,
        100,
        _makeQuery(changes),
        _makeChangesQuery(changes),
      );
      expect(txs, hasLength(2));
      expect(txs.map((t) => t.label), ['addi t0, t1, 10', 'ecall']);
    });
  });

  group('RiscvDecoder.decode — error path', () {
    test('x/z in instruction word skips that cycle silently', () {
      final changes = <String, List<(int, String)>>{
        'clk': [(5, '1'), (10, '0')],
        'instruction': [
          (0, _bin(0, 32)),
          (4, 'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'),
        ],
      };
      final decoder = RiscvDecoder(
        const DecoderConfig(
          signalBindings: {
            'clk': 'tb.clk',
            'instruction': 'tb.instruction',
          },
        ),
        _testAssets(),
      );
      final txs = decoder.decode(
        0,
        50,
        _makeQuery(changes),
        _makeChangesQuery(changes),
      );
      expect(txs, isEmpty);
    });

    test('unknown instruction → UNKNOWN INSN error transaction', () {
      final cycles = <(int, int?)>[
        (0xfffffffe, null), // not a valid encoding under any tested mask
      ];
      final changes = _buildChanges(cycles: cycles);
      final decoder = RiscvDecoder(
        const DecoderConfig(
          signalBindings: {
            'clk': 'tb.clk',
            'instruction': 'tb.instruction',
          },
          parameters: {'xlen': '32', 'ext_c': false},
        ),
        _testAssets(),
      );
      final txs = decoder.decode(
        0,
        50,
        _makeQuery(changes),
        _makeChangesQuery(changes),
      );
      expect(txs, hasLength(1));
      expect(txs[0].isError, isTrue);
      expect(txs[0].label, contains('UNKNOWN INSN'));
      expect(txs[0].fields['raw'], '0xFFFFFFFE');
    });
  });
}
