// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/services/decoders/axi4lite_decoder.dart';

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

/// Creates an [Axi4LiteDecoder] with all required signals bound.
Axi4LiteDecoder makeDecoder({
  bool withWstrb = true,
  bool withAwprot = false,
  bool withArprot = false,
  int addrWidth = 32,
  int dataWidth = 32,
}) {
  return Axi4LiteDecoder(
    DecoderConfig(
      signalBindings: {
        'aclk': 'tb.ACLK',
        'aresetn': 'tb.ARESETn',
        'awaddr': 'tb.AWADDR',
        'awvalid': 'tb.AWVALID',
        'awready': 'tb.AWREADY',
        'wdata': 'tb.WDATA',
        'wvalid': 'tb.WVALID',
        'wready': 'tb.WREADY',
        'bresp': 'tb.BRESP',
        'bvalid': 'tb.BVALID',
        'bready': 'tb.BREADY',
        'araddr': 'tb.ARADDR',
        'arvalid': 'tb.ARVALID',
        'arready': 'tb.ARREADY',
        'rdata': 'tb.RDATA',
        'rresp': 'tb.RRESP',
        'rvalid': 'tb.RVALID',
        'rready': 'tb.RREADY',
        if (withWstrb) 'wstrb': 'tb.WSTRB',
        if (withAwprot) 'awprot': 'tb.AWPROT',
        if (withArprot) 'arprot': 'tb.ARPROT',
      },
      parameters: {
        'addr_width': addrWidth,
        'data_width': dataWidth,
      },
    ),
  );
}

// ── clock helpers ─────────────────────────────────────────────────────────────

/// Returns a clock change list: [halfPeriod] ticks high, [halfPeriod] ticks
/// low, starting at [offset].  [numEdges] is the total number of transitions.
List<(int, String)> makeClock({
  int numEdges = 10,
  int halfPeriod = 5,
  int offset = 0,
}) {
  final result = <(int, String)>[];
  for (var i = 0; i < numEdges; i++) {
    result.add((offset + (i + 1) * halfPeriod, i.isEven ? '1' : '0'));
  }
  return result;
}

/// All-idle channel changes for [numEdges] clock transitions, reset released.
/// Tests overwrite the channels they exercise.
Map<String, List<(int, String)>> _idleChanges({required int numEdges}) => {
  'aclk': makeClock(numEdges: numEdges),
  'aresetn': [(0, '1')],
  'awaddr': [(0, _bits32(0))],
  'awvalid': [(0, '0')],
  'awready': [(0, '0')],
  'wdata': [(0, _bits32(0))],
  'wvalid': [(0, '0')],
  'wready': [(0, '0')],
  'wstrb': [(0, 'b0000')],
  'bresp': [(0, 'b00')],
  'bvalid': [(0, '0')],
  'bready': [(0, '0')],
  'araddr': [(0, _bits32(0))],
  'arvalid': [(0, '0')],
  'arready': [(0, '0')],
  'rdata': [(0, _bits32(0))],
  'rresp': [(0, 'b00')],
  'rvalid': [(0, '0')],
  'rready': [(0, '0')],
};

/// A 32-bit VCD vector literal for [value].
String _bits32(int value) => 'b${value.toRadixString(2).padLeft(32, '0')}';

/// A 1-bit signal high for 3 ticks either side of each rising edge in [edges].
List<(int, String)> _pulses(List<int> edges) => [
  (0, '0'),
  for (final t in edges) ...[(t - 3, '1'), (t + 3, '0')],
];

// ── fixture signal changes (derived from axi4lite_basic.vcd) ─────────────────

// Clock: 10ns period, rising edges at t=5,15,25,35,45,55,65,75,85,95
final _fixtureClk = <(int, String)>[
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
];

// ARESETn low at t=0, deasserted at t=18.
final _fixtureResetn = <(int, String)>[(0, '0'), (18, '1')];

