// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/rohd/rohd_sidecar.dart';
import 'package:wavecrux/services/rohd/rohd_wave_map.dart';

import '../../support/rohd_fixture_package.dart';

String _identity(String raw) => raw.replaceFirst('.dart_tool/../', '');

RohdWaveMap _map(Object json) => RohdWaveMap.fromSidecar(
  parseRohdSidecar(jsonEncode(json)).sidecar!,
  resolveFile: _identity,
);

RohdWaveMap _real() => RohdWaveMap.fromSidecar(
  parseRohdSidecar(
    File('$kRohdFixtureDir/Top.flc.json').readAsStringSync(),
  ).sidecar!,
  resolveFile: _identity,
);

void main() {
  group('the real ROHD waveform joined to the real sidecar', () {
    final map = _real();
    final signals = vcdSignals(
      File('$kRohdFixtureDir/top.vcd').readAsStringSync(),
    );

    test('resolves every signal but the whole-struct aggregate', () {
      final missed = <String>[
        for (final (scope, name) in signals)
          if (map.resolve(scope, name) == null) '$scope.$name',
      ];
      expect(signals, hasLength(32));
      // `inner_pkt` is the struct as one wire: the trace has its fields, not it.
      expect(missed, ['top.inner_pkt']);
    });

    test('a port and an internal signal map to their declaring line', () {
      expect(
        map.resolve('top', 'gated')!.primary.toString(),
        'lib/design.dart:59:19',
      );
      expect(map.resolve('top', 'clk')!.primary.line, 44);
    });

    test(
      'a signal inside a submodule lists where the module was instantiated',
      () {
        final sum = map.resolve('top.adder', 'sum')!;
        expect(sum.primary.line, 24);
        expect(sum.calledFrom.map((l) => l.line), [58]);
      },
    );

    test('the keyword-renamed instance resolves through the rename', () {
      // The sidecar says `top.reg`; the waveform and the SystemVerilog `reg_`.
      final q = map.resolve('top.reg_', 'q')!;
      expect(q.primary.line, 36);
      expect(map.resolve('top.reg_.flipflop', '_q')!.primary.line, 37);
      expect(map.resolve('top.reg_.flipflop.sequential', '_in0__d'), isNotNull);
    });

    test('a struct field matches the original name the sidecar kept', () {
      expect(map.resolve('top', 'valid')!.primary.line, 9);
      expect(map.resolve('top', 'data')!.primary.line, 8);
    });

    test('the ROHD-internal scopes map to the call that made them', () {
      final comb = map.resolve('top.combinational', '_out4_gated')!;
      expect(comb.primary.line, 60);
      expect(map.resolve('top.adder.add', '_a_add_b_carry')!.primary.line, 26);
    });

    test('knowsPath answers for both spellings of a renamed instance', () {
      expect(map.knowsPath('top'), isTrue);
      expect(map.knowsPath('top.reg_'), isTrue);
      expect(map.knowsPath('top.reg'), isTrue);
      expect(map.knowsPath('nothing.here'), isFalse);
    });

    test('unknown scopes and names resolve to nothing', () {
      expect(map.resolve('elsewhere', 'gated'), isNull);
      expect(map.resolve('top', 'not_a_signal'), isNull);
      expect(map.resolve('', ''), isNull);
    });

    test('two bus slices that trace to one Dart line are not a choice', () {
      final s = map.resolve('top.bussubset', '_original_pkt')!;
      expect(s.candidates, 1);
      expect(s.ambiguous, isFalse);
      expect(s.primary.line, 52);
    });
  });

  group('the bus-slice ambiguity', () {
    final map = _map({
      'version': 6,
      'files': ['lib/d.dart'],
      'modules': {
        'BusSubset': {
          'sourceOccurrences': [
            {'path': 'top.slice'},
            {'path': 'top.slice'},
          ],
          'tree': [
            ['0:10:3', '_original_pkt', '_subset_7_0_pkt'],
            ['0:20:3', '_original_pkt', '_subset_8_8_pkt'],
          ],
        },
      },
    });

    test('slices from different lines: the first is returned, and counted', () {
      final s = map.resolve('top.slice', '_original_pkt')!;
      expect(s.ambiguous, isTrue);
      expect(s.candidates, 2);
      expect(s.primary.line, 10, reason: 'the first the sidecar listed');
    });

    test('the choice does not depend on how often it is asked', () {
      for (var i = 0; i < 3; i++) {
        expect(map.resolve('top.slice', '_original_pkt')!.primary.line, 10);
      }
    });

    test('a name only one slice has is exact', () {
      final s = map.resolve('top.slice', '_subset_8_8_pkt')!;
      expect(s.ambiguous, isFalse);
      expect(s.primary.line, 20);
    });
  });

  group('the keyword-rename fix-up', () {
    final map = _map({
      'version': 6,
      'files': ['lib/d.dart'],
      'modules': {
        'Leaf': {
          'sourceOccurrences': [
            {'path': 'top.reg.wire.inner'},
          ],
          'tree': [
            ['0:5:5', 'x'],
          ],
        },
      },
    });

    test('drops a trailing underscore from any part, fewest drops first', () {
      expect(map.resolve('top.reg_.wire_.inner', 'x'), isNotNull);
      expect(map.resolve('top.reg_.wire.inner', 'x'), isNotNull);
      expect(map.resolve('top.reg.wire.inner', 'x'), isNotNull);
    });

    test('does not strip an underscore the instance really has', () {
      final exact = _map({
        'version': 6,
        'files': ['lib/d.dart'],
        'modules': {
          'A': {
            'sourceOccurrences': [
              {'path': 'top.u_'},
            ],
            'tree': [
              ['0:1:1', 'plain'],
            ],
          },
          'B': {
            'sourceOccurrences': [
              {'path': 'top.u'},
            ],
            'tree': [
              ['0:2:2', 'plain'],
            ],
          },
        },
      });
      expect(exact.resolve('top.u_', 'plain')!.primary.line, 1);
      expect(exact.resolve('top.u', 'plain')!.primary.line, 2);
    });

    test('a path with very many renamed parts stays cheap', () {
      final path = List.filled(60, 'p_').join('.');
      expect(map.resolve(path, 'x'), isNull);
    });
  });

  test('a frame whose file index is not in the table is skipped', () {
    final map = _map({
      'version': 6,
      'files': ['lib/d.dart'],
      'modules': {
        'M': {
          'sourceOccurrences': [
            {'path': 'top'},
          ],
          'tree': [
            ['9:1:1', 'orphan'],
            ['0:3:3', 'fine'],
          ],
        },
      },
    });
    expect(map.resolve('top', 'orphan'), isNull);
    expect(map.resolve('top', 'fine')!.primary.line, 3);
  });
}
