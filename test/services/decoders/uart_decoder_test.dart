// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/services/decoders/uart_decoder.dart';

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
SignalChangesQuery makeChangesQuery(Map<String, List<(int, String)>> changes) {
  return (signal, start, end) {
    final list = changes[signal] ?? [];
    return [
      for (final e in list)
        if (e.$1 >= start && e.$1 < end) e,
    ];
  };
}

/// Creates a [UartDecoder] with the given parameters.
UartDecoder makeDecoder({
  String baudRate = '1000000',
  int dataBits = 8,
  String parity = 'none',
  String stopBits = '1',
  String bitOrder = 'lsb',
  int groupGapBits = 10,
  bool withTx = true,
  bool withRx = false,
}) {
  return UartDecoder(
    DecoderConfig(
      signalBindings: {
        if (withTx) 'tx': 'tb.tx',
        if (withRx) 'rx': 'tb.rx',
      },
      parameters: {
        'baud_rate': int.parse(baudRate),
        'data_bits': dataBits,
        'parity': parity,
        'stop_bits': stopBits,
        'bit_order': bitOrder,
        'group_gap_bits': groupGapBits,
      },
    ),
  );
}

// ── signal builders ───────────────────────────────────────────────────────────

/// Builds VCD change list for one UART frame starting at [startTime].
///
/// [bitPeriod] ticks per bit; idle level is HIGH.  Returns to idle after the
/// last stop bit automatically (only required when stop bit is forced low).
List<(int, String)> buildUartFrame(
  int byteVal, {
  int startTime = 0,
  int bitPeriod = 1000,
  int dataBits = 8,
  bool lsbFirst = true,
  String parity = 'none',
  int stopBitsCount = 1,
  bool forceFramingError = false,
}) {
  // Build the sequence of logic values to drive, one per bit period.
  final driveValues = <int>[0]; // start bit

  var parityCount = 0;
  for (var i = 0; i < dataBits; i++) {
    final bit = lsbFirst
        ? (byteVal >> i) & 1
        : (byteVal >> (dataBits - 1 - i)) & 1;
    driveValues.add(bit);
    parityCount += bit;
  }

  if (parity != 'none') {
    final parityBit = parity == 'even'
        ? parityCount % 2
        : 1 - (parityCount % 2);
    driveValues.add(parityBit);
  }

  for (var s = 0; s < stopBitsCount; s++) {
    driveValues.add(forceFramingError && s == stopBitsCount - 1 ? 0 : 1);
  }

  // Convert to changes (only record transitions).
  final changes = <(int, String)>[];
  var prev = '1'; // idle = high

  for (var i = 0; i < driveValues.length; i++) {
    final t = startTime + i * bitPeriod;
    final v = driveValues[i] == 1 ? '1' : '0';
    if (v != prev) {
      changes.add((t, v));
      prev = v;
    }
  }

  // Return to idle if stop bit was forced low.
  if (forceFramingError && prev != '1') {
    final endT = startTime + (driveValues.length + 1) * bitPeriod;
    changes.add((endT, '1'));
  }

  return changes;
}

/// Builds frames for a sequence of [bytes] back-to-back (no inter-frame gap).
List<(int, String)> buildUartFrames(
  List<int> bytes, {
  int startTime = 0,
  int bitPeriod = 1000,
  int dataBits = 8,
  bool lsbFirst = true,
  String parity = 'none',
  int stopBitsCount = 1,
}) {
  final parityBits = parity != 'none' ? 1 : 0;
  final bitsPerFrame = 1 + dataBits + parityBits + stopBitsCount;
  final changes = <(int, String)>[];

  for (var i = 0; i < bytes.length; i++) {
    final base = startTime + i * bitsPerFrame * bitPeriod;
    changes.addAll(
      buildUartFrame(
        bytes[i],
        startTime: base,
        bitPeriod: bitPeriod,
        dataBits: dataBits,
        lsbFirst: lsbFirst,
        parity: parity,
        stopBitsCount: stopBitsCount,
      ),
    );
  }

  return changes;
}