// ── Transaction 1: Write addr=0x4, data=0xDEADBEEF, WSTRB=0xF, resp=OKAY ───
final _fixtureAwAddr = <(int, String)>[
  (0, 'b00000000000000000000000000000000'),
  (22, 'b00000000000000000000000000000100'), // 4
  (62, 'b00000000000000000000000000001100'), // 12 = 0xC
];
final _fixtureAwValid = <(int, String)>[
  (0, '0'),
  (22, '1'),
  (27, '0'),
  (62, '1'),
  (67, '0'),
];
final _fixtureAwReady = <(int, String)>[
  (0, '0'),
  (22, '1'),
  (27, '0'),
  (62, '1'),
  (67, '0'),
];
final _fixtureWData = <(int, String)>[
  (0, 'b00000000000000000000000000000000'),
  (22, 'b11011110101011011011111011101111'), // 0xDEADBEEF
  (62, 'b11001010111111101011101010111110'), // 0xCAFEBABE
];
final _fixtureWValid = <(int, String)>[
  (0, '0'),
  (22, '1'),
  (27, '0'),
  (62, '1'),
  (67, '0'),
];
final _fixtureWReady = <(int, String)>[
  (0, '0'),
  (22, '1'),
  (27, '0'),
  (62, '1'),
  (67, '0'),
];
final _fixtureWStrb = <(int, String)>[
  (0, 'b0000'),
  (22, 'b1111'),
];
final _fixtureBresp = <(int, String)>[
  (0, 'b00'), (67, 'b10'), // 2 = SLVERR for tx3
];
final _fixtureBValid = <(int, String)>[
  (0, '0'),
  (27, '1'),
  (37, '0'),
  (67, '1'),
  (77, '0'),
];
final _fixtureBReady = <(int, String)>[
  (0, '0'),
  (27, '1'),
  (37, '0'),
  (67, '1'),
  (77, '0'),
];

// ── Transaction 2: Read addr=0x8, data=0x12345678, resp=OKAY ────────────────
final _fixtureArAddr = <(int, String)>[
  (0, 'b00000000000000000000000000000000'),
  (42, 'b00000000000000000000000000001000'), // 8
  (82, 'b00000000000000000000000000010000'), // 16 = 0x10
];
final _fixtureArValid = <(int, String)>[
  (0, '0'),
  (42, '1'),
  (47, '0'),
  (82, '1'),
  (87, '0'),
];
final _fixtureArReady = <(int, String)>[
  (0, '0'),
  (42, '1'),
  (47, '0'),
  (82, '1'),
  (87, '0'),
];
final _fixtureRData = <(int, String)>[
  (0, 'b00000000000000000000000000000000'),
  (47, 'b00010010001101000101011001111000'), // 0x12345678
  (87, 'b10100101101001011010010110100101'), // 0xA5A5A5A5
];
final _fixtureRResp = <(int, String)>[
  (0, 'b00'), (87, 'b11'), // 3 = DECERR for tx4
];
final _fixtureRValid = <(int, String)>[
  (0, '0'),
  (47, '1'),
  (57, '0'),
  (87, '1'),
  (97, '0'),
];
final _fixtureRReady = <(int, String)>[
  (0, '0'),
  (47, '1'),
  (57, '0'),
  (87, '1'),
  (97, '0'),
];

