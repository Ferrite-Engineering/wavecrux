// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates Wishbone bus VCD fixtures used by the WishboneDecoder unit
// tests and by the verification guide (§5.7).
//
// Output (mirrored to both test/ and verification/ trees):
//   test/fixtures/protocol/wishbone/generated/<scenario>.vcd
//   test/fixtures/protocol/wishbone/generated/<scenario>.expected_transactions.json
//   verification/fixtures/protocol/wishbone/generated/<scenario>.vcd
//   verification/fixtures/protocol/wishbone/generated/<scenario>.expected_transactions.json
//
// Usage:
//   dart run tool/generate_wishbone_fixtures.dart
//
// All fixtures are hand-crafted: the timeline is encoded as a sequence of
// "cycle frames" (one per bus clock tick). The tool unrolls each frame into
// VCD value-change records and runs the WishboneDecoder against the
// emitted timeline to produce the matching expected_transactions.json.
//
// The expected JSON is therefore always *consistent* with the decoder
// implementation — the test file then asserts hand-verified anchor points
// (key labels, transaction counts, error flags) so a silent regression in
// decoder output is still caught.
//
// ignore_for_file: avoid_print, prefer_const_constructors,
// ignore_for_file: prefer_const_literals_to_create_immutables,
// ignore_for_file: omit_local_variable_types,
// ignore_for_file: prefer_function_declarations_over_variables,
// ignore_for_file: unintended_html_in_doc_comment

import 'dart:convert';
import 'dart:io';

import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/services/decoders/wishbone_decoder.dart';

const _testOutDir = 'test/fixtures/protocol/wishbone/generated';
const _verificationOutDir = 'verification/fixtures/protocol/wishbone/generated';

void main() {
  Directory(_testOutDir).createSync(recursive: true);
  Directory(_verificationOutDir).createSync(recursive: true);

  for (final s in _scenarios) {
    final vcd = _renderVcd(s);
    final expected = _runDecoder(s);
    final json = _encodeExpected(expected);
    for (final dir in <String>[_testOutDir, _verificationOutDir]) {
      File('$dir/${s.name}.vcd').writeAsStringSync(vcd);
      File('$dir/${s.name}.expected_transactions.json').writeAsStringSync(json);
    }
  }

  print('Generated Wishbone fixtures:');
  for (final s in _scenarios) {
    print('  $_testOutDir/${s.name}.vcd');
    print('  $_testOutDir/${s.name}.expected_transactions.json');
  }
  print(
    'and in $_verificationOutDir/. Run `flutter test '
    'test/services/decoders/wishbone_decoder_test.dart` to verify.',
  );
}

// ── scenario authoring API ───────────────────────────────────────────────────

class _SignalDecl {
  const _SignalDecl(this.name, this.width);
  final String name;
  final int width;
}

class _Frame {
  const _Frame(this.cycle, this.changes);

  /// Cycle index (0-based). Rising edge of clk lands at `cycle * 10 + 5`.
  final int cycle;

  /// Signal-name → value snapshot for this cycle (held until next change).
  /// Vector values are decimal ints; scalar values are 0/1.
  final Map<String, Object> changes;
}

class _Scenario {
  const _Scenario({
    required this.name,
    required this.signals,
    required this.frames,
    required this.bindings,
    required this.parameters,
    this.totalCycles,
  });

  final String name;
  final List<_SignalDecl> signals;
  final List<_Frame> frames;

  /// Decoder-side binding map (logical name to tb signal path).
  final Map<String, String> bindings;
  final Map<String, dynamic> parameters;
  final int? totalCycles;
}

// ── VCD emission ─────────────────────────────────────────────────────────────

