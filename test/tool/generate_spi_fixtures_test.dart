// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates richer SPI bus VCD fixtures by running the SpiDecoder
// against handcrafted timelines. Packaged as a Flutter test rather
// than a `dart run tool/...` script because the current Dart 3.12 SDK
// crashes when AOT-compiling tool scripts that transitively import
// dart:ffi-using packages.
//
// Run with:
//   flutter test test/tool/generate_spi_fixtures_test.dart
//
// Output (mirrored to both test/ and verification/ trees):
//   test/fixtures/protocol/spi/generated/<scenario>.vcd
//   test/fixtures/protocol/spi/generated/<scenario>.expected_transactions.json
//   verification/fixtures/protocol/spi/generated/<scenario>.vcd
//   verification/fixtures/protocol/spi/generated/<scenario>.expected_transactions.json
//
// Generated fixtures:
//   spi_mode0.vcd  CPOL=0 CPHA=0 — idle low, sample on rising
//   spi_mode1.vcd  CPOL=0 CPHA=1 — idle low, sample on falling
//   spi_mode2.vcd  CPOL=1 CPHA=0 — idle high, sample on falling
//   spi_mode3.vcd  CPOL=1 CPHA=1 — idle high, sample on rising
//   spi_glitch.vcd CPOL=0 CPHA=0 with one MOSI change exactly on a
//                  sample edge — exercises the decoder's glitch detector.
//
// The legacy spi_basic.vcd (handcrafted, two Mode-0 transactions) is
// preserved untouched so existing hardcoded test arrays still pass.

// Generator emits a one-line status print per fixture; quietening it
// would lose useful CI output. Print is intentional for tooling.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';

const _testOutDir = 'test/fixtures/protocol/spi/generated';
const _verificationOutDir = 'verification/fixtures/protocol/spi/generated';

// Each bit takes _bitPeriod ticks. Within a bit period, SCLK toggles
// twice (active edge at _bitPeriod/2, return-to-idle at _bitPeriod).
// MOSI/MISO are driven _setup ticks before each sample edge.
const _bitPeriod = 20;
const _setup = 5;

void main() {
  test('regenerate SPI fixtures', () {
    Directory(_testOutDir).createSync(recursive: true);
    Directory(_verificationOutDir).createSync(recursive: true);

    final scenarios = <_Scenario>[
      _modeScenario(0, [0xA5, 0x3C], [0x5A, 0xC3]),
      _modeScenario(1, [0xDE, 0xAD], [0xBE, 0xEF]),
      _modeScenario(2, [0x12, 0x34], [0x56, 0x78]),
      _modeScenario(3, [0xFF, 0x00], [0xAA, 0x55]),
      _glitchScenario(),
    ];

    for (final s in scenarios) {
      final vcd = _renderVcd(s);
      final expected = _runDecoder(s);
      final json = _encodeExpected(expected);
      for (final dir in <String>[_testOutDir, _verificationOutDir]) {
        File('$dir/${s.name}.vcd').writeAsStringSync(vcd);
        File(
          '$dir/${s.name}.expected_transactions.json',
        ).writeAsStringSync(json);
      }
      // Always emit at least one transaction.
      expect(
        expected,
        isNotEmpty,
        reason: 'scenario ${s.name} should yield ≥1 transaction',
      );
      print('  ${s.name}.vcd  (${expected.length} transactions)');
    }
    print(
      'Wrote ${scenarios.length} scenarios to '
      '$_testOutDir/ and $_verificationOutDir/.',
    );
  });
}

class _Scenario {
  _Scenario({
    required this.name,
    required this.cpol,
    required this.cpha,
    required this.transactions,
  });

  final String name;
  final int cpol;
  final int cpha;
  final List<_Tx> transactions;
}

class _Tx {
  _Tx({
    required this.mosi,
    required this.miso,
    this.glitchBit,
  });

  final List<int> mosi;
  final List<int> miso;
  final int? glitchBit;
}

_Scenario _modeScenario(int mode, List<int> mosiTx, List<int> misoTx) {
  final cpol = (mode == 2 || mode == 3) ? 1 : 0;
  final cpha = (mode == 1 || mode == 3) ? 1 : 0;
  return _Scenario(
    name: 'spi_mode$mode',
    cpol: cpol,
    cpha: cpha,
    transactions: [
      _Tx(mosi: [mosiTx[0]], miso: [misoTx[0]]),
      _Tx(mosi: mosiTx, miso: misoTx),
    ],
  );
}

_Scenario _glitchScenario() {
  return _Scenario(
    name: 'spi_glitch',
    cpol: 0,
    cpha: 0,
    transactions: [
      _Tx(mosi: [0xA5], miso: [0x5A]),
      _Tx(mosi: [0xC3], miso: [0x3C], glitchBit: 3),
    ],
  );
}

String _renderVcd(_Scenario s) {
  final buf = StringBuffer()
    ..writeln(r'$timescale 1 ns $end')
    ..writeln(r'$scope module spi_tb $end')
    ..writeln(r'$var wire 1 ! sclk $end')
    ..writeln(r'$var wire 1 " mosi $end')
    ..writeln(r'$var wire 1 # miso $end')
    ..writeln(r'$var wire 1 % cs $end')
    ..writeln(r'$upscope $end')
    ..writeln(r'$enddefinitions $end')
    ..writeln(r'$dumpvars')
    ..writeln('${s.cpol}!')
    ..writeln('0"')
    ..writeln('0#')
    ..writeln('1%')
    ..writeln(r'$end');

  var t = 10;
  for (final tx in s.transactions) {
    t = _emitTransaction(buf, s, tx, t);
    t += 10;
  }
  return buf.toString();
}

