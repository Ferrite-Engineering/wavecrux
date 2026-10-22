// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/services/waveform/streaming_vcd_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

/// Variables declared outside any `$scope` are shown by both readers.
///
/// `yosys-smtbmc` writes `smt_step` and `smt_clock` before the first `$scope`
/// of every witness trace SymbiYosys and EQY produce. Both readers present
/// such variables as one unnamed root scope (the shape a file with no scopes
/// at all already had), ahead of the named scopes. The expectations here are
/// read off each file's text, never off a reader.
void main() {
  final captured = p.join(
    Directory.current.path,
    'test',
    'fixtures',
    'formal',
    'captured',
    'sby',
    'handshake_imm',
    'captured',
    'prove_bug',
    'engine_0',
    'trace.vcd',
  );

  final readers = <String, WaveformDataSource Function()>{
    'streaming parser': StreamingVcdService.new,
  };
  if (requireWellenFfiLibrary('root-level variables, native reader')) {
    readers['native reader'] = WellenProvider.new;
  }

  late Directory tmp;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('root_level_vars_'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  Future<WaveformDataSource> open(
    WaveformDataSource Function() make,
    String path,
  ) async {
    final source = make();
    await source.openFile(path);
    if (source is StreamingVcdService) await source.streamEndedFuture;
    addTearDown(source.close);
    return source;
  }

  for (final entry in readers.entries) {
    group('${entry.key}: a captured formal witness trace', () {
      test('shows smt_step and smt_clock, declared before the first scope, '
          'in an unnamed root scope ahead of the design', () async {
        final text = File(captured).readAsStringSync();
        final declared = _declaredBeforeFirstScope(text);
        expect(declared.map((d) => d.name), ['smt_step', 'smt_clock']);

        final source = await open(entry.value, captured);
        final roots = source.rootScopes;
        expect(roots.first.name, '');
        expect(roots.first.path, '');
        expect(roots.first.childScopes, isEmpty);
        expect(roots.first.variables.map((v) => v.name), [
          for (final d in declared) d.name,
        ]);
        expect(roots.first.variables.every((v) => v.scopePath == ''), isTrue);
        expect(roots.first.variables.first.bitWidth, 32);
        // The design keeps its own scope, after the unnamed one.
        expect(roots.skip(1).map((s) => s.name), ['handshake_imm']);
      });

      test('findVariables finds them, and smt_step carries the value the '
          'file gives it at every step', () async {
        final text = File(captured).readAsStringSync();
        final id = _declaredBeforeFirstScope(
          text,
        ).singleWhere((d) => d.name == 'smt_step').id;
        final expected = _valueChanges(text, id);
        expect(expected.length, greaterThan(2));

        final source = await open(entry.value, captured);
        final found = source.findVariables(
          const SignalFilter(namePattern: 'smt_*'),
        );
        expect(found.map((v) => v.name).toSet(), {'smt_step', 'smt_clock'});

        final step = found.singleWhere((v) => v.name == 'smt_step');
        await source.loadSignal(step.signalRef);
        final changes = source.changesInRange(
          step.signalRef,
          source.startTime,
          source.endTime + 1,
        );
        expect(
          [for (final c in changes) (c.time, int.parse(c.value, radix: 2))],
          expected,
        );
      });
    });

    group('${entry.key}: a file mixing root-level and scoped variables', () {
      test('the root-level ones sit in one unnamed scope, in declaration '
          'order, including one declared after a scope closed', () async {
        final path = p.join(tmp.path, '${entry.key.hashCode}_mixed.vcd');
        File(path).writeAsStringSync(_mixed);
        final source = await open(entry.value, path);

        final roots = source.rootScopes;
        expect(roots.map((s) => s.name), ['', 'top']);
        expect(roots[0].variables.map((v) => v.name), ['rootA', 'rootB']);
        expect(roots[0].variables.map((v) => v.scopePath), ['', '']);
        expect(roots[1].variables.map((v) => v.name), ['clk']);
        expect(roots[1].variables.single.scopePath, 'top');
        expect(
          source.findVariables(const SignalFilter()).map((v) => v.name).toSet(),
          {'rootA', 'rootB', 'clk'},
        );
      });
    });

    group('${entry.key}: a file with no scopes at all', () {
      test('still shows its variables in the one unnamed root scope', () async {
        final path = p.join(tmp.path, '${entry.key.hashCode}_flat.vcd');
        File(path).writeAsStringSync(_flat);
        final source = await open(entry.value, path);

        final roots = source.rootScopes;
        expect(roots, hasLength(1));
        expect(roots.single.name, '');
        expect(roots.single.path, '');
        expect(roots.single.variables.map((v) => v.name), ['a', 'b']);
        expect(roots.single.variables.map((v) => v.scopePath), ['', '']);
      });
    });
  }

  if (readers.length == 2) {
    test('both readers present the captured trace identically', () async {
      final streaming = await open(readers['streaming parser']!, captured);
      final native = await open(readers['native reader']!, captured);
      expect(_shape(streaming.rootScopes), _shape(native.rootScopes));
    });
  }
}

/// A scope tree as text: names, paths and variable names, so two readers'
/// trees compare without their reader-specific signal references.
List<String> _shape(List<Scope> scopes) => [
  for (final s in scopes)
    [
      s.name,
      s.path,
      [
        for (final v in s.variables)
          // An event has no width to compare: the native reader leaves it
          // unset where the streaming parser keeps the declared 1.
          [
            v.name,
            v.scopePath,
            if (v.varType == VarType.event) '-' else '${v.bitWidth}',
          ].join('@'),
      ].join(','),
      _shape(s.childScopes).join(';'),
    ].join('|'),
];

/// The `$var` declarations that appear before the first `$scope` of [vcd].
List<({String id, String name})> _declaredBeforeFirstScope(String vcd) {
  final out = <({String id, String name})>[];
  final decl = RegExp(r'^\$var\s+\w+\s+\d+\s+(\S+)\s+(\S+)');
  for (final line in vcd.split('\n')) {
    if (line.startsWith(r'$scope')) break;
    final m = decl.firstMatch(line);
    if (m != null) out.add((id: m.group(1)!, name: m.group(2)!));
  }
  return out;
}

/// Every `(time, value)` the text of [vcd] gives the vector with [id].
List<(int, int)> _valueChanges(String vcd, String id) {
  final out = <(int, int)>[];
  var time = 0;
  final change = RegExp('^b([01]+) ${RegExp.escape(id)}\$');
  for (final line in vcd.split('\n')) {
    if (line.startsWith('#')) {
      time = int.parse(line.substring(1));
      continue;
    }
    final m = change.firstMatch(line.trim());
    if (m != null) out.add((time, int.parse(m.group(1)!, radix: 2)));
  }
  return out;
}

const _mixed = r'''
$timescale 1ns $end
$var wire 1 ! rootA $end
$scope module top $end
$var wire 1 " clk $end
$upscope $end
$var wire 8 # rootB $end
$enddefinitions $end
#0
0!
0"
b00000001 #
#10
1!
1"
b00000010 #
''';

const _flat = r'''
$timescale 1ns $end
$var wire 1 ! a $end
$var wire 4 " b $end
$enddefinitions $end
#0
0!
b0000 "
#10
1!
b0101 "
''';
