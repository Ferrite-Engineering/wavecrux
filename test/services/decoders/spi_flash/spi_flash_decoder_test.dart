// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/services/decoders/spi_flash/spi_flash_decoder.dart';

// ── helpers ──────────────────────────────────────────────────────────────────

/// Builds a synthetic SPI parent transaction whose [mosi] and [miso] fields
/// carry space-separated hex bytes — matching what [SpiDecoder] emits.
DecodedTransaction spiTx({
  required int start,
  required int end,
  required List<int> mosi,
  List<int> miso = const [],
}) {
  String hexBytes(List<int> bytes) => bytes
      .map((b) => '0x${b.toRadixString(16).toUpperCase().padLeft(2, '0')}')
      .join(' ');

  return DecodedTransaction(
    startTime: start,
    endTime: end,
    label: 'SPI',
    fields: {
      'mosi': hexBytes(mosi),
      if (miso.isNotEmpty) 'miso': hexBytes(miso),
    },
  );
}

/// Runs the flash decoder against [txs] and returns the output list.
List<DecodedTransaction> decode(
  List<DecodedTransaction> txs, {
  String vendorPreset = 'generic',
  String addressWidth = '24',
  int dummyCycles = -1,
}) {
  final decoder = SpiFlashDecoder(
    DecoderConfig(
      signalBindings: const {},
      parameters: {
        'vendor_preset': vendorPreset,
        'address_width': addressWidth,
        'dummy_cycles': dummyCycles,
      },
    ),
  );
  return decoder.decodeStacked(
    txs,
    0,
    1 << 62,
    (_, _) => null,
    (_, start, end) => [],
  );
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── definition ──────────────────────────────────────────────────────────────

  group('definition', () {
    test('id is spi_flash', () {
      expect(SpiFlashDecoder.decoderDefinition.id, 'spi_flash');
    });

    test('parentDecoderId is spi', () {
      expect(SpiFlashDecoder.decoderDefinition.parentDecoderId, 'spi');
    });

    test('requiredSignals is empty', () {
      expect(SpiFlashDecoder.decoderDefinition.requiredSignals, isEmpty);
    });

    test('has vendor_preset, address_width, dummy_cycles parameters', () {
      final ids = SpiFlashDecoder.decoderDefinition.parameters
          .map((p) => p.name)
          .toSet();
      expect(
        ids,
        containsAll(['vendor_preset', 'address_width', 'dummy_cycles']),
      );
    });
  });

  // ── decode() delegates to decodeStacked ──────────────────────────────────────

  test('decode() with empty parent list returns empty', () {
    const decoder = SpiFlashDecoder(
      DecoderConfig(signalBindings: {}),
    );
    final out = decoder.decode(0, 1000, (_, _) => null, (_, start, end) => []);
    expect(out, isEmpty);
  });

  // ── RDID ─────────────────────────────────────────────────────────────────────

  group('RDID (0x9F)', () {
    test('produces jedec_id field from 3 MISO bytes', () {
      final txs = [
        spiTx(
          start: 100,
          end: 200,
          mosi: [0x9F],
          miso: [0x00, 0xEF, 0x40, 0x18],
        ),
      ];
      final out = decode(txs);
      expect(out, hasLength(1));
      expect(out.first.label, 'RDID');
      expect(out.first.fields['jedec_id'], '0xEF-0x40-0x18');
      expect(out.first.isError, false);
    });

    test('incomplete MISO → incomplete_frame error', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x9F]),
      ];
      final out = decode(txs);
      expect(out.first.isError, true);
      expect(out.first.errorMessage, contains('incomplete_frame'));
    });
  });

  // ── WREN / WRDI ──────────────────────────────────────────────────────────────

  group('WREN (0x06)', () {
    test('sets WEL for subsequent write', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x06]),
        spiTx(start: 200, end: 300, mosi: [0x02, 0x00, 0x01, 0x00, 0xAB]),
      ];
      final out = decode(txs);
      expect(out[0].label, 'WREN');
      expect(out[0].isError, false);
      expect(out[1].label, 'PP');
      expect(out[1].isError, false);
    });

    test('double WREN → double_wren error on second', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x06]),
        spiTx(start: 200, end: 300, mosi: [0x06]),
      ];
      final out = decode(txs);
      expect(out[0].isError, false);
      expect(out[1].isError, true);
      expect(out[1].errorMessage, contains('double_wren'));
    });

    test('WRDI clears WEL so subsequent PP → write_without_wel', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x06]),
        spiTx(start: 200, end: 300, mosi: [0x04]),
        spiTx(start: 400, end: 500, mosi: [0x02, 0x00, 0x01, 0x00, 0xAB]),
      ];
      final out = decode(txs);
      expect(out[0].label, 'WREN');
      expect(out[1].label, 'WRDI');
      expect(out[2].isError, true);
      expect(out[2].errorMessage, contains('write_without_wel'));
    });
  });

  // ── Page Program ──────────────────────────────────────────────────────────────

  group('PP (0x02)', () {
    test('without WEL → write_without_wel error', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x02, 0x00, 0x01, 0x00, 0xDE, 0xAD]),
      ];
      final out = decode(txs);
      expect(out.first.isError, true);
      expect(out.first.errorMessage, contains('write_without_wel'));
    });

    test('with WEL decodes 24-bit address and write data', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x06]),
        spiTx(start: 200, end: 300, mosi: [0x02, 0x00, 0x01, 0x00, 0xDE, 0xAD]),
      ];
      final out = decode(txs);
      expect(out[1].label, 'PP');
      expect(out[1].fields['address'], '0x000100');
      expect(out[1].fields['data'], '0xDE 0xAD');
      expect(out[1].isError, false);
    });

    test('with WEL decodes 32-bit address', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x06]),
        spiTx(
          start: 200,
          end: 300,
          mosi: [0x02, 0x01, 0x00, 0x01, 0x00, 0xBE, 0xEF],
        ),
      ];
      final out = decode(txs, addressWidth: '32');
      expect(out[1].fields['address'], '0x01000100');
      expect(out[1].fields['data'], '0xBE 0xEF');
    });

    test('incomplete address → incomplete_frame error', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x06]),
        spiTx(start: 200, end: 300, mosi: [0x02, 0x00]),
      ];
      final out = decode(txs);
      expect(out[1].isError, true);
      expect(out[1].errorMessage, contains('incomplete_frame'));
    });
  });

  // ── READ / FAST_READ ──────────────────────────────────────────────────────────

  group('READ (0x03)', () {
    test('no dummy bytes, data from MISO after address', () {
      // MOSI: opcode + 3-byte addr (no dummy)
      // MISO: 4 bytes (opcode echo + 3 addr echoes + data in the data region)
      final txs = [
        spiTx(
          start: 0,
          end: 100,
          mosi: [0x03, 0x00, 0x00, 0x00],
          miso: [0x00, 0x00, 0x00, 0x00, 0xCA, 0xFE],
        ),
      ];
      final out = decode(txs);
      expect(out.first.label, 'READ');
      expect(out.first.fields['address'], '0x000000');
      expect(out.first.fields['data'], '0xCA 0xFE');
    });
  });

  group('FAST_READ (0x0B)', () {
    test('1 default dummy cycle, data extracted from MISO', () {
      // MISO layout: [opcode echo] [addr x3] [dummy x1] [data...]
      final txs = [
        spiTx(
          start: 0,
          end: 100,
          mosi: [0x0B, 0x00, 0x00, 0x01],
          miso: [0x00, 0x00, 0x00, 0x00, 0xFF, 0xAA, 0xBB],
        ),
      ];
      final out = decode(txs);
      expect(out.first.label, 'FAST_READ');
      expect(out.first.fields['address'], '0x000001');
      expect(out.first.fields['data'], '0xAA 0xBB');
    });

    test('dummy override applies over default', () {
      final txs = [
        spiTx(
          start: 0,
          end: 100,
          mosi: [0x0B, 0x00, 0x00, 0x00],
          miso: [0x00, 0x00, 0x00, 0x00, 0x11, 0x22, 0x33, 0x44],
        ),
      ];
      // With dummyCycles override = 2 instead of default 1.
      final out = decode(txs, dummyCycles: 2);
      expect(out.first.fields['data'], '0x33 0x44');
    });
  });

  // ── Sector Erase ──────────────────────────────────────────────────────────────

  group('SE (0x20)', () {
    test('without WEL → write_without_wel', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x20, 0x00, 0x10, 0x00]),
      ];
      final out = decode(txs);
      expect(out.first.isError, true);
      expect(out.first.errorMessage, contains('write_without_wel'));
    });

    test('with WEL decodes sector address', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x06]),
        spiTx(start: 200, end: 300, mosi: [0x20, 0x00, 0x10, 0x00]),
      ];
      final out = decode(txs);
      expect(out[1].label, 'SE');
      expect(out[1].fields['address'], '0x001000');
      expect(out[1].isError, false);
    });
  });

  // ── Chip Erase ───────────────────────────────────────────────────────────────

  group('CE (0x60 / 0xC7)', () {
    test('CE without WEL → write_without_wel', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x60]),
      ];
      final out = decode(txs);
      expect(out.first.isError, true);
      expect(out.first.errorMessage, contains('write_without_wel'));
    });

    test('CE with WEL succeeds (no address field)', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x06]),
        spiTx(start: 200, end: 300, mosi: [0xC7]),
      ];
      final out = decode(txs);
      expect(out[1].label, 'CE');
      expect(out[1].isError, false);
      expect(out[1].fields.containsKey('address'), false);
    });
  });

  // ── RDSR / WRSR ──────────────────────────────────────────────────────────────

  group('RDSR (0x05)', () {
    test('status byte from MISO', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x05], miso: [0x00, 0x02]),
      ];
      final out = decode(txs);
      expect(out.first.label, 'RDSR');
      expect(out.first.fields['status'], '0x02');
    });

    test('no MISO bytes → no status field', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x05]),
      ];
      final out = decode(txs);
      expect(out.first.fields.containsKey('status'), false);
    });
  });

  group('WRSR (0x01)', () {
    test('without WEL → write_without_wel error', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x01, 0x80]),
      ];
      final out = decode(txs);
      expect(out.first.isError, true);
    });

    test('with WEL decodes status register bytes', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x06]),
        spiTx(start: 200, end: 300, mosi: [0x01, 0x80]),
      ];
      final out = decode(txs);
      expect(out[1].label, 'WRSR');
      expect(out[1].fields['status'], '0x80');
      expect(out[1].isError, false);
    });
  });

  // ── Unknown opcode ───────────────────────────────────────────────────────────

  test('unknown opcode emits raw field', () {
    final txs = [
      spiTx(start: 0, end: 100, mosi: [0x77, 0xAA, 0xBB]),
    ];
    final out = decode(txs);
    expect(out.first.label, '0x77');
    expect(out.first.fields['raw'], '0xAA 0xBB');
  });

  // ── Vendor preset: Winbond ───────────────────────────────────────────────────

  group('Winbond vendor preset', () {
    test('0x28 decodes as BE32K (not unknown)', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x06]),
        spiTx(start: 200, end: 300, mosi: [0x28, 0x00, 0x00, 0x00]),
      ];
      final out = decode(txs, vendorPreset: 'winbond_w25q');
      expect(out[1].label, 'BE32K');
      expect(out[1].isError, false);
    });

    test('0x28 decodes as unknown with generic preset', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x28, 0x00, 0x00, 0x00]),
      ];
      final out = decode(txs);
      expect(out.first.label, '0x28');
    });

    test('RDSR2 (0x35) decodes with winbond preset', () {
      final txs = [
        spiTx(start: 0, end: 100, mosi: [0x35], miso: [0x00, 0x00]),
      ];
      final out = decode(txs, vendorPreset: 'winbond_w25q');
      expect(out.first.label, 'RDSR2');
    });
  });

  // ── time window filtering ─────────────────────────────────────────────────────

  test('transactions outside startTime..endTime window are excluded', () {
    const decoder = SpiFlashDecoder(
      DecoderConfig(signalBindings: {}),
    );
    final txs = [
      spiTx(start: 50, end: 60, mosi: [0x9F]),
      spiTx(start: 200, end: 210, mosi: [0x9F]),
      spiTx(start: 350, end: 360, mosi: [0x9F]),
    ];
    final out = decoder.decodeStacked(
      txs,
      100,
      300,
      (_, _) => null,
      (_, start, end) => [],
    );
    expect(out, hasLength(1));
    expect(out.first.startTime, 200);
  });

  // ── opcode field on all outputs ───────────────────────────────────────────────

  test('every output transaction carries an opcode field', () {
    final txs = [
      spiTx(start: 0, end: 100, mosi: [0x9F]),
      spiTx(start: 200, end: 300, mosi: [0x06]),
      spiTx(start: 400, end: 500, mosi: [0x05]),
      spiTx(start: 600, end: 700, mosi: [0x77]),
    ];
    final out = decode(txs);
    for (final tx in out) {
      expect(
        tx.fields.containsKey('opcode'),
        true,
        reason: 'Missing opcode field on ${tx.label}',
      );
    }
  });

  // ── empty MOSI ────────────────────────────────────────────────────────────────

  test('parent transaction with empty mosi is skipped', () {
    final txs = [
      const DecodedTransaction(
        startTime: 0,
        endTime: 100,
        label: 'SPI',
        fields: {'mosi': ''},
      ),
    ];
    final out = decode(txs);
    expect(out, isEmpty);
  });

  // ── NOP ───────────────────────────────────────────────────────────────────────

  test('NOP (0x00) produces no error', () {
    final txs = [
      spiTx(start: 0, end: 100, mosi: [0x00]),
    ];
    final out = decode(txs);
    expect(out.first.label, 'NOP');
    expect(out.first.isError, false);
  });

  // ── RES (0xAB) ────────────────────────────────────────────────────────────────

  test('RES decodes device_id after 3 default dummy bytes', () {
    // MISO: [opcode echo] [dummy x3] [device_id]
    final txs = [
      spiTx(
        start: 0,
        end: 100,
        mosi: [0xAB],
        miso: [0x00, 0xFF, 0xFF, 0xFF, 0x16],
      ),
    ];
    final out = decode(txs);
    expect(out.first.label, 'RES');
    expect(out.first.fields['device_id'], '0x16');
  });

  // ── WEL cleared after write/erase ────────────────────────────────────────────

  test('WEL is cleared after successful PP, so next PP fails', () {
    final txs = [
      spiTx(start: 0, end: 100, mosi: [0x06]),
      spiTx(start: 200, end: 300, mosi: [0x02, 0x00, 0x00, 0x00, 0xAA]),
      // No second WREN — PP should fail.
      spiTx(start: 400, end: 500, mosi: [0x02, 0x00, 0x10, 0x00, 0xBB]),
    ];
    final out = decode(txs);
    expect(out[1].isError, false); // first PP with WEL
    expect(out[2].isError, true); // second PP without WEL
    expect(out[2].errorMessage, contains('write_without_wel'));
  });

  // ── fixture-driven integration tests ─────────────────────────────────────────
  //
  // Each scenario is reproduced inline (matching what the SPI decoder would
  // produce from the corresponding VCD) and compared against the committed
  // expected_transactions.json companions generated by
  //   dart run tool/generate_spi_flash_fixtures.dart
  //
  // Timing formula: for N bytes → endTime = 10 + N*8*20 + 10
  //   (20 ns/bit SPI period, CS falls at t=10, CS rises 10 ns after last edge)
  // Second CS in a scenario: starts at prevEnd + 100 (inter-transaction gap).

  List<Map<String, dynamic>> loadFixture(String name) {
    final file = File(
      'test/fixtures/protocol/spi_flash/generated/$name.expected_transactions.json',
    );
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'fixture not found at ${file.path}; '
          'regenerate via `dart run tool/generate_spi_flash_fixtures.dart`',
    );
    return (jsonDecode(file.readAsStringSync()) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  void assertMatchesFixture(
    List<DecodedTransaction> actual,
    List<Map<String, dynamic>> expected,
  ) {
    expect(actual, hasLength(expected.length));
    for (var i = 0; i < actual.length; i++) {
      final e = expected[i];
      expect(
        actual[i].startTime,
        e['startTime'] as int,
        reason: 'tx[$i] startTime',
      );
      expect(actual[i].endTime, e['endTime'] as int, reason: 'tx[$i] endTime');
      expect(actual[i].label, e['label'] as String, reason: 'tx[$i] label');
      expect(actual[i].isError, e['isError'] as bool, reason: 'tx[$i] isError');
      final expFields = (e['fields'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as String),
      );
      expect(actual[i].fields, expFields, reason: 'tx[$i] fields');
    }
  }

  group('fixture: spi_flash_rdid', () {
    test('RDID decodes JEDEC ID correctly', () {
      final expected = loadFixture('spi_flash_rdid');
      final txs = [
        spiTx(
          start: 10,
          end: 660,
          mosi: [0x9F, 0x00, 0x00, 0x00],
          miso: [0x00, 0xEF, 0x40, 0x18],
        ),
      ];
      assertMatchesFixture(decode(txs), expected);
    });

    test('RDID label is RDID', () {
      final out = decode([
        spiTx(
          start: 10,
          end: 660,
          mosi: [0x9F, 0x00, 0x00, 0x00],
          miso: [0x00, 0xEF, 0x40, 0x18],
        ),
      ]);
      expect(out.first.label, 'RDID');
      expect(out.first.fields['jedec_id'], '0xEF-0x40-0x18');
    });
  });

  group('fixture: spi_flash_wren_pp', () {
    test('WREN then PP decodes both commands', () {
      final expected = loadFixture('spi_flash_wren_pp');
      final txs = [
        spiTx(start: 10, end: 180, mosi: [0x06], miso: [0x00]),
        spiTx(
          start: 280,
          end: 1250,
          mosi: [0x02, 0x01, 0x20, 0x00, 0xAA, 0xBB],
          miso: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        ),
      ];
      assertMatchesFixture(decode(txs), expected);
    });

    test('PP address is 0x012000 and data is 0xAA 0xBB', () {
      final out = decode([
        spiTx(start: 10, end: 180, mosi: [0x06], miso: [0x00]),
        spiTx(
          start: 280,
          end: 1250,
          mosi: [0x02, 0x01, 0x20, 0x00, 0xAA, 0xBB],
          miso: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        ),
      ]);
      expect(out[1].fields['address'], '0x012000');
      expect(out[1].fields['data'], '0xAA 0xBB');
      expect(out[1].isError, isFalse);
    });
  });

  group('fixture: spi_flash_read', () {
    test('READ decodes address and data correctly', () {
      final expected = loadFixture('spi_flash_read');
      final txs = [
        spiTx(
          start: 10,
          end: 980,
          mosi: [0x03, 0x00, 0x10, 0x00, 0x00, 0x00],
          miso: [0x00, 0x00, 0x00, 0x00, 0x55, 0xAA],
        ),
      ];
      assertMatchesFixture(decode(txs), expected);
    });

    test('READ data bytes are 0x55 0xAA', () {
      final out = decode([
        spiTx(
          start: 10,
          end: 980,
          mosi: [0x03, 0x00, 0x10, 0x00, 0x00, 0x00],
          miso: [0x00, 0x00, 0x00, 0x00, 0x55, 0xAA],
        ),
      ]);
      expect(out.first.fields['data'], '0x55 0xAA');
      expect(out.first.fields['address'], '0x001000');
    });
  });

  group('fixture: spi_flash_wren_se', () {
    test('WREN then SE decodes sector erase at address', () {
      final expected = loadFixture('spi_flash_wren_se');
      final txs = [
        spiTx(start: 10, end: 180, mosi: [0x06], miso: [0x00]),
        spiTx(
          start: 280,
          end: 930,
          mosi: [0x20, 0x01, 0x00, 0x00],
          miso: [0x00, 0x00, 0x00, 0x00],
        ),
      ];
      assertMatchesFixture(decode(txs), expected);
    });
  });

  group('fixture: spi_flash_wel_violation', () {
    test('PP without prior WREN is an error', () {
      final expected = loadFixture('spi_flash_wel_violation');
      final txs = [
        spiTx(
          start: 10,
          end: 820,
          mosi: [0x02, 0x00, 0x00, 0x00, 0xFF],
          miso: [0x00, 0x00, 0x00, 0x00, 0x00],
        ),
      ];
      assertMatchesFixture(decode(txs), expected);
    });

    test('violation errorMessage contains write_without_wel', () {
      final out = decode([
        spiTx(
          start: 10,
          end: 820,
          mosi: [0x02, 0x00, 0x00, 0x00, 0xFF],
          miso: [0x00, 0x00, 0x00, 0x00, 0x00],
        ),
      ]);
      expect(out.first.isError, isTrue);
      expect(out.first.errorMessage, contains('write_without_wel'));
    });
  });

  group('fixture: spi_flash_rdsr', () {
    test('RDSR decodes status register', () {
      final expected = loadFixture('spi_flash_rdsr');
      final txs = [
        spiTx(
          start: 10,
          end: 340,
          mosi: [0x05, 0x00],
          miso: [0x00, 0x02],
        ),
      ];
      assertMatchesFixture(decode(txs), expected);
    });
  });

  group('fixture: spi_flash_fast_read', () {
    test('FAST_READ decodes with dummy byte and data', () {
      final expected = loadFixture('spi_flash_fast_read');
      final txs = [
        spiTx(
          start: 10,
          end: 980,
          mosi: [0x0B, 0x00, 0x20, 0x00, 0x00, 0x00],
          miso: [0x00, 0x00, 0x00, 0x00, 0x00, 0xAB],
        ),
      ];
      assertMatchesFixture(decode(txs), expected);
    });

    test('FAST_READ data byte is 0xAB', () {
      final out = decode([
        spiTx(
          start: 10,
          end: 980,
          mosi: [0x0B, 0x00, 0x20, 0x00, 0x00, 0x00],
          miso: [0x00, 0x00, 0x00, 0x00, 0x00, 0xAB],
        ),
      ]);
      expect(out.first.label, 'FAST_READ');
      expect(out.first.fields['data'], '0xAB');
    });
  });
}
