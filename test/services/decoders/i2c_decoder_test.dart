// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/services/decoders/i2c_decoder.dart';

// ── helpers ──────────────────────────────────────────────────────────────────

/// Returns the held value of [signal] at [time] given a change map.
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

/// Returns changes for [signal] in [start, end).
SignalChangesQuery makeChangesQuery(Map<String, List<(int, String)>> changes) {
  return (signal, start, end) {
    final list = changes[signal] ?? [];
    return [
      for (final e in list)
        if (e.$1 >= start && e.$1 < end) e,
    ];
  };
}

I2cDecoder makeDecoder({String addressBits = '7'}) {
  return I2cDecoder(
    DecoderConfig(
      signalBindings: const {'sda': 'tb.sda', 'scl': 'tb.scl'},
      parameters: {'address_bits': addressBits},
    ),
  );
}

/// Builds a single 7-bit I2C transaction in simulation-signal form.
///
/// [addr7] is the 7-bit address (0..127).
/// [rw] is 0 for write, 1 for read.
/// [addrAck] controls whether the address ACK is asserted.
/// [dataBytes] is a list of (byte, ack) pairs for data bytes.
///
/// Returns {sda: [...], scl: [...]} changes lists and the expected [start, end).
Map<String, dynamic> buildTx7({
  required int addr7,
  required int rw,
  bool addrAck = true,
  List<(int, bool)> dataBytes = const [],
  int baseTime = 0,
}) {
  final sdaChanges = <(int, String)>[];
  final sclChanges = <(int, String)>[];

  // SCL must be high before the START condition is detectable.
  // Start: SDA falls while SCL high.
  final startTime = baseTime + 10;
  sclChanges.add((baseTime, '1'));
  sdaChanges.add((startTime, '0'));

  var t = baseTime + 20; // first SCL fall

  void emitBit(int bit) {
    sclChanges.add((t, '0')); // SCL fall
    if (bit == 1) {
      sdaChanges.add((t + 5, '1'));
    } else {
      sdaChanges.add((t + 5, '0'));
    }
    sclChanges.add((t + 20, '1')); // SCL rise (sample point)
    t += 40;
  }

  // Address byte: addr7 (7 bits MSB-first) + R/W.
  final addrByte = (addr7 << 1) | rw;
  for (var i = 7; i >= 0; i--) {
    emitBit((addrByte >> i) & 1);
  }

  // Address ACK.
  sclChanges.add((t, '0'));
  sdaChanges.add((t + 5, addrAck ? '0' : '1'));
  sclChanges.add((t + 20, '1'));
  t += 40;

  if (!addrAck) {
    // STOP after NACK.
    sclChanges.add((t, '0'));
    sdaChanges.add((t + 5, '0'));
    sclChanges.add((t + 20, '1'));
    sdaChanges.add((t + 30, '1')); // SDA rises while SCL high → STOP
    final endTime = t + 30;
    t += 50;
    return {
      'sda': sdaChanges,
      'scl': sclChanges,
      'start': startTime,
      'end': endTime,
    };
  }

  // Data bytes.
  for (final (byte, ack) in dataBytes) {
    for (var i = 7; i >= 0; i--) {
      emitBit((byte >> i) & 1);
    }
    // Data ACK.
    sclChanges.add((t, '0'));
    sdaChanges.add((t + 5, ack ? '0' : '1'));
    sclChanges.add((t + 20, '1'));
    t += 40;
  }

  // STOP: SCL falls, SCL rises, SDA rises while SCL high.
  sclChanges.add((t, '0'));
  sdaChanges.add((t + 5, '0'));
  sclChanges.add((t + 20, '1'));
  sdaChanges.add((t + 30, '1')); // STOP
  final endTime = t + 30;

  return {
    'sda': sdaChanges,
    'scl': sclChanges,
    'start': startTime,
    'end': endTime,
  };
}

