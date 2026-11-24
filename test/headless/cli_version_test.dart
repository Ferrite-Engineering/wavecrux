// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The headless binary's constants against the manifests they restate: the
// version every document names against `pubspec.yaml`, and the wellen
// series against `native/wellen_ffi/Cargo.toml` and its lockfile.

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/headless/cli_version.dart';
import 'package:wavecrux/native/wellen_ffi_library_io.dart';

void main() {
  test('the version is the pubspec version without its build number', () {
    final line = File(
      'pubspec.yaml',
    ).readAsLinesSync().firstWhere((l) => l.startsWith('version: '));
    final version = line.substring('version: '.length).split('+').first;
    expect(kWaveCruxCliVersion, version);
  });

  test('the wellen series is the one the FFI crate builds against', () {
    final manifest = File('native/wellen_ffi/Cargo.toml').readAsStringSync();
    expect(manifest, contains('wellen = "$kWellenEngineVersion"'));
    final lock = File('native/wellen_ffi/Cargo.lock').readAsStringSync();
    final resolved = RegExp(
      r'name = "wellen"\r?\nversion = "([^"]+)"',
    ).firstMatch(lock)!.group(1)!;
    expect(resolved, startsWith('$kWellenEngineVersion.'));
  });

  test('the binary looks for the library beside it, then in ../lib', () {
    final name = wellenFfiLibraryFileName();
    final sep = Platform.pathSeparator;
    final exe = ['', 'opt', 'wavecrux', 'bin', 'wavecrux'].join(sep);
    expect(wellenFfiBesideExecutable(exe), <String>[
      ['', 'opt', 'wavecrux', 'bin', name].join(sep),
      ['', 'opt', 'wavecrux', 'lib', name].join(sep),
    ]);
  });
}
