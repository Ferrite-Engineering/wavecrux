// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/session/gtkw_import_service.dart';
import 'package:wavecrux/services/session/gtkw_parser.dart';

// ── helpers ────────────────────────────────────────────────────────────────

const _service = GtkwImportService();

Variable _mkVar(String scopePath, String name, {String? ref}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: ref ?? '$scopePath.$name',
  scopePath: scopePath,
);

List<Variable> get _fixtureVars => [
  _mkVar('top', 'clk', ref: 'ref_clk'),
  _mkVar('top', 'rst', ref: 'ref_rst'),
  _mkVar('top', 'data', ref: 'ref_data'),
  _mkVar('top.cpu', 'addr', ref: 'ref_addr'),
  _mkVar('top.cpu', 'dout', ref: 'ref_dout'),
];

GtkwImportResult _import(
  GtkwFile gtkwFile, {
  List<Variable>? variables,
  String? sourceFilePath,
}) => _service.importSession(
  gtkwFile,
  variables ?? _fixtureVars,
  sourceFilePath: sourceFilePath,
);

// ── tests ──────────────────────────────────────────────────────────────────

void main() {
  // ── GtkwImportResult model ───────────────────────────────────────────────

  group('GtkwImportResult', () {
    test('hasUnmatchedSignals is false when list is empty', () {
      const r = GtkwImportResult(
        sessionState: SessionState(),
        matchedSignalCount: 3,
        groupCount: 0,
        markerCount: 0,
        unmatchedSignalPaths: [],
      );
      expect(r.hasUnmatchedSignals, isFalse);
    });

    test('hasUnmatchedSignals is true when list is non-empty', () {
      const r = GtkwImportResult(
        sessionState: SessionState(),
        matchedSignalCount: 1,
        groupCount: 0,
        markerCount: 0,
        unmatchedSignalPaths: ['top.missing'],
      );
      expect(r.hasUnmatchedSignals, isTrue);
    });

    test('toString includes all counts', () {
      const r = GtkwImportResult(
        sessionState: SessionState(),
        matchedSignalCount: 2,
        groupCount: 1,
        markerCount: 3,
        unmatchedSignalPaths: ['bad'],
      );
      expect(r.toString(), contains('matched: 2'));
      expect(r.toString(), contains('groups: 1'));
      expect(r.toString(), contains('markers: 3'));
      expect(r.toString(), contains('unmatched: 1'));
    });
  });

  // ── Signal matching ───────────────────────────────────────────────────────

  group('GtkwImportService — signal matching', () {
    test('exact full-path match resolves signal', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwSignalEntry(
            path: 'top.clk',
            format: DisplayFormat.hexadecimal,
          ),
        ],
      );
      final r = _import(gtkw);
      expect(r.matchedSignalCount, 1);
      expect(r.unmatchedSignalPaths, isEmpty);
      expect(r.sessionState.signalGroup.entries.first.signalRef, 'ref_clk');
      expect(r.sessionState.signalGroup.entries.first.displayName, 'clk');
    });

    test('case-insensitive full-path match', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwSignalEntry(
            path: 'TOP.CLK',
            format: DisplayFormat.hexadecimal,
          ),
        ],
      );
      final r = _import(gtkw);
      expect(r.matchedSignalCount, 1);
    });

    test('name-only suffix match used as fallback', () {
      // Path prefix differs — only the last component 'clk' matches.
      const gtkw = GtkwFile(
        entries: [
          GtkwSignalEntry(
            path: 'tb.dut.clk',
            format: DisplayFormat.hexadecimal,
          ),
        ],
      );
      final r = _import(gtkw);
      expect(r.matchedSignalCount, 1);
    });

    test('bit-range suffix stripped before matching', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwSignalEntry(
            path: 'top.data[7:0]',
            format: DisplayFormat.hexadecimal,
          ),
        ],
      );
      final r = _import(gtkw);
      expect(r.matchedSignalCount, 1);
      expect(r.unmatchedSignalPaths, isEmpty);
    });

    test('unresolvable path goes to unmatchedSignalPaths', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwSignalEntry(
            path: 'top.nonexistent',
            format: DisplayFormat.hexadecimal,
          ),
        ],
      );
      final r = _import(gtkw);
      expect(r.matchedSignalCount, 0);
      expect(r.unmatchedSignalPaths, ['top.nonexistent']);
    });

    test('empty variable list results in all unmatched', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwSignalEntry(
            path: 'top.clk',
            format: DisplayFormat.hexadecimal,
          ),
        ],
      );
      final r = _import(gtkw, variables: []);
      expect(r.matchedSignalCount, 0);
      expect(r.unmatchedSignalPaths.length, 1);
    });

    test('signalRef comes from Variable.signalRef, not the path string', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwSignalEntry(
            path: 'top.rst',
            format: DisplayFormat.hexadecimal,
          ),
        ],
      );
      final r = _import(gtkw);
      expect(r.sessionState.signalGroup.entries.first.signalRef, 'ref_rst');
    });
  });

  // ── Format preservation ───────────────────────────────────────────────────

  group('GtkwImportService — format preservation', () {
    test('binary format preserved in SignalEntry', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwSignalEntry(path: 'top.clk', format: DisplayFormat.binary),
        ],
      );
      final r = _import(gtkw);
      expect(
        r.sessionState.signalGroup.entries.first.format,
        DisplayFormat.binary,
      );
    });

    test('signedDecimal format preserved', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwSignalEntry(
            path: 'top.data',
            format: DisplayFormat.signedDecimal,
          ),
        ],
      );
      final r = _import(gtkw);
      expect(
        r.sessionState.signalGroup.entries.first.format,
        DisplayFormat.signedDecimal,
      );
    });
  });

  // ── Color preservation ────────────────────────────────────────────────────

  group('GtkwImportService — color preservation', () {
    test('colorArgb preserved in SignalEntry', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwSignalEntry(
            path: 'top.clk',
            format: DisplayFormat.hexadecimal,
            colorArgb: 0xFFFF0000,
          ),
        ],
      );
      final r = _import(gtkw);
      expect(r.sessionState.signalGroup.entries.first.argbColor, 0xFFFF0000);
    });

    test('null colorArgb yields null in SignalEntry', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwSignalEntry(
            path: 'top.clk',
            format: DisplayFormat.hexadecimal,
          ),
        ],
      );
      final r = _import(gtkw);
      expect(r.sessionState.signalGroup.entries.first.argbColor, isNull);
    });
  });

  // ── Group assembly ────────────────────────────────────────────────────────

  group('GtkwImportService — group assembly', () {
    test('group begin/end wraps child signals', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwGroupBeginEntry('Clocks'),
          GtkwSignalEntry(path: 'top.clk', format: DisplayFormat.hexadecimal),
          GtkwSignalEntry(path: 'top.rst', format: DisplayFormat.hexadecimal),
          GtkwGroupEndEntry('Clocks'),
        ],
      );
      final r = _import(gtkw);
      expect(r.groupCount, 1);
      expect(r.sessionState.signalGroup.entries.length, 1);
      final group = r.sessionState.signalGroup.entries.first;
      expect(group.kind, SignalEntryKind.group);
      expect(group.groupName, 'Clocks');
      expect(group.children.length, 2);
    });

    test('nested groups assembled correctly', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwGroupBeginEntry('Outer'),
          GtkwGroupBeginEntry('Inner'),
          GtkwSignalEntry(path: 'top.clk', format: DisplayFormat.hexadecimal),
          GtkwGroupEndEntry('Inner'),
          GtkwGroupEndEntry('Outer'),
        ],
      );
      final r = _import(gtkw);
      expect(r.groupCount, 2);
      final outer = r.sessionState.signalGroup.entries.first;
      expect(outer.kind, SignalEntryKind.group);
      final inner = outer.children.first;
      expect(inner.kind, SignalEntryKind.group);
      expect(inner.children.length, 1);
    });

    test('separator entries produce SignalEntry.separator', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwSignalEntry(path: 'top.clk', format: DisplayFormat.hexadecimal),
          GtkwSeparatorEntry(),
          GtkwSignalEntry(path: 'top.rst', format: DisplayFormat.hexadecimal),
        ],
      );
      final r = _import(gtkw);
      expect(
        r.sessionState.signalGroup.entries[1].kind,
        SignalEntryKind.separator,
      );
    });

    test('comment entries produce SignalEntry.comment', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwCommentEntry('My label'),
          GtkwSignalEntry(path: 'top.clk', format: DisplayFormat.hexadecimal),
        ],
      );
      final r = _import(gtkw);
      final comment = r.sessionState.signalGroup.entries.first;
      expect(comment.kind, SignalEntryKind.comment);
      expect(comment.text, 'My label');
    });

    test('unmatched signal inside group excluded but group still created', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwGroupBeginEntry('Bus'),
          GtkwSignalEntry(path: 'top.clk', format: DisplayFormat.hexadecimal),
          GtkwSignalEntry(path: 'top.bogus', format: DisplayFormat.hexadecimal),
          GtkwGroupEndEntry('Bus'),
        ],
      );
      final r = _import(gtkw);
      expect(r.unmatchedSignalPaths, ['top.bogus']);
      final group = r.sessionState.signalGroup.entries.first;
      expect(group.kind, SignalEntryKind.group);
      expect(group.children.length, 1); // only the matched signal
    });

    test('unclosed group at end of file handled gracefully', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwGroupBeginEntry('Open'),
          GtkwSignalEntry(path: 'top.clk', format: DisplayFormat.hexadecimal),
          // No GtkwGroupEndEntry — parser exhausts the cursor
        ],
      );
      final r = _import(gtkw);
      // The group is still created with the contained signal.
      expect(r.sessionState.signalGroup.entries.length, 1);
      expect(
        r.sessionState.signalGroup.entries.first.kind,
        SignalEntryKind.group,
      );
    });
  });

  // ── Markers ───────────────────────────────────────────────────────────────

  group('GtkwImportService — markers', () {
    test('named markers transferred to MarkerState', () {
      const gtkw = GtkwFile(namedMarkers: {'a': 100, 'b': 200});
      final r = _import(gtkw);
      expect(r.markerCount, 2);
      expect(r.sessionState.markerState.getMarker('a'), 100);
      expect(r.sessionState.markerState.getMarker('b'), 200);
    });

    test('no markers when namedMarkers is empty', () {
      const gtkw = GtkwFile();
      final r = _import(gtkw);
      expect(r.markerCount, 0);
      expect(r.sessionState.markerState.markers, isEmpty);
    });

    test('primary marker becomes the primary cursor, not a named marker', () {
      const gtkw = GtkwFile(primaryMarker: 81110, namedMarkers: {'a': 5});
      final r = _import(gtkw);
      expect(r.sessionState.cursorState.primaryCursorTime, 81110);
      expect(r.sessionState.cursorState.secondaryCursorTime, isNull);
      expect(r.markerCount, 1);
      expect(r.sessionState.markerState.markers, {'a': 5});
    });

    test('no primary cursor when the primary marker is unset', () {
      const gtkw = GtkwFile();
      final r = _import(gtkw);
      expect(r.sessionState.cursorState.primaryCursorTime, isNull);
    });
  });

  // ── Session metadata ──────────────────────────────────────────────────────

  group('GtkwImportService — session metadata', () {
    test('timeStart sets panOffsetTicks', () {
      const gtkw = GtkwFile(timeStart: 500);
      final r = _import(gtkw);
      expect(r.sessionState.panOffsetTicks, 500.0);
    });

    test('null timeStart yields zero panOffsetTicks', () {
      const gtkw = GtkwFile();
      final r = _import(gtkw);
      expect(r.sessionState.panOffsetTicks, 0.0);
      // The result tells "absent" apart from a start time of zero.
      expect(r.panOffsetTicks, isNull);
    });

    test('timeStart is carried on the result for the viewer to apply', () {
      final r = _import(const GtkwFile(timeStart: 500));
      expect(r.panOffsetTicks, 500.0);
    });

    test('sourceFilePath override takes precedence over dumpFilePath', () {
      const gtkw = GtkwFile(dumpFilePath: '/original.vcd');
      final r = _import(gtkw, sourceFilePath: '/override.vcd');
      expect(r.sessionState.sourceFilePath, '/override.vcd');
    });

    test('dumpFilePath used when no sourceFilePath override', () {
      const gtkw = GtkwFile(dumpFilePath: '/sim/out.vcd');
      final r = _import(gtkw);
      expect(r.sessionState.sourceFilePath, '/sim/out.vcd');
    });

    test('null dumpFilePath and no override yields null sourceFilePath', () {
      const gtkw = GtkwFile();
      final r = _import(gtkw);
      expect(r.sessionState.sourceFilePath, isNull);
    });
  });

  // ── matchedSignalCount ────────────────────────────────────────────────────

  group('GtkwImportService — matchedSignalCount', () {
    test('counts matched signals recursively through groups', () {
      const gtkw = GtkwFile(
        entries: [
          GtkwSignalEntry(path: 'top.clk', format: DisplayFormat.hexadecimal),
          GtkwGroupBeginEntry('Bus'),
          GtkwSignalEntry(path: 'top.rst', format: DisplayFormat.hexadecimal),
          GtkwSignalEntry(path: 'top.data', format: DisplayFormat.hexadecimal),
          GtkwGroupEndEntry('Bus'),
        ],
      );
      final r = _import(gtkw);
      expect(r.matchedSignalCount, 3);
    });

    test('empty .gtkw yields zero matched', () {
      const gtkw = GtkwFile();
      final r = _import(gtkw);
      expect(r.matchedSignalCount, 0);
    });
  });

  // ── canvasBackgroundHex passthrough ────────────────────────────────────────

  group('GtkwImportResult — canvasBackgroundHex', () {
    test('canvasBackgroundHex is null when absent from .gtkw', () {
      const gtkw = GtkwFile();
      final r = _import(gtkw);
      expect(r.canvasBackgroundHex, isNull);
    });

    test('canvasBackgroundHex is passed through from GtkwFile', () {
      const gtkw = GtkwFile(canvasBackgroundHex: '#002B36');
      final r = _import(gtkw);
      expect(r.canvasBackgroundHex, '#002B36');
    });

    test(
      'hasUnmatchedSignals is false when canvasBackgroundHex is the only field',
      () {
        const gtkw = GtkwFile(canvasBackgroundHex: '#1A1A1A');
        final r = _import(gtkw);
        expect(r.hasUnmatchedSignals, isFalse);
      },
    );
  });

  // ── A real GTKWave 3.3.115 save, end to end ────────────────────────────────

  group('GtkwImportService — real GTKWave 3.3.115 save (mealy FSM)', () {
    // The save GTKWave 3.3.115 wrote for mealy_state_machine_tb in
    // JeffDeCola/my-verilog-examples (MIT), with named markers A and B, a
    // Stimulus group and three colors added in GTKWave's own syntax. Its `*`
    // line leaves the primary marker unset (-1) and sets A=2500, B=6100 — the
    // layout that used to import as markers b and c.
    const mealyGtkw = '''
[*]
[*] GTKWave Analyzer v3.3.115 (w)1999-2023 BSI
[*] Wed May 10 05:09:32 2023
[*]
[dumpfile] "/home/jeff/verilog/my-verilog-examples/sequential-logic/finite-state-machines/mealy_state_machine/mealy_state_machine_tb.vcd"
[dumpfile_mtime] "Wed May 10 05:08:09 2023"
[dumpfile_size] 2953
[savefile] "/home/jeff/verilog/my-verilog-examples/sequential-logic/finite-state-machines/mealy_state_machine/mealy_state_machine_tb.gtkw"
[timestart] 0
[size] 1203 600
[pos] 51 223
*-17.277769 -1 2500 6100 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1
[treeopen] MEALY_STATE_MACHINE_TB.
[sst_width] 204
[signals_width] 110
[sst_expanded] 1
[sst_vpaned_height] 152
@800200
-Stimulus
@28
MEALY_STATE_MACHINE_TB.CLK
MEALY_STATE_MACHINE_TB.RST
[color] 5
MEALY_STATE_MACHINE_TB.IN
@1000200
-Stimulus
@200
-
@24
[color] 3
MEALY_STATE_MACHINE_TB.UUT_mealy_state_machine_behavioral.state[2:0]
@200
-
@28
[color] 4
MEALY_STATE_MACHINE_TB.FOUND
[pattern_trace] 1
[pattern_trace] 0
''';

    // The variables wellen reports for mealy_state_machine_tb.vcd (the Icarus
    // dump), as scope path + name. `state [2:0]` arrives as `state`.
    const tb = 'MEALY_STATE_MACHINE_TB';
    const uut = '$tb.UUT_mealy_state_machine_behavioral';
    final mealyVars = [
      for (final n in [
        'FOUND',
        'CLKPERIOD',
        'CLK',
        'COMMENT',
        'ERRORS',
        'FOUNDEXP',
        'IN',
        'RST',
        'VECTORCOUNT',
        'COUNT',
        'FD',
      ])
        _mkVar(tb, n),
      for (final n in [
        'clk',
        'in',
        'rst',
        'S1',
        'S2',
        'S3',
        'START',
        'WAIT',
        'ZERO',
        'found',
        'state',
      ])
        _mkVar(uut, n),
    ];

    GtkwImportResult importMealy() => _service.importSession(
      const GtkwParser().parse(mealyGtkw),
      mealyVars,
    );

    test('zoom, start time and the open scope are carried', () {
      final r = importMealy();
      // 2^17.277769 / 200: GTKWave's zoom exponent as ticks per pixel.
      expect(r.ticksPerPixel, closeTo(794.5, 0.1));
      expect(r.sessionState.ticksPerPixel, r.ticksPerPixel);
      expect(r.panOffsetTicks, 0.0);
      expect(r.sessionState.expandedScopePaths, {tb});
      expect(r.filterIssues, isEmpty);
      expect(r.sessionState.translateFilterPaths, isEmpty);
    });

    test('markers are exactly A=2500 and B=6100, with no cursor', () {
      final r = importMealy();
      expect(r.sessionState.markerState.markers, {'a': 2500, 'b': 6100});
      expect(r.markerCount, 2);
      expect(r.sessionState.cursorState.primaryCursorTime, isNull);
    });

    test('every signal matches', () {
      final r = importMealy();
      expect(r.unmatchedSignalPaths, isEmpty);
      expect(r.matchedSignalCount, 5);
    });

    test('Stimulus group holds CLK, RST and IN; IN is blue', () {
      final r = importMealy();
      expect(r.groupCount, 1);
      final group = r.sessionState.signalGroup.entries.first;
      expect(group.kind, SignalEntryKind.group);
      expect(group.groupName, 'Stimulus');
      expect(group.children.map((e) => e.displayName), ['CLK', 'RST', 'IN']);
      expect(group.children[2].argbColor, 0xFF6699FF); // [color] 5
    });

    test('state is decimal and yellow; FOUND is green', () {
      final r = importMealy();
      final signals = {
        for (final e in r.sessionState.signalGroup.entries)
          if (e.kind == SignalEntryKind.signal) e.displayName: e,
      };
      expect(signals['state']!.format, DisplayFormat.unsignedDecimal); // @24
      expect(signals['state']!.argbColor, 0xFFFFFF00); // [color] 3
      expect(signals['FOUND']!.argbColor, 0xFF00FF00); // [color] 4
    });
  });

  // ── Zoom ──────────────────────────────────────────────────────────────────

  group('GtkwImportService — zoom', () {
    test('converts GTKWave zoom exponents to ticks per pixel', () {
      // ticks per pixel = max(2^-z, 1) / 200 (GTKWave's calczoom).
      expect(GtkwImportService.ticksPerPixelForZoom(-19), 2621.44);
      expect(GtkwImportService.ticksPerPixelForZoom(-1), 0.01);
      // A frame narrower than one time unit is floored at one unit.
      expect(GtkwImportService.ticksPerPixelForZoom(3), 0.005);
    });

    test('the zoom lands on the session and the result', () {
      final r = _import(const GtkwFile(zoomFactor: -10));
      expect(r.ticksPerPixel, closeTo(5.12, 1e-9));
      expect(r.sessionState.ticksPerPixel, closeTo(5.12, 1e-9));
    });

    test('no zoom in the file leaves the result zoom null', () {
      final r = _import(const GtkwFile());
      expect(r.ticksPerPixel, isNull);
    });

    test('a non-finite zoom is ignored', () {
      final r = _import(const GtkwFile(zoomFactor: double.nan));
      expect(r.ticksPerPixel, isNull);
    });
  });

  // ── Expanded scopes ───────────────────────────────────────────────────────

  group('GtkwImportService — [treeopen] scopes', () {
    test('trailing dots are dropped and paths match the dump scopes', () {
      final r = _import(const GtkwFile(openScopes: ['top.', 'top.cpu.']));
      expect(r.sessionState.expandedScopePaths, {'top', 'top.cpu'});
    });

    test('match falls back to case-insensitive', () {
      final r = _import(const GtkwFile(openScopes: ['TOP.CPU.']));
      expect(r.sessionState.expandedScopePaths, {'top.cpu'});
    });

    test('a scope the dump does not have is dropped', () {
      final r = _import(const GtkwFile(openScopes: ['other.', '.', '']));
      expect(r.sessionState.expandedScopePaths, isEmpty);
    });

    test('an ancestor with no variables of its own still matches', () {
      final r = _import(
        const GtkwFile(openScopes: ['a.']),
        variables: [_mkVar('a.b.c', 'x')],
      );
      expect(r.sessionState.expandedScopePaths, {'a'});
    });
  });

  // ── Translate filters ─────────────────────────────────────────────────────

  group('GtkwImportService — translate filters', () {
    GtkwFile withFilter(String filter, {String? savedFilePath}) =>
        const GtkwParser().parse(
          '${savedFilePath == null ? '' : '[savefile] "$savedFilePath"\n'}'
          '@2022\n^1 $filter\ntop.data[7:0]\n@28\ntop.clk\n',
        );

    test('a found filter is keyed by the matched signal ref', () {
      final r = _service.importSession(
        withFilter('/proj/states.txt'),
        _fixtureVars,
        gtkwFilePath: '/proj/view.gtkw',
        fileExists: (path) => path == '/proj/states.txt',
      );
      expect(r.sessionState.translateFilterPaths, {
        'ref_data': '/proj/states.txt',
      });
      expect(r.filterIssues, isEmpty);
    });

    test('a moved project re-anchors the filter beside the save file', () {
      final r = _service.importSession(
        withFilter(
          '/home/jeff/proj/filters/states.txt',
          savedFilePath: '/home/jeff/proj/waves/view.gtkw',
        ),
        _fixtureVars,
        gtkwFilePath: '/Users/me/checkout/waves/view.gtkw',
        fileExists: (path) =>
            path == '/Users/me/checkout/filters/states.txt' ||
            path == '/home/jeff/proj/filters/states.txt',
      );
      // GTKWave's own rule wins over the literal path.
      expect(
        r.sessionState.translateFilterPaths['ref_data'],
        '/Users/me/checkout/filters/states.txt',
      );
    });

    test('a relative filter path resolves against the save file', () {
      final r = _service.importSession(
        withFilter('filters/states.txt'),
        _fixtureVars,
        gtkwFilePath: '/proj/view.gtkw',
        sourceFilePath: '/sim/out.vcd',
        fileExists: (path) => path == '/proj/filters/states.txt',
      );
      expect(
        r.sessionState.translateFilterPaths['ref_data'],
        '/proj/filters/states.txt',
      );
    });

    test('a relative filter path falls back to the dump directory', () {
      final r = _service.importSession(
        withFilter('filters/states.txt'),
        _fixtureVars,
        gtkwFilePath: '/proj/view.gtkw',
        sourceFilePath: '/sim/out.vcd',
        fileExists: (path) => path == '/sim/filters/states.txt',
      );
      expect(
        r.sessionState.translateFilterPaths['ref_data'],
        '/sim/filters/states.txt',
      );
    });

    test('the file name alone is tried beside the save, then the dump', () {
      final besideDump = _service.importSession(
        withFilter('/elsewhere/states.txt'),
        _fixtureVars,
        gtkwFilePath: '/proj/view.gtkw',
        sourceFilePath: '/sim/out.vcd',
        fileExists: (path) => path == '/sim/states.txt',
      );
      expect(
        besideDump.sessionState.translateFilterPaths['ref_data'],
        '/sim/states.txt',
      );
    });

    test('a missing filter is reported, not dropped silently', () {
      final r = _service.importSession(
        withFilter('/proj/gone.txt'),
        _fixtureVars,
        gtkwFilePath: '/proj/view.gtkw',
        fileExists: (_) => false,
      );
      expect(r.sessionState.translateFilterPaths, isEmpty);
      expect(r.hasFilterIssues, isTrue);
      expect(r.filterIssues, [
        const GtkwFilterIssue(
          signalPath: 'top.data[7:0]',
          filterPath: '/proj/gone.txt',
          kind: GtkwFilterIssueKind.missingFile,
        ),
      ]);
      // The trace itself still imports.
      expect(r.matchedSignalCount, 2);
      expect(r.hasUnmatchedSignals, isFalse);
    });

    test('without fileExists every filter is reported missing', () {
      final r = _import(withFilter('/proj/states.txt'));
      expect(r.filterIssues.single.kind, GtkwFilterIssueKind.missingFile);
    });

    test('a filter on an unmatched signal is not reported twice', () {
      final r = _service.importSession(
        const GtkwParser().parse('@2022\n^1 /f.txt\ntop.nothere\n'),
        _fixtureVars,
        fileExists: (_) => false,
      );
      expect(r.unmatchedSignalPaths, ['top.nothere']);
      expect(r.filterIssues, isEmpty);
    });

    test('process and transaction filters are reported as not imported', () {
      final r = _service.importSession(
        const GtkwParser().parse(
          '@4022\n^>1 /bin/decode\ntop.cpu.addr\n'
          '@10000022\n^<1 /bin/txn\ntop.cpu.dout\n',
        ),
        _fixtureVars,
        fileExists: (_) => true,
      );
      expect(r.sessionState.translateFilterPaths, isEmpty);
      expect(r.filterIssues.map((i) => (i.signalPath, i.kind)), [
        ('top.cpu.addr', GtkwFilterIssueKind.process),
        ('top.cpu.dout', GtkwFilterIssueKind.transaction),
      ]);
    });

    test('GtkwFilterIssue equality and toString', () {
      const a = GtkwFilterIssue(
        signalPath: 's',
        filterPath: 'f',
        kind: GtkwFilterIssueKind.process,
      );
      const b = GtkwFilterIssue(
        signalPath: 's',
        filterPath: 'f',
        kind: GtkwFilterIssueKind.process,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('process'));
    });
  });

  group('GtkwImportService.resolveFilterPath', () {
    test('a Windows-written path re-anchors by its own separators', () {
      final resolved = GtkwImportService.resolveFilterPath(
        r'C:\proj\filters\states.txt',
        savedFilePath: r'C:\proj\waves\view.gtkw',
        gtkwFilePath: '/Users/me/proj/waves/view.gtkw',
        fileExists: (path) => path == '/Users/me/proj/filters/states.txt',
      );
      expect(resolved, '/Users/me/proj/filters/states.txt');
    });

    test('no candidate found returns null', () {
      expect(
        GtkwImportService.resolveFilterPath(
          '/x/y.txt',
          gtkwFilePath: '/proj/view.gtkw',
          fileExists: (_) => false,
        ),
        isNull,
      );
    });
  });
}