// ── fixture signal data (from uart_basic.vcd) ─────────────────────────────────
//
// 1 Mbaud, 1 ns/tick → bit_period = 1000 ticks, frame = 10 000 ticks (8N1)
//
// TX: 'H' (0x48) @1000, 'i' (0x69) @11000, 0x55 (framing error) @32000
// RX: 'O' (0x4F) @35000, 'K' (0x4B) @45000

final _fixtureTxChanges = <(int, String)>[
  (1000, '0'),
  (5000, '1'),
  (6000, '0'),
  (8000, '1'),
  (9000, '0'),
  (10000, '1'),
  (11000, '0'),
  (12000, '1'),
  (13000, '0'),
  (15000, '1'),
  (16000, '0'),
  (17000, '1'),
  (19000, '0'),
  (20000, '1'),
  (32000, '0'),
  (33000, '1'),
  (34000, '0'),
  (35000, '1'),
  (36000, '0'),
  (37000, '1'),
  (38000, '0'),
  (39000, '1'),
  (40000, '0'),
  (43000, '1'),
];

final _fixtureRxChanges = <(int, String)>[
  (35000, '0'),
  (36000, '1'),
  (40000, '0'),
  (42000, '1'),
  (43000, '0'),
  (44000, '1'),
  (45000, '0'),
  (46000, '1'),
  (48000, '0'),
  (49000, '1'),
  (50000, '0'),
  (52000, '1'),
  (53000, '0'),
  (54000, '1'),
];

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── definition ──────────────────────────────────────────────────────────────

  group('UartDecoder.decoderDefinition', () {
    const def = UartDecoder.decoderDefinition;

    test('id is uart', () => expect(def.id, 'uart'));
    test('displayName is UART', () => expect(def.displayName, 'UART'));
    test('description is non-empty', () => expect(def.description, isNotEmpty));

    test('required signal is tx', () {
      expect(def.requiredSignals.map((s) => s.name), contains('tx'));
    });

    test('optional signal is rx', () {
      expect(def.optionalSignals.map((s) => s.name), contains('rx'));
    });

    test('has all expected parameters', () {
      final names = def.parameters.map((p) => p.name).toList();
      expect(
        names,
        containsAll([
          'baud_rate',
          'data_bits',
          'parity',
          'stop_bits',
          'bit_order',
          'group_gap_bits',
        ]),
      );
    });

    test('does not expose timescale_ns as a user parameter', () {
      final names = def.parameters.map((p) => p.name).toList();
      expect(names, isNot(contains('timescale_ns')));
    });

    test('baud_rate is integer with default 9600', () {
      final p = def.parameters.firstWhere((p) => p.name == 'baud_rate');
      expect(p.type, DecoderParameterType.integer);
      expect(p.defaultValue, 9600);
    });

    test('parity is enumeration with none/even/odd', () {
      final p = def.parameters.firstWhere((p) => p.name == 'parity');
      expect(p.type, DecoderParameterType.enumeration);
      expect(p.enumValues, containsAll(['none', 'even', 'odd']));
      expect(p.defaultValue, 'none');
    });

    test('bit_order default is lsb', () {
      final p = def.parameters.firstWhere((p) => p.name == 'bit_order');
      expect(p.defaultValue, 'lsb');
    });

    test('instance definition matches static', () {
      final decoder = makeDecoder();
      expect(decoder.definition, UartDecoder.decoderDefinition);
    });
  });

  // ── single-byte decode ────────────────────────────────────────────────────

  group('single-byte decode (LSB-first, 8N1)', () {
    // 'A' = 0x41 = 01000001 binary, LSB-first wire: 1,0,0,0,0,0,1,0
    test('decodes 0x41 correctly', () {
      final changes = buildUartFrame(0x41);
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        12000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs, hasLength(1));
      expect(txs.first.fields['data'], '0x41');
    });

    test('label uses ASCII when byte is printable', () {
      final changes = buildUartFrame(0x41); // 'A'
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        12000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs.first.label, 'UART TX: A');
    });

    test('label uses hex when byte is non-printable', () {
      final changes = buildUartFrame(0x01);
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        12000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs.first.label, 'UART TX: 0x01');
    });

    test('fields contain channel, data, ascii, bytes', () {
      final changes = buildUartFrame(0x42); // 'B'
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        12000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      final f = txs.first.fields;
      expect(f['channel'], 'TX');
      expect(f['data'], '0x42');
      expect(f['ascii'], 'B');
      expect(f['bytes'], '1');
    });

    test('no error for valid frame', () {
      final changes = buildUartFrame(0xFF);
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        12000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs.first.isError, isFalse);
    });

    test('channel is RX when decoding rx signal', () {
      final changes = buildUartFrame(0x55);
      final decoder = makeDecoder(withTx: false, withRx: true);
      final txs = decoder.decode(
        0,
        12000,
        makeQuery({'rx': changes}),
        makeChangesQuery({'rx': changes}),
      );
      expect(txs.first.fields['channel'], 'RX');
    });
  });

  // ── MSB-first bit order ───────────────────────────────────────────────────

  group('MSB-first bit order', () {
    test('MSB-first decodes MSB-encoded frame correctly', () {
      // 0x43 = 01000011 MSB-first wire: 0,1,0,0,0,0,1,1
      final changesMsb = buildUartFrame(0x43, lsbFirst: false);
      final decoderMsb = makeDecoder(bitOrder: 'msb');
      final txsMsb = decoderMsb.decode(
        0,
        12000,
        makeQuery({'tx': changesMsb}),
        makeChangesQuery({'tx': changesMsb}),
      );
      expect(txsMsb.first.fields['data'], '0x43');
    });

    test(
      'LSB-first encoded frame read with MSB decoder gives different byte',
      () {
        // 0x43 = 01000011; LSB-first wire: [1,1,0,0,0,0,1,0]
        // Read MSB-first: 11000010 = 0xC2 ≠ 0x43
        final changesLsb = buildUartFrame(0x43);
        final decoderMsb = makeDecoder(bitOrder: 'msb');
        final txsMsb = decoderMsb.decode(
          0,
          12000,
          makeQuery({'tx': changesLsb}),
          makeChangesQuery({'tx': changesLsb}),
        );
        expect(txsMsb.first.fields['data'], '0xC2');
      },
    );
  });

  // ── different data bit widths ─────────────────────────────────────────────

  group('data bit widths', () {
    test('5-bit frame decodes low 5 bits', () {
      // 5-bit: send 0b10101 = 21
      final changes = buildUartFrame(0x15, dataBits: 5);
      final decoder = makeDecoder(dataBits: 5);
      final txs = decoder.decode(
        0,
        8000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs.first.fields['data'], '0x15');
    });

    test('7-bit frame decodes correctly', () {
      final changes = buildUartFrame(0x7F, dataBits: 7);
      final decoder = makeDecoder(dataBits: 7);
      final txs = decoder.decode(
        0,
        11000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs.first.fields['data'], '0x7F');
    });

    test('9-bit frame decodes correctly', () {
      // Send 0x155 (9-bit) but we clamp to 9 bits so max = 0x1FF
      final changes = buildUartFrame(0x1A5, dataBits: 9);
      final decoder = makeDecoder(dataBits: 9);
      final txs = decoder.decode(
        0,
        13000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      // 0x1A5 & 0x1FF = 0x1A5
      expect(txs.first.fields['data'], '0x1A5');
    });
  });

  // ── parity ────────────────────────────────────────────────────────────────

  group('parity', () {
    test('even parity — correct parity bit passes', () {
      final changes = buildUartFrame(0x01, parity: 'even');
      // 0x01 has 1 one-bit → parity bit = 1 (to make total even = 2)
      final decoder = makeDecoder(parity: 'even');
      final txs = decoder.decode(
        0,
        13000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs.first.isError, isFalse);
      expect(txs.first.fields['data'], '0x01');
    });

    test('even parity — wrong parity bit triggers error', () {
      // Manually corrupt the parity bit: use odd parity on decoder with even encoding.
      final changes = buildUartFrame(0x01, parity: 'odd'); // wrong parity bit
      final decoder = makeDecoder(parity: 'even');
      final txs = decoder.decode(
        0,
        13000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs.first.isError, isTrue);
      expect(txs.first.errorMessage, contains('Parity error'));
    });

    test('odd parity — correct parity bit passes', () {
      final changes = buildUartFrame(0xFF, parity: 'odd');
      // 0xFF has 8 one-bits → parity bit = 1 (to make total 9 = odd)
      final decoder = makeDecoder(parity: 'odd');
      final txs = decoder.decode(
        0,
        13000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs.first.isError, isFalse);
    });

    test('odd parity — wrong parity bit triggers error', () {
      final changes = buildUartFrame(0xFF, parity: 'even'); // wrong
      final decoder = makeDecoder(parity: 'odd');
      final txs = decoder.decode(
        0,
        13000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs.first.isError, isTrue);
      expect(txs.first.errorMessage, contains('Parity error'));
    });
  });

  // ── 2 stop bits ───────────────────────────────────────────────────────────

  group('2 stop bits', () {
    test('valid 2-stop-bit frame decodes correctly', () {
      final changes = buildUartFrame(0xAB, stopBitsCount: 2);
      final decoder = makeDecoder(stopBits: '2');
      final txs = decoder.decode(
        0,
        14000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs.first.fields['data'], '0xAB');
      expect(txs.first.isError, isFalse);
    });
  });

  // ── framing error ─────────────────────────────────────────────────────────

  group('framing error', () {
    test('stop bit low is flagged as framing error', () {
      final changes = buildUartFrame(0xAA, forceFramingError: true);
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        14000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs.first.isError, isTrue);
      expect(txs.first.errorMessage, contains('Framing error'));
    });

    test('framing error byte gets its own transaction (not grouped)', () {
      // Good byte then framing error byte immediately after.
      final goodFrame = buildUartFrame(0x41);
      final errorFrame = buildUartFrame(
        0xAA,
        startTime: 10000, // right after good frame
        forceFramingError: true,
      );
      final allChanges = [...goodFrame, ...errorFrame];
      final decoder = makeDecoder(groupGapBits: 100);
      final txs = decoder.decode(
        0,
        25000,
        makeQuery({'tx': allChanges}),
        makeChangesQuery({'tx': allChanges}),
      );
      // Even with a large gap threshold, error bytes split the group.
      expect(txs, hasLength(2));
      expect(txs[0].isError, isFalse);
      expect(txs[1].isError, isTrue);
    });

    test('byte after framing error is still decoded', () {
      final errorFrame = buildUartFrame(
        0xAA,
        forceFramingError: true,
      );
      // Return to idle is added by buildUartFrame; next frame starts at 12000.
      final goodFrame = buildUartFrame(0x42, startTime: 12000);
      final allChanges = [...errorFrame, ...goodFrame];
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        25000,
        makeQuery({'tx': allChanges}),
        makeChangesQuery({'tx': allChanges}),
      );
      expect(txs, hasLength(2));
      expect(txs[1].fields['data'], '0x42');
    });
  });

  // ── byte grouping ─────────────────────────────────────────────────────────

  group('byte grouping', () {
    test('back-to-back bytes are grouped into one transaction', () {
      final changes = buildUartFrames([0x41, 0x42, 0x43]);
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        35000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs, hasLength(1));
      expect(txs.first.fields['data'], '0x41 0x42 0x43');
      expect(txs.first.fields['bytes'], '3');
    });

    test('gap exceeding threshold splits into separate transactions', () {
      final frame1 = buildUartFrame(0x41);
      // Place next frame 15 bit-periods later (> default threshold of 10).
      final frame2 = buildUartFrame(0x42, startTime: 25000);
      final allChanges = [...frame1, ...frame2];
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        38000,
        makeQuery({'tx': allChanges}),
        makeChangesQuery({'tx': allChanges}),
      );
      expect(txs, hasLength(2));
    });

    test('gap within threshold is grouped', () {
      // 5-bit-period gap (< default threshold of 10).
      final frame1 = buildUartFrame(0x41);
      final frame2 = buildUartFrame(0x42, startTime: 15000);
      final allChanges = [...frame1, ...frame2];
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        28000,
        makeQuery({'tx': allChanges}),
        makeChangesQuery({'tx': allChanges}),
      );
      expect(txs, hasLength(1));
      expect(txs.first.fields['bytes'], '2');
    });

    test('custom group_gap_bits overrides default', () {
      final frame1 = buildUartFrame(0x41);
      final frame2 = buildUartFrame(0x42, startTime: 15000); // gap = 5 periods
      final allChanges = [...frame1, ...frame2];
      // threshold = 3 → gap of 5 > 3 → separate transactions
      final decoder = makeDecoder(groupGapBits: 3);
      final txs = decoder.decode(
        0,
        28000,
        makeQuery({'tx': allChanges}),
        makeChangesQuery({'tx': allChanges}),
      );
      expect(txs, hasLength(2));
    });
  });

  // ── single-channel mode ───────────────────────────────────────────────────

  group('single-channel mode', () {
    test('tx-only decoder ignores rx even if rx changes present', () {
      final txChanges = buildUartFrame(0x41);
      final rxChanges = buildUartFrame(0x42);
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        12000,
        makeQuery({'tx': txChanges, 'rx': rxChanges}),
        makeChangesQuery({'tx': txChanges, 'rx': rxChanges}),
      );
      expect(txs, hasLength(1));
      expect(txs.first.fields['channel'], 'TX');
    });

    test('rx-only decoder decodes rx', () {
      final rxChanges = buildUartFrame(0x42);
      final decoder = makeDecoder(withTx: false, withRx: true);
      final txs = decoder.decode(
        0,
        12000,
        makeQuery({'rx': rxChanges}),
        makeChangesQuery({'rx': rxChanges}),
      );
      expect(txs, hasLength(1));
      expect(txs.first.fields['channel'], 'RX');
      expect(txs.first.fields['data'], '0x42');
    });

    test('no tx or rx bound returns empty list', () {
      const decoder = UartDecoder(
        DecoderConfig(signalBindings: {}),
      );
      final txs = decoder.decode(
        0,
        1000,
        makeQuery({}),
        makeChangesQuery({}),
      );
      expect(txs, isEmpty);
    });
  });

  // ── dual-channel ──────────────────────────────────────────────────────────

  group('dual-channel (TX + RX)', () {
    test('transactions from both channels are returned and sorted', () {
      final txChanges = buildUartFrame(0x41);
      final rxChanges = buildUartFrame(0x42, startTime: 500);
      final decoder = makeDecoder(withRx: true);
      final txs = decoder.decode(
        0,
        15000,
        makeQuery({'tx': txChanges, 'rx': rxChanges}),
        makeChangesQuery({'tx': txChanges, 'rx': rxChanges}),
      );
      expect(txs, hasLength(2));
      // TX starts at 0, RX starts at 500 → TX comes first.
      expect(txs[0].fields['channel'], 'TX');
      expect(txs[1].fields['channel'], 'RX');
    });
  });

  // ── baud rate / timescale ─────────────────────────────────────────────────

  group('baud rate and timescale', () {
    test('different bit_period produces correct decode', () {
      // 500 000 baud, 1 ns/tick → bit_period = 2000 ticks
      final changes = buildUartFrame(0x55, bitPeriod: 2000);
      final decoder = makeDecoder(baudRate: '500000');
      final txs = decoder.decode(
        0,
        25000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs.first.fields['data'], '0x55');
    });

    test('timescale from waveform scales bit_period', () {
      // 1 000 000 baud, 2 ns/tick → bit_period = 500 ticks
      final changes = buildUartFrame(0x33, bitPeriod: 500);
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        7000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
        timescale: const Timescale(factor: 2, unit: TimescaleUnit.nanoSeconds),
      );
      expect(txs.first.fields['data'], '0x33');
    });

    test('null timescale falls back to 1 ns/tick', () {
      // Without timescale: assumes 1 ns/tick → bit_period = 1000 ticks
      final changes = buildUartFrame(0xAA);
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        12000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs.first.fields['data'], '0xAA');
    });

    test('picosecond timescale computes correct bit_period', () {
      // 1 Mbaud, 1 ps/tick → bit_period = 1_000_000 ticks
      final changes = buildUartFrame(0xA5, bitPeriod: 1000000);
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        12000000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
        timescale: const Timescale(factor: 1, unit: TimescaleUnit.picoSeconds),
      );
      expect(txs.first.fields['data'], '0xA5');
    });
  });

  // ── edge cases ────────────────────────────────────────────────────────────

  group('edge cases', () {
    test('empty changes returns empty list', () {
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        1000,
        makeQuery({'tx': []}),
        makeChangesQuery({'tx': []}),
      );
      expect(txs, isEmpty);
    });

    test('no start bit in range returns empty list', () {
      // All high = idle, no start bit.
      final changes = <(int, String)>[(0, '1')];
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        5000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs, isEmpty);
    });

    test('frame truncated by endTime is not decoded', () {
      // Frame starts at 500, endTime=2000 → not enough room for full frame.
      final changes = buildUartFrame(0x41, startTime: 500);
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        2000,
        makeQuery({'tx': changes}),
        makeChangesQuery({'tx': changes}),
      );
      expect(txs, isEmpty);
    });
  });

  // ── fixture test ──────────────────────────────────────────────────────────

  group('uart_basic.vcd fixture', () {
    late Map<String, List<(int, String)>> allChanges;

    setUp(() {
      allChanges = {
        'tx': _fixtureTxChanges,
        'rx': _fixtureRxChanges,
      };
    });

    test('decodes three transactions matching expected_transactions.json', () {
      final jsonFile = File(
        'test/fixtures/protocol/uart/generated/uart_basic.expected_transactions.json',
      );
      final expected =
          (jsonDecode(jsonFile.readAsStringSync()) as List<dynamic>)
              .cast<Map<String, dynamic>>();

      final decoder = makeDecoder(withRx: true);
      final txs = decoder.decode(
        0,
        60000,
        makeQuery(allChanges),
        makeChangesQuery(allChanges),
      );

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
        expect(txs[i].isError, e['isError'] as bool, reason: 'tx[$i] isError');
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

    test('TX "Hi" transaction: correct bytes, label, time range', () {
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        60000,
        makeQuery(allChanges),
        makeChangesQuery(allChanges),
      );
      final hi = txs.first;
      expect(hi.startTime, 1000);
      expect(hi.endTime, 21000);
      expect(hi.label, 'UART TX: Hi');
      expect(hi.fields['data'], '0x48 0x69');
      expect(hi.fields['ascii'], 'Hi');
      expect(hi.isError, isFalse);
    });

    test('TX framing error: 0x55 decoded correctly with error', () {
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        60000,
        makeQuery(allChanges),
        makeChangesQuery(allChanges),
      );
      final errTx = txs.last;
      expect(errTx.startTime, 32000);
      expect(errTx.endTime, 42000);
      expect(errTx.fields['data'], '0x55');
      expect(errTx.isError, isTrue);
      expect(errTx.errorMessage, contains('Framing error'));
    });

    test('RX "OK" transaction: correct bytes, label, time range', () {
      final decoder = makeDecoder(withTx: false, withRx: true);
      final txs = decoder.decode(
        0,
        60000,
        makeQuery(allChanges),
        makeChangesQuery(allChanges),
      );
      expect(txs, hasLength(1));
      final ok = txs.first;
      expect(ok.startTime, 35000);
      expect(ok.endTime, 55000);
      expect(ok.label, 'UART RX: OK');
      expect(ok.fields['data'], '0x4F 0x4B');
    });

    test('full-duplex decode yields 3 transactions sorted by startTime', () {
      final decoder = makeDecoder(withRx: true);
      final txs = decoder.decode(
        0,
        60000,
        makeQuery(allChanges),
        makeChangesQuery(allChanges),
      );
      expect(txs, hasLength(3));
      // Sorted by startTime: Hi@1000, error@32000, OK@35000.
      expect(txs[0].startTime, 1000);
      expect(txs[1].startTime, 32000);
      expect(txs[2].startTime, 35000);
    });
  });
}
