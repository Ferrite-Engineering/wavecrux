// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/services/decoders/apb_decoder.dart';

// ── test helpers ──────────────────────────────────────────────────────────────

/// [SignalValueQuery] backed by per-signal change lists (last-held semantics).
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

/// [SignalChangesQuery] returning changes in `[start, end)`.
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

/// Creates an [ApbDecoder] with the required signals bound.
///
/// Optional signals (`pready`, `pslverr`, `pprot`, `pstrb`) bind only when
/// the corresponding flag is true.
ApbDecoder makeDecoder({
  bool withPready = true,
  bool withPslverr = true,
  bool withPstrb = true,
  bool withPprot = false,
  int addrWidth = 32,
  int dataWidth = 32,
}) {
  return ApbDecoder(
    DecoderConfig(
      signalBindings: {
        'pclk': 'tb.PCLK',
        'presetn': 'tb.PRESETn',
        'psel': 'tb.PSEL',
        'penable': 'tb.PENABLE',
        'pwrite': 'tb.PWRITE',
        'paddr': 'tb.PADDR',
        'pwdata': 'tb.PWDATA',
        'prdata': 'tb.PRDATA',
        if (withPready) 'pready': 'tb.PREADY',
        if (withPslverr) 'pslverr': 'tb.PSLVERR',
        if (withPstrb) 'pstrb': 'tb.PSTRB',
        if (withPprot) 'pprot': 'tb.PPROT',
      },
      parameters: {
        'addr_width': addrWidth,
        'data_width': dataWidth,
      },
    ),
  );
}

/// Returns a clock change list with [numEdges] transitions, [halfPeriod] ticks
/// high then low, starting at [offset]. Rising edges land at
/// `offset + halfPeriod, offset + 3*halfPeriod, …`.
List<(int, String)> makeClock({
  int numEdges = 6,
  int halfPeriod = 5,
  int offset = 0,
}) {
  final result = <(int, String)>[];
  for (var i = 0; i < numEdges; i++) {
    result.add((offset + (i + 1) * halfPeriod, i.isEven ? '1' : '0'));
  }
  return result;
}

// ── canonical change-set builders ─────────────────────────────────────────────

/// Builds a minimal change-set for one APB write transaction (no wait states).
///
/// SETUP edge at t=5, ACCESS+complete at t=15.
Map<String, List<(int, String)>> writeNoWaitChanges({
  String paddr = 'b00000000000000000000000000000100', // 0x4
  String pwdata = 'b00000000000000000000000000001010', // 0xA
  String pstrb = 'b1111',
  bool pslverr = false,
}) => {
  'pclk': makeClock(),
  'presetn': [(0, '1')],
  'psel': [(0, '0'), (2, '1'), (18, '0')],
  'penable': [(0, '0'), (12, '1'), (18, '0')],
  'pwrite': [(0, '0'), (2, '1'), (18, '0')],
  'paddr': [
    (0, 'b00000000000000000000000000000000'),
    (2, paddr),
    (18, 'b00000000000000000000000000000000'),
  ],
  'pwdata': [
    (0, 'b00000000000000000000000000000000'),
    (2, pwdata),
    (18, 'b00000000000000000000000000000000'),
  ],
  'prdata': [(0, 'b00000000000000000000000000000000')],
  'pready': [(0, '0'), (2, '1')],
  'pslverr': pslverr ? [(0, '0'), (12, '1'), (18, '0')] : [(0, '0')],
  'pstrb': [(0, 'b0000'), (2, pstrb), (18, 'b0000')],
  'pprot': [(0, 'b000')],
};

