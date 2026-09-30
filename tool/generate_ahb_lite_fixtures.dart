// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates AHB-Lite bus VCD fixtures used by the AhbLiteDecoder unit
// tests and by the verification guide (§5.8).
//
// Output (mirrored to both test/ and verification/ trees):
//   test/fixtures/protocol/ahb_lite/generated/<scenario>.vcd
//   test/fixtures/protocol/ahb_lite/generated/<scenario>.expected_transactions.json
//   verification/fixtures/protocol/ahb_lite/generated/<scenario>.vcd
//   verification/fixtures/protocol/ahb_lite/generated/<scenario>.expected_transactions.json
//
// Usage:
//   dart run tool/generate_ahb_lite_fixtures.dart
//
// All fixtures are hand-crafted: the timeline is encoded as a sequence of
// "cycle frames" (one per bus clock tick). The tool unrolls each frame
// into VCD value-change records and runs the AhbLiteDecoder against the
// emitted timeline to produce the matching expected_transactions.json.
//
// The expected JSON is therefore always *consistent* with the decoder
// implementation — the test file then asserts hand-verified anchor
// points (key labels, transaction counts, error flags) so a silent
// regression in decoder output is still caught.
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
import 'package:wavecrux/services/decoders/ahb_lite_decoder.dart';

const _testOutDir = 'test/fixtures/protocol/ahb_lite/generated';
const _verificationOutDir = 'verification/fixtures/protocol/ahb_lite/generated';

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

  print('Generated AHB-Lite fixtures:');
  for (final s in _scenarios) {
    print('  $_testOutDir/${s.name}.vcd');
    print('  $_testOutDir/${s.name}.expected_transactions.json');
  }
  print(
    'and in $_verificationOutDir/. Run `flutter test '
    'test/services/decoders/ahb_lite_decoder_test.dart` to verify.',
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

  /// Cycle index (0-based). Rising edge of hclk lands at `cycle * 10 + 5`.
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

  /// Decoder-side binding map (logical name → tb signal path).
  final Map<String, String> bindings;
  final Map<String, dynamic> parameters;
  final int? totalCycles;
}

// ── VCD emission ─────────────────────────────────────────────────────────────

String _renderVcd(_Scenario s) {
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

  // Initial values: every signal starts at 0 EXCEPT hresetn and hready
  // which start at 1 — that matches the post-reset, idle-bus state and
  // avoids spurious "reset asserted forever" decoding before the first
  // frame change.
  final state = <String, String>{
    for (final sig in s.signals)
      sig.name: sig.width == 1
          ? (sig.name == 'hresetn' || sig.name == 'hready' ? '1' : '0')
          : 'b${'0' * sig.width}',
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

  final maxCycle =
      s.totalCycles ??
      (s.frames.isEmpty
          ? 0
          : s.frames.map((f) => f.cycle).reduce((a, b) => a > b ? a : b) + 1);

  // Group frames by cycle for efficient lookup. When multiple frames
  // target the same cycle, merge their `changes` maps (later entries
  // override earlier ones for the same key).
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

    final clkId = ids['hclk'];
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
    return v.startsWith('b') ? v : 'b$v';
  }
  throw StateError('vector value must be int or bit-string: $v');
}

// ── Expected-JSON computation via the decoder under test ─────────────────────