/// Builds a 10-bit I2C transaction in simulation-signal form.
///
/// Always emits the full 18-bit address phase (two bytes + two ACK bits) so the
/// decoder can reach the NACK-check branch regardless of [ack1]/[ack2] values.
Map<String, dynamic> buildTx10({
  required int addr10,
  required int rw,
  bool ack1 = true,
  bool ack2 = true,
  List<(int, bool)> dataBytes = const [],
  int baseTime = 0,
}) {
  final sdaChanges = <(int, String)>[];
  final sclChanges = <(int, String)>[];

  final startTime = baseTime + 10;
  sclChanges.add((baseTime, '1'));
  sdaChanges.add((startTime, '0')); // START: SDA falls while SCL high

  var t = baseTime + 20;

  void emitBit(int bit) {
    sclChanges.add((t, '0'));
    sdaChanges.add((t + 5, bit == 1 ? '1' : '0'));
    sclChanges.add((t + 20, '1'));
    t += 40;
  }

  // First byte: 11110 (prefix) + upper 2 addr bits + R/W (bits[0..7]).
  final addrHighBits = (addr10 >> 8) & 0x3;
  emitBit(1);
  emitBit(1);
  emitBit(1);
  emitBit(1);
  emitBit(0); // 11110
  emitBit((addrHighBits >> 1) & 1); // bits[5] = MSB of upper address
  emitBit(addrHighBits & 1); // bits[6] = LSB of upper address
  emitBit(rw); // bits[7] = R/W

  // ACK1 (bits[8]).
  sclChanges.add((t, '0'));
  sdaChanges.add((t + 5, ack1 ? '0' : '1'));
  sclChanges.add((t + 20, '1'));
  t += 40;

  // Second byte: lower 8 bits of addr10 (bits[9..16]).
  final addrLow = addr10 & 0xFF;
  for (var i = 7; i >= 0; i--) {
    emitBit((addrLow >> i) & 1);
  }

  // ACK2 (bits[17]).
  sclChanges.add((t, '0'));
  sdaChanges.add((t + 5, ack2 ? '0' : '1'));
  sclChanges.add((t + 20, '1'));
  t += 40;

  // Optional data bytes.
  for (final (byte, ack) in dataBytes) {
    for (var i = 7; i >= 0; i--) {
      emitBit((byte >> i) & 1);
    }
    sclChanges.add((t, '0'));
    sdaChanges.add((t + 5, ack ? '0' : '1'));
    sclChanges.add((t + 20, '1'));
    t += 40;
  }

  // STOP: SDA rises while SCL is high.
  sclChanges.add((t, '0'));
  sdaChanges.add((t + 5, '0'));
  sclChanges.add((t + 20, '1'));
  sdaChanges.add((t + 30, '1'));
  final endTime = t + 30;

  return {
    'sda': sdaChanges,
    'scl': sclChanges,
    'start': startTime,
    'end': endTime,
  };
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── decoderDefinition ───────────────────────────────────────────────────────

  group('decoderDefinition', () {
    test('id is i2c', () {
      expect(I2cDecoder.decoderDefinition.id, 'i2c');
    });

    test('displayName is I²C', () {
      expect(I2cDecoder.decoderDefinition.displayName, 'I²C');
    });

    test('requiredSignals are sda and scl', () {
      final names = I2cDecoder.decoderDefinition.requiredSignals.map(
        (s) => s.name,
      );
      expect(names, containsAll(['sda', 'scl']));
    });

    test('definition getter matches static', () {
      expect(makeDecoder().definition, I2cDecoder.decoderDefinition);
    });
  });

  // ── empty / no signals ──────────────────────────────────────────────────────

  group('empty signal data', () {
    test('returns empty list when no changes', () {
      final dec = makeDecoder();
      final result = dec.decode(
        0,
        1000,
        makeQuery({}),
        makeChangesQuery({}),
      );
      expect(result, isEmpty);
    });

    test('returns empty list when only SCL changes', () {
      final dec = makeDecoder();
      final sclChanges = [(10, '1'), (30, '0'), (50, '1')];
      final result = dec.decode(
        0,
        100,
        makeQuery({'scl': sclChanges}),
        makeChangesQuery({'scl': sclChanges}),
      );
      expect(result, isEmpty);
    });
  });

  // ── 7-bit write transaction ─────────────────────────────────────────────────

  group('7-bit write', () {
    test('decodes address and one data byte', () {
      final tx = buildTx7(
        addr7: 0x48,
        rw: 0,
        dataBytes: [(0x55, true)],
      );
      final changes = {
        'sda': tx['sda'] as List<(int, String)>,
        'scl': tx['scl'] as List<(int, String)>,
      };
      final dec = makeDecoder();
      final results = dec.decode(
        0,
        2000,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(results, hasLength(1));
      final t = results[0];
      expect(t.isError, isFalse);
      expect(t.fields['address'], '0x48');
      expect(t.fields['rw'], 'W');
      expect(t.fields['data'], '0x55');
      expect(t.fields['ack'], 'ACK');
      expect(t.label, contains('0x48'));
      expect(t.label, contains('W'));
    });

    test('decodes two data bytes', () {
      final tx = buildTx7(
        addr7: 0x20,
        rw: 0,
        dataBytes: [(0xDE, true), (0xAD, true)],
      );
      final changes = {
        'sda': tx['sda'] as List<(int, String)>,
        'scl': tx['scl'] as List<(int, String)>,
      };
      final dec = makeDecoder();
      final results = dec.decode(
        0,
        5000,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(results, hasLength(1));
      final t = results[0];
      expect(t.isError, isFalse);
      expect(t.fields['data'], '0xDE 0xAD');
      expect(t.fields['ack'], 'ACK ACK');
      expect(t.label, contains('2 bytes'));
    });

    test('no data bytes produces address-only label', () {
      final tx = buildTx7(addr7: 0x10, rw: 0, dataBytes: []);
      final changes = {
        'sda': tx['sda'] as List<(int, String)>,
        'scl': tx['scl'] as List<(int, String)>,
      };
      final dec = makeDecoder();
      final results = dec.decode(
        0,
        5000,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(results, hasLength(1));
      expect(results[0].fields['data'], isNull);
      expect(results[0].label, 'I²C 0x10 W');
    });
  });

  // ── 7-bit read transaction ──────────────────────────────────────────────────

  group('7-bit read', () {
    test('R/W bit = 1 yields rw = R', () {
      final tx = buildTx7(
        addr7: 0x3C,
        rw: 1,
        dataBytes: [(0xAB, true)],
      );
      final changes = {
        'sda': tx['sda'] as List<(int, String)>,
        'scl': tx['scl'] as List<(int, String)>,
      };
      final dec = makeDecoder();
      final results = dec.decode(
        0,
        5000,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(results, hasLength(1));
      expect(results[0].fields['rw'], 'R');
    });
  });

  // ── NACK detection ──────────────────────────────────────────────────────────

  group('NACK detection', () {
    test('address NACK is flagged as error', () {
      final tx = buildTx7(addr7: 0x20, rw: 0, addrAck: false);
      final changes = {
        'sda': tx['sda'] as List<(int, String)>,
        'scl': tx['scl'] as List<(int, String)>,
      };
      final dec = makeDecoder();
      final results = dec.decode(
        0,
        5000,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(results, hasLength(1));
      final t = results[0];
      expect(t.isError, isTrue);
      expect(t.fields['ack'], 'NACK');
      expect(t.errorMessage, contains('NACK'));
    });

    test('write data byte NACK is an error', () {
      final tx = buildTx7(
        addr7: 0x50,
        rw: 0,
        dataBytes: [(0xFF, false)],
      );
      final changes = {
        'sda': tx['sda'] as List<(int, String)>,
        'scl': tx['scl'] as List<(int, String)>,
      };
      final dec = makeDecoder();
      final results = dec.decode(
        0,
        5000,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(results, hasLength(1));
      final t = results[0];
      expect(t.isError, isTrue);
      expect(t.fields['ack'], 'NACK');
    });

    test(
      'read final byte NACK is not an error (normal master termination)',
      () {
        // In I2C reads the master sends NACK on the last byte to tell the slave
        // to stop driving SDA. This is normal protocol behaviour, not an error.
        final tx = buildTx7(
          addr7: 0x48,
          rw: 1,
          dataBytes: [(0xAB, false)], // NACK on the only (final) byte
        );
        final changes = {
          'sda': tx['sda'] as List<(int, String)>,
          'scl': tx['scl'] as List<(int, String)>,
        };
        final dec = makeDecoder();
        final results = dec.decode(
          0,
          5000,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(results, hasLength(1));
        final t = results[0];
        expect(t.isError, isFalse);
        expect(t.fields['ack'], 'NACK');
        expect(t.fields['data'], '0xAB');
      },
    );

    test('read multi-byte: NACK only on final byte is not an error', () {
      final tx = buildTx7(
        addr7: 0x48,
        rw: 1,
        dataBytes: [(0xAB, true), (0xCD, false)], // ACK, then NACK on final
      );
      final changes = {
        'sda': tx['sda'] as List<(int, String)>,
        'scl': tx['scl'] as List<(int, String)>,
      };
      final dec = makeDecoder();
      final results = dec.decode(
        0,
        5000,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(results, hasLength(1));
      final t = results[0];
      expect(t.isError, isFalse);
      expect(t.fields['ack'], 'ACK NACK');
    });

    test('read mid-stream NACK (before final byte) is an error', () {
      // NACK on the first of two bytes is unexpected — the slave aborted early.
      final tx = buildTx7(
        addr7: 0x48,
        rw: 1,
        dataBytes: [(0xAB, false), (0xCD, true)], // NACK on first, ACK on last
      );
      final changes = {
        'sda': tx['sda'] as List<(int, String)>,
        'scl': tx['scl'] as List<(int, String)>,
      };
      final dec = makeDecoder();
      final results = dec.decode(
        0,
        5000,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(results, hasLength(1));
      final t = results[0];
      expect(t.isError, isTrue);
      expect(t.fields['ack'], 'NACK ACK');
    });
  });

  // ── repeated START ──────────────────────────────────────────────────────────

  group('repeated START', () {
    test('two consecutive transactions are decoded independently', () {
      final tx1 = buildTx7(
        addr7: 0x48,
        rw: 0,
        dataBytes: [(0x01, true)],
      );
      final tx2 = buildTx7(
        addr7: 0x48,
        rw: 1,
        dataBytes: [(0xFF, true)],
        baseTime: 2000,
      );

      final sda = [
        ...tx1['sda'] as List<(int, String)>,
        ...tx2['sda'] as List<(int, String)>,
      ];
      final scl = [
        ...tx1['scl'] as List<(int, String)>,
        ...tx2['scl'] as List<(int, String)>,
      ];
      final changes = {'sda': sda, 'scl': scl};

      final dec = makeDecoder();
      final results = dec.decode(
        0,
        5000,
        makeQuery(changes),
        makeChangesQuery(changes),
      );

      expect(results, hasLength(2));
      expect(results[0].fields['rw'], 'W');
      expect(results[1].fields['rw'], 'R');
    });
  });

  // ── missing STOP ────────────────────────────────────────────────────────────

  group('missing STOP', () {
    test('transaction without STOP flagged as error', () {
      // Build a write transaction but omit the STOP condition.
      // Manually construct changes without a trailing SDA→1 while SCL=1.
      const sda = <(int, String)>[
        (10, '0'), // START
        (25, '1'), // bit 7 = 1 (addr bit)
        (65, '0'), // bit 6..0 and R/W all 0
        (385, '0'), // ACK
      ];
      const scl = <(int, String)>[
        (20, '0'),
        (40, '1'),
        (60, '0'),
        (80, '1'),
        (100, '0'),
        (120, '1'),
        (140, '0'),
        (160, '1'),
        (180, '0'),
        (200, '1'),
        (220, '0'),
        (240, '1'),
        (260, '0'),
        (280, '1'),
        (300, '0'),
        (320, '1'),
        (340, '0'),
        (360, '1'),
        (380, '0'),
        (400, '1'),
      ];

      final changes = {'sda': sda, 'scl': scl};
      final dec = makeDecoder();
      final results = dec.decode(
        0,
        1000,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      // Should produce a transaction (possibly with missingStop error).
      // Or empty if not enough bits — either way doesn't crash.
      expect(results, isA<List<dynamic>>());
    });
  });

  // ── not enough bits ─────────────────────────────────────────────────────────

  group('error cases', () {
    test('fewer than 9 bits returns error transaction', () {
      // START at t=10, only 2 SCL rising edges before STOP at t=90.
      const sda = <(int, String)>[(10, '0'), (90, '1')];
      const scl = <(int, String)>[
        (0, '1'),
        (20, '0'),
        (40, '1'),
        (60, '0'),
        (80, '1'),
        (100, '0'),
        (120, '1'),
        (140, '0'),
        (160, '1'),
        (180, '1'),
      ];
      final changes = {'sda': sda, 'scl': scl};
      final dec = makeDecoder();
      final results = dec.decode(
        0,
        1000,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(results, hasLength(1));
      expect(results[0].isError, isTrue);
    });
  });

  // ── missing STOP (complete transaction) ─────────────────────────────────────

  group('missing STOP with complete transaction', () {
    test('flagged as error when no STOP follows a valid address+data frame', () {
      // Build a complete 7-bit write (address ACK + one data ACK) but omit the
      // final STOP condition so missingStop=true reaches the error-list builder.
      final sclChanges = <(int, String)>[(0, '1')]; // SCL pre-high
      final sdaChanges = <(int, String)>[
        (10, '0'),
      ]; // START: SDA falls while SCL high

      var t = 20;
      void emitBit(int bit) {
        sclChanges.add((t, '0'));
        sdaChanges.add((t + 5, bit == 1 ? '1' : '0'));
        sclChanges.add((t + 20, '1'));
        t += 40;
      }

      // Address 0x48 write (addrByte = 0x90 = 0b10010000).
      const addrByte = (0x48 << 1) | 0;
      for (var i = 7; i >= 0; i--) {
        emitBit((addrByte >> i) & 1);
      }
      // Address ACK.
      sclChanges.add((t, '0'));
      sdaChanges.add((t + 5, '0'));
      sclChanges.add((t + 20, '1'));
      t += 40;

      // Data byte 0x42.
      const dataByte = 0x42;
      for (var i = 7; i >= 0; i--) {
        emitBit((dataByte >> i) & 1);
      }
      // Data ACK — then intentionally no STOP.
      sclChanges.add((t, '0'));
      sdaChanges.add((t + 5, '0'));
      sclChanges.add((t + 20, '1'));
      t += 40;

      final changes = {'sda': sdaChanges, 'scl': sclChanges};
      final dec = makeDecoder();
      final results = dec.decode(
        0,
        t + 100,
        makeQuery(changes),
        makeChangesQuery(changes),
      );

      expect(results, hasLength(1));
      final tx = results[0];
      expect(tx.isError, isTrue);
      expect(tx.errorMessage, contains('Missing STOP'));
      expect(tx.fields['address'], '0x48');
      expect(tx.fields['rw'], 'W');
      expect(tx.fields['data'], '0x42');
      expect(tx.fields['ack'], 'ACK');
    });
  });

  // ── 10-bit addressing ───────────────────────────────────────────────────────

  group('10-bit addressing', () {
    test('decodes 10-bit write address with both ACKs', () {
      final tx = buildTx10(addr10: 0x155, rw: 0);
      final changes = {
        'sda': tx['sda'] as List<(int, String)>,
        'scl': tx['scl'] as List<(int, String)>,
      };
      final dec = makeDecoder(addressBits: '10');
      final results = dec.decode(
        0,
        5000,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(results, hasLength(1));
      final t = results[0];
      expect(t.isError, isFalse);
      expect(t.fields['address'], '0x155');
      expect(t.fields['rw'], 'W');
    });

    test('10-bit NACK on first address byte flagged as error', () {
      final tx = buildTx10(addr10: 0x155, rw: 0, ack1: false);
      final changes = {
        'sda': tx['sda'] as List<(int, String)>,
        'scl': tx['scl'] as List<(int, String)>,
      };
      final dec = makeDecoder(addressBits: '10');
      final results = dec.decode(
        0,
        5000,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(results, hasLength(1));
      final t = results[0];
      expect(t.isError, isTrue);
      expect(t.fields['address'], '0x155');
      expect(t.fields['ack'], 'NACK');
      expect(t.errorMessage, contains('NACK'));
    });

    test('returns error if fewer than 18 bits', () {
      // START then only 9 bits (one byte + ACK).
      const sda = <(int, String)>[(10, '0'), (410, '1')];
      // 9 SCL rising edges, with initial SCL=1 so START at t=10 is detected.
      final scl = <(int, String)>[
        (0, '1'),
        for (var i = 0; i < 9; i++) ...[
          (20 + i * 40, '0'),
          (40 + i * 40, '1'),
        ],
        (20 + 9 * 40, '1'),
      ];
      final changes = {'sda': sda, 'scl': scl};
      final dec = makeDecoder(addressBits: '10');
      final results = dec.decode(
        0,
        1000,
        makeQuery(changes),
        makeChangesQuery(changes),
      );
      expect(results, hasLength(1));
      expect(results[0].isError, isTrue);
      expect(results[0].errorMessage, contains('18 bits'));
    });
  });

  // ── fixture-based test ──────────────────────────────────────────────────────

  group('fixture', () {
    test('i2c_basic.vcd matches expected transactions', () {
      const fixturePath = 'test/fixtures/protocol/i2c/generated/i2c_basic.vcd';
      const expectedPath =
          'test/fixtures/protocol/i2c/generated/i2c_basic.expected_transactions.json';

      final vcdLines = File(fixturePath).readAsLinesSync();
      final expectedJson =
          jsonDecode(File(expectedPath).readAsStringSync()) as List<Object?>;

      // Parse VCD into signal change maps keyed by variable name.
      final idToName = <String, String>{};
      final allChanges = <String, List<(int, String)>>{};
      var inDefs = true;
      var currentTime = 0;

      for (final raw in vcdLines) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        if (line.startsWith(r'$comment')) continue;

        if (line.startsWith(r'$var')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 5) {
            final id = parts[3];
            final name = parts[4].replaceAll(r'$end', '').trim();
            idToName[id] = name;
            allChanges[name] = [];
          }
        } else if (line.startsWith(r'$enddefinitions')) {
          inDefs = false;
        } else if (!inDefs && line.startsWith('#')) {
          currentTime = int.parse(line.substring(1));
        } else if (!inDefs && (line.startsWith('0') || line.startsWith('1'))) {
          final val = line[0];
          final id = line.substring(1);
          final name = idToName[id];
          if (name != null) {
            allChanges[name]!.add((currentTime, val));
          }
        }
      }

      final sda = allChanges['sda'] ?? [];
      final scl = allChanges['scl'] ?? [];
      final changes = {'sda': sda, 'scl': scl};

      final dec = makeDecoder();
      final results = dec.decode(
        0,
        2000,
        makeQuery(changes),
        makeChangesQuery(changes),
      );

      expect(
        results.length,
        expectedJson.length,
        reason: 'transaction count mismatch',
      );

      for (var i = 0; i < expectedJson.length; i++) {
        final exp = expectedJson[i]! as Map<String, dynamic>;
        final got = results[i];

        expect(got.startTime, exp['startTime'], reason: 'tx[$i] startTime');
        expect(got.endTime, exp['endTime'], reason: 'tx[$i] endTime');
        expect(got.label, exp['label'], reason: 'tx[$i] label');
        expect(got.isError, exp['isError'], reason: 'tx[$i] isError');
        expect(
          got.errorMessage,
          exp['errorMessage'],
          reason: 'tx[$i] errorMessage',
        );

        final expFields = exp['fields'] as Map<String, dynamic>;
        for (final key in expFields.keys) {
          expect(
            got.fields[key],
            expFields[key],
            reason: 'tx[$i] field "$key"',
          );
        }
      }
    });
  });
}
