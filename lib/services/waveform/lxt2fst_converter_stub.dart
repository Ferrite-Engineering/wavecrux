// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Default stub for [Lxt2FstConverter] used by the analyzer when neither
// `dart:io` nor `dart:js_interop` resolves the conditional export.
//
// Production code never reaches these throws — the conditional export shim
// in [lxt2fst_converter.dart] picks the io or web implementation in every
// real build. The stub exists so non-Flutter Dart tools that look at the
// shim see a complete class surface.

import 'package:flutter/foundation.dart';
import 'package:wavecrux/services/waveform/lxt2fst_conversion_types.dart';

export 'package:wavecrux/services/waveform/lxt2fst_conversion_types.dart';

/// Stub [Lxt2FstConverter]; every method throws [UnsupportedError].
class Lxt2FstConverter {
  /// Stub constructor accepting (and ignoring) the same argument shape as
  /// the production io constructor so callers compile uniformly.
  // ignore: avoid_unused_constructor_parameters
  Lxt2FstConverter({@visibleForTesting Object? libraryOpener});

  static Never _unsupported() => throw UnsupportedError(
    'Lxt2FstConverter has no backend on this build target — '
    '`dart:ffi` and `dart:js_interop` are both unavailable.',
  );

  /// Lazy load-and-verify of the native library. No-op on the stub.
  Future<void> ensureLoaded() async {}

  /// Path-based conversion (desktop / mobile). Throws on the stub.
  Stream<ConversionProgress> convertPath({
    required String inPath,
    required String outPath,
  }) {
    _unsupported();
  }

  /// Byte-based conversion (web). Throws on the stub.
  Future<Uint8List> convertBytes(
    Uint8List input, {
    void Function(int done, int total)? onProgress,
  }) {
    _unsupported();
  }
}
