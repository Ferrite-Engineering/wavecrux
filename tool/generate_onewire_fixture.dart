// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates the canonical 1-Wire fixture used by the decoder-plugin
// loader's round-trip integration test and by the demonstrator README's
// "verify the plugin loaded" step.
//
// Output:
//   examples/decoder-plugin-demo/fixtures/onewire_basic.vcd
//   examples/decoder-plugin-demo/fixtures/onewire_basic.expected_transactions.json
//   test/fixtures/decoder_plugins/onewire/onewire_basic.vcd
//   test/fixtures/decoder_plugins/onewire/onewire_basic.expected_transactions.json
//
// Usage:
//   dart run tool/generate_onewire_fixture.dart
//
// The fixture encodes a deterministic DS18B20-style sequence:
//   1. RESET pulse (480 µs low)
//   2. PRESENCE pulse (120 µs low, 50 µs after master release)
//   3. WRITE byte 0x33 (READ_ROM command, LSB-first: 1,1,0,0,1,1,0,0)
//   4. READ byte 0x28 (DS18B20 family code, LSB-first: 0,0,0,1,0,1,0,0)
//
// Each bit slot is 70 µs total: master pulls low for 6 µs (write 1 /
// read X) or 60 µs (write 0), recovery for the remainder.
//
// Timestamps are emitted in 1 ns ticks (the VCD timescale); the
// demonstrator decoder receives them in fs after the loader's
// fs-per-tick conversion.

// Tooling scripts emit progress to stdout via direct `print` calls so
// developers re-running the generator see what was produced; the
// `avoid_print` lint is intended for production code, not one-shot
// fixture-regeneration tools.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

const _examplesOutDir = 'examples/decoder-plugin-demo/fixtures';
const _testOutDir = 'test/fixtures/decoder_plugins/onewire';

// All durations in nanoseconds (matches the 1 ns VCD timescale).
const _resetLowNs = 480 * 1000;
const _presenceGapNs = 50 * 1000;
const _presenceLowNs = 120 * 1000;
const _interByteGapNs = 60 * 1000;
const _bitSlotNs = 70 * 1000;
const _bitOneLowNs = 6 * 1000;
const _bitZeroLowNs = 60 * 1000;

void main() {
  Directory(_examplesOutDir).createSync(recursive: true);
  Directory(_testOutDir).createSync(recursive: true);

  final scenario = _buildScenario();

  for (final dir in <String>[_examplesOutDir, _testOutDir]) {
    File('$dir/onewire_basic.vcd').writeAsStringSync(scenario.vcd);
    File(
      '$dir/onewire_basic.expected_transactions.json',
    ).writeAsStringSync(scenario.expectedJson);
  }

  print('Generated 1-Wire fixtures:');
  print('  $_examplesOutDir/onewire_basic.vcd');
  print('  $_examplesOutDir/onewire_basic.expected_transactions.json');
  print('  $_testOutDir/onewire_basic.vcd');
  print('  $_testOutDir/onewire_basic.expected_transactions.json');
}

class _Scenario {
  _Scenario({required this.vcd, required this.expectedJson});
  final String vcd;
  final String expectedJson;
}

