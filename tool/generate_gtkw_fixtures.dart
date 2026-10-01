// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates the GTKWave `.gtkw` session-import fixture corpus and its golden
// snapshots. This is the deterministic backbone for the unit tests in
// `test/services/session/gtkw_golden_test.dart` and the manual verification
// flow in `verification/VERIFICATION_GUIDE.md` §6.6.
//
// Output (all under test/fixtures/gtkw/ — the verification flow consumes the
// same tree directly, no duplicate copy):
//
//   generated/                      synthetic, hand-designed coverage corpus
//     ├── fixture.vcd               paired waveform (5 vars under top + top.cpu)
//     ├── sample_filter.txt         GTKWave static translate filter
//     ├── <name>.gtkw               5 progressively-featured save files
//     ├── <name>.expected_parse.json     parser output golden  (GtkwFile)
//     └── <name>.expected_session.json   full parse→import golden (against
//                                         fixture.vcd's variable set)
//
//   captured/                       real GTKWave saves from public projects
//     └── <name>.expected_parse.json     parser output golden (regenerated
//                                         from the committed real .gtkw files;
//                                         the .gtkw inputs are NOT rewritten)
//
// Usage:
//   dart run tool/generate_gtkw_fixtures.dart
//
// After regenerating, run:
//   flutter test test/services/session/ test/static/gtkw_*
//
// The fixture-content constants below must be emitted byte-for-byte, so they
// intentionally start at the first content character rather than a newline.
// ignore_for_file: avoid_print, leading_newlines_in_multiline_strings

import 'dart:io';

import 'package:wavecrux/services/session/gtkw_import_service.dart';
import 'package:wavecrux/services/session/gtkw_parser.dart';

import '../test/services/session/gtkw_golden_codec.dart';

const _generatedDir = 'test/fixtures/gtkw/generated';
const _capturedDir = 'test/fixtures/gtkw/captured';

const _parser = GtkwParser();
const _importService = GtkwImportService();

void main() {
  _writeGeneratedInputs();
  _writeGeneratedGoldens();
  _writeCapturedGoldens();
  print('Done.');
}

// ── Generated inputs (synthetic corpus) ───────────────────────────────────────

/// The five synthetic `.gtkw` save files, keyed by filename. Each is designed
/// to exercise one more parser feature than the last. This map is the canonical
/// definition — editing a fixture means editing it here and re-running.
final Map<String, String> _generatedGtkw = {
  // 3 signals, two display formats, one open scope — the happy-path baseline.
  'simple_signals.gtkw':
      '''
[dumpfile] "fixture.vcd"
[timestart] 0
${_star(-19.499983)}
[treeopen] top
@28
top.clk
top.rst
@8
top.data
''',
  // Two named groups (begin/end markers) plus a trailing ungrouped signal.
  'groups.gtkw':
      '''
[dumpfile] "fixture.vcd"
[timestart] 0
${_star(-19)}
@800200
-Clocks
@28
top.clk
@1000200
-Clocks
@800200
-CPU Bus
@28
top.cpu.addr
top.cpu.dout
@1000200
-CPU Bus
@28
top.rst
''',
  // Every supported per-signal display format flag.
  // One trace per radix bit, written the way GTKWave writes them: the radix
  // bit OR'd with TR_RJUSTIFY (0x20), which real saves set on nearly every
  // trace. Values are `1 << <bit>` over `enum TraceEntFlagBits` in GTKWave's
  // src/analyzer.h.
  'format_flags.gtkw':
      '''
[dumpfile] "fixture.vcd"
[timestart] 0
${_star(-19)}
@22
top.clk
@28
top.rst
@24
top.data
@424
top.cpu.addr
@30
top.cpu.dout
''',
  // The flag combinations the radix table above does not reach: ASCII, signed
  // with no radix bit at all (GTKWave's `@420`, seen in the fpxx_adder
  // capture), and the Gray-code mask. Kept separate so `format_flags` stays a
  // one-trace-per-radix table.
  'format_flags_extra.gtkw':
      '''
[dumpfile] "fixture.vcd"
[timestart] 0
${_star(-19)}
@820
top.data
@420
top.cpu.addr
@2000020
top.cpu.dout
@4000020
top.clk
''',
  // The two analog bits, each with a radix so the numeric reading is pinned
  // too: TR_ANALOG_STEP (0x8000) and TR_ANALOG_INTERPOLATED (0x10000). The
  // third trace sets both, which GTKWave renders interpolated.
  'analog_flags.gtkw':
      '''
[dumpfile] "fixture.vcd"
[timestart] 0
${_star(-19)}
@8024
top.data
@10424
top.cpu.addr
@18024
top.cpu.dout
@24
top.clk
''',
  // Per-signal [color] directives + a primary marker + named markers a/b +
  // non-zero timestart.
  'colors_and_markers.gtkw':
      '''
[dumpfile] "fixture.vcd"
[timestart] 10
${_star(-19, primary: 40, named: {0: 30, 1: 50})}
@28
[color] 1
top.clk
[color] 4
top.rst
[color] 5
top.data
[color] 0
top.cpu.addr
''',
  // Filter references written the way GTKWave 3.3.115 writes them
  // (`savefile.c`, `write_save_helper`): the trace's flag word carries the
  // filter bit (TR_FTRANSLATED 0x2000, TR_PTRANSLATED 0x4000, TR_TTRANSLATED
  // 0x10000000), and the `^` line names the filter by its absolute path on the
  // saving machine. `[savefile]` records where that save lived, so the import
  // re-anchors `/home/user/proj/sample_filter.txt` to the sample_filter.txt
  // beside this fixture. The `^2` filter does not exist anywhere and must be
  // reported missing; the `^>` and `^<` processes must be reported as not
  // imported. Ends with a group holding a separator and a comment row.
  'translate_refs.gtkw':
      '''
[*]
[*] GTKWave Analyzer v3.3.115 (w)1999-2023 BSI
[*]
[dumpfile] "/home/user/proj/fixture.vcd"
[savefile] "/home/user/proj/translate_refs.gtkw"
[timestart] 0
${_star(-19)}
[treeopen] top.
@28
top.clk
@2022
^1 /home/user/proj/sample_filter.txt
top.data[7:0]
@2028
^2 /home/user/proj/filters/missing_filter.txt
top.rst
@4022
^>1 /home/user/proj/bin/decode_proc
top.cpu.addr[15:0]
@10000022
[transaction_args] ""
^<1 /home/user/proj/bin/txn_proc
top.cpu.dout[7:0]
@800200
-Separators and Comments
@200
-
-This is a comment
@1000200
-Separators and Comments
''',
};

