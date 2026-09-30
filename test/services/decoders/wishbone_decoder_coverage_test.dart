// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/services/decoders/wishbone_decoder.dart';

// ── test helpers ──────────────────────────────────────────────────────────────
//
// Mirror the harness in wishbone_decoder_test.dart. This sibling file targets
// the registered-feedback burst body, the B4 reset/lock/misalignment paths,
// the LOCK/tags transaction fields, and the burst-parent label formatting that
// the primary suite leaves uncovered.

SignalValueQuery makeQuery(Map<String, List<(int, String)>> changes) {
  return (signal, time) {
    final list = changes[signal] ?? [];
    String? held;
    for (final (t, v) in list) {
      if (t > time) break;
      held = v;
    }
    return held;
  };
}

SignalChangesQuery makeChangesQuery(Map<String, List<(int, String)>> changes) {
  return (signal, start, end) {
    final list = changes[signal] ?? [];
    return [
      for (final e in list)
        if (e.$1 >= start && e.$1 < end) e,
    ];
  };
}

/// Rising edges at `(2k+1)*halfPeriod`; falling at `(2k+2)*halfPeriod`.
List<(int, String)> makeClock({int numEdges = 8, int halfPeriod = 5}) {
  return [
    for (var i = 0; i < numEdges; i++)
      ((i + 1) * halfPeriod, i.isEven ? '1' : '0'),
  ];
}

String bv32(int v) => 'b${v.toUnsigned(32).toRadixString(2).padLeft(32, '0')}';

WishboneDecoder makeDecoder({
  Map<String, String>? bindings,
  Map<String, dynamic>? parameters,
}) {
  return WishboneDecoder(
    DecoderConfig(
      signalBindings: bindings ?? _defaultBindings,
      parameters: parameters ?? _defaultParams,
    ),
  );
}

