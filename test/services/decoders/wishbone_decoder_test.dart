// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/decoder_category.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/services/decoders/wishbone_decoder.dart';

// ── test helpers ──────────────────────────────────────────────────────────────

/// Last-held-value query backed by per-signal change lists.
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

/// Range-bound changes query covering `[start, end)`.
SignalChangesQuery makeChangesQuery(
  Map<String, List<(int, String)>> changes,
) {
  return (signal, start, end) {
    final list = changes[signal] ?? [];
    return [
      for (final e in list)
        if (e.$1 >= start && e.$1 < end) e,
    ];
  };
}

/// Rising/falling clk transitions for [numEdges] half-periods of [halfPeriod]
/// ticks. Rising edges land at `(2k+1)*halfPeriod`.
List<(int, String)> makeClock({int numEdges = 8, int halfPeriod = 5}) {
  return [
    for (var i = 0; i < numEdges; i++)
      ((i + 1) * halfPeriod, i.isEven ? '1' : '0'),
  ];
}

/// 32-bit binary-encoded vector value (MSB first).
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

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('WishboneDecoder', () {
    // ── definition ────────────────────────────────────────────────────────────

    group('definition', () {
      test('id is wishbone, category is amba, openCore tier', () {
        const def = WishboneDecoder.decoderDefinition;
        expect(def.id, 'wishbone');
        expect(def.displayName, 'Wishbone');
        expect(def.category, DecoderCategory.amba);
        expect(def.requiredTier, LicenseTier.openCore);
      });

      test('exposes the 9 required Wishbone signals', () {
        final names = WishboneDecoder.decoderDefinition.requiredSignals
            .map((s) => s.name)
            .toSet();
        expect(
          names,
          containsAll([
            'clk',
            'rst',
            'cyc',
            'stb',
            'we',
            'adr',
            'dat_o',
            'dat_i',
            'ack',
          ]),
        );
        expect(WishboneDecoder.decoderDefinition.requiredSignals, hasLength(9));
      });

      test('exposes optional CTI/BTE/STALL/SEL/LOCK/ERR/RTY/tags', () {
        final names = WishboneDecoder.decoderDefinition.optionalSignals
            .map((s) => s.name)
            .toSet();
        expect(
          names,
          containsAll([
            'cti',
            'bte',
            'stall',
            'sel',
            'lock',
            'err',
            'rty',
            'tga',
            'tgd_o',
            'tgd_i',
            'tgc',
          ]),
        );
      });

      test(
        'exposes revision/widths/granularity/endianness/alignment params',
        () {
          final params = WishboneDecoder.decoderDefinition.parameters;
          final byName = {for (final p in params) p.name: p};
          expect(
            byName.keys,
            containsAll([
              'revision',
              'addr_width',
              'data_width',
              'granularity',
              'endianness',
              'check_alignment',
            ]),
          );
          expect(byName['revision']!.type, DecoderParameterType.enumeration);
          expect(byName['revision']!.enumValues, ['b3', 'b4']);
          expect(byName['data_width']!.enumValues, ['8', '16', '32', '64']);
          expect(byName['check_alignment']!.defaultValue, true);
        },
      );

      test('get definition returns the static decoderDefinition', () {
        final decoder = makeDecoder();
        expect(decoder.definition, same(WishboneDecoder.decoderDefinition));
      });
    });

    // ── B3 Classic basic handshakes ───────────────────────────────────────────

    group('B3 Classic', () {
      test('basic write OKAY: correct label, fields, no error', () {
        final changes = {
          'clk': makeClock(numEdges: 4),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1'), (8, '0')],
          'stb': [(0, '0'), (2, '1'), (8, '0')],
          'we': [(0, '0'), (2, '1'), (8, '0')],
          'adr': [(0, bv32(0)), (2, bv32(0x100)), (8, bv32(0))],
          'dat_o': [(0, bv32(0)), (2, bv32(0xDEADBEEF)), (8, bv32(0))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0'), (2, '1'), (8, '0')],
          'sel': [(0, 'b0000'), (2, 'b1111'), (8, 'b0000')],
        };
        final txs = makeDecoder().decode(
          0,
          50,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        final t = txs.first;
        expect(t.startTime, 5);
        expect(t.endTime, 5);
        expect(t.label, 'W 0x00000100 = 0xDEADBEEF');
        expect(t.fields['type'], 'Write');
        expect(t.fields['cycle'], 'Classic');
        expect(t.fields['termination'], 'ACK');
        expect(t.fields['sel'], '0xF');
        expect(t.isError, isFalse);
      });

      test('basic read OKAY: captures dat_i as the data field', () {
        final changes = {
          'clk': makeClock(numEdges: 4),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1'), (8, '0')],
          'stb': [(0, '0'), (2, '1'), (8, '0')],
          'we': [(0, '0')],
          'adr': [(0, bv32(0)), (2, bv32(0x200)), (8, bv32(0))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0)), (2, bv32(0xCAFEBABE)), (8, bv32(0))],
          'ack': [(0, '0'), (2, '1'), (8, '0')],
          'sel': [(0, 'b0000'), (2, 'b1111'), (8, 'b0000')],
        };
        final txs = makeDecoder().decode(
          0,
          50,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.label, 'R 0x00000200 → 0xCAFEBABE');
        expect(txs.first.fields['type'], 'Read');
      });

      test('ERR termination flags isError and ERR label suffix', () {
        final changes = {
          'clk': makeClock(numEdges: 4),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1'), (8, '0')],
          'stb': [(0, '0'), (2, '1'), (8, '0')],
          'we': [(0, '0')],
          'adr': [(0, bv32(0)), (2, bv32(0x100))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0)), (2, bv32(0xBADBADBA))],
          'ack': [(0, '0')],
          'err': [(0, '0'), (2, '1'), (8, '0')],
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder().decode(
          0,
          50,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.label, 'R 0x00000100 → 0xBADBADBA [ERR]');
        expect(txs.first.fields['termination'], 'ERR');
        expect(txs.first.isError, isTrue);
      });

      test('RTY termination flags isError and RTY label suffix', () {
        final changes = {
          'clk': makeClock(numEdges: 4),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1'), (8, '0')],
          'stb': [(0, '0'), (2, '1'), (8, '0')],
          'we': [(0, '0'), (2, '1'), (8, '0')],
          'adr': [(0, bv32(0)), (2, bv32(0x300)), (8, bv32(0))],
          'dat_o': [(0, bv32(0)), (2, bv32(0xCAFEBABE)), (8, bv32(0))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0')],
          'rty': [(0, '0'), (2, '1'), (8, '0')],
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder().decode(
          0,
          50,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.fields['termination'], 'RTY');
        expect(txs.first.isError, isTrue);
        expect(txs.first.errorMessage, 'Termination = RTY');
      });

      test(
        'reset asserted: drops in-flight state, no transactions emitted',
        () {
          final changes = {
            'clk': makeClock(numEdges: 4),
            'rst': [(0, '1')], // held in reset
            'cyc': [(2, '1')],
            'stb': [(2, '1')],
            'we': [(2, '1')],
            'adr': [(0, bv32(0)), (2, bv32(0x100))],
            'dat_o': [(0, bv32(0)), (2, bv32(0xDEADBEEF))],
            'dat_i': [(0, bv32(0))],
            'ack': [(0, '0'), (2, '1')],
            'sel': [(0, 'b1111')],
          };
          final txs = makeDecoder().decode(
            0,
            50,
            makeQuery(changes),
            makeChangesQuery(changes),
          );
          expect(txs, isEmpty);
        },
      );

      test('empty clock changes returns empty list', () {
        final txs = makeDecoder().decode(
          0,
          100,
          makeQuery({}),
          makeChangesQuery({}),
        );
        expect(txs, isEmpty);
      });
    });

    // ── B3 protocol violations ────────────────────────────────────────────────

    group('B3 violations', () {
      test('mutex violation: ACK + ERR same edge → flagged', () {
        final changes = {
          'clk': makeClock(numEdges: 2),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1')],
          'stb': [(0, '0'), (2, '1')],
          'we': [(0, '0')],
          'adr': [(0, bv32(0)), (2, bv32(0x100))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0'), (2, '1')],
          'err': [(0, '0'), (2, '1')],
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder().decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        final violations = txs.where((t) => t.isError).toList();
        expect(violations, isNotEmpty);
        expect(
          violations.first.errorMessage,
          contains('Multiple terminations asserted'),
        );
      });

      test('STB asserted while CYC=0 emits a violation transaction', () {
        final changes = {
          'clk': makeClock(numEdges: 2),
          'rst': [(0, '0')],
          'cyc': [(0, '0')],
          'stb': [(0, '0'), (2, '1')],
          'we': [(0, '0')],
          'adr': [(0, bv32(0))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0')],
          'sel': [(0, 'b0000')],
        };
        final txs = makeDecoder().decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(
          txs.any(
            (t) => t.errorMessage?.contains('STB asserted while CYC') ?? false,
          ),
          isTrue,
        );
      });

      test('reserved CTI value (011) is flagged', () {
        final bindings = {..._defaultBindings, 'cti': 'tb.CTI'};
        final changes = {
          'clk': makeClock(numEdges: 2),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1')],
          'stb': [(0, '0'), (2, '1')],
          'we': [(0, '0')],
          'adr': [(0, bv32(0)), (2, bv32(0x100))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0)), (2, bv32(0xAAAA))],
          'ack': [(0, '0'), (2, '1')],
          'cti': [(0, 'b000'), (2, 'b011')], // reserved
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder(bindings: bindings).decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(
          txs.any((t) => t.errorMessage?.contains('Reserved CTI') ?? false),
          isTrue,
        );
      });

      test('BTE non-zero with CTI=000 (Classic) is flagged', () {
        final bindings = {
          ..._defaultBindings,
          'cti': 'tb.CTI',
          'bte': 'tb.BTE',
        };
        final changes = {
          'clk': makeClock(numEdges: 2),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1')],
          'stb': [(0, '0'), (2, '1')],
          'we': [(0, '0')],
          'adr': [(0, bv32(0)), (2, bv32(0x100))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0)), (2, bv32(0xAAAA))],
          'ack': [(0, '0'), (2, '1')],
          'cti': [(0, 'b000')], // Classic
          'bte': [(0, 'b00'), (2, 'b01')], // BTE != 0
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder(bindings: bindings).decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(
          txs.any((t) => t.errorMessage?.contains('BTE') ?? false),
          isTrue,
        );
      });

      test('misalignment: addr=0x101 with stride=4 → flagged', () {
        final changes = {
          'clk': makeClock(numEdges: 2),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1')],
          'stb': [(0, '0'), (2, '1')],
          'we': [(0, '0'), (2, '1')],
          'adr': [(0, bv32(0)), (2, bv32(0x101))], // misaligned
          'dat_o': [(0, bv32(0)), (2, bv32(0xDEADBEEF))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0'), (2, '1')],
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder().decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(
          txs.any(
            (t) => t.errorMessage?.contains('Misaligned address') ?? false,
          ),
          isTrue,
        );
      });

      test('check_alignment=false suppresses the misalignment violation', () {
        final changes = {
          'clk': makeClock(numEdges: 2),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1')],
          'stb': [(0, '0'), (2, '1')],
          'we': [(0, '0'), (2, '1')],
          'adr': [(0, bv32(0)), (2, bv32(0x101))],
          'dat_o': [(0, bv32(0)), (2, bv32(0xDEADBEEF))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0'), (2, '1')],
          'sel': [(0, 'b1111')],
        };
        final params = {..._defaultParams, 'check_alignment': false};
        final txs = makeDecoder(parameters: params).decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(
          txs.where((t) => t.errorMessage?.contains('Misaligned') ?? false),
          isEmpty,
        );
      });

      // Violation 2 ─────────────────────────────────────────────────────────

      test('Violation 2: ACK asserted while CYC deasserted → violation', () {
        final changes = {
          'clk': makeClock(numEdges: 2),
          'rst': [(0, '0')],
          'cyc': [(0, '0')], // CYC never rises
          'stb': [(0, '0')],
          'we': [(0, '0')],
          'adr': [(0, bv32(0))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0'), (2, '1')], // ACK fires while CYC=0
          'sel': [(0, 'b0000')],
        };
        final txs = makeDecoder().decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(
          txs.any(
            (t) =>
                t.errorMessage?.contains(
                  'Termination (ACK/ERR/RTY) asserted while CYC',
                ) ??
                false,
          ),
          isTrue,
        );
      });

      test('Violation 2: ERR asserted while CYC deasserted → violation', () {
        final changes = {
          'clk': makeClock(numEdges: 2),
          'rst': [(0, '0')],
          'cyc': [(0, '0')],
          'stb': [(0, '0')],
          'we': [(0, '0')],
          'adr': [(0, bv32(0))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0')],
          'err': [(0, '0'), (2, '1')], // ERR fires while CYC=0
          'sel': [(0, 'b0000')],
        };
        final txs = makeDecoder().decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(
          txs.any(
            (t) =>
                t.errorMessage?.contains(
                  'Termination (ACK/ERR/RTY) asserted while CYC',
                ) ??
                false,
          ),
          isTrue,
        );
      });

      // Violation 4 ─────────────────────────────────────────────────────────

      test(
        'Violation 4: WE changes mid-cycle while CYC asserted → violation',
        () {
          // Rising edges at t=5, t=15, t=25. CYC stays high from t=2.
          // WE changes from 0→1 at t=12 (between edges 5 and 15).
          // At t=15: prevCyc=1, prevWe=0, we=1 → violation.
          final changes = {
            'clk': makeClock(numEdges: 6),
            'rst': [(0, '0')],
            'cyc': [(0, '0'), (2, '1')],
            'stb': [(0, '0')],
            'we': [(0, '0'), (12, '1')],
            'adr': [(0, bv32(0))],
            'dat_o': [(0, bv32(0))],
            'dat_i': [(0, bv32(0))],
            'ack': [(0, '0')],
            'sel': [(0, 'b0000')],
          };
          final txs = makeDecoder().decode(
            0,
            50,
            makeQuery(changes),
            makeChangesQuery(changes),
          );
          expect(
            txs.any(
              (t) => t.errorMessage?.contains('WE changed mid-cycle') ?? false,
            ),
            isTrue,
          );
        },
      );

      test('Violation 4: WE reverts 1→0 mid-cycle is also flagged', () {
        final changes = {
          'clk': makeClock(numEdges: 6),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1')],
          'stb': [(0, '0')],
          'we': [(0, '0'), (2, '1'), (12, '0')], // goes high then low again
          'adr': [(0, bv32(0))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0')],
          'sel': [(0, 'b0000')],
        };
        final txs = makeDecoder().decode(
          0,
          50,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(
          txs.any(
            (t) => t.errorMessage?.contains('WE changed mid-cycle') ?? false,
          ),
          isTrue,
        );
      });

      // Reserved CTI (other values) ──────────────────────────────────────────

      test('all reserved CTI values (100, 101, 110) are flagged', () {
        for (final ctiVec in ['b100', 'b101', 'b110']) {
          final bindings = {..._defaultBindings, 'cti': 'tb.CTI'};
          final changes = {
            'clk': makeClock(numEdges: 2),
            'rst': [(0, '0')],
            'cyc': [(0, '0'), (2, '1')],
            'stb': [(0, '0'), (2, '1')],
            'we': [(0, '0')],
            'adr': [(0, bv32(0)), (2, bv32(0x100))],
            'dat_o': [(0, bv32(0))],
            'dat_i': [(0, bv32(0)), (2, bv32(0xAAAA))],
            'ack': [(0, '0'), (2, '1')],
            'cti': [(0, 'b000'), (2, ctiVec)],
            'sel': [(0, 'b1111')],
          };
          final txs = makeDecoder(bindings: bindings).decode(
            0,
            30,
            makeQuery(changes),
            makeChangesQuery(changes),
          );
          expect(
            txs.any((t) => t.errorMessage?.contains('Reserved CTI') ?? false),
            isTrue,
            reason: 'CTI=$ctiVec must be flagged as reserved',
          );
        }
      });

      // Burst mid-burst CYC drop ────────────────────────────────────────────

      test('CYC drops mid-burst: partial burst parent record emitted', () {
        // Rising edges at t=5, t=15, t=25. First beat at t=5 opens an
        // incrementing burst (CTI=010). CYC drops at t=12 (observed at
        // t=15) before an EOB beat — decoder must emit the partial parent.
        final bindings = {..._defaultBindings, 'cti': 'tb.CTI'};
        final changes = {
          'clk': makeClock(numEdges: 6),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1'), (12, '0')],
          'stb': [(0, '0'), (2, '1'), (8, '0')],
          'we': [(0, '0'), (2, '1')],
          'adr': [(0, bv32(0)), (2, bv32(0x100))],
          'dat_o': [(0, bv32(0)), (2, bv32(0xDEADBEEF))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0'), (2, '1'), (8, '0')],
          'cti': [(0, 'b000'), (2, 'b010')], // Incrementing burst
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder(bindings: bindings).decode(
          0,
          50,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(
          txs.any((t) => t.fields['type'] == 'Burst'),
          isTrue,
          reason:
              'partial burst should produce a parent Burst record on CYC drop',
        );
        final parent = txs.firstWhere((t) => t.fields['type'] == 'Burst');
        expect(parent.fields['beats'], '1');
      });
    });

    // ── B3 optional signals unbound ───────────────────────────────────────────

    group('B3 optional signals unbound', () {
      const minimalBindings = {
        'clk': 'tb.CLK',
        'rst': 'tb.RST',
        'cyc': 'tb.CYC',
        'stb': 'tb.STB',
        'we': 'tb.WE',
        'adr': 'tb.ADR',
        'dat_o': 'tb.DAT_O',
        'dat_i': 'tb.DAT_I',
        'ack': 'tb.ACK',
      };

      test('write-ACK with only required signals decodes correctly', () {
        final changes = {
          'clk': makeClock(numEdges: 4),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1'), (8, '0')],
          'stb': [(0, '0'), (2, '1'), (8, '0')],
          'we': [(0, '0'), (2, '1')],
          'adr': [(0, bv32(0)), (2, bv32(0x200))],
          'dat_o': [(0, bv32(0)), (2, bv32(0xCAFEBABE))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0'), (2, '1'), (8, '0')],
        };
        final txs = makeDecoder(bindings: minimalBindings).decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.label, 'W 0x00000200 = 0xCAFEBABE');
        expect(txs.first.isError, isFalse);
        // No 'sel' field when unbound.
        expect(txs.first.fields.containsKey('sel'), isFalse);
      });

      test('read-ACK with only required signals: no false violations', () {
        final changes = {
          'clk': makeClock(numEdges: 4),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1'), (8, '0')],
          'stb': [(0, '0'), (2, '1'), (8, '0')],
          'we': [(0, '0')],
          'adr': [(0, bv32(0)), (2, bv32(0x400))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0)), (2, bv32(0x12345678))],
          'ack': [(0, '0'), (2, '1'), (8, '0')],
        };
        final txs = makeDecoder(bindings: minimalBindings).decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.label, 'R 0x00000400 → 0x12345678');
        expect(txs.where((t) => t.isError), isEmpty);
      });

      test(
        'rty signal not bound: RTY-like bus state does not trigger false violation',
        () {
          // With err/rty unbound, even if those signals were high they would
          // be invisible to the decoder (hasErr=false, hasRty=false). Verify
          // that a normal ACK cycle emits exactly one clean transaction.
          final changes = {
            'clk': makeClock(numEdges: 4),
            'rst': [(0, '0')],
            'cyc': [(0, '0'), (2, '1'), (8, '0')],
            'stb': [(0, '0'), (2, '1'), (8, '0')],
            'we': [(0, '0')],
            'adr': [(0, bv32(0)), (2, bv32(0x500))],
            'dat_o': [(0, bv32(0))],
            'dat_i': [(0, bv32(0)), (2, bv32(0xABCDABCD))],
            'ack': [(0, '0'), (2, '1'), (8, '0')],
          };
          // Deliberately omit err and rty from bindings.
          final bindings = {
            'clk': 'tb.CLK',
            'rst': 'tb.RST',
            'cyc': 'tb.CYC',
            'stb': 'tb.STB',
            'we': 'tb.WE',
            'adr': 'tb.ADR',
            'dat_o': 'tb.DAT_O',
            'dat_i': 'tb.DAT_I',
            'ack': 'tb.ACK',
            'sel': 'tb.SEL',
          };
          final txs = makeDecoder(bindings: bindings).decode(
            0,
            30,
            makeQuery(changes),
            makeChangesQuery(changes),
          );
          expect(txs, hasLength(1));
          expect(txs.first.fields['termination'], 'ACK');
          expect(txs.first.isError, isFalse);
        },
      );
    });

    // ── B4 Pipelined ──────────────────────────────────────────────────────────

    group('B4 Pipelined', () {
      Map<String, String> b4Bindings() => {
        ..._defaultBindings,
        'stall': 'tb.STALL',
      };

      Map<String, dynamic> b4Params() => {
        ..._defaultParams,
        'revision': 'b4',
      };

      test('basic pipelined read: latency captured in fields', () {
        final changes = {
          'clk': makeClock(numEdges: 6),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1'), (28, '0')],
          'stb': [(0, '0'), (2, '1'), (12, '0')],
          'we': [(0, '0')],
          'adr': [(0, bv32(0)), (2, bv32(0x200)), (12, bv32(0))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0)), (22, bv32(0xFEEDBEEF))],
          'ack': [(0, '0'), (22, '1'), (28, '0')],
          'stall': [(0, '0')],
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder(
          bindings: b4Bindings(),
          parameters: b4Params(),
        ).decode(0, 40, makeQuery(changes), makeChangesQuery(changes));
        expect(txs, hasLength(1));
        expect(txs.first.startTime, 5);
        expect(txs.first.endTime, 25);
        expect(txs.first.label, 'R 0x00000200 → 0xFEEDBEEF [Pipelined]');
        expect(txs.first.fields['cycle'], 'Pipelined');
        expect(txs.first.fields['latency'], '20');
      });

      test('B4 stall not bound: warning + classic-fallback decode', () {
        final bindings = {..._defaultBindings};
        // Note: no 'stall' binding, but revision=b4.
        final changes = {
          'clk': makeClock(numEdges: 4),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1')],
          'stb': [(0, '0'), (2, '1')],
          'we': [(0, '0'), (2, '1')],
          'adr': [(0, bv32(0)), (2, bv32(0x100))],
          'dat_o': [(0, bv32(0)), (2, bv32(0xDEADBEEF))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0'), (2, '1')],
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder(
          bindings: bindings,
          parameters: b4Params(),
        ).decode(0, 30, makeQuery(changes), makeChangesQuery(changes));
        expect(
          txs.any(
            (t) => t.errorMessage?.contains('stall` signal not bound') ?? false,
          ),
          isTrue,
          reason: 'B4 without stall binding must emit a warning transaction',
        );
        // And the fallback to classic decode produces the write as a beat.
        expect(
          txs.any((t) => t.label.startsWith('W 0x00000100')),
          isTrue,
        );
      });

      test('signal change while STB asserted and STALL high → violation', () {
        final changes = {
          'clk': makeClock(numEdges: 4),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1')],
          'stb': [(0, '0'), (2, '1')],
          'we': [(0, '0')],
          // ADR changes between t=15 (sample) and t=25 while still stalled.
          'adr': [(0, bv32(0)), (2, bv32(0x100)), (12, bv32(0x104))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0')],
          'stall': [(0, '1')], // held high throughout
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder(
          bindings: b4Bindings(),
          parameters: b4Params(),
        ).decode(0, 40, makeQuery(changes), makeChangesQuery(changes));
        expect(
          txs.any((t) => t.errorMessage?.contains('STALL high') ?? false),
          isTrue,
        );
      });

      // B4 ERR / RTY termination paths ─────────────────────────────────────

      test('B4 ERR response: isError=true with ERR termination field', () {
        // Rising edges at t=5 and t=15. Request issued at t=5 (STB & ~STALL);
        // ERR arrives at t=15 (err high from t=12).
        final changes = {
          'clk': makeClock(numEdges: 4),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1'), (18, '0')],
          'stb': [(0, '0'), (2, '1'), (8, '0')],
          'we': [(0, '0')],
          'adr': [(0, bv32(0)), (2, bv32(0x100))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0)), (12, bv32(0xBADBAD00))],
          'ack': [(0, '0')],
          'err': [(0, '0'), (12, '1'), (18, '0')],
          'stall': [(0, '0')],
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder(
          bindings: b4Bindings(),
          parameters: b4Params(),
        ).decode(0, 30, makeQuery(changes), makeChangesQuery(changes));
        expect(txs, hasLength(1));
        expect(txs.first.fields['termination'], 'ERR');
        expect(txs.first.isError, isTrue);
        expect(txs.first.fields['cycle'], 'Pipelined');
      });

      test('B4 RTY response: isError=true with RTY termination field', () {
        final changes = {
          'clk': makeClock(numEdges: 4),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1'), (18, '0')],
          'stb': [(0, '0'), (2, '1'), (8, '0')],
          'we': [(0, '0'), (2, '1')],
          'adr': [(0, bv32(0)), (2, bv32(0x200))],
          'dat_o': [(0, bv32(0)), (2, bv32(0xDEADBEEF))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0')],
          'rty': [(0, '0'), (12, '1'), (18, '0')],
          'stall': [(0, '0')],
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder(
          bindings: b4Bindings(),
          parameters: b4Params(),
        ).decode(0, 30, makeQuery(changes), makeChangesQuery(changes));
        expect(txs, hasLength(1));
        expect(txs.first.fields['termination'], 'RTY');
        expect(txs.first.isError, isTrue);
      });

      // B4 Violation 2 ──────────────────────────────────────────────────────

      test('B4 Violation 2: ACK asserted while CYC deasserted → violation', () {
        final changes = {
          'clk': makeClock(numEdges: 2),
          'rst': [(0, '0')],
          'cyc': [(0, '0')], // CYC never rises
          'stb': [(0, '0')],
          'we': [(0, '0')],
          'adr': [(0, bv32(0))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0'), (2, '1')],
          'stall': [(0, '0')],
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder(
          bindings: b4Bindings(),
          parameters: b4Params(),
        ).decode(0, 30, makeQuery(changes), makeChangesQuery(changes));
        expect(
          txs.any(
            (t) =>
                t.errorMessage?.contains(
                  'Termination asserted while CYC deasserted',
                ) ??
                false,
          ),
          isTrue,
        );
      });

      // B4 spurious termination ─────────────────────────────────────────────

      test('B4 spurious ACK with no outstanding request → violation', () {
        // CYC high, ACK fires, but no STB was issued — FIFO is empty.
        final changes = {
          'clk': makeClock(numEdges: 2),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1')],
          'stb': [(0, '0')], // no request
          'we': [(0, '0')],
          'adr': [(0, bv32(0))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0'), (2, '1')], // ACK with nothing outstanding
          'stall': [(0, '0')],
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder(
          bindings: b4Bindings(),
          parameters: b4Params(),
        ).decode(0, 30, makeQuery(changes), makeChangesQuery(changes));
        expect(
          txs.any(
            (t) =>
                t.errorMessage?.contains('no outstanding pipelined request') ??
                false,
          ),
          isTrue,
        );
      });

      // B4 CYC drops with outstanding ───────────────────────────────────────

      test('B4 CYC drops with outstanding request: violation emitted', () {
        // Request issued at t=5 (STB & ~STALL), no ACK follows.
        // CYC drops at t=12 (observed at t=15) — spec violation.
        final changes = {
          'clk': makeClock(numEdges: 6),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1'), (12, '0')],
          'stb': [(0, '0'), (2, '1'), (8, '0')],
          'we': [(0, '0')],
          'adr': [(0, bv32(0)), (2, bv32(0x100))],
          'dat_o': [(0, bv32(0))],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0')], // no ACK — request stays outstanding
          'stall': [(0, '0')],
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder(
          bindings: b4Bindings(),
          parameters: b4Params(),
        ).decode(0, 50, makeQuery(changes), makeChangesQuery(changes));
        expect(
          txs.any((t) => t.errorMessage?.contains('CYC dropped with') ?? false),
          isTrue,
        );
      });
    });

    // ── multi-width formatting ────────────────────────────────────────────────

    group('multi-width formatting', () {
      test('addr_width=16 / data_width=16: 4-nibble formatting', () {
        final changes = {
          'clk': makeClock(numEdges: 2),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1')],
          'stb': [(0, '0'), (2, '1')],
          'we': [(0, '0'), (2, '1')],
          'adr': [(0, 'b0000000000000000'), (2, 'b0000000000001000')],
          'dat_o': [
            (0, 'b0000000000000000'),
            (2, 'b0000000011111111'),
          ],
          'dat_i': [(0, 'b0000000000000000')],
          'ack': [(0, '0'), (2, '1')],
          'sel': [(0, 'b00')],
        };
        final params = {
          ..._defaultParams,
          'addr_width': 16,
          'data_width': '16',
        };
        final txs = makeDecoder(parameters: params).decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.label, 'W 0x0008 = 0x00FF');
      });

      test('X bits in dat_o produce question-mark fallback', () {
        final changes = {
          'clk': makeClock(numEdges: 2),
          'rst': [(0, '0')],
          'cyc': [(0, '0'), (2, '1')],
          'stb': [(0, '0'), (2, '1')],
          'we': [(0, '0'), (2, '1')],
          'adr': [(0, bv32(0)), (2, bv32(0x100))],
          'dat_o': [
            (0, bv32(0)),
            (2, 'b0000000000000000000000000000xxxx'),
          ],
          'dat_i': [(0, bv32(0))],
          'ack': [(0, '0'), (2, '1')],
          'sel': [(0, 'b1111')],
        };
        final txs = makeDecoder().decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs.first.fields['data'], '0x????????');
      });
    });

    // ── fixture round-trip: each generated VCD's expected JSON ────────────────

    group('fixture round-trip', () {
      // The fixtures are produced by `tool/generate_wishbone_fixtures.dart`,
      // which runs the decoder against the timeline to produce the JSON. The
      // round-trip test re-runs the decoder against the same fixtures and
      // diffs the output JSON to catch silent regressions.

      const fixtures = [
        ('wishbone_b3_classic_basic', 'b3'),
        ('wishbone_b3_burst_incr', 'b3'),
        ('wishbone_b3_burst_wrap', 'b3'),
        ('wishbone_b3_classic_violations', 'b3'),
        ('wishbone_b4_pipelined_basic', 'b4'),
        ('wishbone_b4_pipelined_stall', 'b4'),
        ('wishbone_b4_pipelined_violations', 'b4'),
      ];

      for (final (name, _) in fixtures) {
        test('$name expected JSON exists and parses', () {
          final f = File(
            'test/fixtures/protocol/wishbone/generated/'
            '$name.expected_transactions.json',
          );
          expect(f.existsSync(), isTrue, reason: 'missing fixture $name');
          final json = jsonDecode(f.readAsStringSync()) as List<dynamic>;
          expect(json, isNotEmpty);
        });
      }

      // Anchor-point assertions on key fixtures — these survive even if the
      // round-trip JSON drifts, ensuring the human-meaningful behavior is
      // protected.

      test('classic_basic: 4 transactions in canonical order', () {
        final txs = _loadExpected('wishbone_b3_classic_basic');
        expect(txs, hasLength(4));
        expect(txs[0].label, 'W 0x00000100 = 0xDEADBEEF');
        expect(txs[1].label, 'R 0x00000100 → 0x12345678');
        expect(txs[2].label, 'R 0x00000200 → 0xBADBADBA [ERR]');
        expect(txs[3].label, 'W 0x00000300 = 0xCAFEBABE [RTY]');
        expect(txs[2].isError, isTrue);
        expect(txs[3].isError, isTrue);
      });

      test('burst_incr: 4 child beats + 1 parent burst record', () {
        final txs = _loadExpected('wishbone_b3_burst_incr');
        expect(txs, hasLength(5));
        final children = txs.where((t) => t.fields['type'] != 'Burst').toList();
        final parents = txs.where((t) => t.fields['type'] == 'Burst').toList();
        expect(children, hasLength(4));
        expect(parents, hasLength(1));
        expect(parents.first.label, 'Burst-Incr 4× W 0x100..0x10C');
      });

      test(
        'burst_wrap: 4-beat-wrap addresses cycle 0x108→0x10C→0x100→0x104',
        () {
          final txs = _loadExpected('wishbone_b3_burst_wrap');
          // First burst's child beats (skip parent records).
          final wrapBeats = txs
              .where(
                (t) =>
                    t.fields['type'] != 'Burst' &&
                    (t.fields['burst_id']?.startsWith('b3-15') ?? false),
              )
              .toList();
          expect(wrapBeats.map((t) => t.fields['address']).toList(), [
            '0x00000108',
            '0x0000010C',
            '0x00000100',
            '0x00000104',
          ]);
        },
      );

      test('classic_violations: every required violation class is present', () {
        final txs = _loadExpected('wishbone_b3_classic_violations');
        final messages = txs
            .where((t) => t.isError)
            .map((t) => t.errorMessage ?? '')
            .toList();
        for (final fragment in [
          'STB asserted while CYC',
          'Termination (ACK/ERR/RTY) asserted while CYC',
          'Multiple terminations',
          'Reserved CTI',
          'BTE',
          'Misaligned address',
          'Constant-address burst',
          'WE changed mid-cycle',
          'Incrementing burst',
        ]) {
          expect(
            messages.any((m) => m.contains(fragment)),
            isTrue,
            reason: 'expected at least one violation containing "$fragment"',
          );
        }
      });

      test('b4_pipelined_basic: latency captured per request', () {
        final txs = _loadExpected('wishbone_b4_pipelined_basic');
        expect(txs, hasLength(2));
        expect(txs[0].fields['cycle'], 'Pipelined');
        expect(txs[0].fields['latency'], '10');
        expect(txs[1].fields['cycle'], 'Pipelined');
        expect(txs[1].fields['latency'], '20');
      });

      test(
        'b4_pipelined_stall: 3 outstanding requests matched in FIFO order',
        () {
          final txs = _loadExpected('wishbone_b4_pipelined_stall');
          expect(txs, hasLength(3));
          expect(txs.map((t) => t.fields['address']).toList(), [
            '0x00000100',
            '0x00000104',
            '0x00000108',
          ]);
        },
      );

      test('b4_pipelined_violations: signal-change-while-stalled detected', () {
        final txs = _loadExpected('wishbone_b4_pipelined_violations');
        expect(
          txs.any((t) => t.errorMessage?.contains('STALL high') ?? false),
          isTrue,
        );
      });
    });
  });
}

// ── fixture loader ───────────────────────────────────────────────────────────

List<DecodedTransaction> _loadExpected(String name) {
  final raw = File(
    'test/fixtures/protocol/wishbone/generated/'
    '$name.expected_transactions.json',
  ).readAsStringSync();
  final list = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
  return [
    for (final e in list)
      DecodedTransaction(
        startTime: e['startTime'] as int,
        endTime: e['endTime'] as int,
        label: e['label'] as String,
        fields: (e['fields'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, v as String),
        ),
        isError: e['isError'] as bool,
        errorMessage: e['errorMessage'] as String?,
      ),
  ];
}