/// Builds a minimal change-set for one APB read transaction (no wait states).
///
/// SETUP edge at t=5, ACCESS+complete at t=15.
Map<String, List<(int, String)>> readNoWaitChanges({
  String paddr = 'b00000000000000000000000000001000', // 0x8
  String prdata = 'b00010010001101000101011001111000', // 0x12345678
  bool pslverr = false,
}) => {
  'pclk': makeClock(),
  'presetn': [(0, '1')],
  'psel': [(0, '0'), (2, '1'), (18, '0')],
  'penable': [(0, '0'), (12, '1'), (18, '0')],
  'pwrite': [(0, '0')],
  'paddr': [
    (0, 'b00000000000000000000000000000000'),
    (2, paddr),
    (18, 'b00000000000000000000000000000000'),
  ],
  'pwdata': [(0, 'b00000000000000000000000000000000')],
  'prdata': [
    (0, 'b00000000000000000000000000000000'),
    (2, prdata),
    (18, 'b00000000000000000000000000000000'),
  ],
  'pready': [(0, '0'), (2, '1')],
  'pslverr': pslverr ? [(0, '0'), (12, '1'), (18, '0')] : [(0, '0')],
  'pstrb': [(0, 'b0000')],
  'pprot': [(0, 'b000')],
};

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('ApbDecoder', () {
    // ── definition ────────────────────────────────────────────────────────────

    group('definition', () {
      test('id is apb', () {
        expect(ApbDecoder.decoderDefinition.id, 'apb');
      });

      test('displayName is APB', () {
        expect(ApbDecoder.decoderDefinition.displayName, 'APB');
      });

      test('has 8 required signals covering the APB pin set', () {
        final req = ApbDecoder.decoderDefinition.requiredSignals;
        expect(req, hasLength(8));
        final names = req.map((s) => s.name).toSet();
        for (final n in [
          'pclk',
          'presetn',
          'psel',
          'penable',
          'pwrite',
          'paddr',
          'pwdata',
          'prdata',
        ]) {
          expect(names, contains(n), reason: 'missing required signal: $n');
        }
      });

      test('has 4 optional signals: pready, pslverr, pprot, pstrb', () {
        final opt = ApbDecoder.decoderDefinition.optionalSignals;
        expect(
          opt.map((s) => s.name).toSet(),
          containsAll(['pready', 'pslverr', 'pprot', 'pstrb']),
        );
      });

      test('exposes addr_width and data_width parameters', () {
        final params = ApbDecoder.decoderDefinition.parameters;
        final names = params.map((p) => p.name).toSet();
        expect(names, containsAll(['addr_width', 'data_width']));
        for (final p in params) {
          expect(p.defaultValue, 32);
        }
      });

      test('get definition returns the static decoderDefinition', () {
        final decoder = makeDecoder();
        expect(decoder.definition, same(ApbDecoder.decoderDefinition));
      });
    });

    // ── write transactions ────────────────────────────────────────────────────

    group('write transaction', () {
      test('decodes basic write OKAY: correct label, times, and fields', () {
        final changes = writeNoWaitChanges();
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        final tx = txs.first;
        expect(tx.startTime, 5);
        expect(tx.endTime, 15);
        expect(tx.label, 'W 0x00000004 = 0x0000000A');
        expect(tx.fields['type'], 'Write');
        expect(tx.fields['address'], '0x00000004');
        expect(tx.fields['data'], '0x0000000A');
        expect(tx.fields['response'], 'OKAY');
        expect(tx.fields['pstrb'], '0xF');
        expect(tx.isError, isFalse);
        expect(tx.errorMessage, isNull);
      });

      test('write with PSLVERR sets isError, label suffix, and response', () {
        final changes = writeNoWaitChanges(pslverr: true);
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        final tx = txs.first;
        expect(tx.label, 'W 0x00000004 = 0x0000000A [SLVERR]');
        expect(tx.fields['response'], 'SLVERR');
        expect(tx.isError, isTrue);
        expect(tx.errorMessage, 'Slave error (PSLVERR)');
      });

      test('write with PSTRB unbound: pstrb field omitted from output', () {
        final changes = writeNoWaitChanges();
        final decoder = makeDecoder(withPstrb: false);
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.fields, isNot(contains('pstrb')));
      });

      test('write with PSTRB=0x3 captures partial byte enables', () {
        final changes = writeNoWaitChanges(pstrb: 'b0011');
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs.first.fields['pstrb'], '0x3');
      });

      test('write with one wait state extends endTime to PREADY edge', () {
        // SETUP at t=5. ACCESS at t=15 with PREADY=0 (wait). PREADY=1 at t=22.
        // Complete at t=25.
        final changes = {
          'pclk': makeClock(numEdges: 8),
          'presetn': [(0, '1')],
          'psel': [(0, '0'), (2, '1'), (28, '0')],
          'penable': [(0, '0'), (12, '1'), (28, '0')],
          'pwrite': [(0, '0'), (2, '1'), (28, '0')],
          'paddr': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000000100'),
          ],
          'pwdata': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000001010'),
          ],
          'prdata': [(0, 'b00000000000000000000000000000000')],
          'pready': [(0, '0'), (2, '1'), (12, '0'), (22, '1')],
          'pslverr': [(0, '0')],
          'pstrb': [(0, 'b0000'), (2, 'b1111')],
          'pprot': [(0, 'b000')],
        };
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          40,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        final tx = txs.first;
        expect(tx.startTime, 5);
        expect(tx.endTime, 25);
        expect(tx.fields['type'], 'Write');
        expect(tx.isError, isFalse);
      });

      test('write with two wait states completes after both', () {
        // SETUP=5; ACCESS@15 wait; ACCESS@25 wait; complete@35.
        final changes = {
          'pclk': makeClock(numEdges: 10),
          'presetn': [(0, '1')],
          'psel': [(0, '0'), (2, '1'), (38, '0')],
          'penable': [(0, '0'), (12, '1'), (38, '0')],
          'pwrite': [(0, '0'), (2, '1'), (38, '0')],
          'paddr': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000000100'),
          ],
          'pwdata': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000001010'),
          ],
          'prdata': [(0, 'b00000000000000000000000000000000')],
          'pready': [(0, '0'), (2, '1'), (12, '0'), (32, '1')],
          'pslverr': [(0, '0')],
          'pstrb': [(0, 'b0000'), (2, 'b1111')],
          'pprot': [(0, 'b000')],
        };
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          50,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.startTime, 5);
        expect(txs.first.endTime, 35);
      });
    });

    // ── read transactions ─────────────────────────────────────────────────────

    group('read transaction', () {
      test('decodes basic read OKAY: correct label, times, and fields', () {
        final changes = readNoWaitChanges();
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        final tx = txs.first;
        expect(tx.startTime, 5);
        expect(tx.endTime, 15);
        expect(tx.label, 'R 0x00000008 → 0x12345678');
        expect(tx.fields['type'], 'Read');
        expect(tx.fields['address'], '0x00000008');
        expect(tx.fields['data'], '0x12345678');
        expect(tx.fields['response'], 'OKAY');
        expect(tx.fields, isNot(contains('pstrb')));
        expect(tx.isError, isFalse);
        expect(tx.errorMessage, isNull);
      });

      test('read with PSLVERR sets isError, label suffix, and response', () {
        final changes = readNoWaitChanges(pslverr: true);
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        final tx = txs.first;
        expect(tx.label, 'R 0x00000008 → 0x12345678 [SLVERR]');
        expect(tx.fields['response'], 'SLVERR');
        expect(tx.isError, isTrue);
        expect(tx.errorMessage, 'Slave error (PSLVERR)');
      });

      test('read with one wait state extends endTime to PREADY edge', () {
        final changes = {
          'pclk': makeClock(numEdges: 8),
          'presetn': [(0, '1')],
          'psel': [(0, '0'), (2, '1'), (28, '0')],
          'penable': [(0, '0'), (12, '1'), (28, '0')],
          'pwrite': [(0, '0')],
          'paddr': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000001000'),
          ],
          'pwdata': [(0, 'b00000000000000000000000000000000')],
          'prdata': [
            (0, 'b00000000000000000000000000000000'),
            (22, 'b00010010001101000101011001111000'),
          ],
          'pready': [(0, '0'), (2, '1'), (12, '0'), (22, '1')],
          'pslverr': [(0, '0')],
          'pstrb': [(0, 'b0000')],
          'pprot': [(0, 'b000')],
        };
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          40,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.startTime, 5);
        expect(txs.first.endTime, 25);
        expect(txs.first.fields['data'], '0x12345678');
      });
    });

    // ── back-to-back transactions ─────────────────────────────────────────────

    group('back-to-back transactions', () {
      test('two writes back-to-back produce two transactions', () {
        // tx1: SETUP=5, complete=15.  tx2: SETUP=25, complete=35.
        final changes = {
          'pclk': makeClock(numEdges: 8),
          'presetn': [(0, '1')],
          'psel': [
            (0, '0'),
            (2, '1'),
            (18, '0'),
            (22, '1'),
            (38, '0'),
          ],
          'penable': [
            (0, '0'),
            (12, '1'),
            (18, '0'),
            (32, '1'),
            (38, '0'),
          ],
          'pwrite': [(0, '0'), (2, '1'), (38, '0')],
          'paddr': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000000100'),
            (22, 'b00000000000000000000000000001000'),
          ],
          'pwdata': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000000001'),
            (22, 'b00000000000000000000000000000010'),
          ],
          'prdata': [(0, 'b00000000000000000000000000000000')],
          'pready': [(0, '0'), (2, '1')],
          'pslverr': [(0, '0')],
          'pstrb': [(0, 'b0000'), (2, 'b1111')],
          'pprot': [(0, 'b000')],
        };
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          50,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(2));
        expect(txs[0].startTime, 5);
        expect(txs[0].endTime, 15);
        expect(txs[0].fields['address'], '0x00000004');
        expect(txs[0].fields['data'], '0x00000001');
        expect(txs[1].startTime, 25);
        expect(txs[1].endTime, 35);
        expect(txs[1].fields['address'], '0x00000008');
        expect(txs[1].fields['data'], '0x00000002');
      });

      test('mixed write then read produces two transactions', () {
        final changes = {
          'pclk': makeClock(numEdges: 8),
          'presetn': [(0, '1')],
          'psel': [
            (0, '0'),
            (2, '1'),
            (18, '0'),
            (22, '1'),
            (38, '0'),
          ],
          'penable': [
            (0, '0'),
            (12, '1'),
            (18, '0'),
            (32, '1'),
            (38, '0'),
          ],
          'pwrite': [(0, '0'), (2, '1'), (22, '0')],
          'paddr': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000000100'),
            (22, 'b00000000000000000000000000001000'),
          ],
          'pwdata': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000000001'),
          ],
          'prdata': [
            (0, 'b00000000000000000000000000000000'),
            (22, 'b00010010001101000101011001111000'),
          ],
          'pready': [(0, '0'), (2, '1')],
          'pslverr': [(0, '0')],
          'pstrb': [(0, 'b0000'), (2, 'b1111')],
          'pprot': [(0, 'b000')],
        };
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          50,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(2));
        expect(txs[0].fields['type'], 'Write');
        expect(txs[1].fields['type'], 'Read');
        expect(txs[1].fields['data'], '0x12345678');
      });
    });

    // ── PPROT ─────────────────────────────────────────────────────────────────

    group('PPROT', () {
      test('captures PPROT field when bound', () {
        final changes = writeNoWaitChanges();
        // Override pprot=2 (privileged data access).
        changes['pprot'] = [(0, 'b000'), (2, 'b010')];
        final decoder = makeDecoder(withPprot: true);
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs.first.fields['pprot'], '0x2');
      });

      test('omits pprot field when unbound', () {
        final changes = writeNoWaitChanges();
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs.first.fields, isNot(contains('pprot')));
      });
    });

    // ── protocol violations ──────────────────────────────────────────────────

    group('protocol violations', () {
      test('PENABLE asserted while PSEL=0: violation transaction', () {
        // PENABLE pulses high across edge 5 only; deasserts before edge 15.
        final changes = {
          'pclk': makeClock(numEdges: 4),
          'presetn': [(0, '1')],
          'psel': [(0, '0')],
          'penable': [(0, '0'), (2, '1'), (8, '0')], // PENABLE without PSEL
          'pwrite': [(0, '0')],
          'paddr': [(0, 'b00000000000000000000000000000000')],
          'pwdata': [(0, 'b00000000000000000000000000000000')],
          'prdata': [(0, 'b00000000000000000000000000000000')],
          'pready': [(0, '1')],
          'pslverr': [(0, '0')],
          'pstrb': [(0, 'b0000')],
          'pprot': [(0, 'b000')],
        };
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          20,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.label, 'APB Violation');
        expect(txs.first.startTime, 5);
        expect(txs.first.endTime, 5);
        expect(txs.first.isError, isTrue);
        expect(
          txs.first.errorMessage,
          contains('PENABLE asserted while PSEL is low'),
        );
      });

      test('persistent PENABLE without PSEL emits one violation per edge', () {
        // PENABLE held high across two rising edges with PSEL=0 produces two
        // violations — the decoder reports the protocol error each cycle.
        final changes = {
          'pclk': makeClock(numEdges: 4),
          'presetn': [(0, '1')],
          'psel': [(0, '0')],
          'penable': [(0, '0'), (2, '1')],
          'pwrite': [(0, '0')],
          'paddr': [(0, 'b00000000000000000000000000000000')],
          'pwdata': [(0, 'b00000000000000000000000000000000')],
          'prdata': [(0, 'b00000000000000000000000000000000')],
          'pready': [(0, '1')],
          'pslverr': [(0, '0')],
          'pstrb': [(0, 'b0000')],
          'pprot': [(0, 'b000')],
        };
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          20,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(2));
        for (final tx in txs) {
          expect(tx.isError, isTrue);
          expect(tx.label, 'APB Violation');
        }
      });

      test('PSEL deasserted during ACCESS wait: violation transaction', () {
        // SETUP=5, ACCESS@15 wait, PSEL=0 at t=18, edge@25 → violation.
        final changes = {
          'pclk': makeClock(numEdges: 8),
          'presetn': [(0, '1')],
          'psel': [(0, '0'), (2, '1'), (18, '0')],
          'penable': [(0, '0'), (12, '1'), (18, '0')],
          'pwrite': [(0, '0'), (2, '1'), (18, '0')],
          'paddr': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000000100'),
          ],
          'pwdata': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000001010'),
          ],
          'prdata': [(0, 'b00000000000000000000000000000000')],
          'pready': [(0, '0')], // never ready → wait state
          'pslverr': [(0, '0')],
          'pstrb': [(0, 'b0000'), (2, 'b1111')],
          'pprot': [(0, 'b000')],
        };
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          40,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.isError, isTrue);
        expect(
          txs.first.errorMessage,
          contains('PSEL deasserted during ACCESS phase'),
        );
        expect(txs.first.startTime, 5); // start of aborted transfer
      });

      test('PADDR change during ACCESS flags bus instability', () {
        // SETUP at 5 captures PADDR=0x4. PADDR changes to 0x8 at t=12.
        // ACCESS at t=15 sees PADDR=0x8 → unstable.
        final changes = {
          'pclk': makeClock(numEdges: 8),
          'presetn': [(0, '1')],
          'psel': [(0, '0'), (2, '1'), (28, '0')],
          'penable': [(0, '0'), (12, '1'), (28, '0')],
          'pwrite': [(0, '0'), (2, '1'), (28, '0')],
          'paddr': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000000100'),
            (12, 'b00000000000000000000000000001000'), // changes mid-flight
          ],
          'pwdata': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000001010'),
          ],
          'prdata': [(0, 'b00000000000000000000000000000000')],
          'pready': [(0, '0'), (2, '1')],
          'pslverr': [(0, '0')],
          'pstrb': [(0, 'b0000'), (2, 'b1111')],
          'pprot': [(0, 'b000')],
        };
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          40,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.isError, isTrue);
        expect(
          txs.first.errorMessage,
          contains('PADDR/PWRITE changed during ACCESS phase'),
        );
        expect(txs.first.fields['type'], 'Write');
      });

      test('PWRITE change during ACCESS flags bus instability', () {
        final changes = {
          'pclk': makeClock(numEdges: 8),
          'presetn': [(0, '1')],
          'psel': [(0, '0'), (2, '1'), (28, '0')],
          'penable': [(0, '0'), (12, '1'), (28, '0')],
          'pwrite': [
            (0, '0'),
            (2, '1'),
            (12, '0'), // flips mid-flight
            (28, '0'),
          ],
          'paddr': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000000100'),
          ],
          'pwdata': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000001010'),
          ],
          'prdata': [(0, 'b00000000000000000000000000000000')],
          'pready': [(0, '0'), (2, '1')],
          'pslverr': [(0, '0')],
          'pstrb': [(0, 'b0000'), (2, 'b1111')],
          'pprot': [(0, 'b000')],
        };
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          40,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.isError, isTrue);
        expect(
          txs.first.errorMessage,
          contains('PADDR/PWRITE changed during ACCESS phase'),
        );
      });
    });

    // ── reset handling ────────────────────────────────────────────────────────

    group('reset handling', () {
      test('edges held in reset produce no transactions', () {
        final changes = {
          'pclk': makeClock(numEdges: 4),
          'presetn': [(0, '0')], // held in reset
          'psel': [(0, '0'), (2, '1')],
          'penable': [(0, '0'), (12, '1')],
          'pwrite': [(0, '0'), (2, '1')],
          'paddr': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000000100'),
          ],
          'pwdata': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000000001'),
          ],
          'prdata': [(0, 'b00000000000000000000000000000000')],
          'pready': [(0, '1')],
          'pslverr': [(0, '0')],
          'pstrb': [(0, 'b1111')],
          'pprot': [(0, 'b000')],
        };
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, isEmpty);
      });

      test('reset mid-transaction clears state; later transfer succeeds', () {
        // SETUP@5, reset asserts before ACCESS@15.  PSEL drops, then a clean
        // transfer at 25.  Only the second transfer should appear.
        final changes = {
          'pclk': makeClock(numEdges: 8),
          'presetn': [(0, '1'), (8, '0'), (18, '1')],
          'psel': [(0, '0'), (2, '1'), (8, '0'), (22, '1'), (38, '0')],
          'penable': [(0, '0'), (32, '1'), (38, '0')],
          'pwrite': [(0, '0'), (2, '1'), (38, '0')],
          'paddr': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000000100'),
            (22, 'b00000000000000000000000000001000'),
          ],
          'pwdata': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000000001'),
            (22, 'b00000000000000000000000000000010'),
          ],
          'prdata': [(0, 'b00000000000000000000000000000000')],
          'pready': [(0, '0'), (2, '1')],
          'pslverr': [(0, '0')],
          'pstrb': [(0, 'b0000'), (2, 'b1111')],
          'pprot': [(0, 'b000')],
        };
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          50,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.startTime, 25);
        expect(txs.first.fields['address'], '0x00000008');
        expect(txs.first.fields['data'], '0x00000002');
        expect(txs.first.isError, isFalse);
      });
    });

    // ── edge cases ────────────────────────────────────────────────────────────

    group('edge cases', () {
      test('empty clock changes returns empty list', () {
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          100,
          makeQuery({}),
          makeChangesQuery({}),
        );
        expect(txs, isEmpty);
      });

      test('PREADY unbound: slave treated as always-ready', () {
        // No pready binding — every ACCESS edge completes immediately.
        final changes = writeNoWaitChanges();
        // Strip pready data; binding is also dropped via withPready: false.
        final decoder = makeDecoder(withPready: false);
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.startTime, 5);
        expect(txs.first.endTime, 15);
        expect(txs.first.fields['type'], 'Write');
      });

      test('addr_width=16 / data_width=16 produces 4-nibble formatting', () {
        final changes = {
          'pclk': makeClock(),
          'presetn': [(0, '1')],
          'psel': [(0, '0'), (2, '1'), (18, '0')],
          'penable': [(0, '0'), (12, '1'), (18, '0')],
          'pwrite': [(0, '0'), (2, '1'), (18, '0')],
          'paddr': [
            (0, 'b0000000000000000'),
            (2, 'b0000000000001000'), // 0x0008 in 16 bits
          ],
          'pwdata': [
            (0, 'b0000000000000000'),
            (2, 'b0000000011111111'), // 0x00FF in 16 bits
          ],
          'prdata': [(0, 'b0000000000000000')],
          'pready': [(0, '1')],
          'pslverr': [(0, '0')],
          'pstrb': [(0, 'b00'), (2, 'b11')],
          'pprot': [(0, 'b000')],
        };
        final decoder = makeDecoder(addrWidth: 16, dataWidth: 16);
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.fields['address'], '0x0008');
        expect(txs.first.fields['data'], '0x00FF');
        expect(txs.first.label, 'W 0x0008 = 0x00FF');
      });

      test('addr_width=10 produces 3-nibble (rounded up) formatting', () {
        final changes = {
          'pclk': makeClock(),
          'presetn': [(0, '1')],
          'psel': [(0, '0'), (2, '1'), (18, '0')],
          'penable': [(0, '0'), (12, '1'), (18, '0')],
          'pwrite': [(0, '0'), (2, '1'), (18, '0')],
          'paddr': [
            (0, 'b0000000000'),
            (2, 'b0000010101'), // 0x015 in 10 bits
          ],
          'pwdata': [(0, 'b00000000'), (2, 'b00000001')],
          'prdata': [(0, 'b00000000')],
          'pready': [(0, '1')],
          'pslverr': [(0, '0')],
          'pstrb': [(0, 'b0')],
          'pprot': [(0, 'b000')],
        };
        final decoder = makeDecoder(addrWidth: 10, dataWidth: 8);
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs.first.fields['address'], '0x015');
        expect(txs.first.fields['data'], '0x01');
      });

      test('PADDR with X bits formats as 0x????????', () {
        final changes = writeNoWaitChanges();
        // Override paddr to contain x bits.
        changes['paddr'] = [
          (0, 'b00000000000000000000000000000000'),
          (2, 'b000000000000000000000000000xxxxx'),
        ];
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.fields['address'], '0x????????');
      });

      test('PWDATA with Z bits formats as 0x????????', () {
        final changes = writeNoWaitChanges();
        changes['pwdata'] = [
          (0, 'b00000000000000000000000000000000'),
          (2, 'b0000000000000000000000000000zzzz'),
        ];
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs.first.fields['data'], '0x????????');
      });

      test('handshakes outside the requested time range are excluded', () {
        // tx at SETUP=5/complete=15.  Decode only [20, 40) — no clock rising
        // edges intersect the in-flight transfer; nothing emitted.
        final changes = writeNoWaitChanges();
        final decoder = makeDecoder();
        final txs = decoder.decode(
          20,
          40,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, isEmpty);
      });
    });

    // ── fixture test ──────────────────────────────────────────────────────────

    group('apb_basic.vcd fixture', () {
      // Hand-translated change lists from
      // test/fixtures/protocol/apb/generated/apb_basic.vcd.  Times match the VCD body
      // exactly (rising edges at 5,15,25,35,45,55,65,75,85,95).
      Map<String, List<(int, String)>> fixtureChanges() => {
        'pclk': [
          (5, '1'),
          (10, '0'),
          (15, '1'),
          (20, '0'),
          (25, '1'),
          (30, '0'),
          (35, '1'),
          (40, '0'),
          (45, '1'),
          (50, '0'),
          (55, '1'),
          (60, '0'),
          (65, '1'),
          (70, '0'),
          (75, '1'),
          (80, '0'),
          (85, '1'),
          (90, '0'),
          (95, '1'),
          (100, '0'),
        ],
        'presetn': [(0, '0'), (1, '1')],
        'psel': [
          (0, '0'),
          (2, '1'),
          (18, '0'),
          (22, '1'),
          (38, '0'),
          (42, '1'),
          (68, '0'),
          (72, '1'),
          (88, '0'),
        ],
        'penable': [
          (0, '0'),
          (12, '1'),
          (18, '0'),
          (32, '1'),
          (38, '0'),
          (52, '1'),
          (68, '0'),
          (82, '1'),
          (88, '0'),
        ],
        'pwrite': [
          (0, '0'),
          (2, '1'),
          (18, '0'),
          (42, '1'),
          (68, '0'),
        ],
        'paddr': [
          (0, 'b00000000000000000000000000000000'),
          (2, 'b00000000000000000000000000000100'),
          (18, 'b00000000000000000000000000000000'),
          (22, 'b00000000000000000000000000001000'),
          (38, 'b00000000000000000000000000000000'),
          (42, 'b00000000000000000000000000001100'),
          (68, 'b00000000000000000000000000000000'),
          (72, 'b00000000000000000000000000010000'),
          (88, 'b00000000000000000000000000000000'),
        ],
        'pwdata': [
          (0, 'b00000000000000000000000000000000'),
          (2, 'b11011110101011011011111011101111'), // 0xDEADBEEF
          (18, 'b00000000000000000000000000000000'),
          (42, 'b11001010111111101011101010111110'), // 0xCAFEBABE
          (68, 'b00000000000000000000000000000000'),
        ],
        'prdata': [
          (0, 'b00000000000000000000000000000000'),
          (22, 'b00010010001101000101011001111000'), // 0x12345678
          (38, 'b00000000000000000000000000000000'),
          (72, 'b10100101101001011010010110100101'), // 0xA5A5A5A5
          (88, 'b00000000000000000000000000000000'),
        ],
        'pready': [
          (0, '0'),
          (2, '1'),
          (42, '0'),
          (62, '1'),
        ],
        'pslverr': [(0, '0'), (82, '1'), (88, '0')],
        'pstrb': [
          (0, 'b0000'),
          (2, 'b1111'),
          (18, 'b0000'),
          (42, 'b1111'),
          (68, 'b0000'),
        ],
        'pprot': [(0, 'b000')],
      };

      late List<DecodedTransaction> txs;

      setUp(() {
        // Bind pprot too so the fixture exercises the optional field path.
        final decoder = makeDecoder(withPprot: true);
        final changes = fixtureChanges();
        txs = decoder.decode(
          0,
          110,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
      });

      test('decodes exactly 4 transactions matching expected JSON', () {
        final jsonFile = File(
          'test/fixtures/protocol/apb/generated/apb_basic.expected_transactions.json',
        );
        final expected =
            (jsonDecode(jsonFile.readAsStringSync()) as List<dynamic>)
                .cast<Map<String, dynamic>>();

        expect(txs, hasLength(expected.length));

        for (var i = 0; i < txs.length; i++) {
          final e = expected[i];
          expect(
            txs[i].startTime,
            e['startTime'] as int,
            reason: 'tx[$i] startTime',
          );
          expect(txs[i].endTime, e['endTime'] as int, reason: 'tx[$i] endTime');
          expect(txs[i].label, e['label'] as String, reason: 'tx[$i] label');
          expect(
            txs[i].isError,
            e['isError'] as bool,
            reason: 'tx[$i] isError',
          );
          if (e['errorMessage'] == null) {
            expect(txs[i].errorMessage, isNull, reason: 'tx[$i] errorMessage');
          } else {
            expect(
              txs[i].errorMessage,
              e['errorMessage'] as String,
              reason: 'tx[$i] errorMessage',
            );
          }
          final expFields = (e['fields'] as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, v as String),
          );
          expect(txs[i].fields, expFields, reason: 'tx[$i] fields');
        }
      });

      test('first transaction: write OKAY at 0x4 with 0xDEADBEEF', () {
        expect(txs[0].startTime, 5);
        expect(txs[0].endTime, 15);
        expect(txs[0].label, 'W 0x00000004 = 0xDEADBEEF');
        expect(txs[0].fields['type'], 'Write');
        expect(txs[0].fields['pstrb'], '0xF');
        expect(txs[0].isError, isFalse);
      });

      test('second transaction: read OKAY at 0x8 returning 0x12345678', () {
        expect(txs[1].startTime, 25);
        expect(txs[1].endTime, 35);
        expect(txs[1].label, 'R 0x00000008 → 0x12345678');
        expect(txs[1].fields['type'], 'Read');
        expect(txs[1].isError, isFalse);
      });

      test('third transaction: write 0xCAFEBABE with one wait state', () {
        expect(txs[2].startTime, 45);
        expect(txs[2].endTime, 65); // wait state extends end by one cycle
        expect(txs[2].label, 'W 0x0000000C = 0xCAFEBABE');
        expect(txs[2].isError, isFalse);
      });

      test('fourth transaction: read with PSLVERR at 0x10', () {
        expect(txs[3].startTime, 75);
        expect(txs[3].endTime, 85);
        expect(txs[3].label, 'R 0x00000010 → 0xA5A5A5A5 [SLVERR]');
        expect(txs[3].fields['response'], 'SLVERR');
        expect(txs[3].isError, isTrue);
        expect(txs[3].errorMessage, 'Slave error (PSLVERR)');
      });

      test('exactly one transaction is flagged as error (the SLVERR read)', () {
        final errorTxs = txs.where((t) => t.isError).toList();
        expect(errorTxs, hasLength(1));
        expect(errorTxs.first.fields['type'], 'Read');
      });
    });
  });
}