List<DecodedTransaction> _runDecoder(_Scenario s) {
  final changes = <String, List<(int, String)>>{};
  final state = <String, String>{
    for (final sig in s.signals)
      sig.name: sig.width == 1
          ? (sig.name == 'hresetn' || sig.name == 'hready' ? '1' : '0')
          : 'b${'0' * sig.width}',
  };
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
    changes.putIfAbsent('hclk', () => [])
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

  final decoder = AhbLiteDecoder(
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

const _coreSignals = [
  _SignalDecl('hclk', 1),
  _SignalDecl('hresetn', 1),
  _SignalDecl('haddr', 32),
  _SignalDecl('htrans', 2),
  _SignalDecl('hwrite', 1),
  _SignalDecl('hsize', 3),
  _SignalDecl('hburst', 3),
  _SignalDecl('hwdata', 32),
  _SignalDecl('hrdata', 32),
  _SignalDecl('hready', 1),
  _SignalDecl('hresp', 1),
];

const _coreSignalsWithProtLock = [
  ..._coreSignals,
  _SignalDecl('hprot', 4),
  _SignalDecl('hmastlock', 1),
];

const _coreBindings = {
  'hclk': 'tb.HCLK',
  'hresetn': 'tb.HRESETN',
  'haddr': 'tb.HADDR',
  'htrans': 'tb.HTRANS',
  'hwrite': 'tb.HWRITE',
  'hsize': 'tb.HSIZE',
  'hburst': 'tb.HBURST',
  'hwdata': 'tb.HWDATA',
  'hrdata': 'tb.HRDATA',
  'hready': 'tb.HREADY',
  'hresp': 'tb.HRESP',
};

const _coreBindingsWithProtLock = {
  ..._coreBindings,
  'hprot': 'tb.HPROT',
  'hmastlock': 'tb.HMASTLOCK',
};

const _baseParams = <String, dynamic>{
  'addr_width': 32,
  'data_width': '32',
  'check_alignment': true,
  'wait_state_threshold': 256,
};

// HTRANS encoding for readability in scenario authoring. Only the
// values actually referenced by the scenarios below are declared; the
// full IHI 0033 encoding lives on the decoder side.
const _idle = 0x0;
const _busy = 0x1;
const _nonseq = 0x2;
const _seq = 0x3;

// HBURST encoding (only values used by the scenarios).
const _bSingle = 0x0;
const _bIncr = 0x1;
const _bWrap4 = 0x2;
const _bIncr4 = 0x3;
const _bIncr8 = 0x5;

// HSIZE encoding (only the word-aligned 32-bit value used by the
// scenarios; 64-bit HSIZE=3 is written as a literal where it appears).
const _sWord = 0x2;

// Fixture-authoring convention (single-edge pipeline, matching the
// AhbLiteDecoder model):
//
//   At the rising edge ending cycle k (visible in frame ck), the decoder:
//   (1) completes the in-flight transfer captured at the PREVIOUS edge
//       (sampling HRDATA/HWDATA/HRESP from frame ck), and
//   (2) latches THIS edge's HTRANS/HADDR/etc. as the new in-flight
//       transfer (becomes the next beat to complete).
//
//   So for a transfer whose address phase is in frame ck:
//     - HADDR/HTRANS/HWRITE/HSIZE/HBURST/HPROT/HMASTLOCK go in frame ck.
//     - HRDATA (reads) or HWDATA (writes) go in frame c(k+1) — they
//       arrive at the edge that completes this transfer.
//   Wait states extend completion: each HREADY=0 frame between ck and
//   the eventual HREADY=1 frame is an extra wait cycle.

final _scenarios = <_Scenario>[
  // ── Fixture 1: SINGLE basic — one read, one write ─────────────────────────
  _Scenario(
    name: 'ahb_lite_single_basic',
    signals: _coreSignals,
    bindings: _coreBindings,
    parameters: _baseParams,
    totalCycles: 6,
    frames: [
      // c0: address phase of READ from 0x00000100.
      _Frame(0, {
        'htrans': _nonseq,
        'hburst': _bSingle,
        'hwrite': 0,
        'hsize': _sWord,
        'haddr': 0x100,
      }),
      // c1: address phase of WRITE to 0x00000200; data of READ arrives.
      _Frame(1, {
        'htrans': _nonseq,
        'hwrite': 1,
        'haddr': 0x200,
        'hrdata': 0x12345678,
      }),
      // c2: bus idle; WRITE's data is sampled here.
      _Frame(2, {
        'htrans': _idle,
        'haddr': 0,
        'hwdata': 0xDEADBEEF,
      }),
      // c3-c5: drain.
      _Frame(3, {'hwdata': 0, 'hrdata': 0}),
    ],
  ),

  // ── Fixture 2: INCR4 burst (4-beat fixed-length incrementing read) ────────
  _Scenario(
    name: 'ahb_lite_incr_burst',
    signals: _coreSignals,
    bindings: _coreBindings,
    parameters: _baseParams,
    totalCycles: 8,
    frames: [
      // c0: NONSEQ at 0x100, INCR4 read (HSIZE=word → stride=4).
      _Frame(0, {
        'htrans': _nonseq,
        'hburst': _bIncr4,
        'hwrite': 0,
        'hsize': _sWord,
        'haddr': 0x100,
      }),
      // c1: SEQ at 0x104; data of beat 1 (addr 0x100) arrives.
      _Frame(1, {
        'htrans': _seq,
        'haddr': 0x104,
        'hrdata': 0xA0A0A0A0,
      }),
      // c2: SEQ at 0x108; data of beat 2 (addr 0x104).
      _Frame(2, {'haddr': 0x108, 'hrdata': 0xB1B1B1B1}),
      // c3: SEQ at 0x10C; data of beat 3 (addr 0x108).
      _Frame(3, {'haddr': 0x10C, 'hrdata': 0xC2C2C2C2}),
      // c4: IDLE; data of beat 4 (addr 0x10C) arrives, completing burst.
      _Frame(4, {
        'htrans': _idle,
        'haddr': 0,
        'hrdata': 0xD3D3D3D3,
      }),
      _Frame(5, {'hrdata': 0}),
    ],
  ),

  // ── Fixture 3: WRAP4 burst (4-beat wrap inside 16-byte window) ────────────
  // First beat at 0x108 (mid-window), wraps within [0x100..0x10F].
  _Scenario(
    name: 'ahb_lite_wrap_burst',
    signals: _coreSignals,
    bindings: _coreBindings,
    parameters: _baseParams,
    totalCycles: 8,
    frames: [
      _Frame(0, {
        'htrans': _nonseq,
        'hburst': _bWrap4,
        'hwrite': 0,
        'hsize': _sWord,
        'haddr': 0x108,
      }),
      _Frame(1, {
        'htrans': _seq,
        'haddr': 0x10C,
        'hrdata': 0x11111111,
      }),
      _Frame(2, {'haddr': 0x100, 'hrdata': 0x22222222}), // wrap
      _Frame(3, {'haddr': 0x104, 'hrdata': 0x33333333}),
      _Frame(4, {
        'htrans': _idle,
        'haddr': 0,
        'hrdata': 0x44444444,
      }),
      _Frame(5, {'hrdata': 0}),
    ],
  ),

  // ── Fixture 4: INCR (undefined-length) with mid-burst BUSY insertion ─────
  // 3 beats of read, with BUSY at cycle 2 (between beats 1 and 2).
  _Scenario(
    name: 'ahb_lite_incr_undefined',
    signals: _coreSignals,
    bindings: _coreBindings,
    parameters: _baseParams,
    totalCycles: 8,
    frames: [
      // c0: NONSEQ at 0x200, INCR (undefined).
      _Frame(0, {
        'htrans': _nonseq,
        'hburst': _bIncr,
        'hwrite': 0,
        'hsize': _sWord,
        'haddr': 0x200,
      }),
      // c1: SEQ at 0x204; data of beat 1 (addr 0x200) arrives.
      _Frame(1, {
        'htrans': _seq,
        'haddr': 0x204,
        'hrdata': 0x01010101,
      }),
      // c2: BUSY (master not ready); haddr held at 0x204; data of
      // beat 2 (addr 0x204) does NOT arrive yet because BUSY does not
      // complete a transfer. Decoder will simply not capture a new beat.
      _Frame(2, {
        'htrans': _busy,
        'hrdata': 0x02020202,
      }),
      // c3: SEQ at 0x208 resumes; data of beat 2 arrives now.
      _Frame(3, {
        'htrans': _seq,
        'haddr': 0x208,
      }),
      // c4: IDLE ends the undefined-length burst; data of beat 3
      // (addr 0x208) arrives.
      _Frame(4, {
        'htrans': _idle,
        'haddr': 0,
        'hrdata': 0x03030303,
      }),
      _Frame(5, {'hrdata': 0}),
    ],
  ),

  // ── Fixture 5: wait states on a single read ──────────────────────────────
  // Slave inserts 2 wait states (HREADY=0) on the data phase.
  _Scenario(
    name: 'ahb_lite_wait_states',
    signals: _coreSignals,
    bindings: _coreBindings,
    parameters: _baseParams,
    totalCycles: 8,
    frames: [
      // c0: NONSEQ READ at 0x100.
      _Frame(0, {
        'htrans': _nonseq,
        'hburst': _bSingle,
        'hwrite': 0,
        'hsize': _sWord,
        'haddr': 0x100,
      }),
      // c1: bus idle; slave inserts wait state #1 (hready=0).
      _Frame(1, {
        'htrans': _idle,
        'haddr': 0,
        'hready': 0,
      }),
      // c2: wait state #2.
      _Frame(2, {}),
      // c3: hready rises; hrdata sampled here; data phase completes.
      _Frame(3, {'hready': 1, 'hrdata': 0xCAFE0001}),
      // c4: drain.
      _Frame(4, {'hrdata': 0}),
    ],
  ),

  // ── Fixture 6: ERROR response with proper two-cycle handshake ────────────
  // Write transfer; slave responds with ERROR using the two-cycle
  // sequence (cycle 1: hready=0,hresp=1; cycle 2: hready=1,hresp=1).
  _Scenario(
    name: 'ahb_lite_error_response',
    signals: _coreSignals,
    bindings: _coreBindings,
    parameters: _baseParams,
    totalCycles: 8,
    frames: [
      // c0: NONSEQ WRITE to 0x300.
      _Frame(0, {
        'htrans': _nonseq,
        'hburst': _bSingle,
        'hwrite': 1,
        'hsize': _sWord,
        'haddr': 0x300,
      }),
      // c1: bus idle; ERROR phase 1 (hready=0, hresp=1).
      _Frame(1, {
        'htrans': _idle,
        'haddr': 0,
        'hready': 0,
        'hresp': 1,
      }),
      // c2: ERROR phase 2 (hready=1, hresp=1); WRITE's hwdata sampled
      // here together with the ERROR completion.
      _Frame(2, {'hready': 1, 'hwdata': 0xBADF00D1}),
      // c3: drain.
      _Frame(3, {'hwdata': 0, 'hresp': 0}),
    ],
  ),

  // ── Fixture 7: HMASTLOCK locked transfer (read-modify-write) ─────────────
  _Scenario(
    name: 'ahb_lite_locked_transfer',
    signals: _coreSignalsWithProtLock,
    bindings: _coreBindingsWithProtLock,
    parameters: _baseParams,
    totalCycles: 6,
    frames: [
      // c0: locked READ from 0x400. HPROT = data, privileged.
      _Frame(0, {
        'htrans': _nonseq,
        'hburst': _bSingle,
        'hwrite': 0,
        'hsize': _sWord,
        'haddr': 0x400,
        'hprot': 0x3,
        'hmastlock': 1,
      }),
      // c1: locked WRITE back to 0x400; data of READ arrives = 0x10.
      _Frame(1, {
        'htrans': _nonseq,
        'hwrite': 1,
        'haddr': 0x400,
        'hrdata': 0x00000010,
      }),
      // c2: bus idle; WRITE's hwdata=0x11 arrives; lock drops.
      _Frame(2, {
        'htrans': _idle,
        'haddr': 0,
        'hwdata': 0x00000011,
        'hmastlock': 0,
      }),
      _Frame(3, {'hwdata': 0, 'hrdata': 0, 'hprot': 0}),
    ],
  ),

  // ── Fixture 8: protocol violations ────────────────────────────────────────
  // Exercises violation classes 1, 2, 4, 5, 6, 7.
  _Scenario(
    name: 'ahb_lite_violations',
    signals: _coreSignals,
    bindings: _coreBindings,
    parameters: _baseParams,
    totalCycles: 18,
    frames: [
      // c0: Violation 2 — HTRANS=SEQ at start (no NONSEQ ever).
      _Frame(0, {
        'htrans': _seq,
        'hburst': _bSingle,
        'hwrite': 0,
        'hsize': _sWord,
        'haddr': 0x100,
      }),
      // c1: back to IDLE.
      _Frame(1, {'htrans': _idle, 'haddr': 0}),
      // c2: Violation 1 — HTRANS=BUSY without an active burst.
      _Frame(2, {'htrans': _busy}),
      // c3: clear.
      _Frame(3, {'htrans': _idle}),
      // c4: Violation 6 — misaligned address (HSIZE=word, addr=0x101).
      _Frame(4, {
        'htrans': _nonseq,
        'hburst': _bSingle,
        'hwrite': 0,
        'hsize': _sWord,
        'haddr': 0x101,
      }),
      // c5: idle; data of the misaligned read arrives.
      _Frame(5, {
        'htrans': _idle,
        'haddr': 0,
        'hrdata': 0x00000000,
      }),
      // c6: Violation 5 — HSIZE=64-bit but data_width=32.
      _Frame(6, {
        'htrans': _nonseq,
        'hburst': _bSingle,
        'hwrite': 0,
        'hsize': 0x3,
        'haddr': 0x110,
      }),
      _Frame(7, {'htrans': _idle, 'haddr': 0, 'hsize': _sWord}),
      // c8: open INCR4 burst at 0x200 (clean) so we can demonstrate
      // violation 3 (HBURST mid-burst change) and violation 4
      // (non-monotonic HADDR) on subsequent SEQ beats.
      _Frame(8, {
        'htrans': _nonseq,
        'hburst': _bIncr4,
        'hwrite': 0,
        'hsize': _sWord,
        'haddr': 0x200,
      }),
      // c9: SEQ at 0x204 with HBURST changed to INCR8 → Violation 3.
      _Frame(9, {
        'htrans': _seq,
        'hburst': _bIncr8,
        'haddr': 0x204,
        'hrdata': 0x10000000,
      }),
      // c10: SEQ at 0x300 (massive jump, not 0x208) → Violation 4.
      // Restore HBURST to INCR4 so we don't pile on more violation 3.
      _Frame(10, {
        'hburst': _bIncr4,
        'haddr': 0x300,
        'hrdata': 0x20000000,
      }),
      // c11: continue the burst at expected next (0x304) to silence
      // further address-increment violations; close burst at c12.
      _Frame(11, {'haddr': 0x304, 'hrdata': 0x30000000}),
      _Frame(12, {
        'htrans': _idle,
        'haddr': 0,
        'hrdata': 0x40000000,
      }),
      // c13: Violation 7 — single-cycle ERROR (no two-cycle handshake).
      _Frame(13, {
        'htrans': _nonseq,
        'hburst': _bSingle,
        'hwrite': 1,
        'hsize': _sWord,
        'haddr': 0x500,
      }),
      // c14: data phase ends immediately with hready=1, hresp=1 — no
      // preceding hready=0,hresp=1 phase.
      _Frame(14, {
        'htrans': _idle,
        'haddr': 0,
        'hwdata': 0xCAFEBABE,
        'hresp': 1,
      }),
      _Frame(15, {'hresp': 0, 'hwdata': 0}),
    ],
  ),
];