Map<String, List<(int, String)>> get _fixtureChanges => {
  'aclk': _fixtureClk,
  'aresetn': _fixtureResetn,
  'awaddr': _fixtureAwAddr,
  'awvalid': _fixtureAwValid,
  'awready': _fixtureAwReady,
  'wdata': _fixtureWData,
  'wvalid': _fixtureWValid,
  'wready': _fixtureWReady,
  'wstrb': _fixtureWStrb,
  'bresp': _fixtureBresp,
  'bvalid': _fixtureBValid,
  'bready': _fixtureBReady,
  'araddr': _fixtureArAddr,
  'arvalid': _fixtureArValid,
  'arready': _fixtureArReady,
  'rdata': _fixtureRData,
  'rresp': _fixtureRResp,
  'rvalid': _fixtureRValid,
  'rready': _fixtureRReady,
};

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Axi4LiteDecoder', () {
    // ── definition ────────────────────────────────────────────────────────────

    group('definition', () {
      test('id is axi4_lite', () {
        expect(Axi4LiteDecoder.decoderDefinition.id, 'axi4_lite');
      });

      test('displayName is AXI4-Lite', () {
        expect(Axi4LiteDecoder.decoderDefinition.displayName, 'AXI4-Lite');
      });

      test('has 18 required signals covering all AXI4-Lite channels', () {
        final req = Axi4LiteDecoder.decoderDefinition.requiredSignals;
        expect(req, hasLength(18));
        final names = req.map((s) => s.name).toSet();
        for (final n in [
          'aclk',
          'aresetn',
          'awaddr',
          'awvalid',
          'awready',
          'wdata',
          'wvalid',
          'wready',
          'bresp',
          'bvalid',
          'bready',
          'araddr',
          'arvalid',
          'arready',
          'rdata',
          'rresp',
          'rvalid',
          'rready',
        ]) {
          expect(names, contains(n), reason: 'missing required signal: $n');
        }
      });

      test('has 3 optional signals: awprot, arprot, wstrb', () {
        final opt = Axi4LiteDecoder.decoderDefinition.optionalSignals;
        expect(
          opt.map((s) => s.name).toSet(),
          containsAll(['awprot', 'arprot', 'wstrb']),
        );
      });

      test('get definition returns the static decoderDefinition', () {
        final decoder = makeDecoder();
        expect(decoder.definition, same(Axi4LiteDecoder.decoderDefinition));
      });
    });

    // ── write transactions ─────────────────────────────────────────────────────

    group('write transaction', () {
      // Minimal changes map for a single write transaction.
      // Rising edge at t=5: AW + W handshake.  Rising edge at t=15: B handshake.
      Map<String, List<(int, String)>> writeChanges({
        String awaddr = 'b00000000000000000000000000000100', // 0x4
        String wdata = 'b00000000000000000000000000001010', // 0xA
        String wstrb = 'b1111',
        String bresp = 'b00',
      }) => {
        'aclk': makeClock(numEdges: 6),
        'aresetn': [(0, '1')],
        'awaddr': [(0, 'b00000000000000000000000000000000'), (2, awaddr)],
        'awvalid': [(0, '0'), (2, '1'), (8, '0')],
        'awready': [(0, '0'), (2, '1'), (8, '0')],
        'wdata': [(0, 'b00000000000000000000000000000000'), (2, wdata)],
        'wvalid': [(0, '0'), (2, '1'), (8, '0')],
        'wready': [(0, '0'), (2, '1'), (8, '0')],
        'wstrb': [(0, 'b0000'), (2, wstrb)],
        'bresp': [(0, bresp)],
        'bvalid': [(0, '0'), (8, '1'), (18, '0')],
        'bready': [(0, '0'), (8, '1'), (18, '0')],
        'araddr': [(0, 'b00000000000000000000000000000000')],
        'arvalid': [(0, '0')],
        'arready': [(0, '0')],
        'rdata': [(0, 'b00000000000000000000000000000000')],
        'rresp': [(0, 'b00')],
        'rvalid': [(0, '0')],
        'rready': [(0, '0')],
      };

      test('decodes write OKAY: correct label, times, and fields', () {
        final changes = writeChanges();
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
        expect(tx.label, 'W 0x00000004 = 0x0000000A [OKAY]');
        expect(tx.fields['type'], 'Write');
        expect(tx.fields['address'], '0x00000004');
        expect(tx.fields['data'], '0x0000000A');
        expect(tx.fields['response'], 'OKAY');
        expect(tx.fields['wstrb'], '0xF');
        expect(tx.isError, isFalse);
        expect(tx.errorMessage, isNull);
      });

      test('decodes write SLVERR: isError true and errorMessage set', () {
        final changes = writeChanges(bresp: 'b10');
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.isError, isTrue);
        expect(txs.first.fields['response'], 'SLVERR');
        expect(txs.first.errorMessage, 'Response: SLVERR');
      });

      test('decodes write DECERR: isError true and errorMessage set', () {
        final changes = writeChanges(bresp: 'b11');
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs.first.isError, isTrue);
        expect(txs.first.fields['response'], 'DECERR');
        expect(txs.first.errorMessage, 'Response: DECERR');
      });

      test('EXOKAY response flags violation in errorMessage', () {
        final changes = writeChanges(bresp: 'b01');
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs.first.isError, isTrue);
        expect(txs.first.fields['response'], 'EXOKAY');
        expect(
          txs.first.errorMessage,
          contains('EXOKAY not valid in AXI4-Lite'),
        );
      });

      test('write without wstrb bound: no wstrb field in output', () {
        final changes = writeChanges();
        final decoder = makeDecoder(withWstrb: false);
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs.first.fields, isNot(contains('wstrb')));
      });

      test(
        'W-before-AW: W handshake before AW still produces a transaction',
        () {
          // W handshake at t=5, AW handshake at t=15, B at t=25.
          final changes = {
            'aclk': makeClock(numEdges: 8),
            'aresetn': [(0, '1')],
            'awaddr': [
              (0, 'b00000000000000000000000000000000'),
              (12, 'b00000000000000000000000000000100'),
            ],
            'awvalid': [(0, '0'), (12, '1'), (18, '0')],
            'awready': [(0, '0'), (12, '1'), (18, '0')],
            'wdata': [
              (0, 'b00000000000000000000000000000000'),
              (2, 'b00000000000000000000000000000001'),
            ],
            'wvalid': [(0, '0'), (2, '1'), (8, '0')],
            'wready': [(0, '0'), (2, '1'), (8, '0')],
            'wstrb': [(0, 'b0000'), (2, 'b1111')],
            'bresp': [(0, 'b00')],
            'bvalid': [(0, '0'), (18, '1'), (28, '0')],
            'bready': [(0, '0'), (18, '1'), (28, '0')],
            'araddr': [(0, 'b00000000000000000000000000000000')],
            'arvalid': [(0, '0')],
            'arready': [(0, '0')],
            'rdata': [(0, 'b00000000000000000000000000000000')],
            'rresp': [(0, 'b00')],
            'rvalid': [(0, '0')],
            'rready': [(0, '0')],
          };
          final decoder = makeDecoder();
          final txs = decoder.decode(
            0,
            40,
            makeQuery(changes),
            makeChangesQuery(changes),
          );
          // W at t=5, AW at t=15 → transaction startTime = 15 (when AW captured
          // as writeOutstanding is set by AW handshake).
          expect(txs, hasLength(1));
          expect(txs.first.fields['type'], 'Write');
          expect(txs.first.isError, isFalse);
        },
      );
    });

    // ── read transactions ──────────────────────────────────────────────────────

    group('read transaction', () {
      Map<String, List<(int, String)>> readChanges({
        String araddr = 'b00000000000000000000000000001000', // 0x8
        String rdata = 'b00010010001101000101011001111000', // 0x12345678
        String rresp = 'b00',
      }) => {
        'aclk': makeClock(numEdges: 6),
        'aresetn': [(0, '1')],
        'awaddr': [(0, 'b00000000000000000000000000000000')],
        'awvalid': [(0, '0')],
        'awready': [(0, '0')],
        'wdata': [(0, 'b00000000000000000000000000000000')],
        'wvalid': [(0, '0')],
        'wready': [(0, '0')],
        'wstrb': [(0, 'b0000')],
        'bresp': [(0, 'b00')],
        'bvalid': [(0, '0')],
        'bready': [(0, '0')],
        'araddr': [(0, 'b00000000000000000000000000000000'), (2, araddr)],
        'arvalid': [(0, '0'), (2, '1'), (8, '0')],
        'arready': [(0, '0'), (2, '1'), (8, '0')],
        'rdata': [(0, 'b00000000000000000000000000000000'), (8, rdata)],
        'rresp': [(0, rresp)],
        'rvalid': [(0, '0'), (8, '1'), (18, '0')],
        'rready': [(0, '0'), (8, '1'), (18, '0')],
      };

      test('decodes read OKAY: correct label, times, and fields', () {
        final changes = readChanges();
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
        expect(tx.label, 'R 0x00000008 = 0x12345678 [OKAY]');
        expect(tx.fields['type'], 'Read');
        expect(tx.fields['address'], '0x00000008');
        expect(tx.fields['data'], '0x12345678');
        expect(tx.fields['response'], 'OKAY');
        expect(tx.isError, isFalse);
      });

      test('decodes read SLVERR: isError true', () {
        final changes = readChanges(rresp: 'b10');
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs.first.isError, isTrue);
        expect(txs.first.fields['response'], 'SLVERR');
        expect(txs.first.errorMessage, 'Response: SLVERR');
      });

      test('decodes read DECERR: isError true', () {
        final changes = readChanges(rresp: 'b11');
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs.first.isError, isTrue);
        expect(txs.first.fields['response'], 'DECERR');
        expect(txs.first.errorMessage, 'Response: DECERR');
      });
    });

    // ── protocol violations ────────────────────────────────────────────────────

    group('protocol violations', () {
      test(
        'orphan B response with no pending write: violation transaction',
        () {
          final changes = {
            'aclk': makeClock(numEdges: 2),
            'aresetn': [(0, '1')],
            'awaddr': [(0, 'b00000000000000000000000000000000')],
            'awvalid': [(0, '0')],
            'awready': [(0, '0')],
            'wdata': [(0, 'b00000000000000000000000000000000')],
            'wvalid': [(0, '0')],
            'wready': [(0, '0')],
            'wstrb': [(0, 'b0000')],
            'bresp': [(0, 'b00')],
            'bvalid': [(0, '0'), (2, '1')], // BVALID asserted, no prior AW/W
            'bready': [(0, '0'), (2, '1')],
            'araddr': [(0, 'b00000000000000000000000000000000')],
            'arvalid': [(0, '0')],
            'arready': [(0, '0')],
            'rdata': [(0, 'b00000000000000000000000000000000')],
            'rresp': [(0, 'b00')],
            'rvalid': [(0, '0')],
            'rready': [(0, '0')],
          };
          final decoder = makeDecoder();
          final txs = decoder.decode(
            0,
            20,
            makeQuery(changes),
            makeChangesQuery(changes),
          );
          expect(txs, hasLength(1));
          expect(txs.first.isError, isTrue);
          expect(txs.first.label, 'AXI Violation');
          expect(
            txs.first.errorMessage,
            contains('write response without pending write'),
          );
        },
      );

      test('orphan B when AW captured but W missing: violation', () {
        // AW handshake at t=5, no W handshake, B handshake at t=15.
        final changes = {
          'aclk': makeClock(numEdges: 6),
          'aresetn': [(0, '1')],
          'awaddr': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000000100'),
          ],
          'awvalid': [(0, '0'), (2, '1'), (8, '0')],
          'awready': [(0, '0'), (2, '1'), (8, '0')],
          'wdata': [(0, 'b00000000000000000000000000000000')],
          'wvalid': [(0, '0')], // W never fires
          'wready': [(0, '0')],
          'wstrb': [(0, 'b0000')],
          'bresp': [(0, 'b00')],
          'bvalid': [(0, '0'), (8, '1'), (18, '0')], // B fires without W
          'bready': [(0, '0'), (8, '1'), (18, '0')],
          'araddr': [(0, 'b00000000000000000000000000000000')],
          'arvalid': [(0, '0')],
          'arready': [(0, '0')],
          'rdata': [(0, 'b00000000000000000000000000000000')],
          'rresp': [(0, 'b00')],
          'rvalid': [(0, '0')],
          'rready': [(0, '0')],
        };
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.isError, isTrue);
        expect(txs.first.errorMessage, contains('write response without'));
      });

      test('orphan R response with no pending read: violation transaction', () {
        final changes = {
          'aclk': makeClock(numEdges: 2),
          'aresetn': [(0, '1')],
          'awaddr': [(0, 'b00000000000000000000000000000000')],
          'awvalid': [(0, '0')],
          'awready': [(0, '0')],
          'wdata': [(0, 'b00000000000000000000000000000000')],
          'wvalid': [(0, '0')],
          'wready': [(0, '0')],
          'wstrb': [(0, 'b0000')],
          'bresp': [(0, 'b00')],
          'bvalid': [(0, '0')],
          'bready': [(0, '0')],
          'araddr': [(0, 'b00000000000000000000000000000000')],
          'arvalid': [(0, '0')],
          'arready': [(0, '0')],
          'rdata': [(0, 'b00000000000000000000000000000000')],
          'rresp': [(0, 'b00')],
          'rvalid': [(0, '0'), (2, '1')], // RVALID with no prior AR
          'rready': [(0, '0'), (2, '1')],
        };
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          20,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.first.isError, isTrue);
        expect(txs.first.label, 'AXI Violation');
        expect(
          txs.first.errorMessage,
          contains('read data without pending read'),
        );
      });

      test(
        'pipelined writes: B completes the oldest AW with the oldest W, '
        'the rest are listed as unanswered',
        () {
          // Rising edges at t=5,15,...,55. AW 0x08 at 5, W 0x22222222 at 15,
          // AW 0x0C + W 0x33333333 at 25, AW 0x10 + W 0x44444444 at 35,
          // one B OKAY at 45.
          final changes = _idleChanges(numEdges: 12)
            ..['awaddr'] = [
              (0, _bits32(0)),
              (2, _bits32(0x08)),
              (22, _bits32(0x0C)),
              (32, _bits32(0x10)),
            ]
            ..['awvalid'] = _pulses([5, 25, 35])
            ..['awready'] = _pulses([5, 25, 35])
            ..['wdata'] = [
              (0, _bits32(0)),
              (12, _bits32(0x22222222)),
              (22, _bits32(0x33333333)),
              (32, _bits32(0x44444444)),
            ]
            ..['wvalid'] = _pulses([15, 25, 35])
            ..['wready'] = _pulses([15, 25, 35])
            ..['bvalid'] = _pulses([45])
            ..['bready'] = _pulses([45]);
          final txs = makeDecoder(withWstrb: false).decode(
            0,
            70,
            makeQuery(changes),
            makeChangesQuery(changes),
          );
          expect(txs.where((t) => t.isError), isEmpty);
          expect(txs.map((t) => t.label), [
            'W 0x00000008 = 0x22222222 [OKAY]',
            'W 0x0000000C = 0x33333333 [no response]',
            'W 0x00000010 = 0x44444444 [no response]',
          ]);
          expect(txs[0].startTime, 5);
          expect(txs[0].endTime, 45);
          expect(txs[1].startTime, 25);
          expect(txs[1].endTime, 55); // last rising edge
          expect(txs[2].fields['response'], 'no response');
        },
      );

      test('pipelined reads: each R completes the oldest AR', () {
        final changes = _idleChanges(numEdges: 10)
          ..['araddr'] = [
            (0, _bits32(0)),
            (2, _bits32(0x08)),
            (12, _bits32(0x0C)),
          ]
          ..['arvalid'] = _pulses([5, 15])
          ..['arready'] = _pulses([5, 15])
          ..['rdata'] = [
            (0, _bits32(0)),
            (22, _bits32(0xAAAA5555)),
            (32, _bits32(0x12345678)),
          ]
          ..['rvalid'] = _pulses([25, 35])
          ..['rready'] = _pulses([25, 35]);
        final txs = makeDecoder().decode(
          0,
          60,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs.where((t) => t.isError), isEmpty);
        expect(txs.map((t) => t.label), [
          'R 0x00000008 = 0xAAAA5555 [OKAY]',
          'R 0x0000000C = 0x12345678 [OKAY]',
        ]);
        expect(txs[0].startTime, 5);
        expect(txs[0].endTime, 25);
        expect(txs[1].startTime, 15);
        expect(txs[1].endTime, 35);
      });

      test(
        'read with no R by the end of the trace is listed as unanswered',
        () {
          final changes = _idleChanges(numEdges: 6)
            ..['araddr'] = [(0, _bits32(0)), (2, _bits32(0x20))]
            ..['arvalid'] = _pulses([5])
            ..['arready'] = _pulses([5]);
          final txs = makeDecoder().decode(
            0,
            40,
            makeQuery(changes),
            makeChangesQuery(changes),
          );
          expect(txs, hasLength(1));
          expect(txs.single.label, 'R 0x00000020 [no response]');
          expect(txs.single.isError, isFalse);
          expect(txs.single.startTime, 5);
          expect(txs.single.endTime, 25);
        },
      );

      test('W beat with no AW by the end of the trace is unanswered', () {
        final changes = _idleChanges(numEdges: 4)
          ..['wdata'] = [(0, _bits32(0)), (2, _bits32(0xCAFEF00D))]
          ..['wvalid'] = _pulses([5])
          ..['wready'] = _pulses([5]);
        final txs = makeDecoder(withWstrb: false).decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, hasLength(1));
        expect(txs.single.label, 'W 0x???????? = 0xCAFEF00D [no response]');
      });
    });

    // ── reset handling ─────────────────────────────────────────────────────────

    group('reset handling', () {
      test('edges during reset produce no transactions', () {
        final changes = {
          'aclk': makeClock(numEdges: 4),
          'aresetn': [(0, '0')], // reset held asserted throughout
          'awaddr': [(0, 'b00000000000000000000000000000000')],
          'awvalid': [(0, '0'), (2, '1')],
          'awready': [(0, '0'), (2, '1')],
          'wdata': [(0, 'b00000000000000000000000000000000'), (2, 'b00000001')],
          'wvalid': [(0, '0'), (2, '1')],
          'wready': [(0, '0'), (2, '1')],
          'wstrb': [(0, 'b1111')],
          'bresp': [(0, 'b00')],
          'bvalid': [(0, '0'), (2, '1')],
          'bready': [(0, '0'), (2, '1')],
          'araddr': [(0, 'b00000000000000000000000000000000')],
          'arvalid': [(0, '0')],
          'arready': [(0, '0')],
          'rdata': [(0, 'b00000000000000000000000000000000')],
          'rresp': [(0, 'b00')],
          'rvalid': [(0, '0')],
          'rready': [(0, '0')],
        };
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          20,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, isEmpty);
      });

      test('reset clears in-flight write; transaction resumes after reset', () {
        // AW + W at t=5, reset asserts at t=8, deasserts at t=18,
        // then a clean write at t=25 should succeed.
        final changes = {
          'aclk': makeClock(),
          'aresetn': [(0, '1'), (8, '0'), (18, '1')],
          'awaddr': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000000100'), // AW for first tx
            (22, 'b00000000000000000000000000001000'), // AW for second tx
          ],
          'awvalid': [(0, '0'), (2, '1'), (9, '0'), (22, '1'), (28, '0')],
          'awready': [(0, '0'), (2, '1'), (9, '0'), (22, '1'), (28, '0')],
          'wdata': [
            (0, 'b00000000000000000000000000000000'),
            (2, 'b00000000000000000000000000000001'),
            (22, 'b00000000000000000000000000000010'),
          ],
          'wvalid': [(0, '0'), (2, '1'), (9, '0'), (22, '1'), (28, '0')],
          'wready': [(0, '0'), (2, '1'), (9, '0'), (22, '1'), (28, '0')],
          'wstrb': [(0, 'b0000'), (2, 'b1111')],
          'bresp': [(0, 'b00')],
          'bvalid': [(0, '0'), (28, '1'), (38, '0')],
          'bready': [(0, '0'), (28, '1'), (38, '0')],
          'araddr': [(0, 'b00000000000000000000000000000000')],
          'arvalid': [(0, '0')],
          'arready': [(0, '0')],
          'rdata': [(0, 'b00000000000000000000000000000000')],
          'rresp': [(0, 'b00')],
          'rvalid': [(0, '0')],
          'rready': [(0, '0')],
        };
        final decoder = makeDecoder();
        final txs = decoder.decode(
          0,
          50,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        // First write is aborted by reset; second write completes.
        expect(txs, hasLength(1));
        expect(txs.first.startTime, 25); // second AW edge
        expect(txs.first.isError, isFalse);
      });
    });

    // ── edge cases ─────────────────────────────────────────────────────────────

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

      test('no handshakes in range returns empty list', () {
        final changes = {
          'aclk': makeClock(numEdges: 6),
          'aresetn': [(0, '1')],
          'awvalid': [(0, '0')],
          'awready': [(0, '0')],
          'wvalid': [(0, '0')],
          'wready': [(0, '0')],
          'bvalid': [(0, '0')],
          'bready': [(0, '0')],
          'arvalid': [(0, '0')],
          'arready': [(0, '0')],
          'rvalid': [(0, '0')],
          'rready': [(0, '0')],
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

      test('address and data format with addr_width=16 uses 4 hex digits', () {
        final changes = {
          'aclk': makeClock(numEdges: 6),
          'aresetn': [(0, '1')],
          'awaddr': [
            (0, 'b0000000000000000'),
            (2, 'b0000000000001000'), // 0x8 in 16 bits
          ],
          'awvalid': [(0, '0'), (2, '1'), (8, '0')],
          'awready': [(0, '0'), (2, '1'), (8, '0')],
          'wdata': [
            (0, 'b0000000000000000'),
            (2, 'b0000000011111111'), // 0xFF in 16 bits
          ],
          'wvalid': [(0, '0'), (2, '1'), (8, '0')],
          'wready': [(0, '0'), (2, '1'), (8, '0')],
          'wstrb': [(0, 'b00'), (2, 'b11')],
          'bresp': [(0, 'b00')],
          'bvalid': [(0, '0'), (8, '1'), (18, '0')],
          'bready': [(0, '0'), (8, '1'), (18, '0')],
          'araddr': [(0, 'b0000000000000000')],
          'arvalid': [(0, '0')],
          'arready': [(0, '0')],
          'rdata': [(0, 'b0000000000000000')],
          'rresp': [(0, 'b00')],
          'rvalid': [(0, '0')],
          'rready': [(0, '0')],
        };
        final decoder = makeDecoder(addrWidth: 16, dataWidth: 16);
        final txs = decoder.decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs.first.fields['address'], '0x0008');
        expect(txs.first.fields['data'], '0x00FF');
      });
    });

    // ── fixture test ───────────────────────────────────────────────────────────

    group('axi4lite_basic.vcd fixture', () {
      late List<DecodedTransaction> txs;

      setUp(() {
        final decoder = makeDecoder();
        txs = decoder.decode(
          0,
          100,
          makeQuery(_fixtureChanges),
          makeChangesQuery(_fixtureChanges),
        );
      });

      test(
        'decodes exactly 4 transactions matching expected_transactions.json',
        () {
          final jsonFile = File(
            'test/fixtures/protocol/axi4lite/generated/'
            'axi4lite_basic.expected_transactions.json',
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
            expect(
              txs[i].endTime,
              e['endTime'] as int,
              reason: 'tx[$i] endTime',
            );
            expect(txs[i].label, e['label'] as String, reason: 'tx[$i] label');
            expect(
              txs[i].isError,
              e['isError'] as bool,
              reason: 'tx[$i] isError',
            );
            if (e['errorMessage'] == null) {
              expect(
                txs[i].errorMessage,
                isNull,
                reason: 'tx[$i] errorMessage',
              );
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
        },
      );

      test('first transaction: write OKAY at 0x00000004 with DEADBEEF', () {
        expect(txs[0].startTime, 25);
        expect(txs[0].endTime, 35);
        expect(txs[0].label, 'W 0x00000004 = 0xDEADBEEF [OKAY]');
        expect(txs[0].fields['type'], 'Write');
        expect(txs[0].fields['address'], '0x00000004');
        expect(txs[0].fields['data'], '0xDEADBEEF');
        expect(txs[0].fields['response'], 'OKAY');
        expect(txs[0].fields['wstrb'], '0xF');
        expect(txs[0].isError, isFalse);
      });

      test(
        'second transaction: read OKAY at 0x00000008 returning 0x12345678',
        () {
          expect(txs[1].startTime, 45);
          expect(txs[1].endTime, 55);
          expect(txs[1].label, 'R 0x00000008 = 0x12345678 [OKAY]');
          expect(txs[1].fields['type'], 'Read');
          expect(txs[1].fields['address'], '0x00000008');
          expect(txs[1].fields['data'], '0x12345678');
          expect(txs[1].fields['response'], 'OKAY');
          expect(txs[1].isError, isFalse);
        },
      );

      test('third transaction: write SLVERR at 0x0000000C with CAFEBABE', () {
        expect(txs[2].startTime, 65);
        expect(txs[2].endTime, 75);
        expect(txs[2].label, 'W 0x0000000C = 0xCAFEBABE [SLVERR]');
        expect(txs[2].fields['response'], 'SLVERR');
        expect(txs[2].isError, isTrue);
        expect(txs[2].errorMessage, 'Response: SLVERR');
      });

      test(
        'fourth transaction: read DECERR at 0x00000010 returning 0xA5A5A5A5',
        () {
          expect(txs[3].startTime, 85);
          expect(txs[3].endTime, 95);
          expect(txs[3].label, 'R 0x00000010 = 0xA5A5A5A5 [DECERR]');
          expect(txs[3].fields['response'], 'DECERR');
          expect(txs[3].isError, isTrue);
          expect(txs[3].errorMessage, 'Response: DECERR');
        },
      );

      test('only two transactions are errors (SLVERR and DECERR)', () {
        final errorTxs = txs.where((t) => t.isError).toList();
        expect(errorTxs, hasLength(2));
      });
    });
  });
}