/// The paired waveform referenced by every generated `.gtkw` via `[dumpfile]`.
/// Its `$var` declarations must match [fixtureVcdVariables] in the golden codec.
const _fixtureVcd = r'''$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 1 " rst $end
$var wire 8 # data $end
$scope module cpu $end
$var wire 16 $ addr $end
$var wire 8 % dout $end
$upscope $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
1"
b00000000 #
b0000000000000000 $
b00000000 %
$end
#10
1!
#20
0!
b00000001 #
#30
1!
0"
#40
0!
b00000010 #
b0000000000000001 $
#50
1!
#60
0!
b11111111 #
b1111111100000000 $
b11111111 %
#100
''';

/// The GTKWave static translate filter referenced by `translate_refs.gtkw`.
const _sampleFilter = '''# GTKWave translate filter file
# Maps integer values to human-readable labels
0 IDLE
1 RUNNING
2 HALTED
3 ERROR
''';

void _writeGeneratedInputs() {
  Directory(_generatedDir).createSync(recursive: true);
  _write('$_generatedDir/fixture.vcd', _fixtureVcd);
  _write('$_generatedDir/sample_filter.txt', _sampleFilter);
  for (final entry in _generatedGtkw.entries) {
    // The map values carry a leading newline from the '''\n…''' literal; trim
    // it so each file starts at the first directive line.
    _write('$_generatedDir/${entry.key}', entry.value.trimLeft());
  }
}

// ── Goldens ───────────────────────────────────────────────────────────────────

void _writeGeneratedGoldens() {
  for (final name in _generatedGtkw.keys) {
    final content = File('$_generatedDir/$name').readAsStringSync();
    final parsed = _parser.parse(content);
    final base = name.replaceFirst(RegExp(r'\.gtkw$'), '');

    // Parse golden — VCD-independent.
    _write(
      '$_generatedDir/$base.expected_parse.json',
      encodeGolden(encodeGtkwFile(parsed)),
    );

    // Import golden — full parse→import against fixture.vcd's variable set,
    // resolving filter files against the fixture tree.
    final result = _importService.importSession(
      parsed,
      fixtureVcdVariables(),
      gtkwFilePath: '$_generatedDir/$name',
      fileExists: (path) => File(path).existsSync(),
    );
    _write(
      '$_generatedDir/$base.expected_session.json',
      encodeGolden(encodeImportResult(result)),
    );
  }
}

void _writeCapturedGoldens() {
  final dir = Directory(_capturedDir);
  if (!dir.existsSync()) return;
  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.gtkw')) continue;
    final parsed = _parser.parse(file.readAsStringSync());
    final base = file.path.replaceFirst(RegExp(r'\.gtkw$'), '');
    _write('$base.expected_parse.json', encodeGolden(encodeGtkwFile(parsed)));
  }
}

// ── helpers ───────────────────────────────────────────────────────────────────

/// Builds a GTKWave `*` line the way GTKWave's `write_save_helper` does: the
/// zoom factor, the primary marker, then 26 named-marker slots (a–z) — 28
/// fields in all. [named] maps a 0-based slot index to a tick; an absent slot
/// or a null [primary] emits `-1` (GTKWave's "unset" sentinel).
String _star(double zoom, {int? primary, Map<int, int> named = const {}}) {
  final slots = List<String>.generate(26, (i) => (named[i] ?? -1).toString());
  return '*$zoom ${primary ?? -1} ${slots.join(' ')}';
}

void _write(String path, String content) {
  File(path).writeAsStringSync(content);
  print('Wrote $path');
}
