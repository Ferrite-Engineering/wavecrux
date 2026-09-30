// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Gate for tests that need the real wellen FFI library — the parser and the
// LXT/LXT2 converter, which ships inside it.
//
// Locally an unbuilt library skips the suite (build it with
// `cd native/wellen_ffi && cargo build --release`). In CI it fails instead:
// every workflow that runs `flutter test` builds the library first, so a
// missing one there is a broken build step, and a skip would hide exactly the
// regression these tests exist to catch.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/native/wellen_ffi_library_io.dart';

/// Whether the production resolver can open the wellen FFI library in this
/// test process.
bool wellenFfiLibraryLoads() {
  try {
    openWellenFfiLibrary();
    return true;
  } on Object {
    return false;
  }
}

/// Returns `true` when the library loads. Otherwise registers a single
/// placeholder test — a skip locally, a failure under `CI` — and returns
/// `false`, so the caller's `main` can return early.
bool requireWellenFfiLibrary(String suite) {
  if (wellenFfiLibraryLoads()) return true;
  if (Platform.environment['CI'] == 'true') {
    test('$suite: wellen FFI library is built', () {
      fail(
        'The wellen FFI library did not load (tried the bare name and '
        'native/wellen_ffi/target/{release,debug}). CI must run '
        '`cargo build --release` in native/wellen_ffi before `flutter test`.',
      );
    });
  } else {
    test(
      '$suite (skipped — native/wellen_ffi not built)',
      () {},
      skip: 'cd native/wellen_ffi && cargo build --release',
    );
  }
  return false;
}