/// Renders the scenario to a VCD string.
///
/// Layout (mirrors the existing apb_basic.vcd):
///   $timescale  ... $end
///   $scope module tb $end
///   $var wire <width> <id> <NAME> $end ...
///   $upscope $end
///   $enddefinitions $end
///   $dumpvars 0! 0" b... # ... $end
///   #<tick> ...records...
String _renderVcd(_Scenario s) {
  // Assign printable-ASCII identifier codes starting at '!'.
  final ids = <String, String>{
    for (var i = 0; i < s.signals.length; i++)
      s.signals[i].name: String.fromCharCode(33 + i),
  };

  final buf = StringBuffer()
    ..writeln(r'$timescale 1ns $end')
    ..writeln(r'$scope module tb $end');
  for (final sig in s.signals) {
    final id = ids[sig.name];
    final upper = sig.name.toUpperCase();
    buf.writeln('\$var wire ${sig.width}  $id  $upper \$end');
  }
  buf
    ..writeln(r'$upscope $end')
    ..writeln(r'$enddefinitions $end');

  // Build initial values: every signal starts at 0.
  final state = <String, String>{
    for (final sig in s.signals)
      sig.name: sig.width == 1 ? '0' : 'b${'0' * sig.width}',
  };

  buf.writeln(r'$dumpvars');
  for (final sig in s.signals) {
    final id = ids[sig.name];
    final v = state[sig.name];
    if (sig.width == 1) {
      buf.writeln('$v$id');
    } else {
      buf.writeln('$v $id');
    }
  }
  buf.writeln(r'$end');

  // Apply each frame: emit clock edges (unless skipped) and signal changes.
  // Convention: each cycle emits two clk records — rising at t=cycle*10+5,
  // falling at t=cycle*10+10. Non-clock changes are emitted at t=cycle*10+2
  // so the decoder samples them as held values at the rising edge.
  // Find largest cycle present so we always emit a "wrap-up" tick.
  final maxCycle =
      s.totalCycles ??
      (s.frames.isEmpty
          ? 0
          : s.frames.map((f) => f.cycle).reduce((a, b) => a > b ? a : b) + 1);

  // Group frames by cycle for efficient lookup. When multiple frames target
  // the same cycle, merge their `changes` maps (later entries override
  // earlier ones for the same key) — this lets fixture authors layer setup
  // (rst release) and behavior (signal drive) into the same cycle.
  final framesByCycle = <int, Map<String, Object>>{};
  for (final f in s.frames) {
    framesByCycle
        .putIfAbsent(f.cycle, () => <String, Object>{})
        .addAll(
          f.changes,
        );
  }

  for (var c = 0; c < maxCycle; c++) {
    final frame = framesByCycle[c];

    // Emit signal-change record at cycle*10+2 (before rising edge at +5).
    if (frame != null) {
      buf.writeln('#${c * 10 + 2}');
      for (final entry in frame.entries) {
        final name = entry.key;
        final id = ids[name];
        if (id == null) {
          throw StateError('signal $name not declared in scenario ${s.name}');
        }
        final width = s.signals.firstWhere((x) => x.name == name).width;
        final encoded = _encodeValue(entry.value, width);
        if (encoded != state[name]) {
          if (width == 1) {
            buf.writeln('$encoded$id');
          } else {
            buf.writeln('$encoded $id');
          }
          state[name] = encoded;
        }
      }
    }

    // Rising edge.
    final clkId = ids['clk'];
    if (clkId != null) {
      buf
        ..writeln('#${c * 10 + 5}')
        ..writeln('1$clkId')
        ..writeln('#${c * 10 + 10}')
        ..writeln('0$clkId');
    }
  }

  return buf.toString();
}

String _encodeValue(Object v, int width) {
  if (width == 1) {
    if (v is int) return v == 0 ? '0' : '1';
    if (v is String) return v;
    throw StateError('1-bit value must be int 0/1 or string: $v');
  }
  if (v is int) {
    final bits = v.toUnsigned(width).toRadixString(2).padLeft(width, '0');
    return 'b$bits';
  }
  if (v is String) {
    // Allow raw bit-string overrides for X/Z scenarios.
    return v.startsWith('b') ? v : 'b$v';
  }
  throw StateError('vector value must be int or bit-string: $v');
}

// ── Expected-JSON computation via the decoder under test ─────────────────────

