// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stems_entry.dart';
import 'package:wavecrux/services/rtl_source/verilator_ast_stems_importer.dart';

/// Tests for the Verilator `--json-only` AST → stems importer.
///
/// The committed fixtures under `test/fixtures/rtl_source/verilator_ast/`
/// were generated with Verilator 5.048 via
/// `tool/generate_verilator_ast_fixtures.sh` — see the README there.
void main() {
  const importer = VerilatorAstStemsImporter();

  final fixtureRoot =
      '${Directory.current.path}/test/fixtures/rtl_source/verilator_ast';

  // ── synthetic-dump helpers ─────────────────────────────────────────────────

  /// A minimal meta JSON with one user file (`e`) and one internal file (`d`).
  String metaJson({String userPath = 'src/top.v'}) => jsonEncode({
    'files': {
      'e': {'filename': userPath, 'realpath': userPath, 'language': '1800'},
      'd': {
        'filename': '<verilated_std>',
        'realpath': '<verilated_std>',
        'language': '1800',
      },
    },
    'pointers': <String, Object?>{},
  });

  Map<String, Object?> varNode(
    String name,
    int line, {
    String varType = 'WIRE',
    String file = 'e',
  }) => {
    'type': 'VAR',
    'name': name,
    'loc': '$file,$line:3,$line:10',
    'varType': varType,
  };

  Map<String, Object?> cellNode(String name, int line, String modRef) => {
    'type': 'CELL',
    'name': name,
    'loc': 'e,$line:5,$line:12',
    'modp': modRef,
  };

  Map<String, Object?> moduleNode(
    String name,
    String addr,
    int line,
    List<Object?> stmts, {
    String file = 'e',
  }) => {
    'type': 'MODULE',
    'name': name,
    'addr': addr,
    'loc': '$file,$line:8,$line:11',
    'stmtsp': stmts,
  };

  String treeJson(List<Object?> modules) =>
      jsonEncode({'type': 'NETLIST', 'name': r'$root', 'modulesp': modules});

  group('cpu fixture (multi-module hierarchy)', () {
    test('imports the full elaborated hierarchy with correct kinds', () async {
      final result = await importer.importFromPath(
        '$fixtureRoot/cpu/Vtop.tree.json',
      );

      expect(result.resolvedTop, 'top');
      expect(result.availableTops, ['top']);

      const cpuDir = 'test/fixtures/rtl_source/cpu';
      StemsEntry entry(String path) =>
          result.stems.entries.firstWhere((e) => e.path == path);

      // 3 scopes + 15 variables = 18 entries, all with elaborated
      // per-instance paths.
      expect(result.stems.entries, hasLength(18));

      expect(entry('top').kind, StemsEntryKind.scope);
      expect(entry('top').sourceFile, '$cpuDir/top.v');
      expect(entry('top').lineNumber, 3);

      expect(entry('top.u_regfile').kind, StemsEntryKind.scope);
      expect(entry('top.u_regfile').sourceFile, '$cpuDir/regfile.v');
      expect(entry('top.u_regfile').lineNumber, 2);

      expect(entry('top.u_alu').kind, StemsEntryKind.scope);
      expect(entry('top.u_alu').sourceFile, '$cpuDir/alu.v');

      expect(entry('top.u_regfile.mem').kind, StemsEntryKind.variable);
      expect(entry('top.u_regfile.mem').sourceFile, '$cpuDir/regfile.v');
      expect(entry('top.u_regfile.mem').lineNumber, 8);

      expect(entry('top.u_alu.y').kind, StemsEntryKind.variable);

      final variablePaths = result.stems.entries
          .where((e) => e.kind == StemsEntryKind.variable)
          .map((e) => e.path)
          .toSet();
      expect(
        variablePaths,
        containsAll(<String>{
          'top.clk', 'top.rst_n', 'top.instr', 'top.result',
          'top.op_a', 'top.op_b', 'top.alu_out', //
          'top.u_regfile.clk', 'top.u_regfile.rst_n',
          'top.u_regfile.a', 'top.u_regfile.b', 'top.u_regfile.mem',
          'top.u_alu.a', 'top.u_alu.b', 'top.u_alu.y',
        }),
      );
    });

    test('emits no entries from Verilator-internal files', () async {
      final result = await importer.importFromPath(
        '$fixtureRoot/cpu/Vtop.tree.json',
      );
      for (final entry in result.stems.entries) {
        expect(entry.sourceFile, isNot(startsWith('<')));
      }
    });

    test('auto-locates the sibling meta and honors an explicit one', () async {
      final auto = await importer.importFromPath(
        '$fixtureRoot/cpu/Vtop.tree.json',
      );
      final explicit = await importer.importFromPath(
        '$fixtureRoot/cpu/Vtop.tree.json',
        metaPath: '$fixtureRoot/cpu/Vtop.tree.meta.json',
      );
      expect(explicit.stems, auto.stems);
    });
  });

  group('genloop fixture (unrolled generate-for)', () {
    test('emits indexed generate scopes matching the waveform '
        'hierarchy', () async {
      final result = await importer.importFromPath(
        '$fixtureRoot/genloop/Vtop.tree.json',
      );

      expect(result.resolvedTop, 'top');
      final paths = result.stems.entries.map((e) => e.path).toSet();

      for (var i = 0; i < 4; i++) {
        expect(paths, contains('top.gen_blink[$i]'));
        expect(paths, contains('top.gen_blink[$i].u_blink'));
        expect(paths, contains('top.gen_blink[$i].u_blink.clk'));
        expect(paths, contains('top.gen_blink[$i].u_blink.led'));
      }

      StemsEntry entry(String path) =>
          result.stems.entries.firstWhere((e) => e.path == path);
      expect(entry('top.gen_blink[2]').kind, StemsEntryKind.scope);
      expect(entry('top.gen_blink[2].u_blink').kind, StemsEntryKind.scope);
      expect(
        entry('top.gen_blink[2].u_blink.led').kind,
        StemsEntryKind.variable,
      );
    });

    test('skips the contentless loop-wrapper scope and the genvar', () async {
      final result = await importer.importFromPath(
        '$fixtureRoot/genloop/Vtop.tree.json',
      );
      final paths = result.stems.entries.map((e) => e.path).toSet();
      // The unrolled loop leaves a contentless "gen_blink" wrapper GENBLOCK
      // alongside the indexed blocks; it has no waveform counterpart.
      expect(paths, isNot(contains('top.gen_blink')));
      // The genvar `i` is not a waveform signal.
      expect(paths, isNot(contains('top.i')));
    });
  });

  group('tolerance (schema surprises warn, never throw)', () {
    test('malformed tree JSON', () {
      final result = importer.import(
        treeJson: '{"type": "NETLIST", truncated',
        metaJson: metaJson(),
      );
      expect(result.stems.isEmpty, isTrue);
      expect(result.resolvedTop, isNull);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, contains('tree JSON'));
    });

    test('malformed meta JSON', () {
      final result = importer.import(
        treeJson: treeJson([]),
        metaJson: 'not json at all',
      );
      expect(result.stems.isEmpty, isTrue);
      expect(result.warnings.single, contains('meta JSON'));
    });

    test('tree JSON that is valid but not an object', () {
      final result = importer.import(treeJson: '[1, 2]', metaJson: metaJson());
      expect(result.stems.isEmpty, isTrue);
      expect(result.warnings.single, contains('not a JSON object'));
    });

    test('meta JSON without a files table', () {
      final result = importer.import(
        treeJson: treeJson([
          moduleNode('top', '(A)', 3, [varNode('clk', 4)]),
        ]),
        metaJson: '{"pointers": {}}',
      );
      expect(result.stems.isEmpty, isTrue);
      expect(result.warnings.single, contains('files'));
    });

    test('tree with no modules', () {
      final result = importer.import(
        treeJson: treeJson([]),
        metaJson: metaJson(),
      );
      expect(result.stems.isEmpty, isTrue);
      expect(result.warnings.single, contains('No modules'));
    });

    test('unknown node types are descended through silently', () {
      final result = importer.import(
        treeJson: treeJson([
          moduleNode('top', '(A)', 3, [
            {
              'type': 'SOME_FUTURE_NODE',
              'name': 'x',
              'weird': {
                'itemsp': [varNode('clk', 4)],
              },
            },
          ]),
        ]),
        metaJson: metaJson(),
      );
      expect(result.warnings, isEmpty);
      expect(result.stems.entries.map((e) => e.path), contains('top.clk'));
    });

    test('unresolvable modp pointer keeps the instance scope and '
        'warns', () {
      final result = importer.import(
        treeJson: treeJson([
          moduleNode('top', '(A)', 3, [
            varNode('clk', 4),
            cellNode('u_ghost', 6, '(ZZ)'),
          ]),
        ]),
        metaJson: metaJson(),
      );
      final entry = result.stems.entries.firstWhere(
        (e) => e.path == 'top.u_ghost',
      );
      expect(entry.kind, StemsEntryKind.scope);
      expect(entry.lineNumber, 6); // the instantiation site
      expect(result.warnings.single, contains('u_ghost'));
    });

    test('VAR nodes with parameter/genvar varTypes are skipped', () {
      final result = importer.import(
        treeJson: treeJson([
          moduleNode('top', '(A)', 3, [
            varNode('WIDTH', 4, varType: 'GPARAM'),
            varNode('DEPTH', 5, varType: 'LPARAM'),
            varNode('i', 6, varType: 'GENVAR'),
            varNode('clk', 7),
          ]),
        ]),
        metaJson: metaJson(),
      );
      final paths = result.stems.entries.map((e) => e.path).toSet();
      expect(paths, {'top', 'top.clk'});
    });

    test('entries in Verilator-internal files are filtered', () {
      final result = importer.import(
        treeJson: treeJson([
          moduleNode('top', '(A)', 3, [
            varNode('clk', 4),
            varNode('std_thing', 9, file: 'd'),
          ]),
        ]),
        metaJson: metaJson(),
      );
      final paths = result.stems.entries.map((e) => e.path).toSet();
      expect(paths, {'top', 'top.clk'});
    });

    test('unknown file references warn once and skip the entries', () {
      final result = importer.import(
        treeJson: treeJson([
          moduleNode('top', '(A)', 3, [
            varNode('a', 4, file: 'q'),
            varNode('b', 5, file: 'q'),
            varNode('clk', 6),
          ]),
        ]),
        metaJson: metaJson(),
      );
      expect(result.stems.entries.map((e) => e.path).toSet(), {
        'top',
        'top.clk',
      });
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, contains('"q"'));
    });

    test('cyclic instantiation truncates the branch with a warning', () {
      final result = importer.import(
        treeJson: treeJson([
          moduleNode('a', '(A)', 1, [cellNode('u_b', 2, '(B)')]),
          moduleNode('b', '(B)', 5, [cellNode('u_a', 6, '(A)')]),
        ]),
        // Neither module is a top candidate (both are instantiated), so
        // pass one explicitly.
        metaJson: metaJson(),
        topModule: 'a',
      );
      expect(result.resolvedTop, 'a');
      final paths = result.stems.entries.map((e) => e.path).toSet();
      expect(paths, contains('a.u_b'));
      expect(paths, contains('a.u_b.u_a')); // recorded, not descended
      expect(result.warnings.single, contains('Cyclic'));
    });
  });

  group('top-module resolution', () {
    final twoTops = treeJson([
      moduleNode('alpha', '(A)', 1, [varNode('x', 2)]),
      moduleNode('beta', '(B)', 5, [varNode('y', 6)]),
    ]);

    test('multiple candidate tops surface availableTops and warn', () {
      final result = importer.import(treeJson: twoTops, metaJson: metaJson());
      expect(result.resolvedTop, isNull);
      expect(result.availableTops, ['alpha', 'beta']);
      expect(result.stems.isEmpty, isTrue);
      expect(result.warnings.single, contains('Multiple candidate'));
    });

    test('an explicit topModule resolves the ambiguity', () {
      final result = importer.import(
        treeJson: twoTops,
        metaJson: metaJson(),
        topModule: 'beta',
      );
      expect(result.resolvedTop, 'beta');
      expect(result.availableTops, ['alpha', 'beta']);
      expect(result.stems.entries.map((e) => e.path).toSet(), {
        'beta',
        'beta.y',
      });
    });

    test('an unknown requested top falls back with a warning', () {
      final result = importer.import(
        treeJson: treeJson([
          moduleNode('top', '(A)', 3, [varNode('clk', 4)]),
        ]),
        metaJson: metaJson(),
        topModule: 'nonexistent',
      );
      expect(result.resolvedTop, 'top'); // unique top auto-detected
      expect(result.warnings.single, contains('nonexistent'));
    });

    test('compiler-internal modules are never top candidates', () {
      final result = importer.import(
        treeJson: treeJson([
          moduleNode('top', '(A)', 3, [varNode('clk', 4)]),
          moduleNode('@CONST-POOL@', '(CP)', 0, [], file: 'd'),
        ]),
        metaJson: metaJson(),
      );
      expect(result.resolvedTop, 'top');
      expect(result.availableTops, ['top']);
    });
  });

  group('cross-machine dumps', () {
    test('absolute paths from another machine still produce entries', () {
      final result = importer.import(
        treeJson: treeJson([
          moduleNode('top', '(A)', 3, [varNode('clk', 4)]),
        ]),
        metaJson: metaJson(userPath: '/home/otheruser/proj/src/top.v'),
      );
      // Path resolution is downstream's concern (same as stems files): the
      // entries carry the recorded path verbatim.
      expect(result.stems.entries, hasLength(2));
      for (final entry in result.stems.entries) {
        expect(entry.sourceFile, '/home/otheruser/proj/src/top.v');
      }
    });
  });

  group('importFromPath IO tolerance', () {
    test('missing tree file warns, never throws', () async {
      final result = await importer.importFromPath(
        '$fixtureRoot/does_not_exist.tree.json',
      );
      expect(result.stems.isEmpty, isTrue);
      expect(result.warnings.single, contains('does_not_exist.tree.json'));
    });

    test('missing meta file warns with the expected sibling path', () async {
      // A tree that exists but has no sibling meta: point at a copy.
      final dir = await Directory.systemTemp.createTemp('wavecrux_ast_test');
      addTearDown(() => dir.delete(recursive: true));
      final orphan = File('${dir.path}/Vtop.tree.json');
      await File(
        '$fixtureRoot/cpu/Vtop.tree.json',
      ).copy(orphan.path);

      final result = await importer.importFromPath(orphan.path);
      expect(result.stems.isEmpty, isTrue);
      expect(result.warnings.single, contains('Vtop.tree.meta.json'));
    });
  });
}
