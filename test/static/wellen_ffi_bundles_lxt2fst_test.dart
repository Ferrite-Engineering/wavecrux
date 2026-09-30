// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: the LXT/LXT2 converter ships inside the wellen FFI library on
// every platform.
//
// No platform bundles a standalone liblxt2fst. The Rust `wellen_ffi` crate
// links `lxt2fst`, so the one library each build already compiles, signs and
// loads also exports `lxt2fst_*`, and the Dart converter opens that library.
// The arrangement has four ways to rot silently, each of which once meant (or
// would mean) every LXT/LXT2 open failing in a shipped build while the Rust
// and Dart unit tests stayed green:
//
//  * the crate link or the fst-writer patch drifts between the two manifests;
//  * iOS dead-strips a symbol the keepalive list forgot (Dart finds it with
//    dlsym, so nothing references it at link time);
//  * the committed iOS xcframework is not rebuilt after the link;
//  * a platform build stops treating lxt2fst sources as rebuild inputs.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Function names declared in a C header (`ret name(args);`).
Set<String> _declaredFunctions(String header, String prefix) => {
  for (final m in RegExp(
    '\\b(${prefix}_[a-z0-9_]+)\\s*\\(',
  ).allMatches(header))
    m.group(1)!,
};

void main() {
  test('wellen_ffi links lxt2fst and both builds patch fst-writer alike', () {
    final wellen = File('native/wellen_ffi/Cargo.toml').readAsStringSync();
    final lxt2fst = File('native/lxt2fst/Cargo.toml').readAsStringSync();
    final lib = File('native/wellen_ffi/src/lib.rs').readAsStringSync();

    expect(wellen, contains('lxt2fst = { path = "../lxt2fst" }'));
    expect(
      lib,
      contains('pub use lxt2fst as _lxt2fst;'),
      reason:
          'without a use, the crate (and its no_mangle exports) is not '
          'linked into the cdylib/staticlib',
    );
    // `[patch]` applies only at the root of a build, so the web build (rooted
    // at lxt2fst) and the native build (rooted at wellen_ffi) each need it.
    const patch = 'fst-writer = { path = "../vendor/fst-writer" }';
    for (final (name, manifest) in [
      ('wellen_ffi', wellen),
      ('lxt2fst', lxt2fst),
    ]) {
      expect(manifest, contains('[patch.crates-io]'), reason: name);
      expect(manifest, contains(patch), reason: name);
    }
    expect(
      File('native/vendor/fst-writer/LICENSE').existsSync(),
      isTrue,
      reason: 'the vendored crate must carry its BSD-3-Clause licence',
    );
  });

  test('the iOS keepalive retains every wellen_* and lxt2fst_* function', () {
    final keepalive = File(
      'native/wellen_ffi/Sources/WellenFFIKeepalive/wellen_ffi_keepalive.c',
    ).readAsStringSync();
    final required = {
      ..._declaredFunctions(
        File('native/wellen_ffi/wellen_ffi.h').readAsStringSync(),
        'wellen',
      ),
      ..._declaredFunctions(
        File('native/lxt2fst/include/lxt2fst.h').readAsStringSync(),
        'lxt2fst',
      ),
    };
    expect(required, containsAll(<String>['wellen_open', 'lxt2fst_convert']));

    final missing = [
      for (final fn in required)
        if (!keepalive.contains('extern void $fn(void);') ||
            !keepalive.contains('(const void*)&$fn,'))
          fn,
    ]..sort();
    expect(
      missing,
      isEmpty,
      reason:
          'Declared in the headers but not kept alive: iOS strips these from '
          'the Runner binary and the Dart lookup fails at runtime. Add an '
          'extern declaration and an array entry for each.',
    );
  });

  test('the WellenFFI package manifest resolves (tools-version on line 1)', () {
    // SwiftPM before 6.0 rejects a manifest whose `swift-tools-version`
    // comment is not its first line, and every iOS build then fails at
    // package resolution — before the xcframework is ever linked.
    final manifest = File('native/wellen_ffi/Package.swift').readAsLinesSync();
    expect(manifest.first, startsWith('// swift-tools-version:'));
  });

  test('the committed WellenFFI.xcframework carries the converter', () {
    final slices = Directory('native/wellen_ffi/WellenFFI.xcframework')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('libwellen_ffi.a'))
        .toList();
    expect(slices, hasLength(2), reason: 'device + simulator slices');
    for (final slice in slices) {
      final symbols = latin1.decode(slice.readAsBytesSync());
      for (final symbol in [
        '_lxt2fst_convert',
        '_lxt2fst_abi_version',
        '_wellen_last_open_error',
      ]) {
        expect(
          symbols.contains(symbol),
          isTrue,
          reason:
              '${slice.path} has no $symbol. Xcode never runs cargo for iOS: '
              'rerun scripts/build_ios.sh and commit the xcframework.',
        );
      }
    }
  });

  test('every native build treats lxt2fst sources as rebuild inputs', () {
    for (final path in [
      'linux/CMakeLists.txt',
      'windows/CMakeLists.txt',
      'android/app/build.gradle.kts',
      'macos/Runner.xcodeproj/project.pbxproj',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('lxt2fst') && source.contains('vendor/fst-writer'),
        isTrue,
        reason:
            '$path builds libwellen_ffi but does not track native/lxt2fst and '
            'native/vendor/fst-writer — a converter change would ship stale.',
      );
    }
  });
}