List<DecodedTransaction> _runDecoder(_Scenario s) {
  // Build a SignalValueQuery / SignalChangesQuery from the scenario timeline.
  final changes = <String, List<(int, String)>>{};
  final state = <String, String>{
    for (final sig in s.signals)
      sig.name: sig.width == 1 ? '0' : 'b${'0' * sig.width}',
  };
  // Initial values at t=0.
  for (final entry in state.entries) {
    changes.putIfAbsent(entry.key, () => []).add((0, entry.value));
  }

  final framesByCycle = <int, Map<String, Object>>{};
  for (final f in s.frames) {
    framesByCycle
        .putIfAbsent(f.cycle, () => <String, Object>{})
        .addAll(
          f.changes,
        );
  }
  final maxCycle =
      s.totalCycles ??
      (s.frames.isEmpty
          ? 0
          : s.frames.map((f) => f.cycle).reduce((a, b) => a > b ? a : b) + 1);

  for (var c = 0; c < maxCycle; c++) {
    final frame = framesByCycle[c];
    if (frame != null) {
      final t = c * 10 + 2;
      for (final entry in frame.entries) {
        final width = s.signals.firstWhere((x) => x.name == entry.key).width;
        final encoded = _encodeValue(entry.value, width);
        if (encoded != state[entry.key]) {
          changes.putIfAbsent(entry.key, () => []).add((t, encoded));
          state[entry.key] = encoded;
        }
      }
    }
    changes.putIfAbsent('clk', () => [])
      ..add((c * 10 + 5, '1'))
      ..add((c * 10 + 10, '0'));
  }

  final SignalValueQuery query = (signal, time) {
    final list = changes[signal] ?? [];
    String? held;
    for (final (t, v) in list) {
      if (t > time) break;
      held = v;
    }
    return held;
  };

  final SignalChangesQuery changesQuery = (signal, start, end) {
    final list = changes[signal] ?? [];
    return [
      for (final e in list)
        if (e.$1 >= start && e.$1 < end) e,
    ];
  };

  final decoder = WishboneDecoder(
    DecoderConfig(signalBindings: s.bindings, parameters: s.parameters),
  );
  return decoder.decode(0, maxCycle * 10 + 5, query, changesQuery);
}

String _encodeExpected(List<DecodedTransaction> txs) {
  final list = [
    for (final tx in txs)
      {
        'startTime': tx.startTime,
        'endTime': tx.endTime,
        'label': tx.label,
        'fields': tx.fields,
        'isError': tx.isError,
        'errorMessage': tx.errorMessage,
      },
  ];
  return const JsonEncoder.withIndent('  ').convert(list);
}

// ── Scenario library ─────────────────────────────────────────────────────────

const _b3SignalsClassic = [
  _SignalDecl('clk', 1),
  _SignalDecl('rst', 1),
  _SignalDecl('cyc', 1),
  _SignalDecl('stb', 1),
  _SignalDecl('we', 1),
  _SignalDecl('adr', 32),
  _SignalDecl('dat_o', 32),
  _SignalDecl('dat_i', 32),
  _SignalDecl('ack', 1),
  _SignalDecl('err', 1),
  _SignalDecl('rty', 1),
  _SignalDecl('sel', 4),
];

const _b3BindingsClassic = {
  'clk': 'tb.CLK',
  'rst': 'tb.RST',
  'cyc': 'tb.CYC',
  'stb': 'tb.STB',
  'we': 'tb.WE',
  'adr': 'tb.ADR',
  'dat_o': 'tb.DAT_O',
  'dat_i': 'tb.DAT_I',
  'ack': 'tb.ACK',
  'err': 'tb.ERR',
  'rty': 'tb.RTY',
  'sel': 'tb.SEL',
};

const _b3SignalsBurst = [
  ..._b3SignalsClassic,
  _SignalDecl('cti', 3),
  _SignalDecl('bte', 2),
];

const _b3BindingsBurst = {
  ..._b3BindingsClassic,
  'cti': 'tb.CTI',
  'bte': 'tb.BTE',
};

