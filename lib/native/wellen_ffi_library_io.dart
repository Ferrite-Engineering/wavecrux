// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Resolution of the one native library behind every desktop/mobile FFI call.
//
// `libwellen_ffi` carries two C ABIs: wellen's waveform parser (`wellen_*`,
// bound by `wellen_ffi_bindings.dart`) and the LXT/LXT2 → FST converter
// (`lxt2fst_*`, bound by `lxt2fst_bindings.dart`), which the Rust crate links
// in as a dependency. Every platform build already compiles, bundles and signs
// this library, so both `WellenProvider` and `Lxt2FstConverter` open it
// through `openWellenFfiLibrary` rather than each guessing at a file name.

import 'dart:ffi' as ffi;
import 'dart:io';

/// Opens a library by name or path. Injectable so tests can observe or stub
/// the `dlopen` without touching the filesystem probe.
typedef WellenFfiLibraryOpener = ffi.DynamicLibrary Function(String path);

ffi.DynamicLibrary _dlopen(String path) => ffi.DynamicLibrary.open(path);

/// The platform file name of the wellen FFI library, e.g.
/// `libwellen_ffi.dylib`. Throws [UnsupportedError] on iOS (statically linked
/// — see [openWellenFfiLibrary]) and on platforms with no native build.
String wellenFfiLibraryFileName() {
  if (Platform.isLinux || Platform.isAndroid) return 'libwellen_ffi.so';
  if (Platform.isMacOS) return 'libwellen_ffi.dylib';
  if (Platform.isWindows) return 'wellen_ffi.dll';
  throw UnsupportedError(
    'wellen_ffi: no native library for ${Platform.operatingSystem}',
  );
}

/// Resolves and opens the wellen FFI library.
///
/// The lookup order is:
///
/// 1. **Bare name** — the production path. In a `flutter run` / packaged
///    desktop build the dylib lives in the `.app`'s Frameworks/ directory
///    (macOS), next to the executable (Windows), or in the package's
///    `lib/` subtree (Linux); on Android it is in the APK's jniLibs. The
///    dynamic loader finds it via the bundle's rpath without an explicit
///    path.
/// 2. **`native/wellen_ffi/target/{release,debug}/...`** under a probed
///    root — the `flutter test` path. The test process is a plain Dart
///    VM with no bundle, so the bare name throws; falling back to the
///    path produced by `cargo build` lets the tests find the library on
///    a developer machine without any extra setup. Probed roots are
///    [Directory.current] (open-core standalone checkout) and
///    `{Directory.current}/wavecrux` (the Pro overlay and any other overlay
///    that consumes this repo as a `./wavecrux` submodule — when those
///    overlays run `flutter test` from the overlay root, `Directory.current`
///    is one level above the submodule). Both `release` and `debug` profiles
///    are probed under each root.
///
/// iOS statically links the library into the app binary, so it always
/// returns [ffi.DynamicLibrary.process] there.
///
/// If every candidate misses, the original bare-name `dlopen` is retried
/// so the caller sees the platform-specific error message rather than a
/// generic "not found".
ffi.DynamicLibrary openWellenFfiLibrary({
  WellenFfiLibraryOpener opener = _dlopen,
}) {
  if (Platform.isIOS) {
    // Statically linked into the Runner binary; the WellenFFIKeepalive
    // target keeps both symbol families exported for dlsym.
    return ffi.DynamicLibrary.process();
  }
  final fileName = wellenFfiLibraryFileName();

  // Production: bundled into the app, found by the dynamic loader by name.
  try {
    return opener(fileName);
  } on Object {
    // Fall through to the test/dev fallbacks below.
  }

  final path = wellenFfiDevBuildPath();
  if (path != null) return opener(path);

  // Last resort — retry the bare name so the caller sees the original
  // "image not found" / "library cannot be opened" platform error.
  return opener(fileName);
}

/// The first existing `cargo build` output of the wellen FFI library under
/// the probed checkout roots (see [openWellenFfiLibrary]), or `null` when
/// none has been built. Release is preferred over debug.
String? wellenFfiDevBuildPath() {
  final fileName = wellenFfiLibraryFileName();
  final cwd = Directory.current.path;
  const profiles = ['release', 'debug'];
  for (final root in [cwd, '$cwd/wavecrux']) {
    for (final profile in profiles) {
      final candidate = '$root/native/wellen_ffi/target/$profile/$fileName';
      if (File(candidate).existsSync()) return candidate;
    }
  }
  return null;
}
