// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates VCD fixture files and expected_transactions.json companions for
// the SPI Flash stacked decoder. Run from the wavecrux/ root:
//   dart run tool/generate_spi_flash_fixtures.dart
//
// Output (mirrored to both test/ and verification/ trees):
//   test/fixtures/protocol/spi_flash/generated/<scenario>.vcd
//   test/fixtures/protocol/spi_flash/generated/<scenario>.expected_transactions.json
//   verification/fixtures/protocol/spi_flash/generated/<scenario>.vcd
//   verification/fixtures/protocol/spi_flash/generated/<scenario>.expected_transactions.json
//
// Each fixture encodes SPI bus signals at the raw level. The generator:
//   1. Converts each scenario's MOSI/MISO byte sequences into SPI waveform data
//      using the same buildSclk / buildDataLine helpers as the SPI decoder tests.
//   2. Runs the SPI decoder to obtain intermediate parent transactions.
//   3. Runs the SPI flash decoder on those transactions to produce the expected
//      flash-level output.
//   4. Serialises both the VCD waveform and the flash decoder output to disk.
//
// The expected JSON is therefore always *consistent* with the decoder
// implementation — the test file then asserts hand-verified anchor points
// (labels, transaction counts, error flags, key field values) so that a silent
// regression in decoder output is still caught.
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';
import 'package:wavecrux/services/decoders/spi_flash/spi_flash_decoder.dart';

const _testOutDir = 'test/fixtures/protocol/spi_flash/generated';
const _verificationOutDir =
    'verification/fixtures/protocol/spi_flash/generated';

// ── scenario model ────────────────────────────────────────────────────────────

class _SpiTx {
  const _SpiTx(this.mosi, this.miso);
  final List<int> mosi;
  final List<int> miso;
}

class _Scenario {
  const _Scenario(
    this.name,
    this.transactions,
  );
  final String name;
  final List<_SpiTx> transactions;

  /// Fixed: every scenario generates the generic vendor preset.
  /// Was a constructor parameter no caller ever overrode, which the
  /// analyzer only reported once tool/ stopped being excluded.
  String get vendorPreset => 'generic';
}

// ── fixture scenarios ─────────────────────────────────────────────────────────