const _b4Signals = [
  _SignalDecl('clk', 1),
  _SignalDecl('rst', 1),
  _SignalDecl('cyc', 1),
  _SignalDecl('stb', 1),
  _SignalDecl('we', 1),
  _SignalDecl('adr', 32),
  _SignalDecl('dat_o', 32),
  _SignalDecl('dat_i', 32),
  _SignalDecl('ack', 1),
  _SignalDecl('err', 1),
  _SignalDecl('stall', 1),
  _SignalDecl('sel', 4),
];

const _b4Bindings = {
  'clk': 'tb.CLK',
  'rst': 'tb.RST',
  'cyc': 'tb.CYC',
  'stb': 'tb.STB',
  'we': 'tb.WE',
  'adr': 'tb.ADR',
  'dat_o': 'tb.DAT_O',
  'dat_i': 'tb.DAT_I',
  'ack': 'tb.ACK',
  'err': 'tb.ERR',
  'stall': 'tb.STALL',
  'sel': 'tb.SEL',
};

const _baseParams = {
  'addr_width': 32,
  'data_width': '32',
  'granularity': '8',
  'endianness': 'little',
  'check_alignment': true,
};

const _b4Params = {
  'revision': 'b4',
  'addr_width': 32,
  'data_width': '32',
  'granularity': '8',
  'endianness': 'little',
  'check_alignment': true,
};

