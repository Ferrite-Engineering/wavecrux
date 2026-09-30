// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Malformed-VCD parser robustness sweep.
//
// For each pathological VCD payload below, writes the bytes to a temp file,
// calls WellenProvider.openFile(), and asserts the call either succeeds
// (some malformations are spec-permissive) or surfaces a clean Dart-level
// exception. What is NOT acceptable: a process-level crash (Rust panic,
// SIGSEGV, FFI-thread death) that takes down the test runner.
//
// The Rust wellen parser is the single most exposed piece of native code
// in WaveCrux — every user file flows through it. A malformed-input crash
// here doesn't just hide one decoder's blind spot; it brings the whole
// app down before the user sees a single signal. This sweep is the
// parser-side equivalent of `_decoder_edge_cases_test.dart`.
//
// New malformation → append a `_Case` entry. Inline the VCD as a raw
// string (no separate fixture file). The harness writes a fresh temp
// file per case so test order doesn't matter.

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

class _Case {
  const _Case(this.name, this.body);
  final String name;
  final String body;
}

// ── malformed payloads ───────────────────────────────────────────────────────

const _validHeader = r'''
$date Mon Jan 1 00:00:00 2026 $end
$version Generator 1.0 $end
$timescale 1ns $end
$scope module top $end
$var wire 1 ! a $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
$end
#10
1!
#20
0!
''';

final List<_Case> _cases = <_Case>[
  // 1. Missing $end on a $var declaration.
  const _Case('missing_var_end', r'''
$date Mon Jan 1 00:00:00 2026 $end
$timescale 1ns $end
$scope module top $end
$var wire 1 ! a
$upscope $end
$enddefinitions $end
#0
'''),

  // 2. Missing $enddefinitions before the value-change section.
  const _Case('missing_enddefinitions', r'''
$timescale 1ns $end
$scope module top $end
$var wire 1 ! a $end
$upscope $end
#0
0!
'''),

  // 3. $upscope with no matching $scope — scope-stack underflow.
  const _Case('orphan_upscope', r'''
$timescale 1ns $end
$upscope $end
$enddefinitions $end
#0
'''),

  // 4. Identifier code reused for two different signals in the same scope.
  const _Case('duplicate_signal_id', r'''
$timescale 1ns $end
$scope module top $end
$var wire 1 ! a $end
$var wire 1 ! b $end
$upscope $end
$enddefinitions $end
#0
0!
'''),

  // 5. Value-change line with no preceding time marker.
  const _Case('value_change_no_time', r'''
$timescale 1ns $end
$scope module top $end
$var wire 1 ! a $end
$upscope $end
$enddefinitions $end
0!
1!
'''),

  // 6. Invalid value character ('5' is not 0/1/x/z).
  const _Case('invalid_value_char', r'''
$timescale 1ns $end
$scope module top $end
$var wire 1 ! a $end
$upscope $end
$enddefinitions $end
#0
5!
'''),

  // 7. Timescale unit unrecognized ("yoctosecond" is not a valid SI symbol).
  const _Case('unknown_timescale_unit', r'''
$timescale 1 ys $end
$scope module top $end
$var wire 1 ! a $end
$upscope $end
$enddefinitions $end
#0
0!
'''),

  // 8. $scope with no body before $upscope.
  const _Case('empty_scope_body', r'''
$timescale 1ns $end
$scope module top $end
$scope module empty $end
$upscope $end
$upscope $end
$enddefinitions $end
#0
'''),

  // 9. Comments mixed into the header (allowed per spec — must not error).
  const _Case('header_comments', r'''
$date Mon Jan 1 00:00:00 2026 $end
$comment this is a header comment $end
$version Generator 1.0 $end
$comment another comment between sections $end
$timescale 1ns $end
$scope module top $end
$var wire 1 ! a $end
$upscope $end
$enddefinitions $end
#0
0!
'''),

  // 10. Negative timestamp.
  const _Case('negative_timestamp', r'''
$timescale 1ns $end
$scope module top $end
$var wire 1 ! a $end
$upscope $end
$enddefinitions $end
#-100
0!
#0
1!
'''),

  // 11. Timestamps going backwards mid-stream.
  const _Case('backwards_timestamp', r'''
$timescale 1ns $end
$scope module top $end
$var wire 1 ! a $end
$upscope $end
$enddefinitions $end
#100
0!
#50
1!
#200
0!
'''),

  // 12. Vector value with width mismatch — b1010 on a 1-bit wire.
  const _Case('vector_width_mismatch', r'''
$timescale 1ns $end
$scope module top $end
$var wire 1 ! a $end
$upscope $end
$enddefinitions $end
#0
b1010 !
'''),

  // 13. $dumpvars block missing closing $end.
  const _Case('dumpvars_missing_end', r'''
$timescale 1ns $end
$scope module top $end
$var wire 1 ! a $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
#10
1!
'''),

  // 14. Unicode BOM at the file start. The BOM is U+FEFF; pre-pending it
  // to the otherwise-valid header lets us isolate the encoding wart from
  // any other malformation.
  const _Case('unicode_bom', '﻿$_validHeader'),

  // 15. Trailing garbage after the value-change section.
  const _Case('trailing_garbage', r'''
$timescale 1ns $end
$scope module top $end
$var wire 1 ! a $end
$upscope $end
$enddefinitions $end
#0
0!
#10
1!
this is not a valid vcd line
0  binary junk ÿ
'''),

  // 16. Empty file.
  const _Case('empty_file', ''),

  // 17. Header only — no value-change section.
  const _Case('header_only_no_values', r'''
$timescale 1ns $end
$scope module top $end
$var wire 1 ! a $end
$upscope $end
$enddefinitions $end
'''),

  // 18. Thousands of consecutive $dumpoff/$dumpon transitions.
  _Case('dumpoff_dumpon_storm', _buildDumpoffStorm()),

  // 19. $dumpvars block with no value lines, only the closing $end.
  const _Case('empty_dumpvars_block', r'''
$timescale 1ns $end
$scope module top $end
$var wire 1 ! a $end
$upscope $end
$enddefinitions $end
$dumpvars
$end
'''),

  // 20. Extremely long signal name (>500 chars).
  _Case('very_long_signal_name', _buildLongSignalName()),
];