const _defaultBindings = {
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

const _defaultParams = <String, dynamic>{
  'revision': 'b3',
  'addr_width': 32,
  'data_width': '32',
  'granularity': '8',
  'endianness': 'little',
  'check_alignment': true,
};

void main() {
  group('WishboneDecoder — B3 registered-feedback bursts', () {
    // A complete incrementing burst: four beats at 0x100/0x104/0x108/0x10C,
    // with the last beat tagged CTI=111 (End-of-Burst). Each beat is its own
    // STB/ACK handshake on consecutive rising edges (t=5,15,25,35). This
    // exercises the burst-accumulator open/append path, the incrementing-burst
    // address-stride check (_wrapBurstAdr with BTE=00 → linear), the EOB close,
    // and the burst-parent record emission.
    test(
      'incrementing burst (4 beats + EOB) emits 4 child beats + 1 parent',
      () {
        final bindings = {..._defaultBindings, 'cti': 'tb.CTI'};
        final changes = {
          'clk': makeClock(),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1'), (38, '0')],
          'stb': [(0, '0'), (2, '1'), (38, '0')],
          'we': [(0, '0'), (2, '1')],
          'adr': [
            (0, bv32(0)),
            (2, bv32(0x100)),
            (12, bv32(0x104)),
            (22, bv32(0x108)),
            (32, bv32(0x10C)),
          ],
          'dat_o': [
            (0, bv32(0)),
            (2, bv32(0xA0)),
            (12, bv32(0xA1)),
            (22, bv32(0xA2)),
            (32, bv32(0xA3)),
          ],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0'), (2, '1'), (38, '0')],
          // 010 incrementing for first 3 beats, 111 EOB on the last beat.
          'cti': [(0, 'b000'), (2, 'b010'), (32, 'b111')],
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder(bindings: bindings).decode(
          0,
          60,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        final children = txs.where((t) => t.fields['type'] != 'Burst').toList();
        final parents = txs.where((t) => t.fields['type'] == 'Burst').toList();
        expect(children, hasLength(4), reason: 'four burst beats');
        expect(parents, hasLength(1), reason: 'one parent burst record');
        expect(
          children.map((t) => t.fields['address']).toList(),
          ['0x00000100', '0x00000104', '0x00000108', '0x0000010C'],
        );
        final parent = parents.first;
        expect(parent.label, 'Burst-Incr 4× W 0x100..0x10C');
        expect(parent.fields['beats'], '4');
        expect(parent.fields['first_address'], '0x100');
        expect(parent.fields['last_address'], '0x10C');
        expect(parent.isError, isFalse);
      },
    );

    test('incrementing burst with non-stride ADR jump is flagged', () {
      final bindings = {..._defaultBindings, 'cti': 'tb.CTI'};
      final changes = {
        'clk': makeClock(numEdges: 6),
        'rst': [(0, '0')],
        'cyc': [(0, '0'), (2, '1'), (28, '0')],
        'stb': [(0, '0'), (2, '1'), (28, '0')],
        'we': [(0, '0'), (2, '1')],
        // 0x100 → 0x200 is not +4: ADR jump violation on the second beat.
        'adr': [(0, bv32(0)), (2, bv32(0x100)), (12, bv32(0x200))],
        'dat_o': [(0, bv32(0)), (2, bv32(0xA0)), (12, bv32(0xA1))],
        'dat_i': [(0, bv32(0))],
        'ack': [(0, '0'), (2, '1'), (28, '0')],
        'cti': [(0, 'b000'), (2, 'b010')],
        'sel': [(0, 'b1111')],
      };
      final txs = makeDecoder(bindings: bindings).decode(
        0,
        40,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(
        txs.any((t) => t.errorMessage?.contains('ADR jumped') ?? false),
        isTrue,
      );
    });

    test('incrementing burst with WE change beat-to-beat is flagged', () {
      final bindings = {..._defaultBindings, 'cti': 'tb.CTI'};
      final changes = {
        'clk': makeClock(numEdges: 6),
        'rst': [(0, '0')],
        'cyc': [(0, '0'), (2, '1'), (28, '0')],
        'stb': [(0, '0'), (2, '1'), (28, '0')],
        // WE=1 on beat 1, flips to 0 on beat 2 within the same burst.
        'we': [(0, '0'), (2, '1'), (12, '0')],
        'adr': [(0, bv32(0)), (2, bv32(0x100)), (12, bv32(0x104))],
        'dat_o': [(0, bv32(0)), (2, bv32(0xA0))],
        'dat_i': [(0, bv32(0)), (12, bv32(0xB1))],
        'ack': [(0, '0'), (2, '1'), (28, '0')],
        'cti': [(0, 'b000'), (2, 'b010')],
        'sel': [(0, 'b1111')],
      };
      final txs = makeDecoder(bindings: bindings).decode(
        0,
        40,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(
        txs.any(
          (t) => t.errorMessage?.contains('WE changed beat-to-beat') ?? false,
        ),
        isTrue,
      );
    });

    test('incrementing burst with SEL change beat-to-beat is flagged', () {
      final bindings = {..._defaultBindings, 'cti': 'tb.CTI'};
      final changes = {
        'clk': makeClock(numEdges: 6),
        'rst': [(0, '0')],
        'cyc': [(0, '0'), (2, '1'), (28, '0')],
        'stb': [(0, '0'), (2, '1'), (28, '0')],
        'we': [(0, '0'), (2, '1')],
        'adr': [(0, bv32(0)), (2, bv32(0x100)), (12, bv32(0x104))],
        'dat_o': [(0, bv32(0)), (2, bv32(0xA0)), (12, bv32(0xA1))],
        'dat_i': [(0, bv32(0))],
        'ack': [(0, '0'), (2, '1'), (28, '0')],
        'cti': [(0, 'b000'), (2, 'b010')],
        // SEL changes between beats: 1111 → 0011.
        'sel': [(0, 'b1111'), (12, 'b0011')],
      };
      final txs = makeDecoder(bindings: bindings).decode(
        0,
        40,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(
        txs.any(
          (t) => t.errorMessage?.contains('SEL changed beat-to-beat') ?? false,
        ),
        isTrue,
      );
    });

    test(
      'constant-address burst (CTI=001) flags an ADR change between beats',
      () {
        final bindings = {..._defaultBindings, 'cti': 'tb.CTI'};
        final changes = {
          'clk': makeClock(numEdges: 6),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1'), (28, '0')],
          'stb': [(0, '0'), (2, '1'), (28, '0')],
          'we': [(0, '0')],
          // Constant-address burst must keep ADR fixed; change it on beat 2.
          'adr': [(0, bv32(0)), (2, bv32(0x100)), (12, bv32(0x104))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0)), (2, bv32(0xC0)), (12, bv32(0xC1))],
          'ack': [(0, '0'), (2, '1'), (28, '0')],
          'cti': [(0, 'b000'), (2, 'b001')], // constant-address
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder(bindings: bindings).decode(
          0,
          40,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(
          txs.any(
            (t) => t.errorMessage?.contains('Constant-address burst') ?? false,
          ),
          isTrue,
        );
        // The burst parent for a constant-address burst spans a single address.
        final parent = txs.firstWhere((t) => t.fields['type'] == 'Burst');
        expect(parent.label, startsWith('Burst-Const'));
        expect(parent.fields['first_address'], '0x100');
      },
    );

    test('4-beat-wrap burst (BTE=01) wraps ADR within its window', () {
      // Window = 4 beats * 4 bytes = 16 bytes. Start at 0x108, increment by 4:
      // 0x108 → 0x10C → wrap → 0x100 → 0x104. Parent carries the wrap label.
      final bindings = {..._defaultBindings, 'cti': 'tb.CTI', 'bte': 'tb.BTE'};
      final changes = {
        'clk': makeClock(),
        'rst': [(0, '0')],
        'cyc': [(0, '0'), (2, '1'), (38, '0')],
        'stb': [(0, '0'), (2, '1'), (38, '0')],
        'we': [(0, '0'), (2, '1')],
        'adr': [
          (0, bv32(0)),
          (2, bv32(0x108)),
          (12, bv32(0x10C)),
          (22, bv32(0x100)),
          (32, bv32(0x104)),
        ],
        'dat_o': [(0, bv32(0)), (2, bv32(0xD0))],
        'dat_i': [(0, bv32(0))],
        'ack': [(0, '0'), (2, '1'), (38, '0')],
        'cti': [(0, 'b000'), (2, 'b010'), (32, 'b111')],
        'bte': [(0, 'b00'), (2, 'b01')], // 4-beat wrap
        'sel': [(0, 'b1111')],
      };
      final txs = makeDecoder(bindings: bindings).decode(
        0,
        60,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      // No "ADR jumped" violation: the wrap math accepts the 0x10C→0x100 step.
      expect(
        txs.where((t) => t.errorMessage?.contains('ADR jumped') ?? false),
        isEmpty,
        reason: 'wrap addresses must not be flagged as jumps',
      );
      final parent = txs.firstWhere((t) => t.fields['type'] == 'Burst');
      expect(parent.label, contains('Wrap-4'));
      expect(parent.fields['bte'], '0b01');
    });

    test('reset mid-burst finalizes the in-flight burst parent', () {
      // Open an incrementing burst, then assert reset before EOB. The reset
      // branch must flush the partial burst as a parent record.
      final bindings = {..._defaultBindings, 'cti': 'tb.CTI'};
      final changes = {
        'clk': makeClock(numEdges: 6),
        'rst': [(0, '0'), (12, '1')], // reset asserted after first beat
        'cyc': [(0, '0'), (2, '1')],
        'stb': [(0, '0'), (2, '1'), (8, '0')],
        'we': [(0, '0'), (2, '1')],
        'adr': [(0, bv32(0)), (2, bv32(0x100))],
        'dat_o': [(0, bv32(0)), (2, bv32(0xA0))],
        'dat_i': [(0, bv32(0))],
        'ack': [(0, '0'), (2, '1'), (8, '0')],
        'cti': [(0, 'b000'), (2, 'b010')],
        'sel': [(0, 'b1111')],
      };
      final txs = makeDecoder(bindings: bindings).decode(
        0,
        40,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      final parent = txs.firstWhere((t) => t.fields['type'] == 'Burst');
      expect(parent.fields['beats'], '1');
    });

    test('burst still in flight at end of trace is finalized', () {
      // CYC stays high through the end of the window with no EOB beat: the
      // tail-finalize branch must still emit the parent record.
      final bindings = {..._defaultBindings, 'cti': 'tb.CTI'};
      final changes = {
        'clk': makeClock(numEdges: 4),
        'rst': [(0, '0')],
        'cyc': [(0, '0'), (2, '1')], // never drops
        'stb': [(0, '0'), (2, '1'), (8, '0')],
        'we': [(0, '0'), (2, '1')],
        'adr': [(0, bv32(0)), (2, bv32(0x100))],
        'dat_o': [(0, bv32(0)), (2, bv32(0xA0))],
        'dat_i': [(0, bv32(0))],
        'ack': [(0, '0'), (2, '1'), (8, '0')],
        'cti': [(0, 'b000'), (2, 'b010')],
        'sel': [(0, 'b1111')],
      };
      final txs = makeDecoder(bindings: bindings).decode(
        0,
        30,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(txs.any((t) => t.fields['type'] == 'Burst'), isTrue);
    });
  });

  group('WishboneDecoder — LOCK and user tags', () {
    test('LOCK asserted surfaces a lock field; tags pass through', () {
      final bindings = {
        ..._defaultBindings,
        'lock': 'tb.LOCK',
        'tga': 'tb.TGA',
        'tgd_o': 'tb.TGD_O',
        'tgc': 'tb.TGC',
      };
      final changes = {
        'clk': makeClock(numEdges: 4),
        'rst': [(0, '0')],
        'cyc': [(0, '0'), (2, '1'), (8, '0')],
        'stb': [(0, '0'), (2, '1'), (8, '0')],
        'we': [(0, '0'), (2, '1')],
        'adr': [(0, bv32(0)), (2, bv32(0x100))],
        'dat_o': [(0, bv32(0)), (2, bv32(0xDEADBEEF))],
        'dat_i': [(0, bv32(0))],
        'ack': [(0, '0'), (2, '1'), (8, '0')],
        'lock': [(0, '0'), (2, '1')],
        'tga': [(0, bv32(0)), (2, bv32(0xAB))],
        'tgd_o': [(0, bv32(0)), (2, bv32(0xCD))],
        'tgc': [(0, bv32(0)), (2, bv32(0xEF))],
        'sel': [(0, 'b1111')],
      };
      final txs = makeDecoder(bindings: bindings).decode(
        0,
        30,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(txs, hasLength(1));
      final t = txs.first;
      expect(t.fields['lock'], '1');
      expect(t.fields['tga'], '0xAB');
      expect(t.fields['tgd_o'], '0xCD');
      expect(t.fields['tgc'], '0xEF');
    });
  });

  group('WishboneDecoder — B4 pipelined edge paths', () {
    Map<String, String> b4Bindings() => {
      ..._defaultBindings,
      'stall': 'tb.STALL',
      'lock': 'tb.LOCK',
    };
    Map<String, dynamic> b4Params() => {..._defaultParams, 'revision': 'b4'};

    test('reset clears outstanding pipelined requests', () {
      // Issue a request, then assert reset before the ACK. After reset the
      // request must be discarded — no transaction, no CYC-drop violation.
      final changes = {
        'clk': makeClock(numEdges: 6),
        'rst': [(0, '0'), (12, '1')],
        'cyc': [(0, '0'), (2, '1')],
        'stb': [(0, '0'), (2, '1'), (8, '0')],
        'we': [(0, '0')],
        'adr': [(0, bv32(0)), (2, bv32(0x100))],
        'dat_o': [(0, bv32(0))],
        'dat_i': [(0, bv32(0))],
        'ack': [(0, '0')],
        'stall': [(0, '0')],
        'lock': [(0, '0')],
        'sel': [(0, 'b1111')],
      };
      final txs = makeDecoder(
        bindings: b4Bindings(),
        parameters: b4Params(),
      ).decode(0, 40, makeQuery(changes), makeChangesQuery(changes));
      // Reset wiped the FIFO before the (never-arriving) ACK; nothing emitted.
      expect(txs.where((t) => t.fields['cycle'] == 'Pipelined'), isEmpty);
    });

    test('B4 multiple terminations on one edge is flagged', () {
      final changes = {
        'clk': makeClock(numEdges: 4),
        'rst': [(0, '0')],
        'cyc': [(0, '0'), (2, '1'), (18, '0')],
        'stb': [(0, '0'), (2, '1'), (8, '0')],
        'we': [(0, '0')],
        'adr': [(0, bv32(0)), (2, bv32(0x100))],
        'dat_o': [(0, bv32(0))],
        'dat_i': [(0, bv32(0))],
        'ack': [(0, '0'), (12, '1')],
        'err': [(0, '0'), (12, '1')], // ACK + ERR same edge
        'stall': [(0, '0')],
        'lock': [(0, '0')],
        'sel': [(0, 'b1111')],
      };
      final txs = makeDecoder(
        bindings: b4Bindings(),
        parameters: b4Params(),
      ).decode(0, 30, makeQuery(changes), makeChangesQuery(changes));
      expect(
        txs.any(
          (t) => t.errorMessage?.contains('Multiple terminations') ?? false,
        ),
        isTrue,
      );
    });

    test('B4 STB asserted while CYC deasserted is flagged', () {
      final changes = {
        'clk': makeClock(numEdges: 2),
        'rst': [(0, '0')],
        'cyc': [(0, '0')], // CYC never asserted
        'stb': [(0, '0'), (2, '1')],
        'we': [(0, '0')],
        'adr': [(0, bv32(0))],
        'dat_o': [(0, bv32(0))],
        'dat_i': [(0, bv32(0))],
        'ack': [(0, '0')],
        'stall': [(0, '0')],
        'lock': [(0, '0')],
        'sel': [(0, 'b1111')],
      };
      final txs = makeDecoder(
        bindings: b4Bindings(),
        parameters: b4Params(),
      ).decode(0, 20, makeQuery(changes), makeChangesQuery(changes));
      expect(
        txs.any(
          (t) => t.errorMessage?.contains('STB asserted while CYC') ?? false,
        ),
        isTrue,
      );
    });

    test('B4 misaligned issue address is flagged', () {
      final changes = {
        'clk': makeClock(numEdges: 4),
        'rst': [(0, '0')],
        'cyc': [(0, '0'), (2, '1'), (18, '0')],
        'stb': [(0, '0'), (2, '1'), (8, '0')],
        'we': [(0, '0')],
        'adr': [(0, bv32(0)), (2, bv32(0x101))], // not 4-aligned
        'dat_o': [(0, bv32(0))],
        'dat_i': [(0, bv32(0)), (12, bv32(0x1))],
        'ack': [(0, '0'), (12, '1'), (18, '0')],
        'stall': [(0, '0')],
        'lock': [(0, '0')],
        'sel': [(0, 'b1111')],
      };
      final txs = makeDecoder(
        bindings: b4Bindings(),
        parameters: b4Params(),
      ).decode(0, 30, makeQuery(changes), makeChangesQuery(changes));
      expect(
        txs.any((t) => t.errorMessage?.contains('Misaligned address') ?? false),
        isTrue,
      );
    });

    test('B4 pipelined write carries LOCK and resolves dat_o as data', () {
      final changes = {
        'clk': makeClock(numEdges: 4),
        'rst': [(0, '0')],
        'cyc': [(0, '0'), (2, '1'), (18, '0')],
        'stb': [(0, '0'), (2, '1'), (8, '0')],
        'we': [(0, '0'), (2, '1')],
        'adr': [(0, bv32(0)), (2, bv32(0x100))],
        'dat_o': [(0, bv32(0)), (2, bv32(0xCAFEBABE))],
        'dat_i': [(0, bv32(0))],
        'ack': [(0, '0'), (12, '1'), (18, '0')],
        'stall': [(0, '0')],
        'lock': [(0, '0'), (2, '1')],
        'sel': [(0, 'b1111')],
      };
      final txs = makeDecoder(
        bindings: b4Bindings(),
        parameters: b4Params(),
      ).decode(0, 30, makeQuery(changes), makeChangesQuery(changes));
      final beat = txs.firstWhere((t) => t.fields['cycle'] == 'Pipelined');
      expect(beat.fields['type'], 'Write');
      expect(beat.fields['data'], '0xCAFEBABE');
      expect(beat.fields['lock'], '1');
    });
  });

  group('WishboneDecoder — formatting fallbacks', () {
    test('X bits in adr produce a question-mark address', () {
      final changes = {
        'clk': makeClock(numEdges: 2),
        'rst': [(0, '0')],
        'cyc': [(0, '0'), (2, '1')],
        'stb': [(0, '0'), (2, '1')],
        'we': [(0, '0')],
        'adr': [(0, bv32(0)), (2, 'b${'x' * 32}')], // fully unknown address
        'dat_o': [(0, bv32(0))],
        'dat_i': [(0, bv32(0)), (2, bv32(0x1))],
        'ack': [(0, '0'), (2, '1')],
        'sel': [(0, 'b1111')],
      };
      final txs = makeDecoder().decode(
        0,
        20,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(txs.first.fields['address'], '0x????????');
    });
  });
}