const _scenarios = <_Scenario>[
  // 1. RDID — read JEDEC ID (Winbond W25Q128: 0xEF 0x40 0x18)
  _Scenario('spi_flash_rdid', [
    _SpiTx([0x9F, 0x00, 0x00, 0x00], [0x00, 0xEF, 0x40, 0x18]),
  ]),

  // 2. WREN followed by PP (page program) with 24-bit address
  _Scenario('spi_flash_wren_pp', [
    _SpiTx([0x06], [0x00]),
    _SpiTx(
      [0x02, 0x01, 0x20, 0x00, 0xAA, 0xBB],
      [0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    ),
  ]),

  // 3. READ with 24-bit address, 2 data bytes returned
  _Scenario('spi_flash_read', [
    _SpiTx(
      [0x03, 0x00, 0x10, 0x00, 0x00, 0x00],
      [0x00, 0x00, 0x00, 0x00, 0x55, 0xAA],
    ),
  ]),

  // 4. WREN followed by SE (sector erase) with 24-bit address
  _Scenario('spi_flash_wren_se', [
    _SpiTx([0x06], [0x00]),
    _SpiTx([0x20, 0x01, 0x00, 0x00], [0x00, 0x00, 0x00, 0x00]),
  ]),

  // 5. PP without prior WREN → write_without_wel violation
  _Scenario('spi_flash_wel_violation', [
    _SpiTx([0x02, 0x00, 0x00, 0x00, 0xFF], [0x00, 0x00, 0x00, 0x00, 0x00]),
  ]),

  // 6. RDSR — read status register, WEL bit set (status = 0x02)
  _Scenario('spi_flash_rdsr', [
    _SpiTx([0x05, 0x00], [0x00, 0x02]),
  ]),

  // 7. FAST_READ (0x0B) with 24-bit address, 1 default dummy byte, 1 data byte
  _Scenario('spi_flash_fast_read', [
    _SpiTx(
      [0x0B, 0x00, 0x20, 0x00, 0x00, 0x00],
      [0x00, 0x00, 0x00, 0x00, 0x00, 0xAB],
    ),
  ]),
];

// ── VCD generation ────────────────────────────────────────────────────────────

// SPI timing: 20 ns per bit period, rising edge at offset 10, data setup at +5.
const _period = 20;
const _setupOffset = 5;

/// Converts a byte to MSB-first bit list.
List<int> _msbBits(int byte) => List.generate(8, (i) => (byte >> (7 - i)) & 1);

/// Returns signal-change lists for all four SPI signals across a list of
/// back-to-back CS transactions. Transactions are separated by a 100 ns gap.
Map<String, List<(int, String)>> _buildSignalChanges(List<_SpiTx> txs) {
  final sclk = <(int, String)>[];
  final mosi = <(int, String)>[];
  final miso = <(int, String)>[];
  final cs = <(int, String)>[];

  var t = 10; // start time for first CS assertion
  var mosiState = '0';
  var misoState = '0';

  for (final tx in txs) {
    assert(
      tx.mosi.length == tx.miso.length,
      'MOSI and MISO must have equal length',
    );
    final bits = tx.mosi.length * 8;

    // CS falls
    cs.add((t, '0'));

    // Drive first MOSI/MISO bit 5 ns before the first rising edge
    final firstMosi = _msbBits(tx.mosi[0])[0] == 1 ? '1' : '0';
    final firstMiso = _msbBits(tx.miso[0])[0] == 1 ? '1' : '0';
    if (firstMosi != mosiState) {
      mosi.add((t + _period ~/ 2 - _setupOffset, firstMosi));
      mosiState = firstMosi;
    }
    if (firstMiso != misoState) {
      miso.add((t + _period ~/ 2 - _setupOffset, firstMiso));
      misoState = firstMiso;
    }

    // Clock and data transitions for each bit
    for (var bid = 0; bid < bits; bid++) {
      final rise = t + bid * _period + _period ~/ 2;
      final fall = t + bid * _period + _period;

      sclk
        ..add((rise, '1'))
        ..add((fall, '0'));

      // Drive next bit's data 5 ns after falling edge
      if (bid + 1 < bits) {
        final nextBid = bid + 1;
        final nextByteIdx = nextBid ~/ 8;
        final nextBitInByte = 7 - (nextBid % 8);

        final nextMosi =
            (_msbBits(tx.mosi[nextByteIdx])[7 - nextBitInByte]) == 1
            ? '1'
            : '0';
        final nextMiso =
            (_msbBits(tx.miso[nextByteIdx])[7 - nextBitInByte]) == 1
            ? '1'
            : '0';

        final driveTime = fall + _setupOffset;
        if (nextMosi != mosiState) {
          mosi.add((driveTime, nextMosi));
          mosiState = nextMosi;
        }
        if (nextMiso != misoState) {
          miso.add((driveTime, nextMiso));
          misoState = nextMiso;
        }
      }
    }

    // CS rises 10 ns after last falling edge
    final csEnd = t + bits * _period + 10;
    cs.add((csEnd, '1'));

    // Gap between transactions
    t = csEnd + 100;
  }

  return {
    'sclk': sclk,
    'mosi': mosi,
    'miso': miso,
    'cs': cs,
  };
}

String _renderVcd(_Scenario s) {
  final changes = _buildSignalChanges(s.transactions);
  final allTimes = <int>{
    for (final list in changes.values)
      for (final (t, _) in list) t,
  }.toList()..sort();

  final buf = StringBuffer();
  buf.writeln(r'$timescale 1 ns $end');
  buf.writeln(r'$scope module spi_flash_tb $end');
  buf.writeln(r'$var wire 1 ! sclk $end');
  buf.writeln(r'$var wire 1 " mosi $end');
  buf.writeln(r'$var wire 1 # miso $end');
  buf.writeln(r'$var wire 1 % cs $end');
  buf.writeln(r'$upscope $end');
  buf.writeln(r'$enddefinitions $end');
  buf.writeln(r'$dumpvars');
  buf.writeln('0!');
  buf.writeln('0"');
  buf.writeln('0#');
  buf.writeln('1%');
  buf.writeln(r'$end');

  // Encode scenario as a comment for human readers.
  buf.writeln(r'$comment');
  buf.writeln('  Fixture: ${s.name}');
  for (var i = 0; i < s.transactions.length; i++) {
    final tx = s.transactions[i];
    final mosiHex = tx.mosi
        .map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}')
        .join(' ');
    final misoHex = tx.miso
        .map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}')
        .join(' ');
    buf.writeln('  Transaction ${i + 1}: MOSI=[$mosiHex]  MISO=[$misoHex]');
  }
  buf.writeln(r'$end');

  for (final t in allTimes) {
    buf.writeln('#$t');
    for (final (sig, id) in [
      ('sclk', '!'),
      ('mosi', '"'),
      ('miso', '#'),
      ('cs', '%'),
    ]) {
      for (final (ct, cv) in (changes[sig] ?? [])) {
        if (ct == t) buf.writeln('$cv$id');
      }
    }
  }

  return buf.toString();
}