final _scenarios = <_Scenario>[
  // ── Fixture 1: B3 Classic basic — W ack, R ack, R err, W rty ──────────────
  _Scenario(
    name: 'wishbone_b3_classic_basic',
    signals: _b3SignalsClassic,
    bindings: _b3BindingsClassic,
    parameters: _baseParams,
    totalCycles: 12,
    frames: [
      _Frame(0, {'rst': 1}),
      _Frame(1, {'rst': 0}),
      // Cycle 1 (edge t=15): W 0x100 = 0xDEADBEEF, ack
      _Frame(1, {
        'cyc': 1,
        'stb': 1,
        'we': 1,
        'adr': 0x100,
        'dat_o': 0xDEADBEEF,
        'sel': 0xF,
        'ack': 1,
      }),
      _Frame(2, {
        'cyc': 0,
        'stb': 0,
        'we': 0,
        'adr': 0,
        'dat_o': 0,
        'ack': 0,
        'sel': 0,
      }),
      // Cycle 3 (edge t=35): R 0x100 → 0x12345678, ack
      _Frame(3, {
        'cyc': 1,
        'stb': 1,
        'we': 0,
        'adr': 0x100,
        'dat_i': 0x12345678,
        'sel': 0xF,
        'ack': 1,
      }),
      _Frame(4, {'cyc': 0, 'stb': 0, 'ack': 0, 'dat_i': 0, 'sel': 0}),
      // Cycle 5 (edge t=55): R 0x200 → ?, err
      _Frame(5, {
        'cyc': 1,
        'stb': 1,
        'we': 0,
        'adr': 0x200,
        'dat_i': 0xBADBADBA,
        'sel': 0xF,
        'err': 1,
      }),
      _Frame(6, {
        'cyc': 0,
        'stb': 0,
        'err': 0,
        'dat_i': 0,
        'sel': 0,
      }),
      // Cycle 7 (edge t=75): W 0x300 = 0xCAFEBABE, rty
      _Frame(7, {
        'cyc': 1,
        'stb': 1,
        'we': 1,
        'adr': 0x300,
        'dat_o': 0xCAFEBABE,
        'sel': 0xF,
        'rty': 1,
      }),
      _Frame(8, {
        'cyc': 0,
        'stb': 0,
        'we': 0,
        'rty': 0,
        'adr': 0,
        'dat_o': 0,
        'sel': 0,
      }),
    ],
  ),

  // ── Fixture 2: B3 incrementing burst (Linear, BTE=00, 4 beats) ────────────
  _Scenario(
    name: 'wishbone_b3_burst_incr',
    signals: _b3SignalsBurst,
    bindings: _b3BindingsBurst,
    parameters: _baseParams,
    totalCycles: 9,
    frames: [
      _Frame(0, {'rst': 1}),
      _Frame(1, {'rst': 0}),
      // Beat 1 of incrementing burst: t=15
      _Frame(1, {
        'cyc': 1,
        'stb': 1,
        'we': 1,
        'adr': 0x100,
        'dat_o': 0xA0A0A0A0,
        'sel': 0xF,
        'cti': 0x2,
        'bte': 0x0,
        'ack': 1,
      }),
      // Beat 2: t=25, adr += 4
      _Frame(2, {'adr': 0x104, 'dat_o': 0xB1B1B1B1}),
      // Beat 3: t=35
      _Frame(3, {'adr': 0x108, 'dat_o': 0xC2C2C2C2}),
      // Beat 4 (final, EOB): t=45
      _Frame(4, {
        'adr': 0x10C,
        'dat_o': 0xD3D3D3D3,
        'cti': 0x7,
      }),
      // Cycle ends.
      _Frame(5, {
        'cyc': 0,
        'stb': 0,
        'we': 0,
        'ack': 0,
        'adr': 0,
        'dat_o': 0,
        'sel': 0,
        'cti': 0,
        'bte': 0,
      }),
    ],
  ),

  // ── Fixture 3: B3 wrap bursts + constant-address burst ────────────────────
  _Scenario(
    name: 'wishbone_b3_burst_wrap',
    signals: _b3SignalsBurst,
    bindings: _b3BindingsBurst,
    parameters: _baseParams,
    totalCycles: 18,
    frames: [
      _Frame(0, {'rst': 1}),
      _Frame(1, {'rst': 0}),
      // 4-beat-wrap (BTE=01) read burst starting at 0x108 (wraps within
      // the 16-byte window 0x100..0x10F).
      _Frame(1, {
        'cyc': 1,
        'stb': 1,
        'we': 0,
        'adr': 0x108,
        'dat_i': 0x11111111,
        'sel': 0xF,
        'cti': 0x2,
        'bte': 0x1,
        'ack': 1,
      }),
      _Frame(2, {'adr': 0x10C, 'dat_i': 0x22222222}),
      _Frame(3, {'adr': 0x100, 'dat_i': 0x33333333}), // wrap
      _Frame(4, {
        'adr': 0x104, 'dat_i': 0x44444444, 'cti': 0x7, // EOB
      }),
      _Frame(5, {
        'cyc': 0,
        'stb': 0,
        'ack': 0,
        'cti': 0,
        'bte': 0,
        'sel': 0,
        'adr': 0,
        'dat_i': 0,
      }),
      // Constant-address burst (CTI=001), 3 beats (e.g. polling FIFO).
      _Frame(7, {
        'cyc': 1,
        'stb': 1,
        'we': 0,
        'adr': 0x200,
        'dat_i': 0xAAAA0001,
        'sel': 0xF,
        'cti': 0x1,
        'bte': 0x0,
        'ack': 1,
      }),
      _Frame(8, {'dat_i': 0xAAAA0002}),
      _Frame(9, {
        'dat_i': 0xAAAA0003, 'cti': 0x7, // EOB
      }),
      _Frame(10, {
        'cyc': 0,
        'stb': 0,
        'ack': 0,
        'cti': 0,
        'sel': 0,
        'adr': 0,
        'dat_i': 0,
      }),
    ],
  ),

  // ── Fixture 4: B3 protocol violations ─────────────────────────────────────
  _Scenario(
    name: 'wishbone_b3_classic_violations',
    signals: _b3SignalsBurst,
    bindings: _b3BindingsBurst,
    parameters: _baseParams,
    totalCycles: 22,
    frames: [
      _Frame(0, {'rst': 1}),
      _Frame(1, {'rst': 0}),
      // Violation 3: STB asserted while CYC deasserted (t=15).
      _Frame(1, {'stb': 1, 'we': 0, 'adr': 0x100}),
      _Frame(2, {'stb': 0, 'adr': 0}),
      // Violation 2: ACK asserted while CYC deasserted (t=35).
      _Frame(3, {'ack': 1}),
      _Frame(4, {'ack': 0}),
      // Violation 1: ACK + ERR simultaneously inside a cycle (t=55).
      _Frame(5, {
        'cyc': 1,
        'stb': 1,
        'we': 1,
        'adr': 0x100,
        'dat_o': 0xDEADBEEF,
        'sel': 0xF,
        'ack': 1,
        'err': 1,
      }),
      _Frame(6, {
        'cyc': 0,
        'stb': 0,
        'we': 0,
        'ack': 0,
        'err': 0,
        'adr': 0,
        'dat_o': 0,
        'sel': 0,
      }),
      // Violation 8: reserved CTI value (t=75).
      _Frame(7, {
        'cyc': 1,
        'stb': 1,
        'we': 0,
        'adr': 0x100,
        'dat_i': 0x12345678,
        'sel': 0xF,
        'cti': 0x3,
        'ack': 1,
      }),
      _Frame(8, {
        'cyc': 0,
        'stb': 0,
        'ack': 0,
        'cti': 0,
        'sel': 0,
        'adr': 0,
        'dat_i': 0,
      }),
      // Violation 9: BTE non-zero with CTI=000 (Classic) (t=95).
      _Frame(9, {
        'cyc': 1,
        'stb': 1,
        'we': 0,
        'adr': 0x100,
        'dat_i': 0x12345678,
        'sel': 0xF,
        'cti': 0x0,
        'bte': 0x1,
        'ack': 1,
      }),
      _Frame(10, {
        'cyc': 0,
        'stb': 0,
        'ack': 0,
        'bte': 0,
        'sel': 0,
        'adr': 0,
        'dat_i': 0,
      }),
      // Violation 10: misaligned address (data_width=32, addr=0x101).
      _Frame(11, {
        'cyc': 1,
        'stb': 1,
        'we': 1,
        'adr': 0x101,
        'dat_o': 0xDEADBEEF,
        'sel': 0xF,
        'ack': 1,
      }),
      _Frame(12, {
        'cyc': 0,
        'stb': 0,
        'we': 0,
        'ack': 0,
        'adr': 0,
        'dat_o': 0,
        'sel': 0,
      }),
      // Violation 6: const-addr burst with ADR change.
      _Frame(13, {
        'cyc': 1,
        'stb': 1,
        'we': 0,
        'adr': 0x200,
        'dat_i': 0x10000000,
        'sel': 0xF,
        'cti': 0x1,
        'bte': 0x0,
        'ack': 1,
      }),
      _Frame(14, {'adr': 0x204, 'dat_i': 0x20000000}), // illegal change
      _Frame(15, {
        'cti': 0x7, 'adr': 0x208, 'dat_i': 0x30000000, // EOB
      }),
      _Frame(16, {
        'cyc': 0,
        'stb': 0,
        'ack': 0,
        'cti': 0,
        'sel': 0,
        'adr': 0,
        'dat_i': 0,
      }),
      // Violation 7: incrementing burst with WE change beat-to-beat.
      _Frame(17, {
        'cyc': 1,
        'stb': 1,
        'we': 0,
        'adr': 0x300,
        'dat_i': 0x40000000,
        'sel': 0xF,
        'cti': 0x2,
        'bte': 0x0,
        'ack': 1,
      }),
      _Frame(18, {
        'we': 1, // illegal change (and adr won't increment correctly)
        'adr': 0x304, 'dat_o': 0x50000000,
      }),
      _Frame(19, {
        'cti': 0x7, 'adr': 0x308, 'dat_o': 0x60000000, // EOB
      }),
      _Frame(20, {
        'cyc': 0,
        'stb': 0,
        'we': 0,
        'ack': 0,
        'cti': 0,
        'sel': 0,
        'adr': 0,
        'dat_o': 0,
        'dat_i': 0,
      }),
    ],
  ),

  // ── Fixture 5: B4 Pipelined basic — 1 W + 1 R ─────────────────────────────
  _Scenario(
    name: 'wishbone_b4_pipelined_basic',
    signals: _b4Signals,
    bindings: _b4Bindings,
    parameters: _b4Params,
    totalCycles: 8,
    frames: [
      _Frame(0, {'rst': 1}),
      _Frame(1, {'rst': 0}),
      // t=15: issue W 0x100 = 0xCAFEBABE (no stall)
      _Frame(1, {
        'cyc': 1,
        'stb': 1,
        'we': 1,
        'adr': 0x100,
        'dat_o': 0xCAFEBABE,
        'sel': 0xF,
      }),
      // t=25: ack arrives; STB deasserts
      _Frame(2, {'stb': 0, 'ack': 1}),
      // t=35: issue R 0x200
      _Frame(3, {
        'stb': 1,
        'we': 0,
        'adr': 0x200,
        'dat_o': 0,
        'ack': 0,
      }),
      // t=45: stb deasserts (1-cycle pulse), no ack yet
      _Frame(4, {'stb': 0, 'adr': 0}),
      // t=55: ack returns with read data
      _Frame(5, {'ack': 1, 'dat_i': 0xFEEDBEEF}),
      // t=65: cycle ends
      _Frame(6, {'cyc': 0, 'ack': 0, 'sel': 0, 'dat_i': 0}),
    ],
  ),

  // ── Fixture 6: B4 Pipelined with stalls and overlapping outstanding ───────
  _Scenario(
    name: 'wishbone_b4_pipelined_stall',
    signals: _b4Signals,
    bindings: _b4Bindings,
    parameters: _b4Params,
    totalCycles: 12,
    frames: [
      _Frame(0, {'rst': 1}),
      _Frame(1, {'rst': 0}),
      // t=15: issue R 0x100
      _Frame(1, {
        'cyc': 1,
        'stb': 1,
        'we': 0,
        'adr': 0x100,
        'sel': 0xF,
      }),
      // t=25: try R 0x104 — stalled, master holds STB and ADR
      _Frame(2, {'adr': 0x104, 'stall': 1}),
      // t=35: still stalled (master MUST hold)
      _Frame(3, {}),
      // t=45: stall drops; R 0x104 accepted
      _Frame(4, {'stall': 0}),
      // t=55: try R 0x108
      _Frame(5, {'adr': 0x108}),
      // t=65: STB deasserts (no more requests). First ACK arrives for 0x100.
      _Frame(6, {'stb': 0, 'adr': 0, 'ack': 1, 'dat_i': 0xAAAAAAAA}),
      // t=75: ACK for 0x104
      _Frame(7, {'dat_i': 0xBBBBBBBB}),
      // t=85: ACK for 0x108
      _Frame(8, {'dat_i': 0xCCCCCCCC}),
      // t=95: ack drops, cycle ends
      _Frame(9, {'cyc': 0, 'ack': 0, 'sel': 0, 'dat_i': 0}),
    ],
  ),

  // ── Fixture 7: B4 Pipelined violations ────────────────────────────────────
  _Scenario(
    name: 'wishbone_b4_pipelined_violations',
    signals: _b4Signals,
    bindings: _b4Bindings,
    parameters: _b4Params,
    totalCycles: 10,
    frames: [
      _Frame(0, {'rst': 1}),
      _Frame(1, {'rst': 0}),
      // Violation 5: signal change while STB asserted and STALL high.
      // t=15: R 0x100 issued — but stall is high → not yet accepted.
      _Frame(1, {
        'cyc': 1,
        'stb': 1,
        'we': 0,
        'adr': 0x100,
        'sel': 0xF,
        'stall': 1,
      }),
      // t=25: master illegally changes ADR while still stalled.
      _Frame(2, {'adr': 0x104}),
      // t=35: stall drops, request accepted
      _Frame(3, {'stall': 0}),
      // t=45: stb deasserts
      _Frame(4, {'stb': 0, 'adr': 0}),
      // t=55: ack with mutex violation — ack AND err simultaneously.
      _Frame(5, {'ack': 1, 'err': 1, 'dat_i': 0x12345678}),
      // t=65: cycle ends
      _Frame(6, {'cyc': 0, 'ack': 0, 'err': 0, 'sel': 0, 'dat_i': 0}),
    ],
  ),
];
