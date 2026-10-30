// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/rohd/rohd_sidecar.dart';

import '../../support/rohd_fixture_package.dart';

void main() {
  group('parseRohdSidecar — real ROHD output', () {
    final sidecar = parseRohdSidecar(
      File('$kRohdFixtureDir/Top.flc.json').readAsStringSync(),
    ).sidecar!;

    RohdModule module(String name) =>
        sidecar.modules.firstWhere((m) => m.name == name);

    test('reads the files table and the package root', () {
      expect(sidecar.files, ['.dart_tool/../lib/design.dart']);
      expect(sidecar.packageRoot, '/work/rohd_fixture');
    });

    test('a module lists every hierarchy path that shares it', () {
      expect(module('Top').instancePaths, ['top']);
      expect(module('Reg').instancePaths, ['top.reg']);
      // Two bus slices of one signal: one path, listed twice.
      expect(module('BusSubset').instancePaths, [
        'top.bussubset',
        'top.bussubset',
      ]);
    });

    test(
      'leaves carry their frames outermost first, and the renamed original',
      () {
        final sum = module('Top').leaves.firstWhere((l) => l.name == 'sum');
        expect(sum.frames.map((f) => f.toString()), ['0:58:19', '0:24:15']);
        final valid = module(
          'Top',
        ).leaves.firstWhere((l) => l.name == 'inner_pkt_valid');
        expect(valid.original, 'valid');
        final adder = module('Top').leaves.firstWhere((l) => l.name == 'adder');
        expect(adder.isInstance, isTrue);
      },
    );
  });

  group('parseRohdSidecar — what it refuses', () {
    test('an unknown or missing version is unusable, saying which', () {
      final other = parseRohdSidecar('{"version": 5}');
      expect(other.sidecar, isNull);
      expect(other.problem, contains('version 5'));
      expect(parseRohdSidecar('{}').problem, contains('no version'));
    });

    test('text that is not a JSON object is unusable', () {
      for (final text in ['', '{"version":', '[6]', 'null']) {
        final r = parseRohdSidecar(text);
        expect(r.sidecar, isNull, reason: text);
        expect(r.problem, isNotEmpty, reason: text);
      }
    });

    test('wrong types inside a version 6 file are skipped, not thrown', () {
      final r = parseRohdSidecar(
        jsonEncode({
          'version': 6,
          'files': ['a.dart', 3],
          'packageRoot': 7,
          'modules': {
            'Bad': 5,
            'Odd': {
              'sourceOccurrences': [
                {'path': 'top'},
                {'path': 4},
                'x',
              ],
              'tree': <Object>[
                'str',
                <Object>[],
                <Object>[1],
                <Object>['0:1:1', 'ok@sv:2:3', 9, '@sv:1:1'],
              ],
            },
          },
        }),
      );
      final s = r.sidecar!;
      expect(s.files, ['a.dart']);
      expect(s.packageRoot, isNull);
      final odd = s.modules.single;
      expect(odd.instancePaths, ['top']);
      expect(odd.leaves.map((l) => l.name), ['ok']);
    });

    test('a tree nested far deeper than any real one does not overflow', () {
      var node = '["0:1:1","leaf"]';
      for (var i = 0; i < 5000; i++) {
        node = '["0:1:1",$node]';
      }
      expect(
        parseRohdSidecar(
          '{"version":6,"modules":{"M":{"tree":[$node]}}}',
        ).sidecar,
        isNotNull,
      );
    });
  });
}