String _buildDumpoffStorm() {
  final buf = StringBuffer()
    ..writeln(r'$timescale 1ns $end')
    ..writeln(r'$scope module top $end')
    ..writeln(r'$var wire 1 ! a $end')
    ..writeln(r'$upscope $end')
    ..writeln(r'$enddefinitions $end')
    ..writeln('#0')
    ..writeln('0!');
  for (var i = 1; i <= 2000; i++) {
    buf
      ..writeln('#${i * 10}')
      ..writeln(i.isEven ? r'$dumpoff' : r'$dumpon')
      ..writeln(r'$end');
  }
  return buf.toString();
}

String _buildLongSignalName() {
  final longName = 'x' * 600;
  return '''
\$timescale 1ns \$end
\$scope module top \$end
\$var wire 1 ! $longName \$end
\$upscope \$end
\$enddefinitions \$end
#0
0!
''';
}

// ── main ─────────────────────────────────────────────────────────────────────

void main() {
  if (!requireWellenFfiLibrary('malformed-VCD sweep')) return;

  group('malformed-VCD parser robustness', () {
    late Directory tmpRoot;

    setUpAll(() {
      tmpRoot = Directory.systemTemp.createTempSync('wavecrux_malformed_');
    });

    tearDownAll(() {
      if (tmpRoot.existsSync()) {
        tmpRoot.deleteSync(recursive: true);
      }
    });

    test('sweep covers at least 18 distinct malformations', () {
      // Bump as cases are added; the floor catches accidental case-list
      // trimming.
      expect(_cases.length, greaterThanOrEqualTo(18));
    });

    for (final c in _cases) {
      test(c.name, () async {
        final file = File('${tmpRoot.path}/${c.name}.vcd')
          ..writeAsBytesSync(c.body.codeUnits);
        final provider = WellenProvider();
        try {
          try {
            await provider.openFile(file.path);
            // Successful parse on a malformation is acceptable — VCD is a
            // permissive format and the wellen parser is allowed to coerce
            // many of these into a degraded-but-readable trace. The test
            // is satisfied that no process-level crash happened.
          } on Object {
            // Clean Dart-level throw is equally acceptable. Either path
            // is graceful; only a SIGSEGV / native panic would surface
            // outside this catch as a test runner failure.
          }
        } finally {
          provider.close();
        }
      }, timeout: const Timeout(Duration(seconds: 10)));
    }
  });
}
