// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wavecrux/services/rohd/rohd_sidecar_locator.dart';

import '../../support/rohd_fixture_package.dart';

void main() {
  late RohdFixturePackage pkg;
  late List<LogRecord> logs;
  late StreamSubscription<LogRecord> sub;

  setUp(() {
    logs = <LogRecord>[];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(logs.add);
  });
  tearDown(() async {
    await sub.cancel();
    pkg.dispose();
  });

  group('the file beside the waveform', () {
    test(
      'Top.flc.json beside top.vcd is found with no configuration',
      () async {
        pkg = RohdFixturePackage.create();
        final map = await loadRohdWaveMap(waveformPath: pkg.inBuild('top.vcd'));
        final source = map!.resolve('top', 'gated')!;
        // Normalized, and found in the package even though the sidecar says
        // /work/rohd_fixture.
        expect(source.primary.file, pkg.path('lib/design.dart'));
        expect(source.primary.file, isNot(contains('.dart_tool')));
        expect(source.primary.line, 59);
        expect(source.primary.target, '${pkg.path('lib/design.dart')}:59:19');
      },
    );

    test(
      'a file named for the waveform is preferred over a stranger',
      () async {
        pkg = RohdFixturePackage.create(sidecar: false);
        File(pkg.inBuild('a.flc.json')).writeAsStringSync(
          File('$kRohdFixtureDir/Top.flc.json').readAsStringSync().replaceAll(
            '"0:59:19"',
            '"0:77:7"',
          ),
        );
        File(
          '$kRohdFixtureDir/Top.flc.json',
        ).copySync(pkg.inBuild('top.flc.json'));
        final map = await loadRohdWaveMap(waveformPath: pkg.inBuild('top.vcd'));
        expect(map!.resolve('top', 'gated')!.primary.line, 59);
      },
    );

    test(
      'with several sidecars, the one that describes the open design wins',
      () async {
        pkg = RohdFixturePackage.create(sidecar: false);
        File(pkg.inBuild('a.flc.json')).writeAsStringSync(
          '{"version":6,"files":["lib/x.dart"],"modules":{"Other":{'
          '"sourceOccurrences":[{"path":"other_top"}],'
          '"tree":[["0:1:1","gated"]]}}}',
        );
        File(
          '$kRohdFixtureDir/Top.flc.json',
        ).copySync(pkg.inBuild('z.flc.json'));
        final map = await loadRohdWaveMap(
          waveformPath: pkg.inBuild('top.vcd'),
          topScopes: {'top'},
        );
        expect(map!.knowsPath('top'), isTrue);
        expect(map.resolve('top', 'gated')!.primary.line, 59);
      },
    );

    test('no sidecar anywhere is null, not an error', () async {
      pkg = RohdFixturePackage.create(sidecar: false);
      expect(
        await loadRohdWaveMap(waveformPath: pkg.inBuild('top.vcd')),
        isNull,
      );
      expect(logs.where((r) => r.level >= Level.WARNING), isEmpty);
    });

    test('a waveform in a folder that is gone is null', () async {
      pkg = RohdFixturePackage.create(sidecar: false);
      expect(
        await loadRohdWaveMap(waveformPath: '${pkg.root}/nowhere/top.vcd'),
        isNull,
      );
    });
  });

  group('the setting', () {
    test('a file anywhere', () async {
      pkg = RohdFixturePackage.create(sidecar: false);
      final elsewhere = Directory(pkg.path('trace'))..createSync();
      File(
        '$kRohdFixtureDir/Top.flc.json',
      ).copySync('${elsewhere.path}/Top.flc.json');
      final map = await loadRohdWaveMap(
        waveformPath: pkg.inBuild('top.vcd'),
        configured: '${elsewhere.path}/Top.flc.json',
      );
      expect(map!.resolve('top', 'gated'), isNotNull);
    });

    test('a folder holding some', () async {
      pkg = RohdFixturePackage.create(sidecar: false);
      final elsewhere = Directory(pkg.path('trace'))..createSync();
      File(
        '$kRohdFixtureDir/Top.flc.json',
      ).copySync('${elsewhere.path}/Top.flc.json');
      final map = await loadRohdWaveMap(
        waveformPath: pkg.inBuild('top.vcd'),
        configured: elsewhere.path,
      );
      expect(map!.resolve('top', 'gated'), isNotNull);
    });

    test(
      'a path that does not exist falls through to the file beside it',
      () async {
        pkg = RohdFixturePackage.create();
        final map = await loadRohdWaveMap(
          waveformPath: pkg.inBuild('top.vcd'),
          configured: '${pkg.root}/missing.flc.json',
        );
        expect(map!.resolve('top', 'gated'), isNotNull);
      },
    );
  });

  group('a sidecar that cannot be used', () {
    test(
      'an unknown version is skipped, logged once, and nothing is offered',
      () async {
        pkg = RohdFixturePackage.create();
        File(pkg.inBuild('Top.flc.json')).writeAsStringSync('{"version": 7}');
        final map = await loadRohdWaveMap(waveformPath: pkg.inBuild('top.vcd'));
        expect(map, isNull);
        final warnings = logs.where((r) => r.level == Level.WARNING).toList();
        expect(warnings, hasLength(1));
        expect(warnings.single.message, contains('version 7'));
      },
    );

    test(
      'a truncated one is skipped and a later good one still serves',
      () async {
        pkg = RohdFixturePackage.create(sidecar: false);
        File(
          pkg.inBuild('top.flc.json'),
        ).writeAsStringSync('{"version": 6, "fi');
        File(
          '$kRohdFixtureDir/Top.flc.json',
        ).copySync(pkg.inBuild('z.flc.json'));
        final map = await loadRohdWaveMap(waveformPath: pkg.inBuild('top.vcd'));
        expect(map!.resolve('top', 'gated'), isNotNull);
      },
    );
  });
}
