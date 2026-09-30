// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates a richer I²C bus VCD fixture by running the I2cDecoder
// against a handcrafted timeline.  Packaged as a Flutter test because
// the current Dart 3.12 SDK crashes on `dart run tool/...` scripts
// that transitively import dart:ffi-using packages — see
// generate_spi_fixtures_test.dart for the same workaround.
//
// Run with:
//   flutter test test/tool/generate_i2c_fixtures_test.dart
//
// Output:
//   test/fixtures/protocol/i2c/generated/i2c_full.vcd
//   test/fixtures/protocol/i2c/generated/i2c_full.expected_transactions.json
//   verification/fixtures/protocol/i2c/generated/i2c_full.vcd
//   verification/fixtures/protocol/i2c/generated/i2c_full.expected_transactions.json
//
// Scenarios encoded into i2c_full.vcd (one combined fixture, four
// distinct START-STOP-or-RSTART segments):
//   1. Write 0x42 to 7-bit address 0x50          (ACK address, ACK data)
//   2. Read one byte (0xBE) from 0x50            (ACK address, NACK final byte — normal master-terminates)
//   3. Write 0x77 to 0x55                        (address NACK — no device responds)
//   4. Repeated-START sequence to 0x50:          write 0x10 (ACK), repeated-START,
//                                                read 0xDE (NACK final, normal)
//
// The legacy i2c_basic.vcd remains untouched.

// Test deliberately writes status lines to stdout for tooling use.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/services/decoders/i2c_decoder.dart';

const _testOutDir = 'test/fixtures/protocol/i2c/generated';
const _verificationOutDir = 'verification/fixtures/protocol/i2c/generated';

// SCL period = _sclPeriod ticks (half high, half low).
// SDA changes occur during the SCL-low window; SDA stable during high.
const int _sclPeriod = 40;
const int _sclHigh = _sclPeriod ~/ 2;

void main() {
  test('regenerate I²C fixtures', () {
    Directory(_testOutDir).createSync(recursive: true);
    Directory(_verificationOutDir).createSync(recursive: true);

    // Four logical "segments". Each is a single START-STOP boundary
    // (or START-RSTART-STOP chain when chained=true linking to next).
    final segments = <_Segment>[
      // 1. write 0x42 to 0x50 — clean ack on address + data
      _Segment(
        address7: 0x50,
        rw: 'W',
        addressAcked: true,
        dataBytes: const [0x42],
        dataAcks: const [true],
      ),
      // 2. read one byte from 0x50 — master NACKs final byte (normal)
      _Segment(
        address7: 0x50,
        rw: 'R',
        addressAcked: true,
        dataBytes: const [0xBE],
        dataAcks: const [false],
      ),
      // 3. address NACK on 0x55 write
      _Segment(
        address7: 0x55,
        rw: 'W',
        addressAcked: false,
        dataBytes: const [],
        dataAcks: const [],
      ),
      // 4. repeated-START: write 0x10 to 0x50, RSTART, read 0xDE from 0x50
      _Segment(
        address7: 0x50,
        rw: 'W',
        addressAcked: true,
        dataBytes: const [0x10],
        dataAcks: const [true],
        chainsToRStart: true,
      ),
      _Segment(
        address7: 0x50,
        rw: 'R',
        addressAcked: true,
        dataBytes: const [0xDE],
        dataAcks: const [false],
        precededByRStart: true,
      ),
    ];

    final vcd = _renderVcd(segments);
    final expected = _runDecoder(segments);
    final json = _encodeExpected(expected);

    for (final dir in <String>[_testOutDir, _verificationOutDir]) {
      File('$dir/i2c_full.vcd').writeAsStringSync(vcd);
      File('$dir/i2c_full.expected_transactions.json').writeAsStringSync(json);
    }
    print('  i2c_full.vcd  (${expected.length} transactions)');
    expect(expected, isNotEmpty);
    print('Wrote i2c_full to $_testOutDir/ and $_verificationOutDir/.');
  });
}

class _Segment {
  _Segment({
    required this.address7,
    required this.rw,
    required this.addressAcked,
    required this.dataBytes,
    required this.dataAcks,
    this.chainsToRStart = false,
    this.precededByRStart = false,
  });

  final int address7;
  final String rw; // 'W' or 'R'
  final bool addressAcked;
  final List<int> dataBytes;
  final List<bool> dataAcks;

  /// If true, emit RSTART (instead of STOP) at the end so the next
  /// segment starts inside the same logical transaction.
  final bool chainsToRStart;

  /// If true, this segment begins with RSTART rather than START
  /// (the previous segment's `chainsToRStart` enabled this).
  final bool precededByRStart;
}

class _Event {
  _Event(this.t, this.signal, this.value);

  final int t;
  final String signal; // 'scl' or 'sda'
  final int value; // 0 or 1
}

