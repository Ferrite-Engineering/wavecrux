// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// build_lxt2fst_wasm.dart — rebuild the lxt2fst crate and refresh
// `web/wasm/` with the compiled artefacts.
//
// The web build ships a WebAssembly-backed LXT/LXT2 → FST converter so the
// Flutter Web build can open legacy waveform captures uploaded through
// the file picker. The Rust crate lives in `native/lxt2fst/`; this
// script invokes `wasm-pack`, copies the output into `web/wasm/`, and
// verifies the gzipped bundle stays under its 400 KiB budget — the module
// is fetched on a user's first LXT/LXT2 open, so its size is that open's
// latency.
//
// Run from the repository root any time the Rust crate or its
// dependencies change — including the vendored `native/vendor/fst-writer`.
// CI invokes this script before `flutter build web` so the wasm bundle is
// always in sync with the source. Mirrors the structure of
// `tool/build_web_wasm.dart`.
//
// The hand-written `web/wasm/lxt2fst_loader.js` is not generated here: it
// lazily imports the `lxt2fst.js` glue this script copies and publishes it
// as `globalThis.waveCruxLxt2Fst`. Keep its calls in step with the
// `#[wasm_bindgen(js_name = ...)]` exports in `native/lxt2fst/src/wasm.rs`.
//
//   dart run tool/build_lxt2fst_wasm.dart           # release build, default
//   dart run tool/build_lxt2fst_wasm.dart --check   # verify size only, no build
//
// Prerequisites:
//   * rustup target add wasm32-unknown-unknown
//   * cargo install wasm-pack (or use the official installer)
//
// Bundle-size budget: gzipped `lxt2fst_bg.wasm` ≤ 400 KiB. Regressions
// fail with a non-zero exit code so CI catches them on the same PR that
// causes them. Adjust the budget in `_maxGzippedBytes` only with a
// deliberate review.
//
// ignore_for_file: avoid_print

import 'dart:io';

const _crateDir = 'native/lxt2fst';
const _outDir = 'web/wasm';
const _wasmFileName = 'lxt2fst_bg.wasm';
const _jsFileName = 'lxt2fst.js';
const _maxGzippedBytes = 409600; // 400 KiB

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
      'bytes — investigate which crate feature(s) grew. The module is '
      'fetched on the first LXT/LXT2 open, so its size is that latency.',
    );
    return 4;
  }
  print('✓ Within budget.');
  return 0;
}
