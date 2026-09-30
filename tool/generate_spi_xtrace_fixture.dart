// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates the SPI + X-Trace coexistence fixture for the decoder + X-Trace
// integration test and verification guide §22.9 ("Decoder + X-Trace
// coexistence").
//
// Output:
//   verification/fixtures/protocol/multi/spi_xtrace.vcd
//
// Usage:
//   dart run tool/generate_spi_xtrace_fixture.dart
//
// What it does:
//   Takes the known-good `protocol/spi/generated/spi_basic.vcd` (SPI bus, 2
//   transactions) and augments its `spi_tb` scope with an extra 8-bit
//   `data_out` wire that goes fully `x` at T=620 ns — after the last SPI
//   value change (T=590) so the SPI decode is byte-for-byte unchanged (still
//   2 transactions). The X event gives the X-Trace feature a signal to trace
//   while the SPI decoder is simultaneously active.
//
// There is no `.expected_transactions.json` companion: the SPI side matches
// `spi_basic`'s companion exactly, and X-Trace is verified through provider
// state, not a decoder-style JSON snapshot.
//
// ignore_for_file: avoid_print

import 'dart:io';

void main() {
  const src = 'verification/fixtures/protocol/spi/generated/spi_basic.vcd';
  final lines = File(src).readAsLinesSync();

  final out = <String>[];
  var insertedVar = false;
  for (final line in lines) {
    // Add the data_out declaration just before the scope closes.
    if (line.trim() == r'$upscope $end' && !insertedVar) {
      out.add(r'$var wire 8 & data_out $end');
      insertedVar = true;
    }
    out.add(line);
    // Seed data_out's initial value inside the $dumpvars block.
    if (line.trim() == r'$dumpvars') {
      out.add('b00000001 &');
    }
  }

  if (!insertedVar) {
    stderr.writeln('error: no upscope marker found to insert data_out into');
    exit(1);
  }

  // Append the X event after the existing SPI timeline (last change at #590).
  out.addAll(<String>[
    '#620',
    'bxxxxxxxx &',
    '#700',
    'b00000010 &',
  ]);

  Directory('verification/fixtures/protocol/multi').createSync(recursive: true);
  const dst = 'verification/fixtures/protocol/multi/spi_xtrace.vcd';
  File(dst).writeAsStringSync('${out.join('\n')}\n');
  print('Wrote $dst');
}