// ── decoder execution ─────────────────────────────────────────────────────────

/// Converts change lists into [SignalValueQuery] / [SignalChangesQuery] pair.
(SignalValueQuery, SignalChangesQuery) _makeQueries(
  Map<String, List<(int, String)>> changes,
) {
  // value-at-time maps (last-value semantics)
  final valueMaps = <String, Map<int, String>>{};
  for (final entry in changes.entries) {
    final m = <int, String>{0: entry.key == 'cs' ? '1' : '0'};
    for (final (t, v) in entry.value) {
      m[t] = v;
    }
    valueMaps[entry.key] = m;
  }

  SignalValueQuery query = (name, time) {
    final m = valueMaps[name];
    if (m == null) return null;
    int? latest;
    for (final t in m.keys) {
      if (t <= time && (latest == null || t > latest)) latest = t;
    }
    return latest == null ? null : m[latest];
  };

  SignalChangesQuery changesQuery = (name, start, end) {
    final list = changes[name] ?? [];
    return list.where((c) => c.$1 >= start && c.$1 < end).toList();
  };

  return (query, changesQuery);
}

List<DecodedTransaction> _runDecoders(_Scenario s) {
  final changes = _buildSignalChanges(s.transactions);
  final (query, changesQuery) = _makeQueries(changes);

  // Determine time range from CS changes
  final csTimes = changes['cs']!.map((c) => c.$1).toList();
  final endTime = csTimes.isEmpty ? 1000 : csTimes.last + 200;

  // Step 1: run SPI decoder
  final spiDecoder = SpiDecoder(
    const DecoderConfig(
      signalBindings: {
        'sclk': 'sclk',
        'mosi': 'mosi',
        'miso': 'miso',
        'cs': 'cs',
      },
      parameters: {
        'cpol': '0',
        'cpha': '0',
        'bit_order': 'msb',
        'word_size': 8,
        'cs_active_level': '0',
      },
    ),
  );

  final spiTxs = spiDecoder.decode(0, endTime, query, changesQuery);

  // Step 2: run SPI flash decoder on the SPI output
  final flashDecoder = SpiFlashDecoder(
    DecoderConfig(
      signalBindings: const {},
      parameters: {'vendor_preset': s.vendorPreset, 'address_width': '24'},
    ),
  );

  return flashDecoder.decodeStacked(spiTxs, 0, endTime, query, changesQuery);
}

String _encodeExpected(List<DecodedTransaction> txs) {
  final list = txs
      .map(
        (tx) => {
          'startTime': tx.startTime,
          'endTime': tx.endTime,
          'label': tx.label,
          'fields': tx.fields,
          'isError': tx.isError,
          'errorMessage': tx.errorMessage,
        },
      )
      .toList();
  return const JsonEncoder.withIndent('  ').convert(list);
}

// ── main ──────────────────────────────────────────────────────────────────────

void main() {
  Directory(_testOutDir).createSync(recursive: true);
  Directory(_verificationOutDir).createSync(recursive: true);

  for (final s in _scenarios) {
    final vcd = _renderVcd(s);
    final txs = _runDecoders(s);
    final json = _encodeExpected(txs);

    for (final dir in [_testOutDir, _verificationOutDir]) {
      File('$dir/${s.name}.vcd').writeAsStringSync(vcd);
      File('$dir/${s.name}.expected_transactions.json').writeAsStringSync(json);
    }

    print('✓ ${s.name}: ${txs.length} flash transaction(s)');
    for (final tx in txs) {
      final errStr = tx.isError ? ' [ERROR: ${tx.errorMessage}]' : '';
      print('    ${tx.label} t=${tx.startTime}..${tx.endTime}$errStr');
    }
  }

  print('\nFixtures written to ${_testOutDir} and $_verificationOutDir');
}
