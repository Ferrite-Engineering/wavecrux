// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/app.dart';

/// `wavecrux --help` on a desktop build must end the process.
///
/// A Flutter desktop runner creates its window at launch and keeps its event
/// loop alive after Dart's `main` returns. bootstrap's `--help` branch printed
/// the usage and returned, so the executable then sat there with an empty
/// window. runWaveCrux exits after a headless invocation; the exit is
/// injected here.
void main() {
  test('--help ends the process with exit code 0', () async {
    for (final flag in ['--help', '-h']) {
      int? exitedWith;
      await runWaveCrux(
        args: [flag],
        exitProcess: (code) async => exitedWith = code,
      );
      expect(exitedWith, 0, reason: flag);
    }
  });

  test('bootstrap reports --help as headless, before any GUI starts', () async {
    expect(await bootstrap(args: const ['--help']), isTrue);
  });

  test('the open-core entry point goes through runWaveCrux', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('runWaveCrux(args: args)'));
  });
}