// Append a list of events to the timeline for a single segment.
// `startTick` is when the START (or initial idle setup) begins.
// Returns the tick at which the segment fully ends (STOP completes
// or RSTART begin transition lands).
({int endTick, List<_Event> events}) _emitSegment(
  _Segment seg,
  int startTick,
) {
  final events = <_Event>[];
  var t = startTick;
  var scl = 1; // I²C idle = both lines high.
  var sda = 1;

  void setScl(int v, int when) {
    if (v == scl) return;
    scl = v;
    events.add(_Event(when, 'scl', v));
  }

  void setSda(int v, int when) {
    if (v == sda) return;
    sda = v;
    events.add(_Event(when, 'sda', v));
  }

  // START (or RSTART): drop SDA while SCL=1.
  // For RSTART, the previous segment ended with the bus poised
  // SCL=1, SDA=1 (we'll lift SDA between segments).
  setSda(0, t);
  t += 10;
  // Bring SCL low to start the bit sequence.
  setScl(0, t);
  t += 10;

  // Build the byte stream: address (with R/W in LSB) followed by data bytes,
  // then ACK after each byte.
  final addressByte = (seg.address7 << 1) | (seg.rw == 'R' ? 1 : 0);
  final byteAcks = <(int, bool)>[(addressByte, seg.addressAcked)];
  // If address NACKed, no further bytes (master gives up).
  if (seg.addressAcked) {
    for (var i = 0; i < seg.dataBytes.length; i++) {
      byteAcks.add((seg.dataBytes[i], seg.dataAcks[i]));
    }
  }

  for (final (byte, ack) in byteAcks) {
    // Emit 8 data bits MSB-first.
    for (var bit = 7; bit >= 0; bit--) {
      final bitVal = (byte >> bit) & 1;
      // SDA change while SCL low — at start of bit period.
      setSda(bitVal, t + 5);
      // SCL rises (sample edge).
      setScl(1, t + 10);
      // SCL falls.
      setScl(0, t + 10 + _sclHigh);
      t += _sclPeriod;
    }
    // Ninth clock = ACK/NACK. ACK = SDA low during SCL high.
    final ackBit = ack ? 0 : 1;
    setSda(ackBit, t + 5);
    setScl(1, t + 10);
    setScl(0, t + 10 + _sclHigh);
    t += _sclPeriod;
  }

  // End of segment: chained to RSTART, or STOP.
  if (seg.chainsToRStart) {
    // Bring both lines high in preparation for the next segment's RSTART.
    // SDA must go high while SCL is low so the next START's "SDA falls
    // while SCL high" condition can be observed.
    setSda(1, t + 5);
    setScl(1, t + 10);
    t += 20;
    // Don't drop SCL — next segment's START will drop SDA, then this
    // segment chain handler will issue setScl(0) again.
  } else {
    // STOP = SDA rises while SCL=1.
    // Force SDA low first if it's currently high (so the rise is visible).
    setSda(0, t + 5);
    setScl(1, t + 10);
    setSda(1, t + 15);
    t += 25;
    // Return SCL to idle high (it already is).
  }

  return (endTick: t, events: events);
}

String _renderVcd(List<_Segment> segments) {
  final buf = StringBuffer()
    ..writeln(r'$timescale 1 ns $end')
    ..writeln(r'$scope module i2c_tb $end')
    ..writeln(r'$var wire 1 ! scl $end')
    ..writeln(r'$var wire 1 " sda $end')
    ..writeln(r'$upscope $end')
    ..writeln(r'$enddefinitions $end')
    ..writeln(r'$dumpvars')
    ..writeln('1!')
    ..writeln('1"')
    ..writeln(r'$end');

  final allEvents = <_Event>[];
  var t = 50;
  for (final seg in segments) {
    final result = _emitSegment(seg, t);
    allEvents.addAll(result.events);
    // 60-tick inter-segment gap (kept short when chained so RSTART
    // detection still finds SDA falling while SCL=1).
    t = result.endTick + (seg.chainsToRStart ? 5 : 60);
  }

  // Emit events to VCD in tick order.
  allEvents.sort((a, b) => a.t.compareTo(b.t));
  int? lastTick;
  for (final e in allEvents) {
    if (e.t != lastTick) {
      buf.writeln('#${e.t}');
      lastTick = e.t;
    }
    final id = e.signal == 'scl' ? '!' : '"';
    buf.writeln('${e.value}$id');
  }
  return buf.toString();
}

List<DecodedTransaction> _runDecoder(List<_Segment> segments) {
  // Reuse _emitSegment to build the same change lists.
  final allEvents = <_Event>[];
  var t = 50;
  for (final seg in segments) {
    final result = _emitSegment(seg, t);
    allEvents.addAll(result.events);
    t = result.endTick + (seg.chainsToRStart ? 5 : 60);
  }
  allEvents.sort((a, b) => a.t.compareTo(b.t));

  final changes = <String, List<(int, String)>>{
    'scl': <(int, String)>[(0, '1')],
    'sda': <(int, String)>[(0, '1')],
  };
  for (final e in allEvents) {
    changes[e.signal]!.add((e.t, '${e.value}'));
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

  const decoder = I2cDecoder(
    DecoderConfig(
      signalBindings: {
        'scl': 'i2c_tb.scl',
        'sda': 'i2c_tb.sda',
      },
      parameters: {'address_bits': '7'},
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
