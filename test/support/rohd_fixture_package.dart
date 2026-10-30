// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the committed ROHD fixtures are; see `verification/fixtures/rohd`.
const String kRohdFixtureDir = 'verification/fixtures/rohd';

/// A Dart package on disk the way the machine that ran the design left it:
/// `pubspec.yaml`, the design in `lib/`, and a `build/` folder holding the
/// waveform and its source-trace file.
///
/// The fixtures were generated in `/work/rohd_fixture`, a folder that does not
/// exist here, so resolving the Dart paths has to find the package from where
/// the files were put, as it will for a user who moved them.
class RohdFixturePackage {
  RohdFixturePackage._(this.root);

  /// Creates the package in a fresh temporary directory. [sidecar] copies
  /// `Top.flc.json` beside the waveform.
  factory RohdFixturePackage.create({bool sidecar = true}) {
    final root = Directory.systemTemp.createTempSync('wavecrux_rohd_').path;
    File(
      p.join(root, 'pubspec.yaml'),
    ).writeAsStringSync('name: rohd_fixture\n');
    Directory(p.join(root, 'lib')).createSync();
    File(
      p.join(kRohdFixtureDir, 'generator', 'design.dart.txt'),
    ).copySync(p.join(root, 'lib', 'design.dart'));
    final build = Directory(p.join(root, 'build'))..createSync();
    File(
      p.join(kRohdFixtureDir, 'top.vcd'),
    ).copySync(p.join(build.path, 'top.vcd'));
    if (sidecar) {
      File(
        p.join(kRohdFixtureDir, 'Top.flc.json'),
      ).copySync(p.join(build.path, 'Top.flc.json'));
    }
    return RohdFixturePackage._(root);
  }

  /// The package root.
  final String root;

  /// The generated `build/` folder.
  String get build => p.join(root, 'build');

  /// A path under [build].
  String inBuild(String name) => p.join(build, name);

  /// A path under the package.
  String path(String relative) => p.join(root, relative);

  /// Removes the package.
  void dispose() {
    final dir = Directory(root);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// Every `(scopePath, name)` of the `$var`s in a VCD's header, in order: what
/// WaveCrux's signal tree holds for the file.
List<(String, String)> vcdSignals(String vcdText) {
  final scope = <String>[];
  final out = <(String, String)>[];
  for (final line in vcdText.split('\n')) {
    final t = line.trim().split(RegExp(r'\s+'));
    if (t.isEmpty) continue;
    switch (t[0]) {
      case r'$scope':
        scope.add(t[2]);
      case r'$upscope':
        scope.removeLast();
      case r'$var':
        out.add((scope.join('.'), t[4]));
      case r'$enddefinitions':
        return out;
    }
  }
  return out;
}
