// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates a UART parity-error fixture by running the UartDecoder
// against a handcrafted timeline.  Packaged as a Flutter test for the
// same reason as the SPI/I²C generators — see
// generate_spi_fixtures_test.dart.
//
// Run with:
//   flutter test test/tool/generate_uart_fixtures_test.dart
//
// Output:
//   test/fixtures/protocol/uart/generated/uart_parity.vcd
//   test/fixtures/protocol/uart/generated/uart_parity.expected_transactions.json
//   verification/fixtures/protocol/uart/generated/uart_parity.vcd
//   verification/fixtures/protocol/uart/generated/uart_parity.expected_transactions.json
//
// Scenarios in uart_parity.vcd (one TX channel, 1 Mbaud, 8N1+even parity):
//   1. 'A' (0x41) — even parity correct (passes)
//   2. 'B' (0x42) — even parity DELIBERATELY WRONG (parity-error byte)
//
// The decoder reports the parity-error byte as `isError: true` with
// `errorMessage: "Parity error"`.
//
// The legacy uart_basic.vcd (framing-error case) remains untouched.

// Test deliberately writes status lines to stdout for tooling use.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/services/decoders/uart_decoder.dart';

const _testOutDir = 'test/fixtures/protocol/uart/generated';
const _verificationOutDir = 'verification/fixtures/protocol/uart/generated';

// 1 Mbaud (matches legacy uart_basic.vcd timing).
const int _baudRate = 1000000;
// Tick period = 1 ns. So 1 bit = 1e9 / 1e6 = 1000 ticks/bit.
const int _bitPeriod = 1000;

void main() {
  test('regenerate UART parity fixture', () {
    Directory(_testOutDir).createSync(recursive: true);
    Directory(_verificationOutDir).createSync(recursive: true);

    final frames = <_Frame>[
      // Byte 'A' (0x41) — even parity correct.
      _Frame(byte: 0x41, channel: 'tx', forceWrongParity: false),
      // 4-bit-period idle gap.
      // Byte 'B' (0x42) — even parity flipped (decoder must flag).
      _Frame(byte: 0x42, channel: 'tx', forceWrongParity: true),
    ];

    final vcd = _renderVcd(frames);
    final expected = _runDecoder(frames);
    final json = _encodeExpected(expected);

    for (final dir in <String>[_testOutDir, _verificationOutDir]) {
      File('$dir/uart_parity.vcd').writeAsStringSync(vcd);
      File(
        '$dir/uart_parity.expected_transactions.json',
      ).writeAsStringSync(json);
    }
    print('  uart_parity.vcd  (${expected.length} transactions)');
    for (final tx in expected) {
      print(
        '    ${tx.label}'
        '${tx.isError ? "  [${tx.errorMessage}]" : ""}',
      );
    }
    expect(expected, isNotEmpty);
    print('Wrote uart_parity to $_testOutDir/ and $_verificationOutDir/.');
  });
}

class _Frame {
  _Frame({
    required this.byte,
    required this.channel,
    required this.forceWrongParity,
  });

  final int byte;
  final String channel; // 'tx' or 'rx' — only 'tx' used here.
  final bool forceWrongParity;
}

/// Emits a UART frame onto a signal trace:
///   start(0) + 8 data bits LSB-first + parity bit + stop(1)
/// where parity is forced wrong when [forceWrongParity] is set.
List<(int, int)> _emitFrame(_Frame frame, int startTick) {
  // Start bit: line falls to 0 at startTick.
  final out = <(int, int)>[(startTick, 0)];

  // 8 data bits LSB-first.
  var parityCount = 0;
  for (var bit = 0; bit < 8; bit++) {
    final v = (frame.byte >> bit) & 1;
    final t = startTick + (bit + 1) * _bitPeriod;
    out.add((t, v));
    parityCount += v;
  }

  // Parity bit (even parity). Correct: chosen so total ones (data + parity)
  // is even. Wrong: invert the chosen parity bit.
  final correctParity = parityCount % 2;
  final parityBit = frame.forceWrongParity ? 1 - correctParity : correctParity;
  out
    ..add((startTick + 9 * _bitPeriod, parityBit))
    // Stop bit (1).
    ..add((startTick + 10 * _bitPeriod, 1));

  return out;
}

String _renderVcd(List<_Frame> frames) {
  final buf = StringBuffer()
    ..writeln(r'$timescale 1ns $end')
    ..writeln(r'$scope module tb $end')
    ..writeln(r'$var wire 1 ! tx $end')
    ..writeln(r'$var wire 1 " rx $end')
    ..writeln(r'$upscope $end')
    ..writeln(r'$enddefinitions $end')
    ..writeln(r'$dumpvars')
    ..writeln('1!')
    ..writeln('1"')
    ..writeln(r'$end');

  // 1000-tick lead-in so the first start bit isn't at t=0.
  var t = 1000;
  final allEvents = <(int, int, String)>[]; // (tick, value, signal)
  for (final f in frames) {
    final frameEvents = _emitFrame(f, t);
    for (final (tick, v) in frameEvents) {
      allEvents.add((tick, v, f.channel));
    }
    // 4-bit-period gap before next frame.
    t += 11 * _bitPeriod + 4 * _bitPeriod;
  }

  allEvents.sort((a, b) => a.$1.compareTo(b.$1));
  var lastTick = -1;
  // Track per-signal last value to skip duplicates.
  final lastVal = <String, int>{'tx': 1, 'rx': 1};
  for (final (tick, v, sig) in allEvents) {
    if (lastVal[sig] == v) continue;
    lastVal[sig] = v;
    if (tick != lastTick) {
      buf.writeln('#$tick');
      lastTick = tick;
    }
    final id = sig == 'tx' ? '!' : '"';
    buf.writeln('$v$id');
  }
  return buf.toString();
}

List<DecodedTransaction> _runDecoder(List<_Frame> frames) {
  // Build the same change lists as _emitFrame produced.
  final changes = <String, List<(int, String)>>{
    'tx': <(int, String)>[(0, '1')],
    'rx': <(int, String)>[(0, '1')],
  };

  void add(String sig, int t, int v) {
    final list = changes[sig]!;
    if (list.isNotEmpty && list.last.$2 == '$v') return;
    list.add((t, '$v'));
  }

  var t = 1000;
  for (final f in frames) {
    final frameEvents = _emitFrame(f, t);
    for (final (tick, v) in frameEvents) {
      add(f.channel, tick, v);
    }
    t += 11 * _bitPeriod + 4 * _bitPeriod;
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

  const decoder = UartDecoder(
    DecoderConfig(
      signalBindings: {
        'tx': 'tb.tx',
        'rx': 'tb.rx',
      },
      parameters: {
        'baud_rate': _baudRate,
        'data_bits': 8,
        'parity': 'even',
        'stop_bits': '1',
      },
    ),
  );
  return decoder.decode(0, t + 1000, query, changesQuery);
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