int _emitTransaction(StringBuffer buf, _Scenario s, _Tx tx, int startTick) {
  buf
    ..writeln('#$startTick')
    ..writeln('0%');

  var t = startTick;
  for (var byteIdx = 0; byteIdx < tx.mosi.length; byteIdx++) {
    final mosiByte = tx.mosi[byteIdx];
    final misoByte = tx.miso[byteIdx];
    for (var bit = 7; bit >= 0; bit--) {
      final bitGlobalIdx = byteIdx * 8 + (7 - bit);
      final mosiBit = (mosiByte >> bit) & 1;
      final misoBit = (misoByte >> bit) & 1;
      final isGlitchBit = tx.glitchBit == bitGlobalIdx;

      final firstEdgeTick = t + _bitPeriod ~/ 2;
      final secondEdgeTick = t + _bitPeriod;
      final sampleEdgeTick = s.cpha == 0 ? firstEdgeTick : secondEdgeTick;
      final driveTick = sampleEdgeTick - _setup;

      buf
        ..writeln('#$driveTick')
        ..writeln('$mosiBit"')
        ..writeln('$misoBit#');

      final firstEdgeVal = s.cpol == 0 ? 1 : 0;
      final secondEdgeVal = s.cpol;
      buf
        ..writeln('#$firstEdgeTick')
        ..writeln('$firstEdgeVal!');

      if (isGlitchBit && sampleEdgeTick == firstEdgeTick) {
        final flipped = 1 - mosiBit;
        buf
          ..writeln('#$sampleEdgeTick')
          ..writeln('$flipped"');
      }

      buf
        ..writeln('#$secondEdgeTick')
        ..writeln('$secondEdgeVal!');

      if (isGlitchBit && sampleEdgeTick == secondEdgeTick) {
        final flipped = 1 - mosiBit;
        buf
          ..writeln('#$sampleEdgeTick')
          ..writeln('$flipped"');
      }

      t += _bitPeriod;
    }
  }

  buf
    ..writeln('#$t')
    ..writeln('1%');
  return t;
}

List<DecodedTransaction> _runDecoder(_Scenario s) {
  final changes = <String, List<(int, String)>>{
    'sclk': <(int, String)>[(0, '${s.cpol}')],
    'mosi': <(int, String)>[(0, '0')],
    'miso': <(int, String)>[(0, '0')],
    'cs': <(int, String)>[(0, '1')],
  };

  void add(String sig, int t, String v) {
    final list = changes[sig]!;
    if (list.isNotEmpty && list.last.$2 == v) return;
    list.add((t, v));
  }

  var t = 10;
  for (final tx in s.transactions) {
    add('cs', t, '0');
    for (var byteIdx = 0; byteIdx < tx.mosi.length; byteIdx++) {
      final mosiByte = tx.mosi[byteIdx];
      final misoByte = tx.miso[byteIdx];
      for (var bit = 7; bit >= 0; bit--) {
        final bitGlobalIdx = byteIdx * 8 + (7 - bit);
        final mosiBit = (mosiByte >> bit) & 1;
        final misoBit = (misoByte >> bit) & 1;
        final isGlitchBit = tx.glitchBit == bitGlobalIdx;

        final firstEdgeTick = t + _bitPeriod ~/ 2;
        final secondEdgeTick = t + _bitPeriod;
        final sampleEdgeTick = s.cpha == 0 ? firstEdgeTick : secondEdgeTick;
        final driveTick = sampleEdgeTick - _setup;

        add('mosi', driveTick, '$mosiBit');
        add('miso', driveTick, '$misoBit');

        final firstEdgeVal = s.cpol == 0 ? 1 : 0;
        final secondEdgeVal = s.cpol;
        add('sclk', firstEdgeTick, '$firstEdgeVal');
        if (isGlitchBit && sampleEdgeTick == firstEdgeTick) {
          final flipped = 1 - mosiBit;
          add('mosi', sampleEdgeTick, '$flipped');
        }
        add('sclk', secondEdgeTick, '$secondEdgeVal');
        if (isGlitchBit && sampleEdgeTick == secondEdgeTick) {
          final flipped = 1 - mosiBit;
          add('mosi', sampleEdgeTick, '$flipped');
        }

        t += _bitPeriod;
      }
    }
    add('cs', t, '1');
    t += 10;
  }

  final valueMap = <String, Map<int, String>>{
    for (final entry in changes.entries)
      entry.key: {for (final c in entry.value) c.$1: c.$2},
  };

  String? query(String name, int time) {
    final m = valueMap[name];
    if (m == null) return null;
    int? latest;
    for (final k in m.keys) {
      if (k <= time && (latest == null || k > latest)) latest = k;
    }
    return latest == null ? null : m[latest];
  }

  List<(int, String)> changesQuery(String name, int start, int end) {
    final list = changes[name] ?? const <(int, String)>[];
    return list.where((c) => c.$1 >= start && c.$1 < end).toList();
  }

  final decoder = SpiDecoder(
    DecoderConfig(
      signalBindings: const {
        'sclk': 'spi_tb.sclk',
        'mosi': 'spi_tb.mosi',
        'miso': 'spi_tb.miso',
        'cs': 'spi_tb.cs',
      },
      parameters: {
        'cpol': '${s.cpol}',
        'cpha': '${s.cpha}',
        'bit_order': 'msb',
        'word_size': 8,
        'cs_active_level': '0',
      },
    ),
  );

  return decoder.decode(0, t + 100, query, changesQuery);
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
