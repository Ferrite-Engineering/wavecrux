// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// build_web_wasm.dart — rebuild the wellen_wasm crate and refresh
// `web/wasm/` with the compiled artefacts.
//
// The web build uses a WebAssembly-backed wellen provider so it has the same
// VCD/FST/GHW parsing surface as the desktop/mobile FFI build. The Rust crate
// lives in `native/wellen_wasm/`; this script invokes `wasm-pack`, copies the
// output into `web/wasm/`, and verifies the gzipped bundle stays under its
// size budget — every web user downloads the module before the first open,
// so its size is the web build's first-load cost.
//
// Run from the repository root any time the Rust crate, its dependencies,
// or the loader JS change. CI invokes this script before `flutter build web`
// so the wasm bundle is always in sync with the source.
//
//   dart run tool/build_web_wasm.dart           # release build, default
//   dart run tool/build_web_wasm.dart --check   # verify size only, no build
//
// Prerequisites:
//   * rustup target add wasm32-unknown-unknown
//   * cargo install wasm-pack (or use the official installer)
//
// Bundle-size budget: gzipped `wellen_wasm_bg.wasm` ≤ 1.5 MB. Regressions
// fail with a non-zero exit code so CI catches them on the same PR that
// causes them. Adjust the budget in `_maxGzippedBytes` only with a deliberate
// review.
//
// ignore_for_file: avoid_print

import 'dart:io';

const _crateDir = 'native/wellen_wasm';
const _outDir = 'web/wasm';
const _wasmFileName = 'wellen_wasm_bg.wasm';
const _jsFileName = 'wellen_wasm.js';
const _maxGzippedBytes = 1572864; // 1.5 MiB

Future<int> main(List<String> args) async {
  final checkOnly = args.contains('--check');
  if (!checkOnly) {
    print('▶ Building $_crateDir with wasm-pack...');
    final result = await Process.run(
      'wasm-pack',
      ['build', _crateDir, '--target', 'web', '--release'],
      runInShell: true,
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      stderr.writeln(
        '✗ wasm-pack failed. Did you `rustup target add wasm32-unknown-unknown`?',
      );
      return result.exitCode;
    }

    print('▶ Copying artifacts to $_outDir/...');
    final pkgDir = Directory('$_crateDir/pkg');
    if (!pkgDir.existsSync()) {
      stderr.writeln('✗ Expected output directory missing: ${pkgDir.path}');
      return 2;
    }
    final outDir = Directory(_outDir);
    outDir.createSync(recursive: true);
    for (final name in const [_wasmFileName, _jsFileName]) {
      final src = File('${pkgDir.path}/$name');
      if (!src.existsSync()) {
        stderr.writeln('✗ Expected artifact not found: ${src.path}');
        return 2;
      }
      src.copySync('$_outDir/$name');
      print('  copied $name → $_outDir/$name');
    }
  }

  // Bundle-size gate. Computes gzipped size in pure Dart so the gate works
  // on every developer machine without needing `gzip` installed.
  final wasmPath = '$_outDir/$_wasmFileName';
  final wasmFile = File(wasmPath);
  if (!wasmFile.existsSync()) {
    stderr.writeln('✗ Wasm output missing — run without --check first.');
    return 3;
  }
  final raw = wasmFile.readAsBytesSync();
  final gz = gzip.encode(raw);

  final rawKb = (raw.length / 1024).toStringAsFixed(1);
  final gzKb = (gz.length / 1024).toStringAsFixed(1);
  final budgetKb = (_maxGzippedBytes / 1024).toStringAsFixed(1);

  print('');
  print('Bundle size:');
  print('  raw:      ${raw.length} bytes ($rawKb KiB)');
  print('  gzipped:  ${gz.length} bytes ($gzKb KiB)');
  print('  budget:   $_maxGzippedBytes bytes ($budgetKb KiB)');

  if (gz.length > _maxGzippedBytes) {
    stderr.writeln('');
    stderr.writeln(
      '✗ Bundle exceeds gzipped budget by ${gz.length - _maxGzippedBytes} '
      'bytes — investigate which crate feature(s) grew. Every web user '
      'downloads the module before the first open.',
    );
    return 4;
  }
  print('✓ Within budget.');
  return 0;
}
