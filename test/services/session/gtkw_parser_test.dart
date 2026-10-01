// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/analog_interpolation.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/services/session/gtkw_parser.dart';

void main() {
  const parser = GtkwParser();

  // ── helpers ────────────────────────────────────────────────────────────────

  GtkwFile parse(String content) => parser.parse(content);

  // ── empty / trivial input ──────────────────────────────────────────────────

  group('GtkwParser — empty / trivial input', () {
    test('empty string produces empty GtkwFile', () {
      final f = parse('');
      expect(f.dumpFilePath, isNull);
      expect(f.timeStart, isNull);
      expect(f.zoomFactor, isNull);
      expect(f.namedMarkers, isEmpty);
      expect(f.openScopes, isEmpty);
      expect(f.entries, isEmpty);
    });

    test('whitespace-only input produces empty GtkwFile', () {
      final f = parse('   \n\n\t\n');
      expect(f.entries, isEmpty);
    });

    test('unknown directives are silently skipped', () {
      final f = parse('[unknown_key] some value\n[another_key] 42\n');
      expect(f.entries, isEmpty);
      expect(f.dumpFilePath, isNull);
    });
  });

  // ── [dumpfile] directive ───────────────────────────────────────────────────

  group('GtkwParser — [dumpfile]', () {
    test('parses quoted dumpfile path', () {
      final f = parse('[dumpfile] "path/to/sim.vcd"\n');
      expect(f.dumpFilePath, 'path/to/sim.vcd');
    });

    test('parses unquoted dumpfile path', () {
      final f = parse('[dumpfile] path/to/sim.vcd\n');
      expect(f.dumpFilePath, 'path/to/sim.vcd');
    });

    test('empty dumpfile value yields null', () {
      final f = parse('[dumpfile] ""\n');
      expect(f.dumpFilePath, isNull);
    });

    test('dumpfile with spaces in path', () {
      final f = parse('[dumpfile] "/my projects/sim output.vcd"\n');
      expect(f.dumpFilePath, '/my projects/sim output.vcd');
    });
  });

  // ── [timestart] directive ──────────────────────────────────────────────────

  group('GtkwParser — [timestart]', () {
    test('parses positive integer', () {
      final f = parse('[timestart] 1000\n');
      expect(f.timeStart, 1000);
    });

    test('parses zero', () {
      final f = parse('[timestart] 0\n');
      expect(f.timeStart, 0);
    });

    test('non-numeric value yields null', () {
      final f = parse('[timestart] abc\n');
      expect(f.timeStart, isNull);
    });
  });

  // ── [treeopen] directive ───────────────────────────────────────────────────

  group('GtkwParser — [treeopen]', () {
    test('single treeopen', () {
      final f = parse('[treeopen] top\n');
      expect(f.openScopes, ['top']);
    });

    test('multiple treeopen entries', () {
      final f = parse('[treeopen] top\n[treeopen] top.cpu\n');
      expect(f.openScopes, ['top', 'top.cpu']);
    });
  });

  // ── * zoom / marker line ───────────────────────────────────────────────────

  // GTKWave writes `*<zoom> <primary marker> <named A> … <named Z>`
  // (savefile.c, write_save_helper): field 1 is the primary marker, and the
  // named markers start at field 2.
  group('GtkwParser — * zoom/marker line', () {
    // Verbatim from a real GTKWave 3.3.115 save: zoom, then 27 `-1`s (the
    // primary marker plus 26 named markers), 28 fields in all.
    const realStarLine =
        '*-17.277769 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 '
        '-1 -1 -1 -1 -1 -1 -1 -1 -1';

    /// A 28-field star line with [primary] and the named markers in [named]
    /// (0 = a … 25 = z); every other slot is GTKWave's `-1`.
    String star(
      double zoom, {
      int primary = -1,
      Map<int, int> named = const {},
    }) {
      final slots = List<int>.generate(26, (i) => named[i] ?? -1);
      return '*$zoom $primary ${slots.join(' ')}\n';
    }

    test('real GTKWave 3.3.115 star line: zoom, no cursor, no markers', () {
      expect(realStarLine.substring(1).split(' '), hasLength(28));
      final f = parse('$realStarLine\n');
      expect(f.zoomFactor, closeTo(-17.277769, 1e-5));
      expect(f.primaryMarker, isNull);
      expect(f.namedMarkers, isEmpty);
    });

    test('parses zoom factor', () {
      final f = parse(star(-19.499983));
      expect(f.zoomFactor, closeTo(-19.499983, 1e-5));
    });

    test('no markers when all are -1', () {
      final f = parse(star(-19));
      expect(f.primaryMarker, isNull);
      expect(f.namedMarkers, isEmpty);
    });

    test('field 1 is the primary marker, not named marker a', () {
      final f = parse(star(-19, primary: 500));
      expect(f.primaryMarker, 500);
      expect(f.namedMarkers, isEmpty);
    });

    test('field 2 is named marker a', () {
      final f = parse(star(-19, named: {0: 750}));
      expect(f.namedMarkers, {'a': 750});
      expect(f.primaryMarker, isNull);
    });

    test('field 27 is named marker z', () {
      final f = parse(star(-19, named: {25: 900}));
      expect(f.namedMarkers, {'z': 900});
    });

    test('parses the primary marker and several named markers together', () {
      final f = parse(star(-10, primary: 42, named: {0: 100, 1: 200, 2: 300}));
      expect(f.primaryMarker, 42);
      expect(f.namedMarkers, {'a': 100, 'b': 200, 'c': 300});
    });

    test('zero marker time is included', () {
      final f = parse(star(-19, primary: 0, named: {0: 0}));
      expect(f.primaryMarker, 0);
      expect(f.namedMarkers['a'], 0);
    });

    test('star line with no markers after zoom', () {
      final f = parse('*-5.0\n');
      expect(f.zoomFactor, -5.0);
      expect(f.primaryMarker, isNull);
      expect(f.namedMarkers, isEmpty);
    });

    test('fields beyond z are ignored', () {
      final f = parse('${star(-19).trimRight()} 1234\n');
      expect(f.namedMarkers, isEmpty);
    });
  });

  // ── @ flag lines ──────────────────────────────────────────────────────────

  // The `@` word is a bit set over `enum TraceEntFlagBits` in GTKWave's
  // src/analyzer.h, not an enumeration of low-byte values. TR_RJUSTIFY (0x20)
  // is set on nearly every trace a real GTKWave writes, so each radix below is
  // exercised OR'd with it — the combination is what actually appears in save
  // files, and testing the bare bit would not have caught the mapping this
  // group replaced.
  group('GtkwParser — @ format flags', () {
    DisplayFormat formatOf(String flagWord) {
      final f = parse('@$flagWord\ntop.data\n');
      return (f.entries.first as GtkwSignalEntry).format;
    }

    test('TR_HEX | TR_RJUSTIFY (@22) maps to hexadecimal', () {
      expect(formatOf('22'), DisplayFormat.hexadecimal);
    });

    test('TR_BIN | TR_RJUSTIFY (@28) maps to binary', () {
      expect(formatOf('28'), DisplayFormat.binary);
    });

    test('TR_DEC | TR_RJUSTIFY (@24) maps to unsigned decimal', () {
      expect(formatOf('24'), DisplayFormat.unsignedDecimal);
    });

    test('TR_OCT | TR_RJUSTIFY (@30) maps to octal', () {
      expect(formatOf('30'), DisplayFormat.octal);
    });

    test('TR_ASCII | TR_RJUSTIFY (@820) maps to ASCII', () {
      expect(formatOf('820'), DisplayFormat.ascii);
    });

    test('TR_SIGNED upgrades decimal to signed decimal (@424)', () {
      expect(formatOf('424'), DisplayFormat.signedDecimal);
    });

    test('TR_SIGNED with no radix bit (@420) means signed decimal', () {
      // Exactly the word the fpxx_adder capture carries on
      // `TOP.FpxxAddDut.fp_op.exp_add_m_lz[8:0]`.
      expect(formatOf('420'), DisplayFormat.signedDecimal);
    });

    test('either Gray bit maps to Gray code', () {
      expect(formatOf('2000020'), DisplayFormat.grayCode); // TR_BINGRAY
      expect(formatOf('4000020'), DisplayFormat.grayCode); // TR_GRAYBIN
    });

    test('ASCII wins over a radix bit set alongside it', () {
      // TR_NUMMASK lists ASCII first and GTKWave applies it first.
      expect(formatOf('822'), DisplayFormat.ascii);
    });

    test('no radix bit at all defaults to hexadecimal', () {
      expect(formatOf('20'), DisplayFormat.hexadecimal);
      expect(formatOf('0'), DisplayFormat.hexadecimal);
    });

    test('attribute-only bits do not select a radix', () {
      // TR_HIGHLIGHT (0x01) rides along on a highlighted trace; @25 is
      // TR_HIGHLIGHT | TR_DEC | TR_RJUSTIFY and appears in the fpxx_adder
      // capture. It must still read as decimal.
      expect(formatOf('25'), DisplayFormat.unsignedDecimal);
    });

    test('flag persists across multiple signals', () {
      final f = parse('@28\ntop.clk\ntop.rst\n');
      expect(f.entries.length, 2);
      for (final e in f.entries.cast<GtkwSignalEntry>()) {
        expect(e.format, DisplayFormat.binary);
      }
    });

    test('flag changes mid-list', () {
      final f = parse('@22\ntop.clk\n@28\ntop.rst\n');
      final a = f.entries[0] as GtkwSignalEntry;
      final b = f.entries[1] as GtkwSignalEntry;
      expect(a.format, DisplayFormat.hexadecimal);
      expect(b.format, DisplayFormat.binary);
    });
  });

  group('GtkwParser — @ analog flags', () {
    GtkwSignalEntry entryOf(String flagWord) {
      final f = parse('@$flagWord\ntop.data\n');
      return f.entries.first as GtkwSignalEntry;
    }

    test('no analog bit leaves the trace digital', () {
      final e = entryOf('24');
      expect(e.renderAsAnalog, isFalse);
    });

    test('TR_ANALOG_STEP asks for a step-held curve', () {
      final e = entryOf('8024');
      expect(e.renderAsAnalog, isTrue);
      expect(e.analogInterpolation, AnalogInterpolation.stepHold);
      // The radix travels independently — analog says how to draw, the radix
      // says what number is being drawn.
      expect(e.format, DisplayFormat.unsignedDecimal);
    });

    test('TR_ANALOG_INTERPOLATED asks for a linear curve', () {
      final e = entryOf('10424');
      expect(e.renderAsAnalog, isTrue);
      expect(e.analogInterpolation, AnalogInterpolation.linear);
      expect(e.format, DisplayFormat.signedDecimal);
    });

    test('both analog bits set renders interpolated, matching GTKWave', () {
      final e = entryOf('18024');
      expect(e.renderAsAnalog, isTrue);
      expect(e.analogInterpolation, AnalogInterpolation.linear);
    });

    test('TR_ANALOG_BLANK_STRETCH alone is not an analog trace', () {
      // 0x20000 only governs how blanked rows below contribute height.
      final e = entryOf('20024');
      expect(e.renderAsAnalog, isFalse);
    });
  });

  // ── Signal path lines ─────────────────────────────────────────────────────

  group('GtkwParser — signal paths', () {
    test('simple dot-path becomes GtkwSignalEntry', () {
      final f = parse('@28\ntop.clk\n');
      expect(f.entries.length, 1);
      final e = f.entries.first as GtkwSignalEntry;
      expect(e.path, 'top.clk');
    });

    test('multiple signals parsed in order', () {
      final f = parse('@28\ntop.clk\ntop.rst\ntop.data\n');
      expect(f.entries.length, 3);
      expect((f.entries[0] as GtkwSignalEntry).path, 'top.clk');
      expect((f.entries[1] as GtkwSignalEntry).path, 'top.rst');
      expect((f.entries[2] as GtkwSignalEntry).path, 'top.data');
    });

    test('path with bit-range suffix preserved as-is', () {
      final f = parse('@28\ntop.data[7:0]\n');
      final e = f.entries.first as GtkwSignalEntry;
      expect(e.path, 'top.data[7:0]');
    });

    test('default format is hexadecimal when no @ line precedes', () {
      final f = parse('top.clk\n');
      final e = f.entries.first as GtkwSignalEntry;
      expect(e.format, DisplayFormat.hexadecimal);
    });
  });

  // ── [color] directive ─────────────────────────────────────────────────────

  group('GtkwParser — [color]', () {
    test('[color] 1 maps to red ARGB', () {
      final f = parse('@28\n[color] 1\ntop.clk\n');
      final e = f.entries.first as GtkwSignalEntry;
      expect(e.colorArgb, 0xFFFF5555);
    });

    test('[color] 4 maps to green ARGB', () {
      final f = parse('@28\n[color] 4\ntop.clk\n');
      final e = f.entries.first as GtkwSignalEntry;
      expect(e.colorArgb, 0xFF00FF00);
    });

    test('[color] 0 yields null (auto)', () {
      final f = parse('@28\n[color] 0\ntop.clk\n');
      final e = f.entries.first as GtkwSignalEntry;
      expect(e.colorArgb, isNull);
    });

    test('[color] resets after signal', () {
      final f = parse('@28\n[color] 1\ntop.clk\ntop.rst\n');
      final a = f.entries[0] as GtkwSignalEntry;
      final b = f.entries[1] as GtkwSignalEntry;
      expect(a.colorArgb, 0xFFFF5555);
      expect(b.colorArgb, isNull); // no [color] before rst
    });

    test('all 8 color indices map to non-null', () {
      for (var i = 1; i <= 8; i++) {
        final f = parse('@28\n[color] $i\ntop.clk\n');
        final e = f.entries.first as GtkwSignalEntry;
        expect(
          e.colorArgb,
          isNotNull,
          reason: 'color index $i should map to non-null ARGB',
        );
      }
    });
  });

  // ── ^ filter lines ─────────────────────────────────────────────────────────

  // GTKWave writes `^<n> <path>`, `^><n> <path>` and `^<<n> <path>` before a
  // trace that uses a file, process or transaction filter (savefile.c), and
  // sets TR_FTRANSLATED (0x2000), TR_PTRANSLATED (0x4000) or TR_TTRANSLATED
  // (0x10000000) in that trace's flag word.
  group('GtkwParser — ^ filter lines', () {
    test('^n, ^>n and ^<n lines do not become signal entries', () {
      final f = parse(
        '@28\n'
        '^1 /home/u/filters/states.txt\n'
        'top.state[1:0]\n'
        '^>2 /home/u/bin/decode_proc\n'
        'top.opcode[6:0]\n'
        '^<3 /home/u/bin/txn_proc\n'
        'top.bus[31:0]\n'
        '^0 disabled\n'
        'top.clk\n',
      );
      final paths = f.entries
          .whereType<GtkwSignalEntry>()
          .map((e) => e.path)
          .toList();
      expect(paths, [
        'top.state[1:0]',
        'top.opcode[6:0]',
        'top.bus[31:0]',
        'top.clk',
      ]);
    });

    test('a ^ line between [color] and its trace keeps the color', () {
      final f = parse('@2028\n[color] 1\n^1 /f.txt\ntop.data\n');
      final e = f.entries.single as GtkwSignalEntry;
      expect(e.colorArgb, 0xFFFF5555);
      expect(e.translateFilterPath, '/f.txt');
    });

    test('a file filter applies to a trace flagged TR_FTRANSLATED', () {
      final f = parse('@2022\n^1 /home/u/filters/states.txt\ntop.state\n');
      final e = f.entries.single as GtkwSignalEntry;
      expect(e.translateFilterPath, '/home/u/filters/states.txt');
      // The filter bit does not disturb the radix decode.
      expect(e.format, DisplayFormat.hexadecimal);
    });

    test('a trace without TR_FTRANSLATED takes no file filter', () {
      final f = parse('@22\n^1 /f.txt\ntop.state\n');
      final e = f.entries.single as GtkwSignalEntry;
      expect(e.translateFilterPath, isNull);
    });

    test('the current file filter carries to later flagged traces', () {
      // GTKWave only rewrites `@` when the flags change and keeps the current
      // filter until the next `^` line, so two traces can share one line.
      final f = parse('@2022\n^1 /f.txt\ntop.a\ntop.b\n@22\ntop.c\n');
      final filters = f.entries
          .whereType<GtkwSignalEntry>()
          .map((e) => e.translateFilterPath)
          .toList();
      expect(filters, ['/f.txt', '/f.txt', null]);
    });

    test('^0 disabled clears the current file filter', () {
      final f = parse('@2022\n^1 /f.txt\ntop.a\n^0 disabled\ntop.b\n');
      final filters = f.entries
          .whereType<GtkwSignalEntry>()
          .map((e) => e.translateFilterPath)
          .toList();
      expect(filters, ['/f.txt', null]);
    });

    test('a filter path containing spaces is kept whole', () {
      final f = parse('@2022\n^1 /home/u/My Filters/states map.txt\ntop.s\n');
      final e = f.entries.single as GtkwSignalEntry;
      expect(e.translateFilterPath, '/home/u/My Filters/states map.txt');
    });

    test('^>n on a TR_PTRANSLATED trace is a process filter', () {
      final f = parse('@4022\n^>1 /home/u/bin/decode\ntop.op\n');
      final e = f.entries.single as GtkwSignalEntry;
      expect(e.processFilterPath, '/home/u/bin/decode');
      expect(e.translateFilterPath, isNull);
      expect(e.transactionFilterPath, isNull);
    });

    test('^<n on a TR_TTRANSLATED trace is a transaction filter', () {
      final f = parse(
        '@10000022\n[transaction_args] ""\n^<1 /home/u/bin/txn\ntop.bus\n',
      );
      final e = f.entries.single as GtkwSignalEntry;
      expect(e.transactionFilterPath, '/home/u/bin/txn');
      expect(e.processFilterPath, isNull);
    });

    test('^>0 and ^<0 clear their filters', () {
      final f = parse(
        '@10004022\n^>1 /p\n^<1 /t\ntop.a\n^>0 disabled\n^<0 disabled\n'
        'top.b\n',
      );
      final entries = f.entries.whereType<GtkwSignalEntry>().toList();
      expect(entries[0].processFilterPath, '/p');
      expect(entries[0].transactionFilterPath, '/t');
      expect(entries[1].processFilterPath, isNull);
      expect(entries[1].transactionFilterPath, isNull);
    });

    test('a file filter wins over a process filter, as GTKWave writes it', () {
      final f = parse('@6022\n^1 /f.txt\n^>1 /p\ntop.a\n');
      final e = f.entries.single as GtkwSignalEntry;
      expect(e.translateFilterPath, '/f.txt');
      expect(e.processFilterPath, isNull);
    });

    test('a bare ^ line with no path is ignored', () {
      final f = parse('@2022\n^1\ntop.a\n');
      final e = f.entries.single as GtkwSignalEntry;
      expect(e.translateFilterPath, isNull);
    });

    test(
      '[translate_filter_file] is not a GTKWave directive and is ignored',
      () {
        final f = parse(
          '@2028\n[translate_filter_file] /filters/states.txt\ntop.data\n',
        );
        final e = f.entries.single as GtkwSignalEntry;
        expect(e.translateFilterPath, isNull);
      },
    );
  });

  // ── > time shift lines ───────────────────────────────────────────────────

  group('GtkwParser — > time shift lines', () {
    test('a >N line is not read as a signal path', () {
      final f = parse('@28\n>100\ntop.clk\n>0\ntop.rst\n');
      final paths = f.entries
          .whereType<GtkwSignalEntry>()
          .map((e) => e.path)
          .toList();
      expect(paths, ['top.clk', 'top.rst']);
    });
  });

  // ── [savefile] ─────────────────────────────────────────────────────────────

  group('GtkwParser — [savefile]', () {
    test('records where GTKWave wrote the save', () {
      final f = parse('[savefile] "/home/u/proj/view.gtkw"\n');
      expect(f.savedFilePath, '/home/u/proj/view.gtkw');
    });

    test('is null when absent', () {
      expect(parse('@28\ntop.clk\n').savedFilePath, isNull);
    });
  });

  // ── - dash lines ──────────────────────────────────────────────────────────

  group('GtkwParser — dash lines', () {
    test('dash with text and no group flags is a comment', () {
      final f = parse('@28\n-This is a comment\n');
      expect(f.entries.first, isA<GtkwCommentEntry>());
      expect((f.entries.first as GtkwCommentEntry).text, 'This is a comment');
    });

    test('dash with empty text is a separator', () {
      final f = parse('@28\n-\n');
      expect(f.entries.first, isA<GtkwSeparatorEntry>());
    });

    test('dash with whitespace-only text is a separator', () {
      final f = parse('@28\n-   \n');
      expect(f.entries.first, isA<GtkwSeparatorEntry>());
    });

    test('[signal_comment] directive produces comment entry', () {
      final f = parse('[signal_comment] My label text\n');
      expect(f.entries.first, isA<GtkwCommentEntry>());
      expect((f.entries.first as GtkwCommentEntry).text, 'My label text');
    });
  });

  // ── Group begin / end ─────────────────────────────────────────────────────

  group('GtkwParser — group markers', () {
    test('@800200 + -Name produces GtkwGroupBeginEntry', () {
      final f = parse('@800200\n-MyGroup\n');
      expect(f.entries.first, isA<GtkwGroupBeginEntry>());
      expect((f.entries.first as GtkwGroupBeginEntry).name, 'MyGroup');
    });

    test('@1000200 + -Name produces GtkwGroupEndEntry', () {
      final f = parse('@1000200\n-MyGroup\n');
      expect(f.entries.first, isA<GtkwGroupEndEntry>());
      expect((f.entries.first as GtkwGroupEndEntry).name, 'MyGroup');
    });

    test('group with brace-wrapped name strips braces', () {
      final f = parse('@800200\n-{My Group Name}\n');
      expect((f.entries.first as GtkwGroupBeginEntry).name, 'My Group Name');
    });

    test('empty group name defaults to Group', () {
      final f = parse('@800200\n-\n');
      expect((f.entries.first as GtkwGroupBeginEntry).name, 'Group');
    });

    test('full group sequence produces begin + signals + end', () {
      final f = parse(
        '@800200\n-Clocks\n@28\ntop.clk\n@1000200\n-Clocks\n',
      );
      expect(f.entries.length, 3);
      expect(f.entries[0], isA<GtkwGroupBeginEntry>());
      expect(f.entries[1], isA<GtkwSignalEntry>());
      expect(f.entries[2], isA<GtkwGroupEndEntry>());
    });
  });

  // ── Fixture files ─────────────────────────────────────────────────────────

  group('GtkwParser — fixture files', () {
    String loadFixture(String name) {
      final path = 'test/fixtures/gtkw/generated/$name';
      return File(path).readAsStringSync();
    }

    test('simple_signals.gtkw — 3 signals, no groups', () {
      final f = parser.parse(loadFixture('simple_signals.gtkw'));
      expect(f.dumpFilePath, 'fixture.vcd');
      expect(f.entries.whereType<GtkwSignalEntry>().length, 3);
      expect(f.entries.whereType<GtkwGroupBeginEntry>(), isEmpty);
    });

    test('groups.gtkw — has group begin/end markers', () {
      final f = parser.parse(loadFixture('groups.gtkw'));
      expect(f.entries.whereType<GtkwGroupBeginEntry>().length, 2);
      expect(f.entries.whereType<GtkwGroupEndEntry>().length, 2);
    });

    test('format_flags.gtkw — signals have correct formats', () {
      final f = parser.parse(loadFixture('format_flags.gtkw'));
      final signals = f.entries.whereType<GtkwSignalEntry>().toList();
      expect(signals[0].format, DisplayFormat.hexadecimal); // @28
      expect(signals[1].format, DisplayFormat.binary); // @20
      expect(signals[2].format, DisplayFormat.unsignedDecimal); // @24
      expect(signals[3].format, DisplayFormat.signedDecimal); // @26
      expect(signals[4].format, DisplayFormat.octal); // @22
    });

    test('colors_and_markers.gtkw — primary marker and markers a, b set', () {
      final f = parser.parse(loadFixture('colors_and_markers.gtkw'));
      expect(f.primaryMarker, 40);
      expect(f.namedMarkers, {'a': 30, 'b': 50});
      expect(f.timeStart, 10);
    });

    test('colors_and_markers.gtkw — color index 1 maps to red', () {
      final f = parser.parse(loadFixture('colors_and_markers.gtkw'));
      final clk = f.entries.whereType<GtkwSignalEntry>().first;
      expect(clk.colorArgb, 0xFFFF5555);
    });

    test('translate_refs.gtkw — file filter on the data trace', () {
      final f = parser.parse(loadFixture('translate_refs.gtkw'));
      final signals = f.entries.whereType<GtkwSignalEntry>().toList();
      final data = signals.firstWhere((e) => e.path == 'top.data[7:0]');
      expect(data.translateFilterPath, '/home/user/proj/sample_filter.txt');
      final clk = signals.firstWhere((e) => e.path == 'top.clk');
      expect(clk.translateFilterPath, isNull);
      expect(f.savedFilePath, '/home/user/proj/translate_refs.gtkw');
    });

    test('translate_refs.gtkw — process and transaction filters', () {
      final f = parser.parse(loadFixture('translate_refs.gtkw'));
      final signals = f.entries.whereType<GtkwSignalEntry>().toList();
      final addr = signals.firstWhere((e) => e.path == 'top.cpu.addr[15:0]');
      expect(addr.processFilterPath, '/home/user/proj/bin/decode_proc');
      final dout = signals.firstWhere((e) => e.path == 'top.cpu.dout[7:0]');
      expect(dout.transactionFilterPath, '/home/user/proj/bin/txn_proc');
    });

    test('translate_refs.gtkw — ^ filter lines are not signal paths', () {
      final f = parser.parse(loadFixture('translate_refs.gtkw'));
      final paths = f.entries.whereType<GtkwSignalEntry>().map((e) => e.path);
      expect(paths, [
        'top.clk',
        'top.data[7:0]',
        'top.rst',
        'top.cpu.addr[15:0]',
        'top.cpu.dout[7:0]',
      ]);
    });

    test('translate_refs.gtkw — separator and comment entries present', () {
      final f = parser.parse(loadFixture('translate_refs.gtkw'));
      expect(f.entries.whereType<GtkwSeparatorEntry>().length, 1);
      expect(f.entries.whereType<GtkwCommentEntry>().length, 1);
    });
  });

  // ── GtkwFile.toString ──────────────────────────────────────────────────────

  group('GtkwFile.toString', () {
    test('includes entry count', () {
      final f = parse('@28\ntop.clk\ntop.rst\n');
      expect(f.toString(), contains('entries: 2'));
    });
  });

  // ── [bgcolor] canvas background ────────────────────────────────────────────

  group('GtkwParser — [bgcolor]', () {
    test('bare hex value without hash is parsed', () {
      final f = parse('[bgcolor] 002B36\n@28\ntop.clk\n');
      expect(f.canvasBackgroundHex, '#002B36');
    });

    test('value with leading hash is accepted', () {
      final f = parse('[bgcolor] #1A1A1A\n@28\ntop.clk\n');
      expect(f.canvasBackgroundHex, '#1A1A1A');
    });

    test('mixed-case hex is preserved', () {
      final f = parse('[bgcolor] aAbBcC\n');
      expect(f.canvasBackgroundHex, '#aAbBcC');
    });

    test('absent [bgcolor] yields null', () {
      final f = parse('[dumpfile] dump.vcd\n@28\ntop.clk\n');
      expect(f.canvasBackgroundHex, isNull);
    });

    test('invalid hex value yields null', () {
      final f = parse('[bgcolor] ZZZZZZ\n');
      expect(f.canvasBackgroundHex, isNull);
    });

    test('value shorter than 6 digits yields null', () {
      final f = parse('[bgcolor] 1A2B\n');
      expect(f.canvasBackgroundHex, isNull);
    });

    test('value longer than 6 digits yields null', () {
      final f = parse('[bgcolor] 1A2B3C4D\n');
      expect(f.canvasBackgroundHex, isNull);
    });
  });

  // ── Adversarial / malformed input ───────────────────────────────────────────
  //
  // The parser's load-bearing contract is "never throws — even a completely
  // malformed file produces a (possibly empty) GtkwFile." These cases exercise
  // that claim against the kinds of garbage a real file dialog can hand us:
  // truncated saves, binary blobs, wrong files entirely, and pathological sizes.

  group('GtkwParser — adversarial / malformed input', () {
    test('unterminated [ bracket directive does not throw', () {
      final f = parse('[dumpfile "no closing bracket\ntop.clk\n');
      // The malformed directive line is skipped (no `]`), the signal survives.
      expect(f.dumpFilePath, isNull);
      expect(f.entries.whereType<GtkwSignalEntry>().length, 1);
    });

    test('truncated mid-directive at EOF does not throw', () {
      expect(() => parse('[dump'), returnsNormally);
      expect(parse('[dump').entries, isEmpty);
    });

    test('binary / non-text bytes do not throw', () {
      final blob = String.fromCharCodes(
        List<int>.generate(512, (i) => (i * 37) % 256),
      );
      late final GtkwFile f;
      expect(() => f = parse(blob), returnsNormally);
      // No assertion on contents — just that parsing terminates without error.
      expect(f, isNotNull);
    });

    test(
      'a wrong-format file (a VCD) parses to no signals, does not throw',
      () {
        const vcd =
            '\n'
            r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
$end
#10
1!''';
        late final GtkwFile f;
        expect(() => f = parse(vcd), returnsNormally);
        // `$timescale …` etc. are non-bracket, non-@, non-* lines → treated as
        // signal "paths". That's acceptable degradation: import then resolves
        // none of them against the loaded waveform and reports them unmatched.
        // The key contract is simply: no throw.
        expect(f.namedMarkers, isEmpty);
      },
    );

    test('CRLF line endings are tolerated', () {
      final f = parse('[dumpfile] "a.vcd"\r\n@28\r\ntop.clk\r\n');
      expect(f.dumpFilePath, 'a.vcd');
      final sig = f.entries.whereType<GtkwSignalEntry>().single;
      expect(sig.path, 'top.clk');
    });

    test('missing trailing newline still parses the last line', () {
      final f = parse('@28\ntop.clk'); // no final \n
      expect(f.entries.whereType<GtkwSignalEntry>().single.path, 'top.clk');
    });

    test('group-end with no matching begin does not throw', () {
      final f = parse('@1000200\n-Orphan\n@28\ntop.clk\n');
      expect(() => f, returnsNormally);
      expect(f.entries.first, isA<GtkwGroupEndEntry>());
    });

    test('@ flag word with non-hex payload is ignored, format unchanged', () {
      final f = parse('@28\ntop.clk\n@zzzz\ntop.rst\n');
      final a = f.entries[0] as GtkwSignalEntry;
      final b = f.entries[1] as GtkwSignalEntry;
      expect(a.format, DisplayFormat.binary);
      // Unparseable @ word leaves the previous flags in effect (no throw).
      expect(b.format, DisplayFormat.binary);
    });

    test('very long single line does not throw', () {
      final huge = 'a' * 200000;
      late final GtkwFile f;
      expect(() => f = parse('@28\n$huge\n'), returnsNormally);
      expect(f.entries.whereType<GtkwSignalEntry>().single.path, huge);
    });

    test('deeply repeated group-begin markers do not overflow', () {
      final buf = StringBuffer();
      for (var i = 0; i < 5000; i++) {
        buf
          ..writeln('@800200')
          ..writeln('-G$i');
      }
      expect(() => parse(buf.toString()), returnsNormally);
    });
  });
}