_Scenario _buildScenario() {
  final builder = _OneWireBuilder();

  // 1. Idle for 100 µs so the simulation doesn't start mid-edge.
  builder.idleFor(100 * 1000);

  // 2. RESET pulse: master pulls DQ low for 480 µs.
  final resetStart = builder.now;
  builder.driveLowFor(_resetLowNs);
  final resetEnd = builder.now;

  // 3. Master release gap: 50 µs idle high before slave responds.
  builder.idleFor(_presenceGapNs);

  // 4. PRESENCE pulse: slave drives low for 120 µs.
  final presenceStart = builder.now;
  builder.driveLowFor(_presenceLowNs);
  final presenceEnd = builder.now;

  // 5. Inter-byte gap: 60 µs idle.
  builder.idleFor(_interByteGapNs);

  // 6. WRITE 0x33 — LSB-first bit pattern.
  final writeByteStart = builder.now;
  const writeByteValue = 0x33;
  for (var i = 0; i < 8; i++) {
    final bit = (writeByteValue >> i) & 1;
    builder.bitSlot(isOne: bit == 1);
  }
  final writeByteEnd = builder.now;

  // 7. Inter-byte gap.
  builder.idleFor(_interByteGapNs);

  // 8. READ 0x28 — same bit-slot timings (passive observer can't
  //    distinguish master-write from slave-read).
  final readByteStart = builder.now;
  const readByteValue = 0x28;
  for (var i = 0; i < 8; i++) {
    final bit = (readByteValue >> i) & 1;
    builder.bitSlot(isOne: bit == 1);
  }
  final readByteEnd = builder.now;

  // 9. Tail-end idle so the parser sees a clean dump termination.
  builder.idleFor(50 * 1000);

  // Assemble the canonical expected-transactions JSON.
  // Timestamps are in ticks of the 1 ns VCD timescale, the unit every
  // decoded transaction is placed in. The plugin itself sees and returns
  // femtoseconds; the loader converts both ways.
  final expected = <Map<String, dynamic>>[
    {
      'startTime': resetStart,
      'endTime': resetEnd,
      'label': 'RESET',
      'fields': {'kind': 'reset'},
      'isError': false,
    },
    {
      'startTime': presenceStart,
      'endTime': presenceEnd,
      'label': 'PRESENCE',
      'fields': {'kind': 'presence', 'valid': 'true'},
      'isError': false,
    },
    {
      'startTime': writeByteStart,
      'endTime': writeByteEnd,
      'label': 'BYTE 0x33',
      'fields': {'value': '0x33', 'bits': '8'},
      'isError': false,
    },
    {
      'startTime': readByteStart,
      'endTime': readByteEnd,
      'label': 'BYTE 0x28',
      'fields': {'value': '0x28', 'bits': '8'},
      'isError': false,
    },
  ];

  // The decoder emits a BYTE transaction whose end-time is the last
  // bit's rising edge, not the slot completion. Patch the expected
  // entries to match the decoder's emission semantics — see the
  // README's transaction table.
  expected[2]['endTime'] = builder.lastWriteByteEndNs;
  expected[3]['endTime'] = builder.lastReadByteEndNs;

  return _Scenario(
    vcd: builder.toVcd(),
    expectedJson: const JsonEncoder.withIndent('  ').convert(expected),
  );
}

/// Helper that walks the simulation timeline and accumulates VCD
/// value-change records, mirroring the master/slave drive pattern of
/// a real 1-Wire bus. The line is open-drain idle-high.
class _OneWireBuilder {
  int now = 0;
  bool _level = true; // idle high
  final StringBuffer _changes = StringBuffer();
  bool _firstWriteByteSlot = true;
  bool _firstReadByteSlot = true;
  int lastWriteByteEndNs = 0;
  int lastReadByteEndNs = 0;
  int _byteSlotCount = 0;

  void _setLevel(bool newLevel) {
    if (_level == newLevel) return;
    _level = newLevel;
    _changes.writeln('#$now');
    _changes.writeln('${newLevel ? 1 : 0}!');
  }

  void idleFor(int durationNs) {
    if (!_level) {
      _setLevel(true);
    }
    now += durationNs;
  }

  void driveLowFor(int lowDurationNs) {
    _setLevel(false);
    now += lowDurationNs;
    _setLevel(true);
  }

  /// Emit a single bit slot. `isOne` selects the master-low duration:
  /// 6 µs for a 1, 60 µs for a 0. The slot completes at 70 µs total.
  void bitSlot({required bool isOne}) {
    final lowNs = isOne ? _bitOneLowNs : _bitZeroLowNs;

    final isWriteByte = _byteSlotCount < 8;
    if (isWriteByte && _firstWriteByteSlot) {
      _firstWriteByteSlot = false;
    }
    if (!isWriteByte && _firstReadByteSlot) {
      _firstReadByteSlot = false;
    }

    final highStart = now + lowNs;
    _setLevel(false);
    now = highStart;
    _setLevel(true);

    if (isWriteByte) {
      lastWriteByteEndNs = now;
    } else {
      lastReadByteEndNs = now;
    }

    final remaining = _bitSlotNs - lowNs;
    now += remaining;
    _byteSlotCount += 1;
  }

  String toVcd() {
    // Final timestamp marker so the parser knows when the simulation
    // ended — VCD parsers don't strictly require a trailing #N but
    // it's helpful for scrubbing.
    final tail = StringBuffer()..writeln('#$now');
    return _vcdHeader() +
        _initialDump() +
        _changes.toString() +
        tail.toString();
  }

  String _vcdHeader() {
    final buf = StringBuffer()
      ..writeln(r'$timescale 1ns $end')
      ..writeln(r'$scope module dut $end')
      ..writeln(r'$var wire 1 ! dq $end')
      ..writeln(r'$upscope $end')
      ..writeln(r'$enddefinitions $end');
    return buf.toString();
  }

  String _initialDump() {
    final buf = StringBuffer()
      ..writeln(r'$dumpvars')
      ..writeln('1!')
      ..writeln(r'$end');
    return buf.toString();
  }
}
